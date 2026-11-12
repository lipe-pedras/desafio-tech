-- 06.2: confere se vendas_por_produto acompanha o recálculo (itens de pedidos não cancelados, por produto)
-- depois de cada tipo de escrita em itens_pedido e em pedidos. Tudo em transações desfeitas (ROLLBACK).
--   docker compose exec -T banco psql -U loja -d loja -X < diagnostico/062-gatilho.sql > diagnostico/062-gatilho.txt
\set ON_ERROR_STOP on
CREATE TEMP VIEW divergencias AS
SELECT count(*) AS produtos_divergentes FROM (
  SELECT i.produto_id, count(*) AS itens, sum(i.quantidade) AS unidades,
         sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
    FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
   WHERE p.status <> 'cancelado' GROUP BY i.produto_id) c
  FULL JOIN (SELECT * FROM vendas_por_produto WHERE itens <> 0 OR unidades <> 0 OR receita_centavos <> 0) t
    USING (produto_id)
 WHERE (c.itens, c.unidades, c.receita_centavos) IS DISTINCT FROM (t.itens, t.unidades, t.receita_centavos);

\echo '=== 0. estado inicial (esperado em todos os passos: 0 produtos divergentes)'
SELECT count(*) AS linhas, sum(itens) AS itens FROM vendas_por_produto;
SELECT * FROM divergencias;

BEGIN;
\echo '=== 1. INSERT de 1000 itens num comando só, em pedidos de todos os status, incluindo um produto que não tinha vendas'
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
SELECT 9000000 + g, 1 + (g * 487) % 500000,
       CASE WHEN g = 1 THEN (SELECT min(id) FROM produtos WHERE id NOT IN (SELECT produto_id FROM vendas_por_produto)) ELSE 1 + (g * 31) % 20000 END,
       1 + g % 5, 1000 + g
  FROM generate_series(1, 1000) g;
SELECT * FROM divergencias;
\echo '=== 2. INSERT de 1 item'
INSERT INTO itens_pedido VALUES (9100001, 1, 1, 3, 4999);
SELECT * FROM divergencias;
\echo '=== 3. UPDATE de itens: quantidade (200), produto (200) e pedido (200, para pedidos cancelados)'
UPDATE itens_pedido SET quantidade = quantidade + 1 WHERE id IN (SELECT id FROM itens_pedido ORDER BY id LIMIT 200);
UPDATE itens_pedido SET produto_id = 1 + (produto_id % 20000) WHERE id IN (SELECT id FROM itens_pedido ORDER BY id DESC LIMIT 200);
UPDATE itens_pedido SET pedido_id = (SELECT min(id) FROM pedidos WHERE status = 'cancelado')
 WHERE id IN (SELECT id FROM itens_pedido ORDER BY id LIMIT 200 OFFSET 1000);
SELECT * FROM divergencias;
\echo '=== 4. UPDATE de status de pedidos: 200 para cancelado, 200 de cancelado para pago, 200 pago -> entregue, 200 só observacoes'
UPDATE pedidos SET status = 'cancelado' WHERE id IN (SELECT id FROM pedidos WHERE status = 'pago' ORDER BY id LIMIT 200);
UPDATE pedidos SET status = 'pago' WHERE id IN (SELECT id FROM pedidos WHERE status = 'cancelado' ORDER BY id DESC LIMIT 200);
UPDATE pedidos SET status = 'entregue' WHERE id IN (SELECT id FROM pedidos WHERE status = 'pago' ORDER BY id DESC LIMIT 200);
UPDATE pedidos SET observacoes = 'alterado' WHERE id IN (SELECT id FROM pedidos ORDER BY id LIMIT 200);
SELECT * FROM divergencias;
\echo '=== 5. DELETE de itens: os 1001 de teste e 300 originais'
DELETE FROM itens_pedido WHERE id > 9000000;
DELETE FROM itens_pedido WHERE id IN (SELECT id FROM itens_pedido WHERE id < 9000000 ORDER BY id LIMIT 300 OFFSET 5000);
SELECT * FROM divergencias;
\echo '=== 6. Pedido novo com 3 itens, cancelado, reaberto, e apagado (itens e pedido)'
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
\echo '=== 7. TRUNCATE de itens_pedido e INSERT de 500 itens depois'
TRUNCATE itens_pedido;
SELECT * FROM divergencias;
INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
SELECT g, 1 + (g * 997) % 500000, 1 + (g * 13) % 20000, 1 + g % 4, 2000 + g FROM generate_series(1, 500) g;
SELECT * FROM divergencias;
ROLLBACK;

\echo '=== 8. depois dos ROLLBACKs'
SELECT * FROM divergencias;

BEGIN;
\echo '=== 9. controle: com os gatilhos de itens_pedido desligados, um INSERT de 1 item (esperado: 1 produto divergente)'
ALTER TABLE itens_pedido DISABLE TRIGGER USER;
INSERT INTO itens_pedido VALUES (9300001, 1, 1, 3, 4999);
SELECT * FROM divergencias;
ROLLBACK;
