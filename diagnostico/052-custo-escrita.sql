-- 05.2: custo de escrita dos gatilhos de pedidos_por_status. A carga do desafio só lê, então isso não aparece
-- no medir.sh. Cada cenário roda num bloco desfeito no fim (subtransação encerrada com
-- uma exceção), com os gatilhos ligados e desligados (ALTER TABLE ... DISABLE TRIGGER USER dentro do bloco),
-- alternando a ordem, 3 vezes cada. O tempo é medido antes de desfazer. Banco ocioso.
-- Cenários:
--   A. 1 INSERT de 100.000 pedidos num comando só;
--   B. 10.000 INSERTs de 1 pedido cada (num laço, na mesma transação);
--   C. 10.000 UPDATEs de status de 1 pedido cada (num laço, na mesma transação).
-- B e C medem o custo de CPU por comando; não medem a disputa pela linha de total entre transações simultâneas.
-- Uso: docker compose exec -T banco psql -U loja -d loja < diagnostico/052-custo-escrita.sql > diagnostico/052-custo-escrita.txt
\set ON_ERROR_STOP on
\pset footer off
CREATE TEMP TABLE tempos (rodada int, cenario text, gatilhos text, ms numeric);

CREATE FUNCTION pg_temp.medir(rodada int, cenario text, gatilhos text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t0 timestamptz; ms numeric; i int;
BEGIN
    BEGIN
        IF gatilhos = 'desligados' THEN
            ALTER TABLE pedidos DISABLE TRIGGER USER;
        END IF;
        t0 := clock_timestamp();
        IF cenario = 'A' THEN
            INSERT INTO pedidos (id, cliente_id, status, criado_em, observacoes)
            SELECT 1000000 + g, 1 + g % 100000, (ARRAY['pago','entregue','cancelado','pendente'])[1 + g % 4], now(), 'teste'
              FROM generate_series(1, 100000) AS g;
        ELSIF cenario = 'B' THEN
            FOR i IN 1..10000 LOOP
                INSERT INTO pedidos (id, cliente_id, status, criado_em, observacoes)
                VALUES (1000000 + i, 1 + i % 100000, (ARRAY['pago','entregue','cancelado','pendente'])[1 + i % 4], now(), 'teste');
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

SELECT count(*) AS gatilhos_em_pedidos FROM pg_trigger WHERE tgrelid = 'pedidos'::regclass AND NOT tgisinternal;
SELECT pg_temp.medir(1, 'A', 'ligados');
SELECT pg_temp.medir(1, 'A', 'desligados');
SELECT pg_temp.medir(1, 'B', 'ligados');
SELECT pg_temp.medir(1, 'B', 'desligados');
SELECT pg_temp.medir(1, 'C', 'ligados');
SELECT pg_temp.medir(1, 'C', 'desligados');
SELECT pg_temp.medir(2, 'A', 'desligados');
SELECT pg_temp.medir(2, 'A', 'ligados');
SELECT pg_temp.medir(2, 'B', 'desligados');
SELECT pg_temp.medir(2, 'B', 'ligados');
SELECT pg_temp.medir(2, 'C', 'desligados');
SELECT pg_temp.medir(2, 'C', 'ligados');
SELECT pg_temp.medir(3, 'A', 'ligados');
SELECT pg_temp.medir(3, 'A', 'desligados');
SELECT pg_temp.medir(3, 'B', 'ligados');
SELECT pg_temp.medir(3, 'B', 'desligados');
SELECT pg_temp.medir(3, 'C', 'ligados');
SELECT pg_temp.medir(3, 'C', 'desligados');

\echo '=== tempos (ms) por execução'
SELECT * FROM tempos ORDER BY cenario, gatilhos, rodada;
\echo '=== mediana por cenário (ms)'
SELECT cenario, gatilhos, percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) AS mediana_ms, min(ms), max(ms)
  FROM tempos GROUP BY 1, 2 ORDER BY 1, 2;
\echo '=== depois: gatilhos ainda ligados (tgenabled = O)'
SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'pedidos'::regclass AND NOT tgisinternal ORDER BY tgname;
