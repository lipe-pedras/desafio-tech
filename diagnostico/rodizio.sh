#!/usr/bin/env bash
# Mede várias versões em rodízio, no formato oficial (scripts/medir.sh, parâmetros padrão, commit limpo).
#
#   diagnostico/rodizio.sh <pasta-temporaria> <commit>:<rotulo> [<commit>:<rotulo> ...]
#   ex.: diagnostico/rodizio.sh /tmp/rod 1e1ba20:04-antes-desktop 96365fe:04-vendas-por-dia-desktop
#
# Cada versão roda numa git worktree e num projeto compose próprios, com o banco criado do zero a partir
# de banco/ daquele commit. Os bancos são criados uma vez e ligados um por vez. Em cada vez:
#   1. sobe a versão e fixa banco e api nos núcleos P;
#   2. aquece por 60 s, fora da medição;
#   3. confere o contrato, registra o mapa de visibilidade e os contadores de cota de CPU, e mede;
#   4. desliga a versão.
# RODADAS rodadas (padrão 3), com a ordem deslocada a cada rodada. Registro em diagnostico/rodizio-registro.txt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"; shift
RAIZ="$(pwd)"
REG="${RAIZ}/diagnostico/rodizio-registro.txt"
NUCLEOS_P="$(nucleos_p)"
RODADAS="${RODADAS:-3}"

versao() { local c="$1"; shift; dc "rod-$c" "$c" "$@"; }  # commit comando...

# Páginas marcadas no mapa de visibilidade (relallvisible/relpages) e último vacuum de cada tabela.
visibilidade() {
  versao "$1" docker compose exec -T banco psql -U loja -d loja -Atc "
    SELECT string_agg(c.relname || '=' || c.relallvisible || '/' || c.relpages || ' vac='
                      || coalesce(to_char(greatest(s.last_vacuum, s.last_autovacuum), 'HH24:MI:SS'), '-'),
                      ' ' ORDER BY c.relname)
      FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid"
}

# Contadores de cota de CPU (cpu.stat) do banco e da API: uso, períodos, períodos pausados por esgotar a cota
# e tempo pausado. A diferença entre antes e depois inclui o aquecimento de 15 s do próprio medir.sh.
cota() {
  local servico
  for servico in banco api; do
    echo -n "$servico: $(versao "$1" docker compose exec -T "$servico" sh -c \
      "grep -E '^(usage_usec|nr_periods|nr_throttled|throttled_usec) ' /sys/fs/cgroup/cpu.stat | tr '\n' ' '")"
  done
}

V=("$@")
n=${#V[@]}
log "rodízio: ${V[*]}"
for par in "${V[@]}"; do
  c="${par%%:*}"
  criar_worktree "$c"
  versao "$c" docker compose down -v 2>&1 | tail -1
  inicio=$(date +%s)
  versao "$c" docker compose up -d --build 2>&1 | tail -1
  log "banco de $c criado em $(( $(date +%s) - inicio )) s"
  versao "$c" docker compose stop 2>&1 | tail -1
done

for (( rodada = 0; rodada < RODADAS; rodada++ )); do
  for (( j = 0; j < n; j++ )); do
    par="${V[$(( (j + rodada) % n ))]}"; c="${par%%:*}"; r="${par#*:}"
    versao "$c" docker compose up -d --wait 2>&1 | tail -1
    fixar "rod-$c" "$c"
    aquecer "rod-$c" "$c"
    conferir_contrato "rod-$c" "$c"
    log "antes de medir $r: $(visibilidade "$c")"
    log "cota antes de medir $r: $(cota "$c")"
    versao "$c" scripts/medir.sh "$r" 2>&1 | tail -1
    log "cota depois de medir $r: $(cota "$c")"
    guardar "$c" "$r"
    registrar_medicao "$c" "$r"
    versao "$c" docker compose stop 2>&1 | tail -1
  done
done

for par in "${V[@]}"; do
  c="${par%%:*}"
  versao "$c" docker compose down -v 2>&1 | tail -1
  remover_worktree "$c"
done
log "fim do rodízio"
