-- Pedidos, unidades e receita de cada dia, só de pedidos não cancelados, mantidos por gatilhos, para
-- /relatorios/vendas-por-dia ler as linhas do período em vez de juntar pedidos e itens a cada chamada.
-- "pedidos" conta os pedidos não cancelados do dia com pelo menos 1 item, como o JOIN da consulta antiga.
-- Gatilhos por comando, com tabelas de transição, como em 05-total-pedidos-por-status.sql:
--   itens_pedido INSERT/UPDATE/DELETE: soma a diferença de cada pedido no dia dele; o pedido passa a contar
--     quando ganha o 1º item e deixa de contar quando perde o último;
--   itens_pedido TRUNCATE: apaga tudo;
--   pedidos UPDATE: quando um pedido entra ou sai de cancelado, ou muda de dia, tira os itens dele do dia
--     antigo e põe no novo.
-- INSERT e DELETE em pedidos não mudam nada: pedido novo não tem itens, e a chave estrangeira impede apagar
-- um pedido com itens.
-- Custo: toda escrita em itens_pedido e toda mudança de status ou de data de pedido atualizam esta tabela.
-- Todo pedido novo cai no dia de hoje, então escritas simultâneas disputam a mesma linha.
-- Detalhes: experimentos/09.2-total-por-dia.md.

\echo 'Criando o total de vendas por dia e os gatilhos que o mantêm...'
CREATE TABLE vendas_por_dia (
    dia              date   PRIMARY KEY,
    pedidos          bigint NOT NULL,  -- pedidos não cancelados com itens; o dia só aparece na rota se > 0
    unidades         bigint NOT NULL,
    receita_centavos bigint NOT NULL
);

INSERT INTO vendas_por_dia (dia, pedidos, unidades, receita_centavos)
SELECT p.criado_em::date, count(DISTINCT p.id), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.status <> 'cancelado'
 GROUP BY p.criado_em::date;

