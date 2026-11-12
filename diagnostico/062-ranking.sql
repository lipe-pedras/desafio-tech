-- 06.2: plano da consulta nova de top-produtos e equivalência com a consulta da main, para os limites 1 a 50.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/062-ranking.sql > diagnostico/062-ranking.txt
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
SELECT pg_size_pretty(pg_relation_size('vendas_por_produto')) AS tabela,
       pg_size_pretty(pg_relation_size('vendas_por_produto_ranking_idx')) AS indice;
\o /dev/null
EXPLAIN ANALYZE WITH ranking AS (
  SELECT produto_id, unidades, receita_centavos FROM vendas_por_produto WHERE itens > 0
   ORDER BY receita_centavos DESC, produto_id LIMIT 10)
SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos FROM ranking r JOIN produtos pr ON pr.id = r.produto_id
 ORDER BY r.receita_centavos DESC, pr.id;
\o
EXPLAIN (ANALYZE, BUFFERS) WITH ranking AS (
  SELECT produto_id, unidades, receita_centavos FROM vendas_por_produto WHERE itens > 0
   ORDER BY receita_centavos DESC, produto_id LIMIT 10)
SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos FROM ranking r JOIN produtos pr ON pr.id = r.produto_id
 ORDER BY r.receita_centavos DESC, pr.id;

WITH antiga AS (
  SELECT limite, string_agg(format('%s|%s|%s|%s|%s', id, nome, categoria, unidades, receita_centavos), E'\n' ORDER BY ord) AS resposta
    FROM generate_series(1, 50) limite, LATERAL (
      SELECT row_number() OVER () AS ord, x.* FROM (
        SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
               sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
          FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
         WHERE p.status <> 'cancelado' GROUP BY pr.id, pr.nome, pr.categoria
         ORDER BY receita_centavos DESC, pr.id LIMIT limite) x) a
   GROUP BY limite),
nova AS (
  SELECT limite, string_agg(format('%s|%s|%s|%s|%s', id, nome, categoria, unidades, receita_centavos), E'\n' ORDER BY ord) AS resposta
    FROM generate_series(1, 50) limite, LATERAL (
      SELECT row_number() OVER () AS ord, x.* FROM (
        WITH ranking AS (
          SELECT produto_id, unidades, receita_centavos FROM vendas_por_produto WHERE itens > 0
           ORDER BY receita_centavos DESC, produto_id LIMIT limite)
        SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos FROM ranking r JOIN produtos pr ON pr.id = r.produto_id
         ORDER BY r.receita_centavos DESC, pr.id) x) b
   GROUP BY limite)
SELECT count(*) AS limites_comparados,
       count(*) FILTER (WHERE antiga.resposta IS DISTINCT FROM nova.resposta) AS diferentes,
       md5(string_agg(antiga.resposta, E'\n' ORDER BY limite)) AS md5_antiga,
       md5(string_agg(nova.resposta, E'\n' ORDER BY limite)) AS md5_nova
  FROM antiga FULL JOIN nova USING (limite);
