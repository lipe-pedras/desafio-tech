const express = require('express');
const { consultar } = require('./db');

const rotas = express.Router();

const STATUS_VALIDOS = ['pago', 'entregue', 'cancelado', 'pendente'];
const TAMANHO_PAGINA = 20;
const MAX_DIAS_RELATORIO = 31;

function inteiroPositivo(valor) {
  if (typeof valor !== 'string' || !/^\d+$/.test(valor)) return null;
  const numero = Number(valor);
  return numero > 0 && Number.isSafeInteger(numero) ? numero : null;
}

function dataValida(valor) {
  if (typeof valor !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(valor)) return null;
  const data = new Date(`${valor}T00:00:00Z`);
  return !Number.isNaN(data.getTime()) && data.toISOString().slice(0, 10) === valor ? data : null;
}

function assincrono(manipulador) {
  return (req, res, next) => manipulador(req, res).catch(next);
}

function formatarCliente(linha) {
  return {
    id: linha.id,
    nome: linha.nome,
    email: linha.email,
    cidade: linha.cidade,
    criado_em: linha.criado_em,
  };
}

rotas.get('/saude', (req, res) => {
  res.json({ status: 'ok' });
});

rotas.get('/clientes', assincrono(async (req, res) => {
  const email = req.query.email;
  if (typeof email !== 'string' || email.trim() === '') {
    return res.status(400).json({ erro: 'informe o parametro email' });
  }

  const linhas = await consultar(
    'SELECT * FROM clientes WHERE lower(email) = lower($1) ORDER BY id',
    [email.trim()],
  );
  res.json(linhas.map(formatarCliente));
}));

rotas.get('/clientes/:id', assincrono(async (req, res) => {
  const id = inteiroPositivo(req.params.id);
  if (id === null) return res.status(400).json({ erro: 'id invalido' });

  const linhas = await consultar('SELECT * FROM clientes WHERE id = $1', [id]);
  if (linhas.length === 0) return res.status(404).json({ erro: 'cliente nao encontrado' });
  res.json(formatarCliente(linhas[0]));
}));

rotas.get('/clientes/:id/pedidos', assincrono(async (req, res) => {
  const id = inteiroPositivo(req.params.id);
  if (id === null) return res.status(400).json({ erro: 'id invalido' });

  const clientes = await consultar('SELECT * FROM clientes WHERE id = $1', [id]);
  if (clientes.length === 0) return res.status(404).json({ erro: 'cliente nao encontrado' });

  // Uma consulta só para pedidos, itens e produtos. O LEFT JOIN mantém pedidos sem itens.
  const linhas = await consultar(
    `SELECT p.id AS pedido_id, p.status, p.criado_em, i.produto_id, pr.nome AS produto_nome,
            i.quantidade, i.preco_unitario_centavos
       FROM pedidos p
       LEFT JOIN itens_pedido i ON i.pedido_id = p.id
       LEFT JOIN produtos pr ON pr.id = i.produto_id
      WHERE p.cliente_id = $1
      ORDER BY p.criado_em DESC, p.id DESC, i.id`,
    [id],
  );

  const resposta = [];
  let pedido = null;
  for (const linha of linhas) {
    if (pedido === null || pedido.id !== linha.pedido_id) {
      pedido = {
        id: linha.pedido_id,
        status: linha.status,
        criado_em: linha.criado_em,
        total_centavos: 0,
        itens: [],
      };
      resposta.push(pedido);
    }
    if (linha.produto_id !== null) {
      pedido.itens.push({
        produto_id: linha.produto_id,
        produto_nome: linha.produto_nome,
        quantidade: linha.quantidade,
        preco_unitario_centavos: linha.preco_unitario_centavos,
      });
      pedido.total_centavos += linha.quantidade * linha.preco_unitario_centavos;
    }
  }

  res.json(resposta);
}));

