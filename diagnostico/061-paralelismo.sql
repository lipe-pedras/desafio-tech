-- 06.1: planos das consultas de top-produtos (versão da 06) e vendas-por-dia com o paralelismo como está
-- (max_parallel_workers_per_gather = 2) e desligado (= 0, só nesta sessão). Banco ocioso, limite de 1 CPU.
-- Para cada consulta e cada valor: 2 execuções de aquecimento e a 3ª registrada com BUFFERS.
-- Mede a duração de uma consulta isolada; o efeito sob carga (20 usuários, 1 conexão) só o medir.sh mostra.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/061-paralelismo.sql > diagnostico/061-paralelismo.txt
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
\set top 'WITH ranking AS (SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id WHERE p.status <> \'cancelado\' GROUP BY i.produto_id ORDER BY receita_centavos DESC, i.produto_id LIMIT 10) SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos FROM ranking r JOIN produtos pr ON pr.id = r.produto_id ORDER BY r.receita_centavos DESC, pr.id'
\set vendas 'SELECT to_char(p.criado_em::date, \'YYYY-MM-DD\') AS dia, count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos) FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id WHERE p.criado_em >= \'2024-06-01\'::date AND p.criado_em < \'2024-06-07\'::date + 1 AND p.status <> \'cancelado\' GROUP BY p.criado_em::date ORDER BY p.criado_em::date'

\echo '=== top-produtos, max_parallel_workers_per_gather = 2'
SET max_parallel_workers_per_gather = 2;
\o /dev/null
EXPLAIN ANALYZE :top;
EXPLAIN ANALYZE :top;
\o
EXPLAIN (ANALYZE, BUFFERS) :top;
\echo '=== top-produtos, max_parallel_workers_per_gather = 0'
SET max_parallel_workers_per_gather = 0;
\o /dev/null
EXPLAIN ANALYZE :top;
EXPLAIN ANALYZE :top;
\o
EXPLAIN (ANALYZE, BUFFERS) :top;

\echo '=== vendas-por-dia (7 dias), max_parallel_workers_per_gather = 2'
SET max_parallel_workers_per_gather = 2;
\o /dev/null
EXPLAIN ANALYZE :vendas;
EXPLAIN ANALYZE :vendas;
\o
EXPLAIN (ANALYZE, BUFFERS) :vendas;
\echo '=== vendas-por-dia (7 dias), max_parallel_workers_per_gather = 0'
SET max_parallel_workers_per_gather = 0;
\o /dev/null
EXPLAIN ANALYZE :vendas;
EXPLAIN ANALYZE :vendas;
\o
EXPLAIN (ANALYZE, BUFFERS) :vendas;

