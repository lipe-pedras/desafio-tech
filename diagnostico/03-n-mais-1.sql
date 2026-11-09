-- Diagnóstico da mudança 03 (N+1 de GET /clientes/:id/pedidos).
-- docker compose exec -T banco psql -U loja -d loja < diagnostico/03-n-mais-1.sql

\echo '== Consultas por requisição no código antigo: 2 + pedidos + itens, por cliente com pedidos'
WITH por_cliente AS (
  SELECT p.cliente_id, count(DISTINCT p.id) AS pedidos, count(i.id) AS itens
    FROM pedidos p LEFT JOIN itens_pedido i ON i.pedido_id = p.id
   GROUP BY p.cliente_id
)
SELECT count(*) AS clientes_com_pedidos,
       round(avg(pedidos), 1) AS pedidos_media,
       round(avg(itens), 1) AS itens_media,
       round(avg(2 + pedidos + itens), 1) AS consultas_media,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY 2 + pedidos + itens) AS consultas_mediana,
       percentile_disc(0.95) WITHIN GROUP (ORDER BY 2 + pedidos + itens) AS consultas_p95,
       max(2 + pedidos + itens) AS consultas_max
  FROM por_cliente;

\echo '== Plano da consulta única (cliente 31337)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id AS pedido_id, p.status, p.criado_em, i.produto_id, pr.nome AS produto_nome,
       i.quantidade, i.preco_unitario_centavos
  FROM pedidos p
  LEFT JOIN itens_pedido i ON i.pedido_id = p.id
  LEFT JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.cliente_id = 31337
 ORDER BY p.criado_em DESC, p.id DESC, i.id;
