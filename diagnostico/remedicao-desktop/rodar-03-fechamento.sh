#!/usr/bin/env bash
# Fechamento da 03: 02 da main (1fd2ae4, pool 2), 02 com pool 1 (d9ee2e5) e 03 com pool 1 (c7dc4f3), em rodízio, mesmo formato do bloco B de rodar.sh:
# banco único com os índices da 01 (466d0f5), aquecido 60 s, banco e api fixados nos núcleos P, 3 rodadas com a ordem deslocada.
# Uso, a partir da raiz do desafio: diagnostico/remedicao-desktop/rodar-03-fechamento.sh <pasta-temporaria>
set -euo pipefail
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"
RAIZ="$(pwd)"
D="${RAIZ}/diagnostico/remedicao-desktop"
NUCLEOS_P="$(cat /sys/devices/cpu_core/cpus)"
PROJ="remed-01"

log() { echo "$(date '+%F %T') perfil=$(powerprofilesctl get 2>/dev/null) carga=$(cut -d' ' -f1-3 /proc/loadavg) $*" | tee -a "$D/registro.txt"; }
wt() { echo "${TMP}/$1"; }
dc() { local c="$1"; shift; (cd "$(wt "$c")" && COMPOSE_PROJECT_NAME="$PROJ" "$@"); }
fixar() {
  local ids; ids="$(dc "$1" docker compose ps -q banco api)"
  # shellcheck disable=SC2086
  docker update --cpuset-cpus "$NUCLEOS_P" $ids >/dev/null
  # shellcheck disable=SC2086
  log "fixado: $(docker inspect --format '{{.Name}} cpuset={{.HostConfig.CpusetCpus}} nanocpus={{.HostConfig.NanoCpus}}' $ids | tr '\n' ' ')"
}
guardar() {
  local d
  for d in "$(wt "$1")"/resultados/*-"$2"; do
    [[ -e "$RAIZ/resultados/$(basename "$d")" ]] || cp -r "$d" "$RAIZ/resultados/"
  done
}
medir() { # commit rotulo
  dc "$1" scripts/verificar-contrato.sh comparar 2>&1 | tail -1 | grep -q "Contrato mantido" || { log "contrato quebrado em $1"; exit 1; }
  dc "$1" scripts/medir.sh "$2" 2>&1 | tail -1
  guardar "$1" "$2"
  log "medido $2 ($1): $(grep -m1 'Requisições/s' "$(ls -d "$(wt "$1")"/resultados/*-"$2" | tail -1)/resumo.txt" | tr -s ' ')"
}

for c in 466d0f5 1fd2ae4 d9ee2e5 c7dc4f3; do
  [[ -d "$(wt "$c")" ]] || git worktree add -q --detach "$(wt "$c")" "$c"
done

log "fechamento 03: criando banco com os índices da 01"
dc 466d0f5 docker compose down -v 2>&1 | tail -1
dc 466d0f5 docker compose up -d --build 2>&1 | tail -1
fixar 466d0f5
dc 466d0f5 docker compose run --rm -e VUS=5 -e DURACAO=60s -e SEMENTE=43 carga run --quiet --no-summary /carga/teste-carga.js >/dev/null

V=("1fd2ae4 03f-02-pool-2-desktop" "d9ee2e5 03f-02-pool-1-desktop" "c7dc4f3 03f-03-pool-1-desktop")
for rodada in 0 1 2; do
  for j in 0 1 2; do
    read -r c r <<< "${V[$(( (j + rodada) % 3 ))]}"
    dc "$c" docker compose up -d --build --no-deps --force-recreate --wait api 2>&1 | tail -1
    fixar "$c"
    sleep 3
    medir "$c" "$r"
  done
done
dc 466d0f5 docker compose down -v 2>&1 | tail -1
for c in 466d0f5 1fd2ae4 d9ee2e5 c7dc4f3; do git worktree remove --force "$(wt "$c")"; done
log "fim fechamento 03"
