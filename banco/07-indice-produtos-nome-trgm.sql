-- Mudança 07: índice de trigramas (pg_trgm, GIN) em produtos (nome) para /produtos/busca?q=.
-- A rota filtra com nome ILIKE '%termo%'. Com o % no começo, nenhum B-tree serve, e o banco lia os 20 mil
-- produtos a cada chamada (cerca de 6 ms; depois da 06, 58% do tempo de execução no banco,
-- diagnostico/07-custo-por-rota.txt). O índice de trigramas atende LIKE e ILIKE sem âncora no começo
-- (documentação do PostgreSQL 16, F.35.4). O ILIKE continua sendo conferido em cada linha encontrada,
-- então o resultado não muda.
-- Custo: cerca de 1,1 MB de disco; escritas em produtos atualizam também este índice.

\echo 'Criando o índice de trigramas em produtos (nome)...'
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX produtos_nome_trgm_idx ON produtos USING gin (nome gin_trgm_ops);
VACUUM (ANALYZE) produtos;
\echo 'Índice de trigramas criado.'
