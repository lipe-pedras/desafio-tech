-- Diagnóstico da 04: /relatorios/vendas-por-dia, período de 7 dias (o que a carga pede).
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/04-vendas-por-dia.sql > diagnostico/04-vendas-por-dia.txt
-- Banco com os índices da 01, banco ocioso. Cada consulta roda 1 vez para aquecer e depois com EXPLAIN ANALYZE.

\echo '=== volume: pedidos por dia (média) e itens por pedido'
SELECT count(*) / 731.0 AS pedidos_por_dia, (SELECT count(*) FROM itens_pedido) / count(*)::numeric AS itens_por_pedido FROM pedidos;

\echo '=== A. consulta atual: criado_em::date BETWEEN, traz observacoes, agrega na API'
SELECT count(*) FROM (SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em::date BETWEEN '2024-01-01' AND '2024-01-07' AND p.status <> 'cancelado') x;
EXPLAIN (ANALYZE, BUFFERS) SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em::date BETWEEN '2024-01-01' AND '2024-01-07' AND p.status <> 'cancelado';

\echo '=== tamanho médio de observacoes (bytes)'
SELECT avg(octet_length(observacoes))::int AS media_bytes FROM pedidos;

\echo '=== B. candidata: intervalo em criado_em (sem cast) e agregação no banco'
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD') AS dia, count(DISTINCT p.id) AS pedidos,
       sum(i.quantidade) AS itens, sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-01-01'::date AND p.criado_em < '2024-01-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY 1 ORDER BY 1;

\echo '=== C. candidata B com um índice em pedidos (criado_em), criado só dentro de uma transação desfeita'
BEGIN;
CREATE INDEX diag_pedidos_criado_em_idx ON pedidos (criado_em);
ANALYZE pedidos;
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD') AS dia, count(DISTINCT p.id) AS pedidos,
       sum(i.quantidade) AS itens, sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-01-01'::date AND p.criado_em < '2024-01-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY 1 ORDER BY 1;
ROLLBACK;
