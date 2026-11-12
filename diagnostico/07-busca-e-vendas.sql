-- 07 (exploração na main depois da 06): planos de busca-produtos e vendas-por-dia, e o efeito de um índice
-- de trigramas (pg_trgm, GIN) na busca. O índice é criado numa transação desfeita: o banco não muda.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/07-busca-e-vendas.sql > diagnostico/07-busca-e-vendas.txt
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
\echo '=== produtos que casam com cada termo da carga'
SELECT t, (SELECT count(*) FROM produtos WHERE nome ILIKE '%' || t || '%') AS produtos
  FROM unnest(ARRAY['cadeira','mesa','lumin','teclado','monitor','ergo','sem fio','portatil','modelo 12','slim','reforcada','webcam']) t;
\echo '=== busca-produtos hoje (termo cadeira)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'cadeira' || '%' ORDER BY nome, id LIMIT 20;
\echo '=== vendas-por-dia hoje (7 dias)'
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-06-01'::date AND p.criado_em < '2024-06-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
BEGIN;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX produtos_nome_trgm_idx ON produtos USING gin (nome gin_trgm_ops);
ANALYZE produtos;
SELECT pg_size_pretty(pg_relation_size('produtos_nome_trgm_idx')) AS indice_trgm;
\echo '=== busca-produtos com índice de trigramas, termos cadeira, ergo e modelo 12'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'cadeira' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'ergo' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'modelo 12' || '%' ORDER BY nome, id LIMIT 20;
ROLLBACK;
