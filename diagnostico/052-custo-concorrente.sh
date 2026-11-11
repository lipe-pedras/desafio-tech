#!/usr/bin/env bash
# 05.2: custo de escrita dos gatilhos de pedidos_por_status com transações independentes e simultâneas (pgbench,
# que vem na imagem do PostgreSQL). Complementa diagnostico/052-custo-escrita.sql, que roda tudo numa transação só.
# Cada transação é um comando de 1 pedido:
#   insert: INSERT de um pedido novo (id sorteado acima de 1.000.000; repetido é ignorado);
#   update: UPDATE do status de um pedido existente para um status sorteado.
# Com 1 e com 8 clientes, gatilhos ligados e desligados (ALTER TABLE ... DISABLE/ENABLE TRIGGER USER),
# alternando a ordem, 3 vezes de 10 s cada. Banco fixado nos núcleos P, limites inalterados.
# ALTERA O BANCO (insere e muda pedidos): rodar só num banco descartável e recriá-lo depois (docker compose down -v).
#
#   diagnostico/052-custo-concorrente.sh > diagnostico/052-custo-concorrente.txt
set -euo pipefail

docker update --cpuset-cpus "$(cat /sys/devices/cpu_core/cpus)" "$(docker compose ps -q banco)" >/dev/null
psql() { docker compose exec -T banco psql -U loja -d loja -X -q "$@"; }

docker compose exec -T banco sh -c 'cat > /tmp/insert.sql' <<'EOF'
\set id random(1000001, 2000000000)
\set c random(1, 100000)
\set s random(1, 4)
INSERT INTO pedidos (id, cliente_id, status, criado_em, observacoes)
VALUES (:id, :c, (ARRAY['pago','entregue','cancelado','pendente'])[:s], now(), 'pgbench') ON CONFLICT (id) DO NOTHING;
EOF
docker compose exec -T banco sh -c 'cat > /tmp/update.sql' <<'EOF'
\set id random(1, 500000)
\set s random(1, 4)
UPDATE pedidos SET status = (ARRAY['pago','entregue','cancelado','pendente'])[:s] WHERE id = :id;
EOF

echo "data: $(date '+%F %T')"
printf '%-7s %-8s %-10s %-7s %12s %14s\n' cenario clientes gatilhos rodada tps latencia_ms
for rodada in 1 2 3; do
  for cenario in insert update; do
    for clientes in 1 8; do
      if (( rodada % 2 )); then ordem="ligados desligados"; else ordem="desligados ligados"; fi
      for g in $ordem; do
        [[ $g == desligados ]] && psql -c 'ALTER TABLE pedidos DISABLE TRIGGER USER'
        saida=$(docker compose exec -T banco pgbench -U loja -n -f "/tmp/${cenario}.sql" -c "$clientes" -j "$clientes" -T 10 loja 2>&1)
        [[ $g == desligados ]] && psql -c 'ALTER TABLE pedidos ENABLE TRIGGER USER'
        tps=$(grep -oP 'tps = \K[0-9.]+' <<<"$saida")
        lat=$(grep -oP 'latency average = \K[0-9.]+' <<<"$saida")
        printf '%-7s %-8s %-10s %-7s %12s %14s\n' "$cenario" "$clientes" "$g" "$rodada" "$tps" "$lat"
      done
    done
  done
done

echo
# As escritas feitas com os gatilhos desligados não entram no total, então ele é recalculado antes da conferência.
echo "conferência sob concorrência: total recalculado; 10 s de insert e update juntos, 8 clientes, gatilhos ligados"
psql -c "BEGIN" -c "LOCK TABLE pedidos" -c "DELETE FROM pedidos_por_status" \
     -c "INSERT INTO pedidos_por_status SELECT status, count(*) FROM pedidos GROUP BY status" -c "COMMIT"
docker compose exec -T banco pgbench -U loja -n -f /tmp/insert.sql -f /tmp/update.sql -c 8 -j 8 -T 10 loja 2>&1 \
  | grep -E 'number of transactions actually processed|number of failed|tps ='
echo "divergências entre pedidos_por_status e count(*) (esperado: 0 linhas)"
psql -c "SELECT coalesce(c.status, t.status) AS status, c.n AS contado, t.total AS na_tabela
  FROM (SELECT status, count(*) AS n FROM pedidos GROUP BY status) c
  FULL JOIN (SELECT status, total FROM pedidos_por_status WHERE total <> 0) t ON t.status = c.status
 WHERE c.n IS DISTINCT FROM t.total"
psql -c "SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'pedidos'::regclass AND NOT tgisinternal ORDER BY tgname"
