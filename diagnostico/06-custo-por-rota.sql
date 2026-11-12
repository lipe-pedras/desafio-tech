-- 06: quanto tempo de execução no banco cada rota gasta, ponderado pelo peso da rota na carga
-- (carga/teste-carga.js). Com DB_POOL_MAX=1, as consultas de todas as rotas passam por uma conexão só,
-- então a rota que mais ocupa o banco por requisição média é a candidata da próxima mudança.
--
-- Cada rota roda as mesmas consultas de api/src/rotas.js, com parâmetros sorteados como na carga
-- (setseed fixo), dentro de uma função plpgsql que mede com clock_timestamp(). O tempo medido é só o de
-- execução: não inclui rede, parse nem o trabalho da API. Banco ocioso, sem a carga.
--
--   docker compose exec -T banco psql -U loja -d loja -X -f - < diagnostico/06-custo-por-rota.sql > diagnostico/06-custo-por-rota.txt

\pset footer off
SELECT 'data: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS " ";

CREATE OR REPLACE FUNCTION pg_temp.medir(rota text, vezes int) RETURNS double precision LANGUAGE plpgsql AS $$
DECLARE
  t0 timestamptz; v_total double precision := 0; i int; r record; n bigint;
  termos text[] := ARRAY['cadeira','mesa','lumin','teclado','monitor','ergo','sem fio','portatil','modelo 12','slim','reforcada','webcam'];
  status text[] := ARRAY['pago','entregue','cancelado','pendente'];
  v_id int; v_d date; v_s text;
BEGIN
  FOR i IN 1..vezes LOOP
    v_id := 1 + floor(random() * 100000)::int;
    v_s := status[1 + floor(random() * 4)::int];
    v_d := date '2024-01-01' + floor(random() * 725)::int;
    t0 := clock_timestamp();
    IF rota = 'cliente' THEN
      PERFORM * FROM clientes WHERE clientes.id = v_id;
    ELSIF rota = 'cliente-por-email' THEN
      PERFORM * FROM clientes WHERE lower(email) = lower('cliente' || v_id || '@exemplo.com') ORDER BY clientes.id;
    ELSIF rota = 'pedidos-do-cliente' THEN
      PERFORM * FROM clientes WHERE clientes.id = v_id;
      PERFORM p.id AS pedido_id, p.status, p.criado_em, i.produto_id, pr.nome, i.quantidade, i.preco_unitario_centavos
         FROM pedidos p
         LEFT JOIN itens_pedido i ON i.pedido_id = p.id
         LEFT JOIN produtos pr ON pr.id = i.produto_id
        WHERE p.cliente_id = v_id
        ORDER BY p.criado_em DESC, p.id DESC, i.id;
    ELSIF rota = 'pedidos-por-status' THEN
      PERFORM coalesce((SELECT total FROM pedidos_por_status WHERE pedidos_por_status.status = v_s), 0);
      PERFORM pedidos.id, cliente_id, pedidos.status, criado_em FROM pedidos WHERE pedidos.status = v_s
        ORDER BY criado_em DESC, pedidos.id DESC LIMIT 20 OFFSET (floor(random() * 1000)::int) * 20;
    ELSIF rota = 'busca-produtos' THEN
      PERFORM * FROM produtos WHERE nome ILIKE '%' || termos[1 + floor(random() * 12)::int] || '%' ORDER BY nome, produtos.id LIMIT 20;
    ELSIF rota = 'vendas-por-dia' THEN
      PERFORM to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade),
              sum(i.quantidade::bigint * i.preco_unitario_centavos)
         FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
        WHERE p.criado_em >= v_d AND p.criado_em < v_d + 7 AND p.status <> 'cancelado'
        GROUP BY p.criado_em::date ORDER BY p.criado_em::date;
    ELSIF rota = 'top-produtos' THEN
      PERFORM pr.id, pr.nome, pr.categoria, sum(i.quantidade) AS unidades,
              sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
         FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id JOIN produtos pr ON pr.id = i.produto_id
        WHERE p.status <> 'cancelado'
        GROUP BY pr.id, pr.nome, pr.categoria ORDER BY receita_centavos DESC, pr.id LIMIT 10;
    END IF;
    v_total := v_total + extract(epoch FROM clock_timestamp() - t0) * 1000;
  END LOOP;
  RETURN v_total / vezes;
END $$;

-- Aquecimento: uma passada em cada rota, sem registrar.
SELECT setseed(0.42);
SELECT rota, pg_temp.medir(rota, CASE WHEN rota = 'top-produtos' THEN 2 ELSE 50 END) IS NOT NULL AS aquecido
  FROM unnest(ARRAY['cliente','cliente-por-email','pedidos-do-cliente','pedidos-por-status','busca-produtos','vendas-por-dia','top-produtos']) rota;

-- 3 rodadas; ms por requisição = média da rodada; ms por 100 requisições da carga = ms × peso.
SELECT setseed(0.42);
CREATE TEMP TABLE medidas AS
SELECT rodada, rota, peso, pg_temp.medir(rota, CASE WHEN rota = 'top-produtos' THEN 10 ELSE 300 END) AS ms
  FROM generate_series(1, 3) rodada,
       (VALUES ('cliente', 25), ('cliente-por-email', 15), ('pedidos-do-cliente', 20), ('pedidos-por-status', 15),
               ('busca-produtos', 15), ('vendas-por-dia', 8), ('top-produtos', 2)) v(rota, peso);

SELECT rota, peso,
       round(min(ms)::numeric, 3) AS ms_min, round(percentile_disc(0.5) WITHIN GROUP (ORDER BY ms)::numeric, 3) AS ms_mediana,
       round(max(ms)::numeric, 3) AS ms_max,
       round((percentile_disc(0.5) WITHIN GROUP (ORDER BY ms) * peso)::numeric, 1) AS ms_por_100_req,
       round((100 * percentile_disc(0.5) WITHIN GROUP (ORDER BY ms) * peso
              / sum(percentile_disc(0.5) WITHIN GROUP (ORDER BY ms) * peso) OVER ())::numeric, 1) AS pct_do_banco
  FROM medidas GROUP BY rota, peso ORDER BY ms_por_100_req DESC;