-- Os gatilhos de itens somam as diferenças de cada pedido (d: linhas de itens, unidades, receita) no dia dele.
-- a.n é o número de linhas de itens do pedido depois do comando; antes, eram a.n - d.linhas. O pedido passa a
-- contar quando a.n > 0 e antes não, e deixa de contar no caso contrário.
-- Cada ramo repete o comando inteiro: a versão com uma função auxiliar comum ficou mais lenta
-- (experimentos/09.2-total-por-dia.md).
CREATE FUNCTION vendas_por_dia_itens() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        DELETE FROM vendas_por_dia;
        RETURN NULL;
    END IF;

    -- Trava os pedidos envolvidos (em ordem de id) para ler status e dia sem disputa com uma mudança simultânea.
    -- O outro gatilho de itens_pedido (06-total-vendas-por-produto.sql) trava os mesmos pedidos. Repetir é inofensivo:
    -- na mesma transação, a segunda trava não espera. Fica nos dois arquivos para cada um funcionar sozinho.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM 1 FROM pedidos WHERE id IN (SELECT pedido_id FROM novos) ORDER BY id FOR SHARE;
    END IF;
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        PERFORM 1 FROM pedidos WHERE id IN (SELECT pedido_id FROM antigos) ORDER BY id FOR SHARE;
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO vendas_por_dia AS t (dia, pedidos, unidades, receita_centavos)
        SELECT p.criado_em::date, sum((a.n > 0)::int - (a.n - d.linhas > 0)::int), sum(d.unidades), sum(d.receita)
          FROM (SELECT pedido_id, count(*) AS linhas, sum(quantidade) AS unidades, sum(quantidade::bigint * preco_unitario_centavos) AS receita
                  FROM novos GROUP BY pedido_id) d
         CROSS JOIN LATERAL (SELECT count(*) AS n FROM itens_pedido i WHERE i.pedido_id = d.pedido_id) a
          JOIN pedidos p ON p.id = d.pedido_id
         WHERE p.status <> 'cancelado'
         GROUP BY p.criado_em::date
        HAVING sum((a.n > 0)::int - (a.n - d.linhas > 0)::int) <> 0 OR sum(d.unidades) <> 0 OR sum(d.receita) <> 0
         ORDER BY p.criado_em::date
        ON CONFLICT (dia) DO UPDATE
           SET pedidos = t.pedidos + excluded.pedidos,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO vendas_por_dia AS t (dia, pedidos, unidades, receita_centavos)
        SELECT p.criado_em::date, sum((a.n > 0)::int - (a.n - d.linhas > 0)::int), sum(d.unidades), sum(d.receita)
          FROM (SELECT pedido_id, -count(*) AS linhas, -sum(quantidade) AS unidades, -sum(quantidade::bigint * preco_unitario_centavos) AS receita
                  FROM antigos GROUP BY pedido_id) d
         CROSS JOIN LATERAL (SELECT count(*) AS n FROM itens_pedido i WHERE i.pedido_id = d.pedido_id) a
          JOIN pedidos p ON p.id = d.pedido_id
         WHERE p.status <> 'cancelado'
         GROUP BY p.criado_em::date
        HAVING sum((a.n > 0)::int - (a.n - d.linhas > 0)::int) <> 0 OR sum(d.unidades) <> 0 OR sum(d.receita) <> 0
         ORDER BY p.criado_em::date
        ON CONFLICT (dia) DO UPDATE
           SET pedidos = t.pedidos + excluded.pedidos,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    ELSE -- UPDATE: tira a versão antiga de cada item e põe a nova (o item pode mudar de pedido)
        INSERT INTO vendas_por_dia AS t (dia, pedidos, unidades, receita_centavos)
        SELECT p.criado_em::date, sum((a.n > 0)::int - (a.n - d.linhas > 0)::int), sum(d.unidades), sum(d.receita)
          FROM (SELECT pedido_id, sum(s) AS linhas, sum(s * quantidade) AS unidades, sum(s * quantidade::bigint * preco_unitario_centavos) AS receita
                  FROM (SELECT 1 AS s, pedido_id, quantidade, preco_unitario_centavos FROM novos
                        UNION ALL SELECT -1, pedido_id, quantidade, preco_unitario_centavos FROM antigos) u
                 GROUP BY pedido_id) d
         CROSS JOIN LATERAL (SELECT count(*) AS n FROM itens_pedido i WHERE i.pedido_id = d.pedido_id) a
          JOIN pedidos p ON p.id = d.pedido_id
         WHERE p.status <> 'cancelado'
         GROUP BY p.criado_em::date
        HAVING sum((a.n > 0)::int - (a.n - d.linhas > 0)::int) <> 0 OR sum(d.unidades) <> 0 OR sum(d.receita) <> 0
         ORDER BY p.criado_em::date
        ON CONFLICT (dia) DO UPDATE
           SET pedidos = t.pedidos + excluded.pedidos,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION vendas_por_dia_pedidos() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Pedidos cujo (conta?, dia) mudou: tira a contribuição antiga (se contava) e põe a nova (se conta).
    INSERT INTO vendas_por_dia AS t (dia, pedidos, unidades, receita_centavos)
    SELECT m.dia, sum(m.s), sum(m.s * c.unidades), sum(m.s * c.receita)
      FROM (SELECT o.id, o.criado_em::date AS dia, -1 AS s
              FROM novos n JOIN antigos o ON o.id = n.id
             WHERE o.status <> 'cancelado'
               AND (n.status = 'cancelado' OR n.criado_em::date <> o.criado_em::date)
            UNION ALL
            SELECT n.id, n.criado_em::date, 1
              FROM novos n JOIN antigos o ON o.id = n.id
             WHERE n.status <> 'cancelado'
               AND (o.status = 'cancelado' OR n.criado_em::date <> o.criado_em::date)) m
      JOIN (SELECT i.pedido_id, sum(i.quantidade) AS unidades, sum(i.quantidade::bigint * i.preco_unitario_centavos) AS receita
              FROM itens_pedido i
             WHERE i.pedido_id IN (SELECT id FROM novos)
             GROUP BY i.pedido_id) c ON c.pedido_id = m.id
     GROUP BY m.dia ORDER BY m.dia
    ON CONFLICT (dia) DO UPDATE
       SET pedidos = t.pedidos + excluded.pedidos,
           unidades = t.unidades + excluded.unidades,
           receita_centavos = t.receita_centavos + excluded.receita_centavos;
    RETURN NULL;
END;
$$;

CREATE TRIGGER vendas_por_dia_insert AFTER INSERT ON itens_pedido
    REFERENCING NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_dia_itens();
CREATE TRIGGER vendas_por_dia_update AFTER UPDATE ON itens_pedido
    REFERENCING OLD TABLE AS antigos NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_dia_itens();
CREATE TRIGGER vendas_por_dia_delete AFTER DELETE ON itens_pedido
    REFERENCING OLD TABLE AS antigos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_dia_itens();
CREATE TRIGGER vendas_por_dia_truncate AFTER TRUNCATE ON itens_pedido
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_dia_itens();
CREATE TRIGGER vendas_por_dia_status AFTER UPDATE ON pedidos
    REFERENCING OLD TABLE AS antigos NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_dia_pedidos();

VACUUM (ANALYZE) vendas_por_dia;
\echo 'Total de vendas por dia criado.'
