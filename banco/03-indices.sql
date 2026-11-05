-- Mudança 01: índices para os filtros que hoje fazem Seq Scan (ver diagnostico/explain-linha-de-base.txt).
-- Hipótese: com índice nas chaves estrangeiras e nos filtros das rotas, o banco deixa de ler tabelas
-- inteiras a cada consulta, sai da saturação de CPU e o p95 geral e as requisições/s melhoram muito.

\echo 'Criando índices...'

-- /clientes/:id/pedidos: itens de cada pedido (hoje lê 1,5 milhão de linhas por pedido)
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
