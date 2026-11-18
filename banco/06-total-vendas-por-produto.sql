-- Unidades e receita de cada produto, só de pedidos não cancelados, mantidas por gatilhos, para
-- /relatorios/top-produtos ler o ranking de um índice em vez de agrupar todos os itens a cada chamada.
-- Gatilhos por comando, com tabelas de transição, como em 05-total-pedidos-por-status.sql:
--   itens_pedido INSERT/UPDATE/DELETE: soma ou subtrai os itens cujo pedido não está cancelado;
--   itens_pedido TRUNCATE: zera tudo;
--   pedidos UPDATE: quando um pedido entra ou sai de cancelado, subtrai ou soma os itens dele.
-- INSERT e DELETE em pedidos não mudam nada: pedido novo não tem itens, e a chave estrangeira impede apagar
-- um pedido com itens.
-- Custo: toda escrita em itens_pedido e toda mudança de status de pedido atualizam esta tabela.
-- Detalhes: experimentos/06.2-total-por-produto.md.

\echo 'Criando o total de vendas por produto e os gatilhos que o mantêm...'
CREATE TABLE vendas_por_produto (
    produto_id       integer PRIMARY KEY,
    itens            bigint  NOT NULL,  -- linhas de itens contadas; o produto só entra no ranking se > 0
    unidades         bigint  NOT NULL,
    receita_centavos bigint  NOT NULL
);

INSERT INTO vendas_por_produto (produto_id, itens, unidades, receita_centavos)
SELECT i.produto_id, count(*), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
  FROM itens_pedido i JOIN pedidos p ON p.id = i.pedido_id
 WHERE p.status <> 'cancelado'
 GROUP BY i.produto_id;

-- Mesma ordem da resposta: receita decrescente, depois o id do produto.
CREATE INDEX vendas_por_produto_ranking_idx ON vendas_por_produto (receita_centavos DESC, produto_id)
    INCLUDE (unidades) WHERE itens > 0;

-- Cada gatilho calcula a diferença por produto (itens, unidades, receita) e a soma na tabela, em ordem de
-- produto_id, com INSERT ... ON CONFLICT (um produto que ainda não tinha vendas ganha a sua linha).
CREATE FUNCTION vendas_por_produto_itens() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        UPDATE vendas_por_produto SET itens = 0, unidades = 0, receita_centavos = 0;
        RETURN NULL;
    END IF;

    -- Trava os pedidos envolvidos (em ordem de id) para ler o status sem disputa com uma mudança simultânea.
    -- O outro gatilho de itens_pedido (09-total-vendas-por-dia.sql) trava os mesmos pedidos. Repetir é inofensivo:
    -- na mesma transação, a segunda trava não espera. Fica nos dois arquivos para cada um funcionar sozinho.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM 1 FROM pedidos WHERE id IN (SELECT pedido_id FROM novos) ORDER BY id FOR SHARE;
    END IF;
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        PERFORM 1 FROM pedidos WHERE id IN (SELECT pedido_id FROM antigos) ORDER BY id FOR SHARE;
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO vendas_por_produto AS t (produto_id, itens, unidades, receita_centavos)
        SELECT i.produto_id, count(*), sum(i.quantidade), sum(i.quantidade::bigint * i.preco_unitario_centavos)
          FROM novos i JOIN pedidos p ON p.id = i.pedido_id
         WHERE p.status <> 'cancelado'
         GROUP BY i.produto_id ORDER BY i.produto_id
        ON CONFLICT (produto_id) DO UPDATE
           SET itens = t.itens + excluded.itens,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO vendas_por_produto AS t (produto_id, itens, unidades, receita_centavos)
        SELECT i.produto_id, -count(*), -sum(i.quantidade), -sum(i.quantidade::bigint * i.preco_unitario_centavos)
          FROM antigos i JOIN pedidos p ON p.id = i.pedido_id
         WHERE p.status <> 'cancelado'
         GROUP BY i.produto_id ORDER BY i.produto_id
        ON CONFLICT (produto_id) DO UPDATE
           SET itens = t.itens + excluded.itens,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    ELSE -- UPDATE: tira a versão antiga de cada item e põe a nova
        INSERT INTO vendas_por_produto AS t (produto_id, itens, unidades, receita_centavos)
        SELECT i.produto_id, sum(i.s), sum(i.s * i.quantidade), sum(i.s * i.quantidade::bigint * i.preco_unitario_centavos)
          FROM (SELECT 1 AS s, * FROM novos UNION ALL SELECT -1, * FROM antigos) i
          JOIN pedidos p ON p.id = i.pedido_id
         WHERE p.status <> 'cancelado'
         GROUP BY i.produto_id
        HAVING sum(i.s) <> 0 OR sum(i.s * i.quantidade) <> 0 OR sum(i.s * i.quantidade::bigint * i.preco_unitario_centavos) <> 0
         ORDER BY i.produto_id
        ON CONFLICT (produto_id) DO UPDATE
           SET itens = t.itens + excluded.itens,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION vendas_por_produto_pedidos() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Só os pedidos que entraram (+1) ou saíram (−1) do conjunto contado (status <> 'cancelado').
    INSERT INTO vendas_por_produto AS t (produto_id, itens, unidades, receita_centavos)
    SELECT i.produto_id, sum(m.s), sum(m.s * i.quantidade), sum(m.s * i.quantidade::bigint * i.preco_unitario_centavos)
      FROM (SELECT n.id, CASE WHEN n.status <> 'cancelado' THEN 1 ELSE -1 END AS s
              FROM novos n JOIN antigos o ON o.id = n.id
             WHERE (n.status <> 'cancelado') <> (o.status <> 'cancelado')) m
      JOIN itens_pedido i ON i.pedido_id = m.id
     GROUP BY i.produto_id ORDER BY i.produto_id
        ON CONFLICT (produto_id) DO UPDATE
           SET itens = t.itens + excluded.itens,
               unidades = t.unidades + excluded.unidades,
               receita_centavos = t.receita_centavos + excluded.receita_centavos;
    RETURN NULL;
END;
$$;

CREATE TRIGGER vendas_por_produto_insert AFTER INSERT ON itens_pedido
    REFERENCING NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_produto_itens();
CREATE TRIGGER vendas_por_produto_update AFTER UPDATE ON itens_pedido
    REFERENCING OLD TABLE AS antigos NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_produto_itens();
CREATE TRIGGER vendas_por_produto_delete AFTER DELETE ON itens_pedido
    REFERENCING OLD TABLE AS antigos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_produto_itens();
CREATE TRIGGER vendas_por_produto_truncate AFTER TRUNCATE ON itens_pedido
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_produto_itens();
CREATE TRIGGER vendas_por_produto_status AFTER UPDATE ON pedidos
    REFERENCING OLD TABLE AS antigos NEW TABLE AS novos
    FOR EACH STATEMENT EXECUTE FUNCTION vendas_por_produto_pedidos();

VACUUM (ANALYZE) vendas_por_produto;
\echo 'Total de vendas por produto criado.'
