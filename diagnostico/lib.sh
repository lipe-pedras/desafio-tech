# Funções comuns dos scripts de diagnostico/. Carregue com:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"            (scripts em diagnostico/)
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"         (scripts em subpastas)
# shellcheck shell=bash

# Núcleos de desempenho (P) de um processador Intel híbrido, onde banco e API são fixados nas medições.
nucleos_p() {
  local arquivo=/sys/devices/cpu_core/cpus
  if [[ ! -r $arquivo ]]; then
    echo "$arquivo não existe: os scripts de medição fixam os containers nos núcleos P de um Intel híbrido" >&2
    return 1
  fi
  cat "$arquivo"
}

# ---------- Rodízio de versões em git worktrees ----------
# Antes de usar, defina: TMP (pasta das worktrees), RAIZ (raiz do desafio), REG (arquivo de registro)
# e NUCLEOS_P="$(nucleos_p)".

log() {
  echo "$(date '+%F %T') perfil=$(powerprofilesctl get 2>/dev/null) carga=$(cut -d' ' -f1-3 /proc/loadavg) $*" \
    | tee -a "$REG"
}

wt() { echo "${TMP}/$1"; }  # commit -> pasta da worktree

criar_worktree() { [[ -d "$(wt "$1")" ]] || git worktree add -q --detach "$(wt "$1")" "$1"; }

remover_worktree() { git worktree remove --force "$(wt "$1")"; }

dc() {  # projeto commit comando...: roda o comando na worktree do commit, no projeto compose indicado
  local projeto="$1" commit="$2"
  shift 2
  (cd "$(wt "$commit")" && COMPOSE_PROJECT_NAME="$projeto" "$@")
}

fixar() {  # projeto commit: fixa banco e api nos núcleos P, sem mudar os limites de CPU e memória
  local ids
  ids="$(dc "$1" "$2" docker compose ps -q banco api)"
  # shellcheck disable=SC2086  # um id por palavra
  docker update --cpuset-cpus "$NUCLEOS_P" $ids >/dev/null
  # shellcheck disable=SC2086
  log "fixado: $(docker inspect --format '{{.Name}} cpuset={{.HostConfig.CpusetCpus}} nanocpus={{.HostConfig.NanoCpus}}' $ids \
    | tr '\n' ' ')"
}

aquecer() {  # projeto commit: 60 s de carga leve, fora da medição
  dc "$1" "$2" docker compose run --rm -e VUS=5 -e DURACAO=60s -e SEMENTE=43 \
    carga run --quiet --no-summary /carga/teste-carga.js >/dev/null
}

conferir_contrato() {  # projeto commit: interrompe o script se o contrato quebrou
  if ! dc "$1" "$2" scripts/verificar-contrato.sh comparar 2>&1 | tail -1 | grep -q "Contrato mantido"; then
    log "contrato quebrado em $2"
    exit 1
  fi
}

guardar() {  # commit rotulo: copia as pastas de resultados da worktree para resultados/ da raiz
  local pasta
  for pasta in "$(wt "$1")"/resultados/*-"$2"; do
    [[ -e "$RAIZ/resultados/$(basename "$pasta")" ]] || cp -r "$pasta" "$RAIZ/resultados/"
  done
}

registrar_medicao() {  # commit rotulo: registra as req/s da última medição do rótulo
  local ultima
  ultima="$(ls -d "$(wt "$1")"/resultados/*-"$2" | tail -1)"
  log "medido $2 ($1): $(grep -m1 'Requisições/s' "$ultima/resumo.txt" | tr -s ' ')"
}

# ---------- Custo de escrita dos gatilhos com pgbench (no projeto compose da pasta atual) ----------

psql_banco() { docker compose exec -T banco psql -U loja -d loja -X -q "$@"; }

fixar_banco() { docker update --cpuset-cpus "$(nucleos_p)" "$(docker compose ps -q banco)" >/dev/null; }

escrever_pgbench() { docker compose exec -T banco sh -c "cat > /tmp/$1.sql"; }  # nome < script

FORMATO_PGBENCH='%-7s %-8s %-10s %-7s %12s %14s\n'

medir_pgbench() {  # cenario clientes gatilhos rodada: 10 s de /tmp/<cenario>.sql e uma linha da tabela
  local cenario="$1" clientes="$2" gatilhos="$3" rodada="$4" saida tps latencia
  if [[ $gatilhos == desligados ]]; then desligar_gatilhos; fi
  saida=$(docker compose exec -T banco pgbench -U loja -n -f "/tmp/${cenario}.sql" \
    -c "$clientes" -j "$clientes" -T 10 loja 2>&1)
  if [[ $gatilhos == desligados ]]; then ligar_gatilhos; fi
  tps=$(grep -oP 'tps = \K[0-9.]+' <<<"$saida")
  latencia=$(grep -oP 'latency average = \K[0-9.]+' <<<"$saida")
  printf "$FORMATO_PGBENCH" "$cenario" "$clientes" "$gatilhos" "$rodada" "$tps" "$latencia"
}

medir_ligados_e_desligados() {  # cenario clientes rodada: a ordem inverte a cada rodada
  local ordem gatilhos
  if (( $3 % 2 )); then ordem="ligados desligados"; else ordem="desligados ligados"; fi
  for gatilhos in $ordem; do
    medir_pgbench "$1" "$2" "$gatilhos" "$3"
  done
}

medir_gatilhos() {  # cenario...: 3 rodadas, com 1 e 8 clientes
  # Quem chama define desligar_gatilhos e ligar_gatilhos.
  local rodada cenario clientes
  echo "data: $(date '+%F %T')"
  printf "$FORMATO_PGBENCH" cenario clientes gatilhos rodada tps latencia_ms
  for rodada in 1 2 3; do
    for cenario in "$@"; do
      for clientes in 1 8; do
        medir_ligados_e_desligados "$cenario" "$clientes" "$rodada"
      done
    done
  done
}