rotas.get('/pedidos', assincrono(async (req, res) => {
  const status = req.query.status;
  if (!STATUS_VALIDOS.includes(status)) {
    return res.status(400).json({ erro: `status deve ser um de: ${STATUS_VALIDOS.join(', ')}` });
  }

  const pagina = req.query.pagina === undefined ? 1 : inteiroPositivo(req.query.pagina);
  if (pagina === null) return res.status(400).json({ erro: 'pagina invalida' });

  // O total vem da tabela mantida por gatilhos (banco/05-total-pedidos-por-status.sql), sem contar os pedidos.
  // Status sem pedidos não têm linha (ou têm total 0): a resposta continua 0.
  const [contagem] = await consultar(
    'SELECT coalesce((SELECT total FROM pedidos_por_status WHERE status = $1), 0) AS total',
    [status],
  );
  // Só as colunas que a resposta usa (sem observacoes). Com o índice da 05.1, que inclui cliente_id,
  // a página e as linhas puladas pelo OFFSET são lidas só do índice.
  const linhas = await consultar(
    `SELECT id, cliente_id, status, criado_em
       FROM pedidos
      WHERE status = $1
      ORDER BY criado_em DESC, id DESC
      LIMIT $2 OFFSET $3`,
    [status, TAMANHO_PAGINA, (pagina - 1) * TAMANHO_PAGINA],
  );

  res.json({
    pagina,
    tamanho_pagina: TAMANHO_PAGINA,
    total: Number(contagem.total),
    pedidos: linhas.map((linha) => ({
      id: linha.id,
      cliente_id: linha.cliente_id,
      status: linha.status,
      criado_em: linha.criado_em,
    })),
  });
}));

rotas.get('/produtos/busca', assincrono(async (req, res) => {
  const termo = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  if (termo.length < 3) return res.status(400).json({ erro: 'o termo de busca precisa ter pelo menos 3 caracteres' });

  const linhas = await consultar(
    "SELECT * FROM produtos WHERE nome ILIKE '%' || $1 || '%' ORDER BY nome, id LIMIT 20",
    [termo],
  );
  res.json(linhas.map((linha) => ({
    id: linha.id,
    nome: linha.nome,
    categoria: linha.categoria,
    preco_centavos: linha.preco_centavos,
  })));
}));

rotas.get('/relatorios/vendas-por-dia', assincrono(async (req, res) => {
  const inicio = dataValida(req.query.inicio);
  const fim = dataValida(req.query.fim);
  if (inicio === null || fim === null) {
    return res.status(400).json({ erro: 'informe inicio e fim no formato AAAA-MM-DD' });
  }
  const dias = (fim - inicio) / 86400000 + 1;
  if (dias < 1 || dias > MAX_DIAS_RELATORIO) {
    return res.status(400).json({ erro: `o periodo deve ter entre 1 e ${MAX_DIAS_RELATORIO} dias` });
  }

  // 09.2: pedidos, unidades e receita de cada dia vêm de vendas_por_dia, mantida por gatilhos
  // (banco/09-total-vendas-por-dia.sql). Dias sem pedidos contados não aparecem, como no JOIN de antes.
  const linhas = await consultar(
    `SELECT to_char(dia, 'YYYY-MM-DD') AS dia, pedidos, unidades AS itens, receita_centavos
       FROM vendas_por_dia
      WHERE dia >= $1::date
        AND dia <= $2::date
        AND pedidos > 0
      ORDER BY vendas_por_dia.dia`,
    [req.query.inicio, req.query.fim],
  );

  res.json(linhas.map((linha) => ({
    dia: linha.dia,
    pedidos: Number(linha.pedidos),
    itens: Number(linha.itens),
    receita_centavos: Number(linha.receita_centavos),
  })));
}));

rotas.get('/relatorios/top-produtos', assincrono(async (req, res) => {
  const limite = req.query.limite === undefined ? 10 : inteiroPositivo(req.query.limite);
  if (limite === null || limite > 50) return res.status(400).json({ erro: 'limite deve ser um inteiro entre 1 e 50' });

  // O ranking vem da tabela mantida por gatilhos (banco/06-total-vendas-por-produto.sql), lido em ordem
  // pelo índice parcial (itens > 0), sem agrupar os itens. Só os produtos do LIMIT são juntados a produtos.
  const linhas = await consultar(
    `WITH ranking AS (
       SELECT produto_id, unidades, receita_centavos
         FROM vendas_por_produto
        WHERE itens > 0
        ORDER BY receita_centavos DESC, produto_id
        LIMIT $1
     )
     SELECT pr.id, pr.nome, pr.categoria, r.unidades, r.receita_centavos
       FROM ranking r
       JOIN produtos pr ON pr.id = r.produto_id
      ORDER BY r.receita_centavos DESC, pr.id`,
    [limite],
  );

  res.json(linhas.map((linha) => ({
    produto_id: linha.id,
    nome: linha.nome,
    categoria: linha.categoria,
    unidades: Number(linha.unidades),
    receita_centavos: Number(linha.receita_centavos),
  })));
}));

module.exports = rotas;
