-- 06: a consulta nova de top-produtos devolve as mesmas linhas, na mesma ordem, que a da main,
-- para todos os limites que a rota aceita (1 a 50). Compara a resposta inteira de cada limite como texto.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/06-equivalencia.sql > diagnostico/06-equivalencia.txt
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
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
        WITH t AS (
          SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
            FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
           WHERE p.status <> 'cancelado' GROUP BY i.produto_id ORDER BY receita_centavos DESC, i.produto_id LIMIT limite)
        SELECT pr.id, pr.nome, pr.categoria, t.unidades, t.receita_centavos FROM t JOIN produtos pr ON pr.id = t.produto_id
         ORDER BY t.receita_centavos DESC, pr.id) x) b
   GROUP BY limite)
SELECT count(*) AS limites_comparados,
       count(*) FILTER (WHERE antiga.resposta IS DISTINCT FROM nova.resposta) AS diferentes,
       md5(string_agg(antiga.resposta, E'\n' ORDER BY limite)) AS md5_antiga,
       md5(string_agg(nova.resposta, E'\n' ORDER BY limite)) AS md5_nova
  FROM antiga FULL JOIN nova USING (limite);
