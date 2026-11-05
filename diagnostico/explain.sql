\echo '=== /clientes/:id'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM clientes WHERE id = 31337;
\echo '=== /clientes?email='
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM clientes WHERE lower(email) = lower('cliente3@exemplo.com') ORDER BY id;
\echo '=== /clientes/:id/pedidos (pedidos do cliente)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE cliente_id = 31337 ORDER BY criado_em DESC, id DESC;
\echo '=== /clientes/:id/pedidos (itens de UM pedido; roda 1x por pedido)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM itens_pedido WHERE pedido_id = 12345 ORDER BY id;
\echo '=== /clientes/:id/pedidos (produto de UM item; roda 1x por item)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE id = 10061;
\echo '=== /pedidos (contagem)'
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
\echo '=== /pedidos (pagina 500)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 9980;
\echo '=== /produtos/busca'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'cadeira' || '%' ORDER BY nome, id LIMIT 20;
\echo '=== /relatorios/vendas-por-dia (7 dias)'
EXPLAIN (ANALYZE, BUFFERS) SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em::date BETWEEN '2024-01-01' AND '2024-01-07' AND p.status <> 'cancelado';
\echo '=== /relatorios/top-produtos'
EXPLAIN (ANALYZE, BUFFERS) SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria ORDER BY receita_centavos DESC, pr.id LIMIT 10;
\echo '=== índices existentes'
SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1;
\echo '=== tamanho das tabelas'
SELECT relname, pg_size_pretty(pg_total_relation_size(oid)) FROM pg_class WHERE relname IN ('clientes','produtos','pedidos','itens_pedido');
\echo '=== configuração relevante'
SHOW shared_buffers; SHOW work_mem; SHOW max_connections;
SELECT count(*) AS pedidos_cliente_31337 FROM pedidos WHERE cliente_id = 31337;
