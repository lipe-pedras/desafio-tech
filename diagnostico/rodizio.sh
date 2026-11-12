#!/usr/bin/env bash
# Mede várias versões em rodízio, no formato oficial (scripts/medir.sh, parâmetros padrão, commit limpo).
#
#   diagnostico/rodizio.sh <pasta-temporaria> <commit>:<rotulo> [<commit>:<rotulo> ...]
#   ex.: diagnostico/rodizio.sh /tmp/rod 1e1ba20:04-antes-desktop 96365fe:04-vendas-por-dia-desktop
#
# Cada versão roda numa git worktree própria e tem o seu banco (projeto compose próprio), criado do zero
# a partir dos arquivos de banco/ daquele commit. Assim, mudanças só de API e mudanças de banco seguem
# o mesmo protocolo. Os bancos são criados uma vez e ligados um por vez. Em cada vez:
#   1. sobe a versão e fixa banco e api nos núcleos P (docker update --cpuset-cpus; limites inalterados);
#   2. aquece por 60 s (5 VUs, semente 43, fora da medição);
#   3. confere o contrato, registra o mapa de visibilidade das tabelas (relallvisible/relpages e último vacuum)
#      e mede com scripts/medir.sh, registrando antes e depois os contadores de cota de CPU do banco e da API;
#   4. desliga a versão.
# São 3 rodadas, com a ordem deslocada a cada rodada. As pastas de resultados são copiadas para resultados/.
# Registro de cada passo em diagnostico/rodizio-registro.txt.
set -euo pipefail
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"; shift
RAIZ="$(pwd)"
REG="${RAIZ}/diagnostico/rodizio-registro.txt"
NUCLEOS_P="$(cat /sys/devices/cpu_core/cpus)"
RODADAS="${RODADAS:-3}"

log() { echo "$(date '+%F %T') perfil=$(powerprofilesctl get 2>/dev/null) carga=$(cut -d' ' -f1-3 /proc/loadavg) $*" | tee -a "$REG"; }
wt() { echo "${TMP}/$1"; }
dc() { local c="$1"; shift; (cd "$(wt "$c")" && COMPOSE_PROJECT_NAME="rod-$c" "$@"); }
fixar() {
  local ids; ids="$(dc "$1" docker compose ps -q banco api)"
  # shellcheck disable=SC2086
  docker update --cpuset-cpus "$NUCLEOS_P" $ids >/dev/null
  # shellcheck disable=SC2086
  log "fixado: $(docker inspect --format '{{.Name}} cpuset={{.HostConfig.CpusetCpus}} nanocpus={{.HostConfig.NanoCpus}}' $ids | tr '\n' ' ')"
}
# Páginas marcadas como visíveis no mapa de visibilidade (relallvisible/relpages) e último vacuum de cada tabela.
visibilidade() {
  dc "$1" docker compose exec -T banco psql -U loja -d loja -Atc "SELECT string_agg(c.relname || '=' || c.relallvisible || '/' || c.relpages
      || ' vac=' || coalesce(to_char(greatest(s.last_vacuum, s.last_autovacuum), 'HH24:MI:SS'), '-'), ' ' ORDER BY c.relname)
    FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid"
}
# Contadores de cota de CPU do cgroup do banco e da API (cpu.stat): períodos, períodos em que o banco foi pausado por
# esgotar a cota (nr_throttled) e tempo total pausado (throttled_usec). Lidos antes e depois do medir.sh
# (a diferença inclui o aquecimento de 15 s do próprio medir.sh).
cota() {
  local s
  for s in banco api; do
    echo -n "$s: $(dc "$1" docker compose exec -T "$s" sh -c "grep -E '^(usage_usec|nr_periods|nr_throttled|throttled_usec) ' /sys/fs/cgroup/cpu.stat | tr '\n' ' '")"
  done
}
guardar() {
  local d
  for d in "$(wt "$1")"/resultados/*-"$2"; do
    [[ -e "$RAIZ/resultados/$(basename "$d")" ]] || cp -r "$d" "$RAIZ/resultados/"
  done
}

V=("$@")
n=${#V[@]}
log "rodízio: ${V[*]}"
for par in "${V[@]}"; do
  c="${par%%:*}"
  [[ -d "$(wt "$c")" ]] || git worktree add -q --detach "$(wt "$c")" "$c"
  dc "$c" docker compose down -v 2>&1 | tail -1
  inicio=$(date +%s)
  dc "$c" docker compose up -d --build 2>&1 | tail -1
  log "banco de $c criado em $(( $(date +%s) - inicio )) s"
  dc "$c" docker compose stop 2>&1 | tail -1
done

for (( rodada = 0; rodada < RODADAS; rodada++ )); do
  for (( j = 0; j < n; j++ )); do
    par="${V[$(( (j + rodada) % n ))]}"; c="${par%%:*}"; r="${par#*:}"
    dc "$c" docker compose up -d --wait 2>&1 | tail -1
    fixar "$c"
    dc "$c" docker compose run --rm -e VUS=5 -e DURACAO=60s -e SEMENTE=43 carga run --quiet --no-summary /carga/teste-carga.js >/dev/null
    dc "$c" scripts/verificar-contrato.sh comparar 2>&1 | tail -1 | grep -q "Contrato mantido" || { log "contrato quebrado em $c"; exit 1; }
    log "antes de medir $r: $(visibilidade "$c")"
    log "cota antes de medir $r: $(cota "$c")"
    dc "$c" scripts/medir.sh "$r" 2>&1 | tail -1
    log "cota depois de medir $r: $(cota "$c")"
    guardar "$c" "$r"
    log "medido $r ($c): $(grep -m1 'Requisições/s' "$(ls -d "$(wt "$c")"/resultados/*-"$r" | tail -1)/resumo.txt" | tr -s ' ')"
    dc "$c" docker compose stop 2>&1 | tail -1
  done
done

for par in "${V[@]}"; do
  c="${par%%:*}"
  dc "$c" docker compose down -v 2>&1 | tail -1
  git worktree remove --force "$(wt "$c")"
done
log "fim do rodízio"
