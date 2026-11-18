-- Índice em pedidos (criado_em) para o filtro por período de /relatorios/vendas-por-dia (mudança 04.1,
-- experimentos/04-vendas-por-dia.md). Trocado por uma versão com INCLUDE em 09-indices-vendas-por-dia.sql.

\echo 'Criando índice em pedidos (criado_em)...'
CREATE INDEX pedidos_criado_em_idx ON pedidos (criado_em);
ANALYZE pedidos;
\echo 'Índice criado.'
