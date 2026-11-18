#!/usr/bin/env bash
# Versões só de API em rodízio, no mesmo formato do bloco B de rodar.sh: um banco único com os índices da 01
# (466d0f5), aquecido 60 s, banco e api fixados nos núcleos P, 3 rodadas com a ordem deslocada a cada rodada.
#
#   diagnostico/remedicao-desktop/rodar-bloco-b.sh <pasta-temporaria> <titulo> <commit>:<rotulo> [...]
#
# Execuções registradas em registro.txt (2026-11-11):
#   rodar-bloco-b.sh <tmp> "031 pool 1" c7dc4f3:031-pool-max-1-desktop 958aad1:031-pool-max-2-desktop
#   rodar-bloco-b.sh <tmp> "fechamento 03" 1fd2ae4:03f-02-pool-2-desktop d9ee2e5:03f-02-pool-1-desktop \
#                                          c7dc4f3:03f-03-pool-1-desktop
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
trap 'log "FALHOU na linha $LINENO"' ERR

TMP="$1"; TITULO="$2"; shift 2
RAIZ="$(pwd)"
REG="${RAIZ}/diagnostico/remedicao-desktop/registro.txt"
NUCLEOS_P="$(nucleos_p)"
PROJ="remed-01"
BANCO=466d0f5  # versão cujo banco/ cria o banco único

V=("$@")
n=${#V[@]}
for c in "$BANCO" "${V[@]%%:*}"; do
  criar_worktree "$c"
done

log "$TITULO: criando banco com os índices da 01"
dc "$PROJ" "$BANCO" docker compose down -v 2>&1 | tail -1
dc "$PROJ" "$BANCO" docker compose up -d --build 2>&1 | tail -1
fixar "$PROJ" "$BANCO"
aquecer "$PROJ" "$BANCO"

for rodada in 0 1 2; do
  for (( j = 0; j < n; j++ )); do
    par="${V[$(( (j + rodada) % n ))]}"; c="${par%%:*}"; r="${par#*:}"
    dc "$PROJ" "$c" docker compose up -d --build --no-deps --force-recreate --wait api 2>&1 | tail -1
    fixar "$PROJ" "$c"
    sleep 3
    conferir_contrato "$PROJ" "$c"
    dc "$PROJ" "$c" scripts/medir.sh "$r" 2>&1 | tail -1
    guardar "$c" "$r"
    registrar_medicao "$c" "$r"
  done
done

dc "$PROJ" "$BANCO" docker compose down -v 2>&1 | tail -1
for c in "$BANCO" "${V[@]%%:*}"; do
  remover_worktree "$c"
done
log "fim $TITULO"
