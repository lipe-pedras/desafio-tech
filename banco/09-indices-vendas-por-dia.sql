-- Mudança 09 (versão conservadora): troca dois índices por versões que cobrem a consulta de
-- /relatorios/vendas-por-dia, para que ela leia só índices (Index Only Scan), sem ir às tabelas:
--   itens_pedido (pedido_id), da 01       -> (pedido_id) INCLUDE (quantidade, preco_unitario_centavos)
--   pedidos (criado_em), da 04.1          -> (criado_em) INCLUDE (id, status)
-- Hoje a rota lê cerca de 4.300 pedidos e 13 mil itens por chamada direto das tabelas (235 MB juntas), que
-- não cabem nos 128 MB de shared_buffers. Os dois índices novos somam 64 MB.
-- Evidência: diagnostico/09-vendas-por-dia.txt (29,2 ms -> 6,5 ms por chamada, mesmo resultado nos 725 períodos).
-- Custo: +24 MB no índice de itens e +8 MB no de pedidos; cada escrita grava as colunas incluídas no índice.
-- VACUUM (ANALYZE) marca as páginas no mapa de visibilidade já na criação do banco (como na 05.1).

\echo 'Trocando os índices de itens_pedido (pedido_id) e pedidos (criado_em) por versões com INCLUDE...'
DROP INDEX itens_pedido_pedido_id_idx;
CREATE INDEX itens_pedido_pedido_id_inc_idx ON itens_pedido (pedido_id) INCLUDE (quantidade, preco_unitario_centavos);
DROP INDEX pedidos_criado_em_idx;
CREATE INDEX pedidos_criado_em_inc_idx ON pedidos (criado_em) INCLUDE (id, status);
VACUUM (ANALYZE) itens_pedido;
VACUUM (ANALYZE) pedidos;
\echo 'Índices trocados.'
