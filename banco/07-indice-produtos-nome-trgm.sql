-- Índice de trigramas (pg_trgm, GIN) em produtos (nome) para /produtos/busca?q=, que filtra com
-- nome ILIKE '%termo%': com o % no começo, nenhum B-tree serve. O ILIKE continua sendo conferido em cada
-- linha encontrada, então o resultado não muda. Detalhes: experimentos/07-busca-trigramas.md.

\echo 'Criando o índice de trigramas em produtos (nome)...'
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX produtos_nome_trgm_idx ON produtos USING gin (nome gin_trgm_ops);
VACUUM (ANALYZE) produtos;
\echo 'Índice de trigramas criado.'
