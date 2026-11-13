-- 09.2: custo de escrita dos gatilhos de vendas_por_dia. A carga do desafio só lê, então isso não aparece
-- no medir.sh. Mesmo método e mesmos cenários de diagnostico/062-custo-escrita.sql: cada cenário roda num bloco
-- desfeito no fim, com os gatilhos da 09.2 ligados e desligados, alternando a ordem, 3 vezes cada. Os gatilhos
-- da 05.2 e da 06.2 ficam ligados nos dois casos: a diferença é só a da 09.2.
-- Desligar a 09.2 = ALTER TABLE ... DISABLE TRIGGER nos 5 gatilhos vendas_por_dia_*. Banco ocioso.
-- Cenários:
--   A. 1 INSERT de 100.000 itens num comando só, em pedidos existentes;
--   B. 10.000 INSERTs de 1 item cada (num laço, na mesma transação);
--   C. 10.000 UPDATEs de status de 1 pedido, entrando ou saindo de cancelado (o total muda);
--   D. 10.000 UPDATEs de status de 1 pedido, entre pago e entregue (o gatilho roda, o total não muda).
-- Medem o custo de CPU por comando; não medem a disputa entre transações simultâneas
-- (diagnostico/092-custo-concorrente.sh).
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/092-custo-escrita.sql > diagnostico/092-custo-escrita.txt
\set ON_ERROR_STOP on
\pset footer off
CREATE TEMP TABLE tempos (rodada int, cenario text, gatilhos text, ms numeric);

CREATE FUNCTION pg_temp.medir(rodada int, cenario text, gatilhos text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t0 timestamptz; ms numeric; i int;
BEGIN
    BEGIN
        IF gatilhos = 'desligados' THEN
            ALTER TABLE itens_pedido DISABLE TRIGGER vendas_por_dia_insert;
            ALTER TABLE itens_pedido DISABLE TRIGGER vendas_por_dia_update;
            ALTER TABLE itens_pedido DISABLE TRIGGER vendas_por_dia_delete;
            ALTER TABLE itens_pedido DISABLE TRIGGER vendas_por_dia_truncate;
            ALTER TABLE pedidos DISABLE TRIGGER vendas_por_dia_status;
        END IF;
        t0 := clock_timestamp();
        IF cenario = 'A' THEN
            INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
            SELECT 9000000 + g, 1 + (g * 7) % 500000, 1 + (g * 31) % 20000, 1 + g % 5, 1000 + g % 9000
              FROM generate_series(1, 100000) AS g;
        ELSIF cenario = 'B' THEN
            FOR i IN 1..10000 LOOP
                INSERT INTO itens_pedido (id, pedido_id, produto_id, quantidade, preco_unitario_centavos)
                VALUES (9000000 + i, 1 + (i * 7) % 500000, 1 + (i * 31) % 20000, 1 + i % 5, 1000 + i % 9000);
            END LOOP;
        ELSIF cenario = 'C' THEN
            FOR i IN 1..10000 LOOP
                UPDATE pedidos SET status = CASE status WHEN 'cancelado' THEN 'pago' ELSE 'cancelado' END WHERE id = i * 50;
            END LOOP;
        ELSE
            FOR i IN 1..10000 LOOP
                UPDATE pedidos SET status = CASE status WHEN 'pago' THEN 'entregue' ELSE 'pago' END WHERE id = i * 50;
            END LOOP;
        END IF;
        ms := round(extract(epoch FROM clock_timestamp() - t0)::numeric * 1000, 1);
        RAISE EXCEPTION 'desfazer';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    INSERT INTO tempos VALUES (rodada, cenario, gatilhos, ms);
END;
$$;

SELECT count(*) AS gatilhos FROM pg_trigger WHERE tgrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass) AND NOT tgisinternal;
SELECT pg_temp.medir(1, 'A', 'ligados');
SELECT pg_temp.medir(1, 'A', 'desligados');
SELECT pg_temp.medir(1, 'B', 'ligados');
SELECT pg_temp.medir(1, 'B', 'desligados');
SELECT pg_temp.medir(1, 'C', 'ligados');
SELECT pg_temp.medir(1, 'C', 'desligados');
SELECT pg_temp.medir(1, 'D', 'ligados');
SELECT pg_temp.medir(1, 'D', 'desligados');
SELECT pg_temp.medir(2, 'A', 'desligados');
SELECT pg_temp.medir(2, 'A', 'ligados');
SELECT pg_temp.medir(2, 'B', 'desligados');
SELECT pg_temp.medir(2, 'B', 'ligados');
SELECT pg_temp.medir(2, 'C', 'desligados');
SELECT pg_temp.medir(2, 'C', 'ligados');
SELECT pg_temp.medir(2, 'D', 'desligados');
SELECT pg_temp.medir(2, 'D', 'ligados');
SELECT pg_temp.medir(3, 'A', 'ligados');
SELECT pg_temp.medir(3, 'A', 'desligados');
SELECT pg_temp.medir(3, 'B', 'ligados');
SELECT pg_temp.medir(3, 'B', 'desligados');
SELECT pg_temp.medir(3, 'C', 'ligados');
SELECT pg_temp.medir(3, 'C', 'desligados');
SELECT pg_temp.medir(3, 'D', 'ligados');
SELECT pg_temp.medir(3, 'D', 'desligados');

\echo '=== tempos (ms) por execução'
SELECT * FROM tempos ORDER BY cenario, gatilhos, rodada;
\echo '=== mediana por cenário (ms)'
SELECT cenario, gatilhos, percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) AS mediana_ms, min(ms), max(ms)
  FROM tempos GROUP BY 1, 2 ORDER BY 1, 2;
\echo '=== depois: gatilhos ainda ligados (tgenabled = O)'
SELECT tgrelid::regclass AS tabela, tgname, tgenabled FROM pg_trigger
 WHERE tgrelid IN ('pedidos'::regclass, 'itens_pedido'::regclass) AND NOT tgisinternal ORDER BY 1, 2;
