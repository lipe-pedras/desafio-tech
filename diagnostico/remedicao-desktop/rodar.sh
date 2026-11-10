#!/usr/bin/env bash
# Remedição de todas as versões no desktop, em rodízio.
# Uso, a partir da raiz do desafio: diagnostico/remedicao-desktop/rodar.sh <pasta-temporaria>
#
# Bloco A: linha de base (d29146f) x 01 (466d0f5). Cada uma tem o seu banco (projetos compose
#          separados, porque a 01 depende de banco/03-indices.sql). Os dois bancos são criados uma vez
#          e ligados um por vez, com aquecimento de 60 s, em 3 rodadas com a ordem alternada.
# Bloco B: todas as versões só de API num único banco com os índices da 01, em 3 rodadas,
#          com a ordem deslocada a cada rodada. Troca-se só o container da API.
#
# Em todas as medições, banco e api ficam fixados nos núcleos P (docker update --cpuset-cpus),
# sem mudar os limites de CPU e memória do docker-compose.yml. O k6 roda sem fixação.
# Medição sempre por scripts/medir.sh, com os parâmetros padrão, no commit limpo de cada versão.
set -euo pipefail
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"
RAIZ="$(pwd)"
D="${RAIZ}/diagnostico/remedicao-desktop"
NUCLEOS_P="$(cat /sys/devices/cpu_core/cpus)"
PROJ_BASE="remed-base"
PROJ_01="remed-01"

log() { echo "$(date '+%F %T') perfil=$(powerprofilesctl get 2>/dev/null) carga=$(cut -d' ' -f1-3 /proc/loadavg) $*" | tee -a "$D/registro.txt"; }
wt() { echo "${TMP}/$1"; }
dc() { # projeto commit comando...
  local p="$1" c="$2"; shift 2
  (cd "$(wt "$c")" && COMPOSE_PROJECT_NAME="$p" "$@")
}
fixar() { # projeto commit
  local ids; ids="$(dc "$1" "$2" docker compose ps -q banco api)"
  # shellcheck disable=SC2086
  docker update --cpuset-cpus "$NUCLEOS_P" $ids >/dev/null
  # shellcheck disable=SC2086
  log "fixado: $(docker inspect --format '{{.Name}} cpuset={{.HostConfig.CpusetCpus}} nanocpus={{.HostConfig.NanoCpus}}' $ids | tr '\n' ' ')"
}
guardar() { # commit rotulo
  local d
  for d in "$(wt "$1")"/resultados/*-"$2"; do
    [[ -e "$RAIZ/resultados/$(basename "$d")" ]] || cp -r "$d" "$RAIZ/resultados/"
  done
}
aquecer() { dc "$1" "$2" docker compose run --rm -e VUS=5 -e DURACAO=60s -e SEMENTE=43 carga run --quiet --no-summary /carga/teste-carga.js >/dev/null; }
medir() { # projeto commit rotulo
  dc "$1" "$2" scripts/verificar-contrato.sh comparar 2>&1 | tail -1 | grep -q "Contrato mantido" || { log "contrato quebrado em $2"; exit 1; }
  dc "$1" "$2" scripts/medir.sh "$3" 2>&1 | tail -1
  guardar "$2" "$3"
  log "medido $3 ($2): $(grep -m1 -i 'requisi' "$(ls -d "$(wt "$2")"/resultados/*-"$3" | tail -1)/resumo.txt" | tr -s ' ')"
}

for c in d29146f 466d0f5 63b4693 d9ee2e5 1fd2ae4 4253e8a a8c5c79 acb84a7 92fb437 958aad1 9e2a2dd e9c1dc7; do
  [[ -d "$(wt "$c")" ]] || git worktree add -q --detach "$(wt "$c")" "$c"
done

# ---------- Bloco A ----------
log "bloco A: criando bancos"
for par in "$PROJ_BASE d29146f" "$PROJ_01 466d0f5"; do
  read -r p c <<< "$par"
  dc "$p" "$c" docker compose down -v 2>&1 | tail -1
  inicio=$(date +%s)
  dc "$p" "$c" docker compose up -d --build 2>&1 | tail -1
  log "banco $p criado em $(( $(date +%s) - inicio )) s"
  dc "$p" "$c" docker compose stop 2>&1 | tail -1
done

A=("$PROJ_BASE d29146f 00-linha-de-base-desktop" "$PROJ_01 466d0f5 01-indices-desktop")
for rodada in 0 1 2; do
  for j in 0 1; do
    read -r p c r <<< "${A[$(( (j + rodada) % 2 ))]}"
    dc "$p" "$c" docker compose up -d --wait 2>&1 | tail -1
    fixar "$p" "$c"
    aquecer "$p" "$c"
    medir "$p" "$c" "$r"
    dc "$p" "$c" docker compose stop 2>&1 | tail -1
  done
done
dc "$PROJ_BASE" d29146f docker compose down -v 2>&1 | tail -1

# ---------- Bloco B ----------
log "bloco B: banco único com os índices da 01"
B=(
  "466d0f5 01-indices-rodizio-desktop"
  "63b4693 02-pool-conexoes-desktop"
  "d9ee2e5 021-pool-max-1-desktop"
  "1fd2ae4 021-pool-max-2-desktop"
  "4253e8a 021-pool-max-3-desktop"
  "a8c5c79 021-pool-max-5-desktop"
  "acb84a7 021-pool-max-10-desktop"
  "92fb437 021-pool-max-20-desktop"
  "958aad1 03-n-mais-1-desktop"
  "9e2a2dd 031-pool-max-5-desktop"
  "e9c1dc7 031-pool-max-10-desktop"
)
dc "$PROJ_01" 466d0f5 docker compose up -d --wait 2>&1 | tail -1
fixar "$PROJ_01" 466d0f5
aquecer "$PROJ_01" 466d0f5
n=${#B[@]}
for rodada in 0 1 2; do
  for (( j = 0; j < n; j++ )); do
    read -r c r <<< "${B[$(( (j + rodada * 4) % n ))]}"
    dc "$PROJ_01" "$c" docker compose up -d --build --no-deps --force-recreate --wait api 2>&1 | tail -1
    fixar "$PROJ_01" "$c"
    sleep 3
    medir "$PROJ_01" "$c" "$r"
  done
done
log "fim"
