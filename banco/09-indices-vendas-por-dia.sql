-- Troca dois índices por versões que cobrem a consulta de /relatorios/vendas-por-dia da mudança 09, para ela
-- ler só índices, sem ir às tabelas:
--   itens_pedido (pedido_id), de 03-indices.sql          -> (pedido_id) INCLUDE (quantidade, preco_unitario_centavos)
--   pedidos (criado_em), de 04-indice-pedidos-criado-em.sql -> (criado_em) INCLUDE (id, status)
-- Desde 09-total-vendas-por-dia.sql, a rota lê vendas_por_dia e não usa mais aquela consulta.
-- O VACUUM marca as páginas no mapa de visibilidade já na criação. Detalhes: experimentos/09-vendas-por-dia.md.

\echo 'Trocando os índices de itens_pedido (pedido_id) e pedidos (criado_em) por versões com INCLUDE...'
DROP INDEX itens_pedido_pedido_id_idx;
CREATE INDEX itens_pedido_pedido_id_inc_idx ON itens_pedido (pedido_id) INCLUDE (quantidade, preco_unitario_centavos);
DROP INDEX pedidos_criado_em_idx;
CREATE INDEX pedidos_criado_em_inc_idx ON pedidos (criado_em) INCLUDE (id, status);
VACUUM (ANALYZE) itens_pedido;
VACUUM (ANALYZE) pedidos;
\echo 'Índices trocados.'
