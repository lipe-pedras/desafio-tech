-- Total de pedidos por status, mantido por gatilhos em pedidos, para /pedidos?status= não contar os pedidos
-- a cada chamada. Gatilhos por comando (FOR EACH STATEMENT) com tabelas de transição: cada comando atualiza
-- cada status uma vez, mesmo que altere milhares de pedidos.
-- Custo: toda escrita em pedidos atualiza também esta tabela. Detalhes: experimentos/05.2-total-por-status.md.

\echo 'Criando o total de pedidos por status e os gatilhos que o mantêm...'
CREATE TABLE pedidos_por_status (
    status text   PRIMARY KEY,
    total  bigint NOT NULL
);

INSERT INTO pedidos_por_status (status, total)
SELECT status, count(*) FROM pedidos GROUP BY status;

CREATE FUNCTION pedidos_por_status_atualizar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        UPDATE pedidos_por_status SET total = 0;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO pedidos_por_status AS t (status, total)
        SELECT status, count(*) FROM novos GROUP BY status ORDER BY status
        ON CONFLICT (status) DO UPDATE SET total = t.total + excluded.total;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE pedidos_por_status AS t SET total = t.total - d.n
          FROM (SELECT status, count(*) AS n FROM antigos GROUP BY status) d
         WHERE t.status = d.status;
    ELSE -- UPDATE: só conta as mudanças de status
        INSERT INTO pedidos_por_status AS t (status, total)
        SELECT status, sum(n) FROM (
            SELECT status, 1 AS n FROM novos
            UNION ALL
            SELECT status, -1 FROM antigos
        ) d GROUP BY status HAVING sum(n) <> 0 ORDER BY status
        ON CONFLICT (status) DO UPDATE SET total = t.total + excluded.total;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER pedidos_por_status_insert AFTER INSERT ON pedidos
    REFERENCING NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION pedidos_por_status_atualizar();
CREATE TRIGGER pedidos_por_status_update AFTER UPDATE ON pedidos
    REFERENCING OLD TABLE AS antigos NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION pedidos_por_status_atualizar();
CREATE TRIGGER pedidos_por_status_delete AFTER DELETE ON pedidos
    REFERENCING OLD TABLE AS antigos
    FOR EACH STATEMENT EXECUTE FUNCTION pedidos_por_status_atualizar();
CREATE TRIGGER pedidos_por_status_truncate AFTER TRUNCATE ON pedidos
    FOR EACH STATEMENT EXECUTE FUNCTION pedidos_por_status_atualizar();

VACUUM (ANALYZE) pedidos_por_status;
\echo 'Total por status criado.'
