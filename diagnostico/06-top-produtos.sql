-- 06: plano de /relatorios/top-produtos?limite=10 (a única forma da rota na carga), como está na main.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/06-top-produtos.sql > diagnostico/06-top-produtos.txt
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
SHOW max_parallel_workers_per_gather;
SELECT relname, n_live_tup, pg_size_pretty(pg_relation_size(relid)) AS tamanho
  FROM pg_stat_user_tables WHERE relname IN ('itens_pedido', 'pedidos', 'produtos') ORDER BY relname;
SELECT count(*) FILTER (WHERE status = 'cancelado') AS cancelados, count(*) AS pedidos FROM pedidos;

-- Consulta atual (api/src/rotas.js), 3 vezes; a última fica registrada com BUFFERS.
\o /dev/null
EXPLAIN ANALYZE SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado' GROUP BY pr.id, pr.nome, pr.categoria ORDER BY receita_centavos DESC, pr.id LIMIT 10;
EXPLAIN ANALYZE SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado' GROUP BY pr.id, pr.nome, pr.categoria ORDER BY receita_centavos DESC, pr.id LIMIT 10;
\o
EXPLAIN (ANALYZE, BUFFERS) SELECT pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado' GROUP BY pr.id, pr.nome, pr.categoria ORDER BY receita_centavos DESC, pr.id LIMIT 10;

-- Proposta da 06: agrega por i.produto_id (sem o JOIN com produtos nas 1,35 milhão de linhas) e só busca
-- nome e categoria dos produtos que entram no LIMIT. Mesma ordem: receita DESC, depois o id do produto.
\o /dev/null
EXPLAIN ANALYZE WITH t AS (
  SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
    FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
   WHERE p.status <> 'cancelado' GROUP BY i.produto_id ORDER BY receita_centavos DESC, i.produto_id LIMIT 10)
SELECT pr.id, pr.nome, pr.categoria, t.unidades, t.receita_centavos FROM t JOIN produtos pr ON pr.id = t.produto_id
 ORDER BY t.receita_centavos DESC, pr.id;
EXPLAIN ANALYZE WITH t AS (
  SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
    FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
   WHERE p.status <> 'cancelado' GROUP BY i.produto_id ORDER BY receita_centavos DESC, i.produto_id LIMIT 10)
SELECT pr.id, pr.nome, pr.categoria, t.unidades, t.receita_centavos FROM t JOIN produtos pr ON pr.id = t.produto_id
 ORDER BY t.receita_centavos DESC, pr.id;
\o
EXPLAIN (ANALYZE, BUFFERS) WITH t AS (
  SELECT i.produto_id, sum(i.quantidade) AS unidades, sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
    FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
   WHERE p.status <> 'cancelado' GROUP BY i.produto_id ORDER BY receita_centavos DESC, i.produto_id LIMIT 10)
SELECT pr.id, pr.nome, pr.categoria, t.unidades, t.receita_centavos FROM t JOIN produtos pr ON pr.id = t.produto_id
 ORDER BY t.receita_centavos DESC, pr.id;
