#!/usr/bin/env bash
# 06.1: tempo de CPU que o banco gasta em 10 execuções seguidas de top-produtos (consulta da 06), com
# max_parallel_workers_per_gather = 2 e = 0 (só na sessão), lido do cgroup do container (cpu.stat, usage_usec)
# antes e depois. Inclui os processos auxiliares, que a duração da consulta não mostra. Banco ocioso, 3 rodadas
# alternando a ordem.
#   diagnostico/061-cpu.sh > diagnostico/061-cpu.txt
set -euo pipefail
docker update --cpuset-cpus "$(cat /sys/devices/cpu_core/cpus)" "$(docker compose ps -q banco)" >/dev/null
uso() { docker compose exec -T banco sh -c "grep usage_usec /sys/fs/cgroup/cpu.stat | cut -d' ' -f2"; }
TOP="WITH ranking AS (SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id WHERE p.status <> 'cancelado' GROUP BY i.produto_id ORDER BY receita_centavos DESC, i.produto_id LIMIT 10) SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos FROM ranking r JOIN produtos pr ON pr.id = r.produto_id ORDER BY r.receita_centavos DESC, pr.id"
echo "data: $(date '+%F %T')"
printf '%-7s %-8s %16s %16s\n' rodada workers cpu_ms_por_exec duracao_ms_por_exec
for rodada in 1 2 3; do
  if (( rodada % 2 )); then ordem="2 0"; else ordem="0 2"; fi
  for w in $ordem; do
    sql="SET max_parallel_workers_per_gather = $w; SELECT 1 FROM ($TOP) x LIMIT 0;"
    docker compose exec -T banco psql -U loja -d loja -X -q -o /dev/null -c "$sql" >/dev/null  # aquecimento
    a=$(uso); t0=$(date +%s%N)
    docker compose exec -T banco psql -U loja -d loja -X -q -o /dev/null -c "SET max_parallel_workers_per_gather = $w" \
      -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" \
      -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x" -c "SELECT * FROM ($TOP) x"
    t1=$(date +%s%N); b=$(uso)
    printf '%-7s %-8s %16.1f %16.1f\n' "$rodada" "$w" "$(echo "($b - $a) / 1000 / 10" | bc -l)" "$(echo "($t1 - $t0) / 1000000 / 10" | bc -l)"
  done
done
