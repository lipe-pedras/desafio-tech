-- Mudança 04.1: índice em pedidos (criado_em) para /relatorios/vendas-por-dia.
-- Hipótese: com o filtro por intervalo da mudança 04, o banco deixa de ler os 500 mil pedidos (Seq Scan)
-- e lê só os do período (cerca de 4.800 em 7 dias), o que libera CPU do banco para as outras rotas.
-- Evidência: diagnostico/04-vendas-por-dia.txt (seção C).

\echo 'Criando índice em pedidos (criado_em)...'
CREATE INDEX pedidos_criado_em_idx ON pedidos (criado_em);
ANALYZE pedidos;
\echo 'Índice criado.'
