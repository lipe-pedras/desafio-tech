-- 07: busca-produtos com e sem o índice de trigramas, nos 12 termos da carga (carga/teste-carga.js) e em
-- alguns casos de borda (3 letras, maiúsculas, termo sem resultado, termo com espaço e com % e _ literais
-- vindos do usuário). Para cada termo:
--   - o resultado (as 20 linhas, na ordem) com o índice e sem ele (enable_bitmapscan = off: o plano volta ao
--     Seq Scan), comparado por MD5;
--   - o tempo médio de 50 execuções de cada forma (clock_timestamp, só execução, banco ocioso);
--   - o plano escolhido com o índice.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/07-busca.sql > diagnostico/07-busca.txt
\pset footer off
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
SELECT pg_size_pretty(pg_relation_size('produtos_nome_trgm_idx')) AS indice, pg_size_pretty(pg_relation_size('produtos')) AS tabela;

CREATE FUNCTION pg_temp.busca(termo text, com_indice boolean, vezes int, OUT ms double precision, OUT md5 text, OUT linhas int)
LANGUAGE plpgsql AS $$
DECLARE t0 timestamptz; i int;
BEGIN
  PERFORM set_config('enable_bitmapscan', CASE WHEN com_indice THEN 'on' ELSE 'off' END, true);
  SELECT md5(string_agg(format('%s|%s|%s|%s', id, nome, categoria, preco_centavos), E'\n' ORDER BY ord)), count(*)
    INTO md5, linhas
    FROM (SELECT row_number() OVER () AS ord, x.* FROM
            (SELECT * FROM produtos WHERE nome ILIKE '%' || termo || '%' ORDER BY nome, id LIMIT 20) x) y;
  t0 := clock_timestamp();
  FOR i IN 1..vezes LOOP
    PERFORM * FROM produtos WHERE nome ILIKE '%' || termo || '%' ORDER BY nome, id LIMIT 20;
  END LOOP;
  ms := extract(epoch FROM clock_timestamp() - t0) * 1000 / vezes;
END $$;

CREATE TEMP TABLE termos (ordem serial, termo text, origem text);
INSERT INTO termos (termo, origem)
SELECT t, 'carga' FROM unnest(ARRAY['cadeira','mesa','lumin','teclado','monitor','ergo','sem fio','portatil','modelo 12','slim','reforcada','webcam']) t;
INSERT INTO termos (termo, origem) VALUES ('ado', 'borda'), ('CADEIRA', 'borda'), ('xyzw', 'borda'), ('o 1', 'borda'), ('50%', 'borda'), ('a_b', 'borda');

-- aquecimento
SELECT count(*) AS aquecido FROM termos, LATERAL pg_temp.busca(termo, true, 5) a, LATERAL pg_temp.busca(termo, false, 5) b;

SELECT t.termo, t.origem, s.linhas,
       round(s.ms::numeric, 3) AS ms_sem_indice, round(c.ms::numeric, 3) AS ms_com_indice,
       round((s.ms / nullif(c.ms, 0))::numeric, 1) AS vezes_mais_rapido,
       CASE WHEN s.md5 IS NOT DISTINCT FROM c.md5 THEN 'igual' ELSE 'DIFERENTE' END AS resultado
  FROM termos t, LATERAL pg_temp.busca(t.termo, false, 50) s, LATERAL pg_temp.busca(t.termo, true, 50) c
 ORDER BY t.ordem;

\echo '=== planos com o índice (cadeira, ergo, sem fio, ado, o 1)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'cadeira' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'ergo' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'sem fio' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'ado' || '%' ORDER BY nome, id LIMIT 20;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM produtos WHERE nome ILIKE '%' || 'o 1' || '%' ORDER BY nome, id LIMIT 20;
