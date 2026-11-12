-- 05.2: confere se pedidos_por_status acompanha count(*) por status depois de cada tipo de escrita.
-- Tudo dentro de transações desfeitas (ROLLBACK): o banco não muda.
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/052-gatilho.sql > diagnostico/052-gatilho.txt
\set ON_ERROR_STOP on
CREATE TEMP VIEW divergencias AS
SELECT coalesce(c.status, t.status) AS status, c.n AS contado, t.total AS na_tabela
  FROM (SELECT status, count(*) AS n FROM pedidos GROUP BY status) c
  FULL JOIN (SELECT status, total FROM pedidos_por_status WHERE total <> 0) t ON t.status = c.status
 WHERE c.n IS DISTINCT FROM t.total;

\echo '=== 0. estado inicial: divergências (esperado: nenhuma linha)'
SELECT * FROM pedidos_por_status ORDER BY status;
SELECT * FROM divergencias;

BEGIN;
\echo '=== 1. INSERT de 1000 pedidos num comando só, nos 4 status e num status novo (devolvido)'
INSERT INTO pedidos (id, cliente_id, status, criado_em, observacoes)
SELECT 1000000 + i, 1 + i % 100000, (ARRAY['pago','entregue','cancelado','pendente','devolvido'])[1 + i % 5], now(), 'teste'
  FROM generate_series(1, 1000) AS i;
SELECT * FROM divergencias;
\echo '=== 2. INSERT de 1 pedido'
INSERT INTO pedidos VALUES (1100001, 1, 'pago', now(), 'teste');
SELECT * FROM divergencias;
\echo '=== 3. UPDATE de status de 500 pedidos (pago -> entregue) e de 200 (pendente -> pendente, sem mudança)'
UPDATE pedidos SET status = 'entregue' WHERE id IN (SELECT id FROM pedidos WHERE status = 'pago' ORDER BY id LIMIT 500);
UPDATE pedidos SET status = 'pendente' WHERE id IN (SELECT id FROM pedidos WHERE status = 'pendente' ORDER BY id LIMIT 200);
SELECT * FROM divergencias;
\echo '=== 4. UPDATE de outra coluna (observacoes) de 300 pedidos'
UPDATE pedidos SET observacoes = 'alterado' WHERE id IN (SELECT id FROM pedidos ORDER BY id LIMIT 300);
SELECT * FROM divergencias;
\echo '=== 5. DELETE dos 1001 pedidos de teste'
DELETE FROM pedidos WHERE id > 1000000;
SELECT * FROM divergencias;
SELECT * FROM pedidos_por_status ORDER BY status;
ROLLBACK;

BEGIN;
\echo '=== 6. TRUNCATE (com itens_pedido, por causa da chave estrangeira) e INSERT depois'
TRUNCATE pedidos CASCADE;
SELECT * FROM divergencias;
INSERT INTO pedidos VALUES (1, 1, 'pago', now(), 'teste');
SELECT * FROM divergencias;
ROLLBACK;

\echo '=== 7. depois dos ROLLBACKs: divergências (esperado: nenhuma linha)'
SELECT * FROM pedidos_por_status ORDER BY status;
SELECT * FROM divergencias;
