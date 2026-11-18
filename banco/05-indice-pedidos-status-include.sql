-- Troca o índice de pedidos (status, criado_em DESC, id DESC), de 03-indices.sql, por um igual que inclui
-- cliente_id: com as colunas que /pedidos?status= pede, a página é lida só do índice (Index Only Scan).
-- O VACUUM marca as páginas no mapa de visibilidade já na criação; sem ele, a leitura ainda vai à tabela
-- até o autovacuum passar. Detalhes: experimentos/05-pedidos-por-status.md (mudança 05.1).

\echo 'Trocando o índice de pedidos (status, criado_em, id) por um que inclui cliente_id...'
DROP INDEX pedidos_status_criado_em_idx;
CREATE INDEX pedidos_status_criado_em_inc_idx ON pedidos (status, criado_em DESC, id DESC) INCLUDE (cliente_id);
VACUUM (ANALYZE) pedidos;
\echo 'Índice trocado.'
