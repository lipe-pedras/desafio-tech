-- Índices nas chaves estrangeiras e nos filtros das rotas. Detalhes: experimentos/01-indices.md.

\echo 'Criando índices...'

-- /clientes/:id/pedidos: itens de cada pedido
CREATE INDEX itens_pedido_pedido_id_idx ON itens_pedido (pedido_id);

-- /clientes/:id/pedidos: pedidos do cliente, já na ordem da resposta
CREATE INDEX pedidos_cliente_id_criado_em_idx ON pedidos (cliente_id, criado_em DESC, id DESC);

-- /clientes?email=: índice de expressão para lower(email)
CREATE INDEX clientes_lower_email_idx ON clientes (lower(email));

-- /pedidos?status=&pagina=: filtro por status já na ordem da paginação (também serve ao count)
CREATE INDEX pedidos_status_criado_em_idx ON pedidos (status, criado_em DESC, id DESC);

-- Estatísticas para o índice de expressão
ANALYZE;

\echo 'Índices criados.'
