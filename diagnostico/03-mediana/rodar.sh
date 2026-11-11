#!/usr/bin/env bash
# DIAGNÓSTICO da mediana da 03. Não usa o scripts/medir.sh e NÃO gera resultado oficial.
# Uso, a partir da raiz do desafio: diagnostico/03-mediana/rodar.sh <pasta-temporaria>
# Teste 1: código antigo (1fd2ae4), carga sem a rota do N+1, com 2, 5, 8, 14 e 20 usuários.
# Teste 2: carga oficial nas duas versões (1fd2ae4 e 958aad1), com a API instrumentada.
set -euo pipefail
trap 'echo "FALHOU na linha $LINENO (saída $?)"' ERR

TMP="$1"
RAIZ="$(pwd)"
D="${RAIZ}/diagnostico/03-mediana"
USUARIO="$(id -u):$(id -g)"
ANTES="${TMP}/antes"; ANTES_I="${TMP}/antes-instr"; DEPOIS_I="${TMP}/depois-instr"

git worktree add -q --detach "$ANTES" 1fd2ae4
git worktree add -q --detach "$ANTES_I" 1fd2ae4
git worktree add -q --detach "$DEPOIS_I" 958aad1
for w in "$ANTES_I" "$DEPOIS_I"; do cp "$D"/instrumentacao/{db.js,server.js} "$w/api/src/"; done

estado() { echo "$(date +%T) energia=$(cat /sys/class/power_supply/ACAD/online) perfil=$(powerprofilesctl get) $*"; }
trocar_api() { (cd "$1" && docker compose up -d --build --no-deps --force-recreate api 2>&1 | tail -1); sleep 4; curl -fsS http://127.0.0.1:3000/saude >/dev/null; }
carga() { # script vus duracao semente saida
  local args=(-e VUS="$2" -e DURACAO="$3" -e SEMENTE="$4")
  [[ -n "$5" ]] && args+=(-e SAIDA="$5")
  docker compose run --rm --user "$USUARIO" -v "${D}:/diag" "${args[@]}" carga run --quiet "$1" >/dev/null
}

docker compose down -v 2>&1 | tail -1
(cd "$ANTES" && docker compose up -d --build 2>&1 | tail -3; exit "${PIPESTATUS[0]}")
sleep 3

estado "teste 1"
for rodada in 1 2 3; do
  for vus in 2 5 8 14 20; do
    mkdir -p "$D/saida/teste1/vus-$vus/r$rodada"
    carga /diag/carga-sem-n1.js 5 15s 43 ""
    carga /diag/carga-sem-n1.js "$vus" 60s 42 "/diag/saida/teste1/vus-$vus/r$rodada"
    estado "teste 1 vus=$vus rodada=$rodada"
  done
done

estado "teste 2"
for rodada in 1 2 3; do
  for versao in antes depois; do
    [[ "$versao" == antes ]] && w="$ANTES_I" || w="$DEPOIS_I"
    trocar_api "$w"
    s="$D/saida/teste2/$versao/r$rodada"; mkdir -p "$s"
    curl -fsS http://127.0.0.1:3000/__diag >/dev/null
    carga /carga/teste-carga.js 5 15s 43 ""
    curl -fsS -X POST http://127.0.0.1:3000/__diag/reiniciar >/dev/null
    carga /carga/teste-carga.js 20 60s 42 "/diag/saida/teste2/$versao/r$rodada"
    curl -fsS http://127.0.0.1:3000/__diag > "$s/diag.json"
    estado "teste 2 $versao rodada=$rodada"
  done
done
