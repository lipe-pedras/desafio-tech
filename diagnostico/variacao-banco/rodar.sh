#!/usr/bin/env bash
# Uso, a partir da raiz do desafio: diagnostico/variacao-banco/rodar.sh <pasta-temporaria>
# Etapa 1: mesmo código (1fd2ae4), banco recriado 3 vezes. Mede quanto o banco recriado muda o resultado.
# Etapa 2: formato oficial (scripts/medir.sh), um único banco, versões em rodízio.
set -euo pipefail
trap 'echo "FALHOU na linha $LINENO"' ERR

TMP="$1"
RAIZ="$(pwd)"
D="${RAIZ}/diagnostico/variacao-banco"
estado() { echo "$(date +%T) energia=$(cat /sys/class/power_supply/ACAD/online) perfil=$(powerprofilesctl get) $*"; }
pasta() { echo "${TMP}/$1"; }
for c in 466d0f5 63b4693 1fd2ae4 958aad1; do git worktree add -q --detach "$(pasta "$c")" "$c"; done
guardar() { cp -r "$1"/resultados/*-"$2" "$RAIZ/resultados/"; }

docker compose down -v 2>&1 | tail -1
W="$(pasta 1fd2ae4)"
for b in 1 2 3; do
  estado "etapa 1, banco $b"
  (cd "$W" && docker compose down -v 2>&1 | tail -1 && docker compose up -d --build 2>&1 | tail -1)
  sleep 3
  (cd "$W" && docker compose exec -T banco psql -U loja -d loja -Atc "select count(*), sum(cliente_id::bigint), sum(extract(epoch from criado_em))::bigint, min(ctid::text), max(id) from pedidos" > "$D/dados-banco-$b.txt")
  (cd "$W" && docker compose exec -T banco psql -U loja -d loja < diagnostico/explain.sql > "$D/explain-banco-$b.txt" 2>&1)
  for i in 1 2 3; do (cd "$W" && scripts/medir.sh "var-banco-$b" 2>&1 | tail -1); done
  (cd "$W" && guardar "$W" "var-banco-$b")
done

estado "etapa 2"
(cd "$W" && docker compose down -v 2>&1 | tail -1 && docker compose up -d --build 2>&1 | tail -1)
sleep 3
(cd "$W" && docker compose run --rm -e VUS=5 -e DURACAO=60s -e SEMENTE=43 carga run --quiet --no-summary /carga/teste-carga.js >/dev/null)

medir() { # commit rotulo
  local w; w="$(pasta "$1")"
  (cd "$w" && docker compose up -d --build --no-deps --force-recreate api 2>&1 | tail -1)
  sleep 4
  (cd "$w" && scripts/verificar-contrato.sh comparar 2>&1 | tail -1 | grep -q "Contrato mantido")
  (cd "$w" && scripts/medir.sh "$2" 2>&1 | tail -1)
  estado "$2"
}
V=("466d0f5 ab-01-indices" "63b4693 ab-02-pool-10" "1fd2ae4 ab-02-pool-2" "958aad1 ab-03-n-mais-1")
for rodada in 0 1 2; do
  for j in 0 1 2 3; do
    read -r commit rotulo <<< "${V[$(( (j + rodada) % 4 ))]}"
    medir "$commit" "$rotulo"
  done
done
for par in "${V[@]}"; do read -r commit rotulo <<< "$par"; guardar "$(pasta "$commit")" "$rotulo"; done
estado "fim"
