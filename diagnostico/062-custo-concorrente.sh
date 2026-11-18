#!/usr/bin/env bash
# 06.2: custo de escrita dos gatilhos de vendas_por_produto com transações independentes e simultâneas
# (pgbench, que vem na imagem do PostgreSQL). Mesmo método de diagnostico/052-custo-concorrente.sh.
# Cada transação é um comando:
#   item:   INSERT de 1 item num pedido sorteado (id do item sorteado acima de 9.000.000; repetido é ignorado);
#   status: UPDATE do status de um pedido sorteado (entra ou sai de cancelado em parte das vezes).
# Com 1 e 8 clientes, gatilhos da 06.2 ligados e desligados, alternando a ordem, 3 vezes de 10 s.
# Os gatilhos da 05.2 ficam ligados nos dois casos. Banco fixado nos núcleos P.
# No fim, uma conferência sob disputa: 8 clientes fazendo os dois comandos nos mesmos 100 pedidos.
# ALTERA O BANCO (insere itens e muda pedidos): rodar só num banco descartável e recriá-lo depois (docker compose down -v).
#
#   diagnostico/062-custo-concorrente.sh > diagnostico/062-custo-concorrente.txt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

desligar_gatilhos() {
  psql_banco -c 'ALTER TABLE itens_pedido DISABLE TRIGGER USER' \
             -c 'ALTER TABLE pedidos DISABLE TRIGGER vendas_por_produto_status'
}
ligar_gatilhos() {
  psql_banco -c 'ALTER TABLE itens_pedido ENABLE TRIGGER USER' \
             -c 'ALTER TABLE pedidos ENABLE TRIGGER vendas_por_produto_status'
}

escrever_item() {  # nome maior_pedido: INSERT de 1 item num pedido sorteado entre 1 e maior_pedido
  escrever_pgbench "$1" <<EOF
\\set id random(9000001, 2000000000)
\\set p random(1, $2)
\\set pr random(1, 20000)
\\set q random(1, 5)
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
VALUES (:id, :p, :pr, :q, 1990) ON CONFLICT (id) DO NOTHING;
EOF
}

fixar_banco

escrever_item item 500000
escrever_item item-disputa 100
escrever_pgbench status <<'EOF'
\set id random(1, 500000)
\set s random(1, 4)
UPDATE pedidos SET status = (ARRAY['pago','entregue','cancelado','pendente'])[:s] WHERE id = :id;
EOF
escrever_pgbench status-disputa <<'EOF'
\set id random(1, 100)
\set s random(1, 2)
UPDATE pedidos SET status = (ARRAY['pago','cancelado'])[:s] WHERE id = :id;
EOF

medir_gatilhos item status

echo
# As escritas feitas com os gatilhos desligados não entram no total, então ele é recalculado antes da conferência.
echo "conferência sob disputa: total recalculado; 10 s de item e status nos mesmos 100 pedidos, 8 clientes, gatilhos ligados"
psql_banco -c "BEGIN" -c "LOCK TABLE pedidos, itens_pedido" -c "DELETE FROM vendas_por_produto" -c "
  INSERT INTO vendas_por_produto
  SELECT i.produto_id, count(*), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
    FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
   WHERE p.status <> 'cancelado'
   GROUP BY i.produto_id" -c "COMMIT"
docker compose exec -T banco pgbench -U loja -n -f /tmp/item-disputa.sql -f /tmp/status-disputa.sql \
  -c 8 -j 8 -T 10 --max-tries 20 loja 2>&1 \
  | grep -E 'number of transactions actually processed|number of failed|number of transactions retried|tps =|deadlock|ERROR' \
  || true
echo "produtos com divergência entre vendas_por_produto e o recálculo (esperado: 0)"
psql_banco -c "
  SELECT count(*) AS produtos_divergentes
    FROM (SELECT i.produto_id, count(*) AS itens, sum(i.quantidade) AS unidades,
                 sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
            FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
           WHERE p.status <> 'cancelado'
           GROUP BY i.produto_id) c
    FULL JOIN (SELECT * FROM vendas_por_produto WHERE itens <> 0 OR unidades <> 0 OR receita_centavos <> 0) t
         USING (produto_id)
   WHERE (c.itens, c.unidades, c.receita_centavos) IS DISTINCT FROM (t.itens, t.unidades, t.receita_centavos)"
psql_banco -c "
  SELECT tgrelid::regclass AS tabela, tgname, tgenabled FROM pg_trigger
   WHERE tgrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass) AND NOT tgisinternal ORDER BY 1, 2"
