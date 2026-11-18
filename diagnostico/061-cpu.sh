#!/usr/bin/env bash
# 06.1: tempo de CPU que o banco gasta em 10 execuções seguidas de top-produtos (consulta da 06), com
# max_parallel_workers_per_gather = 2 e = 0 (só na sessão), lido do cgroup do container (cpu.stat, usage_usec)
# antes e depois. Inclui os processos auxiliares, que a duração da consulta não mostra. Banco ocioso, 3 rodadas
# alternando a ordem.
#   diagnostico/061-cpu.sh > diagnostico/061-cpu.txt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXECUCOES=10
TOP="
  WITH ranking AS (
    SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
      FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
     WHERE p.status <> 'cancelado'
     GROUP BY i.produto_id
     ORDER BY receita_centavos DESC, i.produto_id
     LIMIT 10
  )
  SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos
    FROM ranking r JOIN produtos pr ON pr.id = r.produto_id
   ORDER BY r.receita_centavos DESC, pr.id"

uso_cpu_us() { docker compose exec -T banco sh -c "grep usage_usec /sys/fs/cgroup/cpu.stat | cut -d' ' -f2"; }
psql_silencioso() { docker compose exec -T banco psql -U loja -d loja -X -q -o /dev/null "$@" >/dev/null; }

medir_workers() {  # rodada workers
  local workers="$2" consultas=() antes depois t0 t1 i
  for (( i = 0; i < EXECUCOES; i++ )); do consultas+=(-c "SELECT * FROM ($TOP) x"); done
  psql_silencioso -c "SET max_parallel_workers_per_gather = $workers; SELECT 1 FROM ($TOP) x LIMIT 0;"  # aquecimento
  antes=$(uso_cpu_us); t0=$(date +%s%N)
  psql_silencioso -c "SET max_parallel_workers_per_gather = $workers" "${consultas[@]}"
  t1=$(date +%s%N); depois=$(uso_cpu_us)
  printf '%-7s %-8s %16.1f %16.1f\n' "$1" "$workers" \
    "$(echo "($depois - $antes) / 1000 / $EXECUCOES" | bc -l)" "$(echo "($t1 - $t0) / 1000000 / $EXECUCOES" | bc -l)"
}

fixar_banco
echo "data: $(date '+%F %T')"
printf '%-7s %-8s %16s %16s\n' rodada workers cpu_ms_por_exec duracao_ms_por_exec
for rodada in 1 2 3; do
  if (( rodada % 2 )); then ordem="2 0"; else ordem="0 2"; fi
  for workers in $ordem; do
    medir_workers "$rodada" "$workers"
  done
done
