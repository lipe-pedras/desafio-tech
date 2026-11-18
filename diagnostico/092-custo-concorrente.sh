#!/usr/bin/env bash
# 09.2: custo de escrita dos gatilhos de vendas_por_dia com transações independentes e simultâneas
# (pgbench, que vem na imagem do PostgreSQL). Mesmo método de diagnostico/062-custo-concorrente.sh.
# Cada transação é um comando:
#   item:     INSERT de 1 item num pedido sorteado entre todos (os dias se espalham por 731 linhas);
#   item-dia: INSERT de 1 item num pedido sorteado entre os de um dia só (2025-12-31): todas as transações
#             disputam a mesma linha de vendas_por_dia, como pedidos novos de hoje;
#   status:   UPDATE do status de um pedido sorteado (entra ou sai de cancelado em parte das vezes).
# Com 1 e 8 clientes, gatilhos da 09.2 ligados e desligados, alternando a ordem, 3 vezes de 10 s.
# Os gatilhos da 05.2 e da 06.2 ficam ligados nos dois casos. Banco fixado nos núcleos P.
# No fim, uma conferência sob disputa: 8 clientes fazendo item-dia e status nos pedidos desse mesmo dia.
# ALTERA O BANCO (insere itens e muda pedidos): rodar só num banco descartável e recriá-lo depois (docker compose down -v).
#
#   diagnostico/092-custo-concorrente.sh > diagnostico/092-custo-concorrente.txt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GATILHOS_ITENS='vendas_por_dia_insert vendas_por_dia_update vendas_por_dia_delete vendas_por_dia_truncate'

alternar_gatilhos() {  # ENABLE | DISABLE
  local gatilho
  for gatilho in $GATILHOS_ITENS; do
    psql_banco -c "ALTER TABLE itens_pedido $1 TRIGGER $gatilho"
  done
  psql_banco -c "ALTER TABLE pedidos $1 TRIGGER vendas_por_dia_status"
}
desligar_gatilhos() { alternar_gatilhos DISABLE; }
ligar_gatilhos() { alternar_gatilhos ENABLE; }

fixar_banco

escrever_pgbench item <<'EOF'
\set id random(9000001, 2000000000)
\set p random(1, 500000)
\set pr random(1, 20000)
\set q random(1, 5)
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
VALUES (:id, :p, :pr, :q, 1990) ON CONFLICT (id) DO NOTHING;
EOF
escrever_pgbench status <<'EOF'
\set id random(1, 500000)
\set s random(1, 4)
UPDATE pedidos SET status = (ARRAY['pago','entregue','cancelado','pendente'])[:s] WHERE id = :id;
EOF

# Pedidos de um dia só, numerados de 1 a n, para o pgbench sortear.
psql_banco -c "DROP TABLE IF EXISTS pedidos_do_dia" -c "
  CREATE TABLE pedidos_do_dia AS
  SELECT row_number() OVER (ORDER BY id) AS k, id
    FROM pedidos
   WHERE criado_em >= '2025-12-31' AND criado_em < '2026-01-01'" \
  -c "ALTER TABLE pedidos_do_dia ADD PRIMARY KEY (k)"
N=$(psql_banco -Atc "SELECT count(*) FROM pedidos_do_dia")
escrever_pgbench item-dia <<EOF
\\set id random(9000001, 2000000000)
\\set k random(1, $N)
\\set pr random(1, 20000)
\\set q random(1, 5)
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
SELECT :id, id, :pr, :q, 1990 FROM pedidos_do_dia WHERE k = :k ON CONFLICT (id) DO NOTHING;
EOF
escrever_pgbench status-dia <<EOF
\\set k random(1, $N)
\\set s random(1, 2)
UPDATE pedidos SET status = (ARRAY['pago','cancelado'])[:s] WHERE id = (SELECT id FROM pedidos_do_dia WHERE k = :k);
EOF

medir_gatilhos item item-dia status

RECALCULO="
  SELECT p.criado_em::date AS dia, count(DISTINCT p.id) AS pedidos, sum(i.quantidade) AS unidades,
         sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
    FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
   WHERE p.status <> 'cancelado'
   GROUP BY 1"

echo
# As escritas feitas com os gatilhos desligados não entram no total, então ele é recalculado antes da conferência.
echo "conferência sob disputa: total recalculado; 10 s de item-dia e status-dia nos pedidos de 2025-12-31, 8 clientes, gatilhos ligados"
psql_banco -c "BEGIN" -c "LOCK TABLE pedidos, itens_pedido" -c "DELETE FROM vendas_por_dia" \
  -c "INSERT INTO vendas_por_dia $RECALCULO" -c "COMMIT"
docker compose exec -T banco pgbench -U loja -n -f /tmp/item-dia.sql -f /tmp/status-dia.sql \
  -c 8 -j 8 -T 10 --max-tries 20 loja 2>&1 \
  | grep -E 'number of transactions actually processed|number of failed|number of transactions retried|tps =|deadlock|ERROR' \
  || true
echo "dias com divergência entre vendas_por_dia e o recálculo (esperado: 0)"
psql_banco -c "
  SELECT count(*) AS dias_divergentes
    FROM ($RECALCULO) c
    FULL JOIN (SELECT * FROM vendas_por_dia WHERE pedidos <> 0 OR unidades <> 0 OR receita_centavos <> 0) t USING (dia)
   WHERE (c.pedidos, c.unidades, c.receita_centavos) IS DISTINCT FROM (t.pedidos, t.unidades, t.receita_centavos)"
psql_banco -c "
  SELECT tgrelid::regclass AS tabela, tgname, tgenabled FROM pg_trigger
   WHERE tgrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass) AND NOT tgisinternal ORDER BY 1, 2"
