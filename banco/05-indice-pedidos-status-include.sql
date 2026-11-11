-- Mudança 05.1: troca o índice de pedidos (status, criado_em DESC, id DESC), criado na 01, por um igual
-- que inclui cliente_id. Com a consulta da 05 (só id, cliente_id, status, criado_em), a página e as linhas
-- puladas pelo OFFSET passam a ser lidas só do índice (Index Only Scan), sem ir à tabela.
-- 05.1 com VACUUM: VACUUM (ANALYZE) em vez de só ANALYZE, para marcar as páginas de pedidos no mapa de visibilidade
-- já na criação do banco, sem esperar o autovacuum. Evidência: diagnostico/051-vacuum.txt.
-- O índice novo tem o mesmo tamanho do antigo (21 MB). Evidência: diagnostico/05-pedidos-por-status.txt (seção C).

\echo 'Trocando o índice de pedidos (status, criado_em, id) por um que inclui cliente_id...'
DROP INDEX pedidos_status_criado_em_idx;
CREATE INDEX pedidos_status_criado_em_inc_idx ON pedidos (status, criado_em DESC, id DESC) INCLUDE (cliente_id);
VACUUM (ANALYZE) pedidos;
\echo 'Índice trocado.'
