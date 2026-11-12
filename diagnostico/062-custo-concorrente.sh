#!/usr/bin/env bash
# 06.2: custo de escrita dos gatilhos de vendas_por_produto com transações independentes e simultâneas
# (pgbench, que vem na imagem do PostgreSQL). Mesmo método de diagnostico/052-custo-concorrente.sh.
# Cada transação é um comando:
#   item:   INSERT de 1 item num pedido sorteado (id do item sorteado acima de 9.000.000; repetido é ignorado);
#   status: UPDATE do status de um pedido sorteado para um status sorteado (entra ou sai de cancelado em parte das vezes).
# Com 1 e com 8 clientes, gatilhos da 06.2 ligados e desligados, alternando a ordem, 3 vezes de 10 s cada.
# Os gatilhos da 05.2 ficam ligados nos dois casos. Banco fixado nos núcleos P, limites inalterados.
# No fim, uma conferência sob disputa: 8 clientes fazendo os dois comandos nos mesmos 100 pedidos.
# ALTERA O BANCO (insere itens e muda pedidos): rodar só num banco descartável e recriá-lo depois (docker compose down -v).
#
#   diagnostico/062-custo-concorrente.sh > diagnostico/062-custo-concorrente.txt
set -euo pipefail

docker update --cpuset-cpus "$(cat /sys/devices/cpu_core/cpus)" "$(docker compose ps -q banco)" >/dev/null
psql() { docker compose exec -T banco psql -U loja -d loja -X -q "$@"; }
desligar() { psql -c 'ALTER TABLE itens_pedido DISABLE TRIGGER USER' -c 'ALTER TABLE pedidos DISABLE TRIGGER vendas_por_produto_status'; }
ligar() { psql -c 'ALTER TABLE itens_pedido ENABLE TRIGGER USER' -c 'ALTER TABLE pedidos ENABLE TRIGGER vendas_por_produto_status'; }

escrever() { docker compose exec -T banco sh -c "cat > /tmp/$1.sql"; }
escrever item <<'EOF2'
\set id random(9000001, 2000000000)
\set p random(1, 500000)
\set pr random(1, 20000)
\set q random(1, 5)
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
VALUES (:id, :p, :pr, :q, 1990) ON CONFLICT (id) DO NOTHING;
EOF2
escrever status <<'EOF2'
\set id random(1, 500000)
\set s random(1, 4)
UPDATE pedidos SET status = (ARRAY['pago','entregue','cancelado','pendente'])[:s] WHERE id = :id;
EOF2
escrever item-disputa <<'EOF2'
\set id random(9000001, 2000000000)
\set p random(1, 100)
\set pr random(1, 20000)
\set q random(1, 5)
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
VALUES (:id, :p, :pr, :q, 1990) ON CONFLICT (id) DO NOTHING;
EOF2
escrever status-disputa <<'EOF2'
\set id random(1, 100)
\set s random(1, 2)
UPDATE pedidos SET status = (ARRAY['pago','cancelado'])[:s] WHERE id = :id;
EOF2

echo "data: $(date '+%F %T')"
printf '%-7s %-8s %-10s %-7s %12s %14s\n' cenario clientes gatilhos rodada tps latencia_ms
for rodada in 1 2 3; do
  for cenario in item status; do
    for clientes in 1 8; do
      if (( rodada % 2 )); then ordem="ligados desligados"; else ordem="desligados ligados"; fi
      for g in $ordem; do
        [[ $g == desligados ]] && desligar
        saida=$(docker compose exec -T banco pgbench -U loja -n -f "/tmp/${cenario}.sql" -c "$clientes" -j "$clientes" -T 10 loja 2>&1)
        [[ $g == desligados ]] && ligar
        tps=$(grep -oP 'tps = \K[0-9.]+' <<<"$saida")
        lat=$(grep -oP 'latency average = \K[0-9.]+' <<<"$saida")
        printf '%-7s %-8s %-10s %-7s %12s %14s\n' "$cenario" "$clientes" "$g" "$rodada" "$tps" "$lat"
      done
    done
  done
done

echo
# As escritas feitas com os gatilhos desligados não entram no total, então ele é recalculado antes da conferência.
echo "conferência sob disputa: total recalculado; 10 s de item e status nos mesmos 100 pedidos, 8 clientes, gatilhos ligados"
psql -c "BEGIN" -c "LOCK TABLE pedidos, itens_pedido" -c "DELETE FROM vendas_por_produto" \
     -c "INSERT INTO vendas_por_produto SELECT i.produto_id, count(*), sum(i.quantidade), sum(i.quantidade * i.preco_unitario_centavos)
           FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id WHERE p.status <> 'cancelado' GROUP BY i.produto_id" -c "COMMIT"
docker compose exec -T banco pgbench -U loja -n -f /tmp/item-disputa.sql -f /tmp/status-disputa.sql -c 8 -j 8 -T 10 --max-tries 20 loja 2>&1 \
  | grep -E 'number of transactions actually processed|number of failed|number of transactions retried|tps =|deadlock|ERROR' || true
echo "produtos com divergência entre vendas_por_produto e o recálculo (esperado: 0)"
psql -c "SELECT count(*) AS produtos_divergentes FROM (
  SELECT i.produto_id, count(*) AS itens, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
    FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id WHERE p.status <> 'cancelado' GROUP BY i.produto_id) c
  FULL JOIN (SELECT * FROM vendas_por_produto WHERE itens <> 0 OR unidades <> 0 OR receita_centavos <> 0) t USING (produto_id)
 WHERE (c.itens, c.unidades, c.receita_centavos) IS DISTINCT FROM (t.itens, t.unidades, t.receita_centavos)"
psql -c "SELECT tgrelid::regclass AS tabela, tgname, tgenabled FROM pg_trigger
 WHERE tgrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass) AND NOT tgisinternal ORDER BY 1, 2"
