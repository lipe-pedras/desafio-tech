-- Diagnóstico da 04.1: tamanho do índice novo e plano da consulta da 04 com ele. Banco criado do zero com banco/04-*.sql.
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/041-indice-criado-em.sql > diagnostico/041-indice-criado-em.txt
\echo '=== tamanho do índice novo e da tabela pedidos'
SELECT 'pedidos_criado_em_idx' AS relacao, pg_size_pretty(pg_relation_size('pedidos_criado_em_idx')) AS tamanho, pg_relation_size('pedidos_criado_em_idx') AS bytes
UNION ALL SELECT 'pedidos (tabela)', pg_size_pretty(pg_relation_size('pedidos')), pg_relation_size('pedidos');
\echo '=== consulta da 04, 7 dias (aquecida por 1 execução antes)'
SELECT count(*) FROM pedidos WHERE criado_em >= '2024-01-01'::date AND criado_em < '2024-01-07'::date + 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD') AS dia, count(DISTINCT p.id) AS pedidos,
       sum(i.quantidade) AS itens, sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-01-01'::date AND p.criado_em < '2024-01-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
