-- 09 (exploração na main depois da 08): plano e custo de vendas-por-dia com índices que cobrem a consulta.
-- ATENÇÃO: altera o banco (VACUUM e índices não podem ficar numa transação desfeita). Rodar num banco
-- descartável, recriado depois com docker compose down -v:
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/09-vendas-por-dia.sql > diagnostico/09-vendas-por-dia.txt
-- Cada "tempo" é a média de 300 períodos de 7 dias sorteados como na carga (início entre 0 e 724 dias depois
-- de 2024-01-01, semente fixa), medidos com clock_timestamp() dentro do banco, depois de uma passada de aquecimento.
\pset pager off
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";

CREATE TEMP TABLE periodos AS
SELECT g AS n, ('2024-01-01'::date + (floor(random() * 725))::int) AS inicio
  FROM (SELECT setseed(0.42)) s, generate_series(1, 300) g;

CREATE FUNCTION pg_temp.tempo() RETURNS text LANGUAGE plpgsql AS $$
DECLARE r record; t0 timestamptz; total interval := '0'; passada int;
BEGIN
  FOR passada IN 1..2 LOOP
    total := '0';
    FOR r IN SELECT inicio FROM periodos ORDER BY n LOOP
      t0 := clock_timestamp();
      PERFORM to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade),
              sum(i.quantidade::bigint * i.preco_unitario_centavos)
         FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
        WHERE p.criado_em >= r.inicio AND p.criado_em < r.inicio + 6 + 1 AND p.status <> 'cancelado'
        GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
      total := total + (clock_timestamp() - t0);
    END LOOP;
  END LOOP;
  RETURN 'tempo médio por chamada: ' || round((extract(epoch FROM total) * 1000 / 300)::numeric, 3) || ' ms';
END $$;

-- Resultado de referência de todos os 725 períodos possíveis (hash), para conferir que nada muda.
CREATE FUNCTION pg_temp.hash() RETURNS text LANGUAGE sql AS $$
  SELECT md5(string_agg(x, '|' ORDER BY x)) FROM (
    SELECT d.inicio || ':' || coalesce((SELECT string_agg(dia || ',' || pedidos || ',' || itens || ',' || receita, ';' ORDER BY dia) FROM (
      SELECT to_char(p.criado_em::date, 'YYYY-MM-DD') AS dia, count(DISTINCT p.id) AS pedidos, sum(i.quantidade) AS itens,
             sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita
        FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
       WHERE p.criado_em >= d.inicio AND p.criado_em < d.inicio + 7 AND p.status <> 'cancelado'
       GROUP BY p.criado_em::date) q), '') AS x
    FROM (SELECT '2024-01-01'::date + k AS inicio FROM generate_series(0, 724) k) d) z $$;

\echo '=== mapa de visibilidade antes'
SELECT relname, relallvisible, relpages FROM pg_class WHERE relname IN ('pedidos', 'itens_pedido') ORDER BY 1;
\echo '=== índices de pedidos e itens_pedido'
SELECT indexrelid::regclass AS indice, pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho
  FROM pg_index WHERE indrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass) ORDER BY 1;

\echo '=== A. main (itens_pedido sem VACUUM, como o banco é criado)'
SELECT pg_temp.hash() AS hash_725_periodos;
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-06-01'::date AND p.criado_em < '2024-06-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
SELECT pg_temp.tempo();

\echo '=== B. só VACUUM (ANALYZE) itens_pedido, sem índice novo'
VACUUM (ANALYZE) itens_pedido;
SELECT relname, relallvisible, relpages FROM pg_class WHERE relname = 'itens_pedido';
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-06-01'::date AND p.criado_em < '2024-06-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
SELECT pg_temp.tempo();

\echo '=== C. troca itens_pedido (pedido_id) por (pedido_id) INCLUDE (quantidade, preco_unitario_centavos)'
DROP INDEX itens_pedido_pedido_id_idx;
CREATE INDEX itens_pedido_pedido_id_inc_idx ON itens_pedido (pedido_id) INCLUDE (quantidade, preco_unitario_centavos);
VACUUM (ANALYZE) itens_pedido;
SELECT pg_size_pretty(pg_relation_size('itens_pedido_pedido_id_inc_idx')) AS indice_itens_inc;
SELECT pg_temp.hash() AS hash_725_periodos;
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-06-01'::date AND p.criado_em < '2024-06-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
SELECT pg_temp.tempo();
\echo '--- pedidos-do-cliente com o índice novo (cliente 4242)'
EXPLAIN (ANALYZE, BUFFERS) SELECT p.id AS pedido_id, p.status, p.criado_em, i.produto_id, pr.nome AS produto_nome, i.quantidade, i.preco_unitario_centavos
  FROM pedidos p LEFT JOIN itens_pedido i ON i.pedido_id = p.id LEFT JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.cliente_id = 4242 ORDER BY p.criado_em DESC, p.id DESC, i.id;

\echo '=== D. C + troca pedidos (criado_em) por (criado_em) INCLUDE (id, status)'
DROP INDEX pedidos_criado_em_idx;
CREATE INDEX pedidos_criado_em_inc_idx ON pedidos (criado_em) INCLUDE (id, status);
VACUUM (ANALYZE) pedidos;
SELECT pg_size_pretty(pg_relation_size('pedidos_criado_em_inc_idx')) AS indice_pedidos_inc;
SELECT pg_temp.hash() AS hash_725_periodos;
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-06-01'::date AND p.criado_em < '2024-06-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
SELECT pg_temp.tempo();

\echo '=== E. total por dia pré-calculado (tabela de resumo, sem gatilhos), para estimar a versão agressiva'
CREATE TEMP TABLE vpd AS
SELECT p.criado_em::date AS dia, count(DISTINCT p.id) AS pedidos, sum(i.quantidade) AS itens,
       sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita_centavos
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id WHERE p.status <> 'cancelado' GROUP BY 1;
ALTER TABLE vpd ADD PRIMARY KEY (dia);
ANALYZE vpd;
SELECT count(*) AS dias, pg_size_pretty(pg_total_relation_size('vpd')) AS tamanho FROM vpd;
EXPLAIN (ANALYZE, BUFFERS) SELECT to_char(dia, 'YYYY-MM-DD'), pedidos, itens, receita_centavos FROM vpd
 WHERE dia >= '2024-06-01'::date AND dia <= '2024-06-07'::date ORDER BY dia;
