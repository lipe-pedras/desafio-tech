#!/usr/bin/env bash
# 05.1: só ANALYZE contra VACUUM ANALYZE, medidos "a frio": scripts/medir.sh logo depois de o banco ser criado,
# sem o aquecimento de 60 s do rodízio. Assim a medição começa antes de o autovacuum passar por pedidos
# (cerca de 48 s depois de o banco subir, diagnostico/051-vacuum.txt).
#
#   diagnostico/051-frio.sh <pasta-temporaria> <commit>:<rotulo> [<commit>:<rotulo> ...]
#
# Em cada vez: apaga e cria o banco da versão, fixa banco e api nos núcleos P, mede, registra o mapa de
# visibilidade de pedidos antes e depois, e desliga. RODADAS rodadas (padrão 3) com a ordem deslocada.
# O contrato é conferido pelo próprio medir.sh. Registro em diagnostico/rodizio-registro.txt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"; shift
RAIZ="$(pwd)"
REG="${RAIZ}/diagnostico/rodizio-registro.txt"
NUCLEOS_P="$(nucleos_p)"
RODADAS="${RODADAS:-3}"

versao() { local c="$1"; shift; dc "frio-$c" "$c" "$@"; }  # commit comando...

visibilidade_pedidos() {
  versao "$1" docker compose exec -T banco psql -U loja -d loja -Atc "
    SELECT 'pedidos=' || c.relallvisible || '/' || c.relpages
           || ' vac=' || coalesce(to_char(greatest(s.last_vacuum, s.last_autovacuum), 'HH24:MI:SS'), '-')
           || ' no_ar=' || round(extract(epoch FROM now() - pg_postmaster_start_time())) || 's'
      FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid
     WHERE c.relname = 'pedidos'"
}

V=("$@")
n=${#V[@]}
log "a frio: ${V[*]}"
for par in "${V[@]}"; do
  criar_worktree "${par%%:*}"
done

for (( rodada = 0; rodada < RODADAS; rodada++ )); do
  for (( j = 0; j < n; j++ )); do
    par="${V[$(( (j + rodada) % n ))]}"; c="${par%%:*}"; r="${par#*:}"
    versao "$c" docker compose down -v 2>&1 | tail -1
    versao "$c" docker compose up -d --build --wait 2>&1 | tail -1
    fixar "frio-$c" "$c"
    log "antes de medir $r: $(visibilidade_pedidos "$c")"
    versao "$c" scripts/medir.sh "$r" 2>&1 | tail -1
    log "depois de medir $r: $(visibilidade_pedidos "$c")"
    guardar "$c" "$r"
    registrar_medicao "$c" "$r"
    versao "$c" docker compose down -v 2>&1 | tail -1
  done
done

for par in "${V[@]}"; do
  remover_worktree "${par%%:*}"
done
log "fim das medições a frio"
