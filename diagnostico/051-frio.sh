#!/usr/bin/env bash
# 05.1: só ANALYZE contra VACUUM ANALYZE, medidos "a frio": scripts/medir.sh logo depois de o banco ser criado,
# sem o aquecimento de 60 s do rodízio (só o aquecimento de 15 s do próprio medir.sh). Assim a medição começa
# antes do autovacuum, que no diagnóstico (diagnostico/051-vacuum.txt) passou por pedidos cerca de 48 s depois
# de o banco subir.
#
#   diagnostico/051-frio.sh <pasta-temporaria> <commit>:<rotulo> [<commit>:<rotulo> ...]
#
# Em cada vez: apaga e cria o banco da versão, fixa banco e api nos núcleos P, mede, registra o mapa de
# visibilidade de pedidos e o último vacuum antes e depois da medição, e desliga. 3 rodadas com a ordem deslocada.
# Como no rodízio, o contrato é conferido pelo próprio medir.sh, no fim de cada medição.
# Registro em diagnostico/rodizio-registro.txt.
set -euo pipefail
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"; shift
RAIZ="$(pwd)"
REG="${RAIZ}/diagnostico/rodizio-registro.txt"
NUCLEOS_P="$(cat /sys/devices/cpu_core/cpus)"
RODADAS="${RODADAS:-3}"

log() { echo "$(date '+%F %T') perfil=$(powerprofilesctl get 2>/dev/null) carga=$(cut -d' ' -f1-3 /proc/loadavg) $*" | tee -a "$REG"; }
wt() { echo "${TMP}/$1"; }
dc() { local c="$1"; shift; (cd "$(wt "$c")" && COMPOSE_PROJECT_NAME="frio-$c" "$@"); }
pedidos() {
  dc "$1" docker compose exec -T banco psql -U loja -d loja -Atc "SELECT 'pedidos=' || c.relallvisible || '/' || c.relpages
      || ' vac=' || coalesce(to_char(greatest(s.last_vacuum, s.last_autovacuum), 'HH24:MI:SS'), '-')
      || ' no_ar=' || round(extract(epoch FROM now() - pg_postmaster_start_time())) || 's'
    FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid WHERE c.relname = 'pedidos'"
}

V=("$@")
n=${#V[@]}
log "a frio: ${V[*]}"
for par in "${V[@]}"; do
  c="${par%%:*}"
  [[ -d "$(wt "$c")" ]] || git worktree add -q --detach "$(wt "$c")" "$c"
done

for (( rodada = 0; rodada < RODADAS; rodada++ )); do
  for (( j = 0; j < n; j++ )); do
    par="${V[$(( (j + rodada) % n ))]}"; c="${par%%:*}"; r="${par#*:}"
    dc "$c" docker compose down -v 2>&1 | tail -1
    dc "$c" docker compose up -d --build --wait 2>&1 | tail -1
    # shellcheck disable=SC2046
    docker update --cpuset-cpus "$NUCLEOS_P" $(dc "$c" docker compose ps -q banco api) >/dev/null
    log "antes de medir $r: $(pedidos "$c")"
    dc "$c" scripts/medir.sh "$r" 2>&1 | tail -1
    log "depois de medir $r: $(pedidos "$c")"
    for d in "$(wt "$c")"/resultados/*-"$r"; do
      [[ -e "$RAIZ/resultados/$(basename "$d")" ]] || cp -r "$d" "$RAIZ/resultados/"
    done
    log "medido $r ($c): $(grep -m1 'Requisições/s' "$(ls -d "$(wt "$c")"/resultados/*-"$r" | tail -1)/resumo.txt" | tr -s ' ')"
    dc "$c" docker compose down -v 2>&1 | tail -1
  done
done

for par in "${V[@]}"; do
  git worktree remove --force "$(wt "${par%%:*}")"
done
log "fim das medições a frio"
