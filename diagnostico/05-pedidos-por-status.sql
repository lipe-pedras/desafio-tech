-- Diagnóstico da 05: /pedidos?status=&pagina= (a carga sorteia o status e a página de 1 a 1000).
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/05-pedidos-por-status.sql > diagnostico/05-pedidos-por-status.txt
-- Banco da main (índices da 01 e da 04.1), ocioso, depois do autovacuum (o estado em que as medições acontecem).
-- Cada consulta roda 1 vez para aquecer e depois com EXPLAIN ANALYZE. Status 'pago' (o maior).

\echo '=== estado: pedidos por status, páginas visíveis (relallvisible/relpages) e último vacuum'
SELECT status, count(*) FROM pedidos GROUP BY 1 ORDER BY 1;
SELECT relname, relallvisible, relpages FROM pg_class WHERE relname = 'pedidos';
SELECT relname, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze FROM pg_stat_user_tables WHERE relname = 'pedidos';

\echo '=== A1. contagem atual (status pago)'
SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS total FROM pedidos WHERE status = 'pago';

\echo '=== A2. página atual: SELECT *, pagina 1, 500 e 1000 (OFFSET 0, 9980 e 19980)'
SELECT count(*) FROM (SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980) x;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 0;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 9980;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;

\echo '=== B. candidata 05: só as 4 colunas usadas, pagina 1000'
EXPLAIN (ANALYZE, BUFFERS) SELECT id, cliente_id, status, criado_em FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;

\echo '=== C. candidata 05.1: B com o índice incluindo cliente_id, criado só dentro de uma transação desfeita'
BEGIN;
CREATE INDEX diag_pedidos_status_criado_em_inc_idx ON pedidos (status, criado_em DESC, id DESC) INCLUDE (cliente_id);
ANALYZE pedidos;
SELECT id, cliente_id, status, criado_em FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, cliente_id, status, criado_em FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 0;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, cliente_id, status, criado_em FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
SELECT pg_size_pretty(pg_relation_size('diag_pedidos_status_criado_em_inc_idx')) AS indice_novo,
       pg_size_pretty(pg_relation_size('pedidos_status_criado_em_idx')) AS indice_da_01;
ROLLBACK;
