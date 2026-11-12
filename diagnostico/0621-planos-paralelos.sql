-- 06.2 sem paralelismo: quais consultas das rotas ainda escolheriam um plano paralelo depois da 06.2, com o
-- padrão max_parallel_workers_per_gather = 2 (ligado só nesta sessão). Um parâmetro de exemplo por rota,
-- como na carga. Mostra só o plano (EXPLAIN sem ANALYZE) e se há Gather.
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/0621-planos-paralelos.sql > diagnostico/0621-planos-paralelos.txt
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";
SET max_parallel_workers_per_gather = 2;
\echo '=== cliente'
EXPLAIN SELECT * FROM clientes WHERE id = 4242;
\echo '=== cliente-por-email'
EXPLAIN SELECT * FROM clientes WHERE lower(email) = lower('cliente4242@exemplo.com') ORDER BY id;
\echo '=== pedidos-do-cliente'
EXPLAIN SELECT p.id, p.status, p.criado_em, i.produto_id, pr.nome, i.quantidade, i.preco_unitario_centavos
  FROM pedidos p LEFT JOIN itens_pedido i ON i.pedido_id = p.id LEFT JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.cliente_id = 4242 ORDER BY p.criado_em DESC, p.id DESC, i.id;
\echo '=== pedidos-por-status (total e página 500)'
EXPLAIN SELECT coalesce((SELECT total FROM pedidos_por_status WHERE status = 'pago'), 0);
EXPLAIN SELECT id, cliente_id, status, criado_em FROM pedidos WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 9980;
\echo '=== busca-produtos'
EXPLAIN SELECT * FROM produtos WHERE nome ILIKE '%' || 'cadeira' || '%' ORDER BY nome, id LIMIT 20;
\echo '=== vendas-por-dia (7 dias)'
EXPLAIN SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.criado_em >= '2024-06-01'::date AND p.criado_em < '2024-06-07'::date + 1 AND p.status <> 'cancelado'
 GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
\echo '=== top-produtos'
EXPLAIN WITH ranking AS (SELECT produto_id, unidades, receita_centavos FROM vendas_por_produto WHERE itens > 0
   ORDER BY receita_centavos DESC, produto_id LIMIT 10)
SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos FROM ranking r JOIN produtos pr ON pr.id = r.produto_id
 ORDER BY r.receita_centavos DESC, pr.id;
