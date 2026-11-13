-- 09.2: confere se vendas_por_dia acompanha o recálculo (pedidos não cancelados com itens, unidades e receita,
-- por dia) depois de cada tipo de escrita em itens_pedido e em pedidos. Tudo em transações desfeitas (ROLLBACK).
-- Mesmo roteiro de diagnostico/062-gatilho.sql, mais mudanças de data (criado_em) de pedidos.
--   docker compose exec -T banco psql -U loja -d loja -X < diagnostico/092-gatilho.sql > diagnostico/092-gatilho.txt
\set ON_ERROR_STOP on
CREATE TEMP VIEW divergencias AS
SELECT count(*) AS dias_divergentes FROM (
  SELECT p.criado_em::date AS dia, count(DISTINCT p.id) AS pedidos, sum(i.quantidade) AS unidades,
         sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
    FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
   WHERE p.status <> 'cancelado' GROUP BY 1) c
  FULL JOIN (SELECT * FROM vendas_por_dia WHERE pedidos <> 0 OR unidades <> 0 OR receita_centavos <> 0) t
    USING (dia)
 WHERE (c.pedidos, c.unidades, c.receita_centavos) IS DISTINCT FROM (t.pedidos, t.unidades, t.receita_centavos);

\echo '=== 0. estado inicial (esperado em todos os passos: 0 dias divergentes)'
SELECT count(*) AS linhas, sum(pedidos) AS pedidos, sum(unidades) AS unidades FROM vendas_por_dia;
SELECT * FROM divergencias;

BEGIN;
\echo '=== 1. INSERT de 1000 itens num comando só, em pedidos de todos os status (alguns pedidos sem itens antes)'
INSERT INTO pedidos (id, cliente_id, status, criado_em, observacoes)
SELECT 1100000 + g, 1, (ARRAY['pago','cancelado','pendente','entregue'])[1 + g % 4], '2024-03-01'::date + g % 9 + interval '1 hour', 't'
  FROM generate_series(1, 40) g;
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
SELECT 9000000 + g, CASE WHEN g <= 80 THEN 1100001 + g % 40 ELSE 1 + (g * 487) % 500000 END,
       1 + (g * 31) % 20000, 1 + g % 5, 1000 + g
  FROM generate_series(1, 1000) g;
SELECT * FROM divergencias;
\echo '=== 2. INSERT de 1 item'
INSERT INTO itens_pedido VALUES (9100001, 1, 1, 3, 4999);
SELECT * FROM divergencias;
\echo '=== 3. UPDATE de itens: quantidade (200), preço (200) e pedido (200, para pedidos cancelados e para um pedido sem itens)'
UPDATE itens_pedido SET quantidade = quantidade + 1 WHERE id IN (SELECT id FROM itens_pedido ORDER BY id LIMIT 200);
UPDATE itens_pedido SET preco_unitario_centavos = preco_unitario_centavos + 7 WHERE id IN (SELECT id FROM itens_pedido ORDER BY id DESC LIMIT 200);
UPDATE itens_pedido SET pedido_id = (SELECT min(id) FROM pedidos WHERE status = 'cancelado')
 WHERE id IN (SELECT id FROM itens_pedido ORDER BY id LIMIT 200 OFFSET 1000);
INSERT INTO pedidos VALUES (1150000, 1, 'pago', '2025-05-05 10:00', 't');
UPDATE itens_pedido SET pedido_id = 1150000 WHERE id IN (SELECT id FROM itens_pedido ORDER BY id LIMIT 3 OFFSET 2000);
SELECT * FROM divergencias;
\echo '=== 4. UPDATE de pedidos: 200 para cancelado, 200 de cancelado para pago, 200 pago -> entregue, 200 só observacoes'
UPDATE pedidos SET status = 'cancelado' WHERE id IN (SELECT id FROM pedidos WHERE status = 'pago' ORDER BY id LIMIT 200);
UPDATE pedidos SET status = 'pago' WHERE id IN (SELECT id FROM pedidos WHERE status = 'cancelado' ORDER BY id DESC LIMIT 200);
UPDATE pedidos SET status = 'entregue' WHERE id IN (SELECT id FROM pedidos WHERE status = 'pago' ORDER BY id DESC LIMIT 200);
UPDATE pedidos SET observacoes = 'alterado' WHERE id IN (SELECT id FROM pedidos ORDER BY id LIMIT 200);
SELECT * FROM divergencias;
\echo '=== 5. UPDATE de data: 200 pedidos mudam de dia, 200 mudam de hora no mesmo dia, 100 cancelados mudam de dia e 100 mudam de dia e são cancelados'
UPDATE pedidos SET criado_em = criado_em + interval '3 days' WHERE id IN (SELECT id FROM pedidos ORDER BY id LIMIT 200 OFFSET 300);
UPDATE pedidos SET criado_em = date_trunc('day', criado_em) + interval '1 minute' WHERE id IN (SELECT id FROM pedidos ORDER BY id LIMIT 200 OFFSET 600);
UPDATE pedidos SET criado_em = criado_em - interval '10 days' WHERE id IN (SELECT id FROM pedidos WHERE status = 'cancelado' ORDER BY id LIMIT 100);
UPDATE pedidos SET criado_em = criado_em + interval '1 day', status = 'cancelado' WHERE id IN (SELECT id FROM pedidos WHERE status <> 'cancelado' ORDER BY id LIMIT 100 OFFSET 900);
SELECT * FROM divergencias;
\echo '=== 6. DELETE de itens: os de teste e 300 originais (alguns pedidos ficam sem itens)'
DELETE FROM itens_pedido WHERE id > 9000000;
DELETE FROM itens_pedido WHERE id IN (SELECT id FROM itens_pedido WHERE id < 9000000 ORDER BY id LIMIT 300 OFFSET 5000);
SELECT * FROM divergencias;
\echo '=== 7. Pedido novo hoje com 3 itens, cancelado, reaberto, e apagado (itens e pedido)'
INSERT INTO pedidos VALUES (1200001, 1, 'pendente', now(), 'teste');
INSERT INTO itens_pedido VALUES (9200001, 1200001, 10, 2, 500), (9200002, 1200001, 11, 1, 700), (9200003, 1200001, 10, 1, 500);
SELECT * FROM divergencias;
UPDATE pedidos SET status = 'cancelado' WHERE id = 1200001;
SELECT * FROM divergencias;
UPDATE pedidos SET status = 'pago' WHERE id = 1200001;
SELECT * FROM divergencias;
DELETE FROM itens_pedido WHERE pedido_id = 1200001;
DELETE FROM pedidos WHERE id = 1200001;
SELECT * FROM divergencias;
ROLLBACK;

BEGIN;
\echo '=== 8. TRUNCATE de itens_pedido e INSERT de 500 itens depois'
TRUNCATE itens_pedido;
SELECT * FROM divergencias;
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
SELECT g, 1 + (g * 997) % 500000, 1 + (g * 13) % 20000, 1 + g % 4, 2000 + g FROM generate_series(1, 500) g;
SELECT * FROM divergencias;
ROLLBACK;

\echo '=== 9. depois dos ROLLBACKs'
SELECT * FROM divergencias;

BEGIN;
\echo '=== 10. controle: com os gatilhos de vendas_por_dia desligados, um INSERT de 1 item (esperado: 1 dia divergente)'
ALTER TABLE itens_pedido DISABLE TRIGGER vendas_por_dia_insert;
INSERT INTO itens_pedido VALUES (9300001, 1, 1, 3, 4999);
SELECT * FROM divergencias;
ROLLBACK;
