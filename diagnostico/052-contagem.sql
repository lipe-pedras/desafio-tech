-- 05.2: a contagem antiga (com o índice da 05.1) contra a leitura do total em pedidos_por_status, status pago.
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/052-contagem.sql > diagnostico/052-contagem.txt
-- Banco da 05.2 recém-criado, ocioso. Cada consulta roda 1 vez para aquecer e depois com EXPLAIN ANALYZE.
\echo '=== antes: count(*) no índice'
SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
\echo '=== 05.2: total em pedidos_por_status'
SELECT coalesce((SELECT total FROM pedidos_por_status WHERE status = 'pago'), 0) AS total;
EXPLAIN (ANALYZE, BUFFERS) SELECT coalesce((SELECT total FROM pedidos_por_status WHERE status = 'pago'), 0) AS total;
\echo '=== tamanho de pedidos_por_status'
SELECT pg_size_pretty(pg_total_relation_size('pedidos_por_status')) AS tabela_com_indice;
