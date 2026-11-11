// DIAGNÓSTICO, não vai para a main. Igual ao api/src/db.js, com medição de espera e execução por rota.
const { AsyncLocalStorage } = require('async_hooks');
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
  max: Number(process.env.DB_POOL_MAX || 10),
});
pool.on('error', (erro) => console.error('erro em conexao ociosa do pool', erro));

const contexto = new AsyncLocalStorage();
const agora = () => Number(process.hrtime.bigint()) / 1e6;
let rotas = {};
let amostras = { n: 0, esperando: 0 };

function daRota(nome) {
  if (!rotas[nome]) rotas[nome] = { consultas: 0, espera_ms: 0, execucao_ms: 0, requisicoes: 0, total_ms: 0, em_andamento: 0, soma_em_andamento: 0 };
  return rotas[nome];
}

function reiniciar() {
  const novas = {};
  for (const [nome, r] of Object.entries(rotas)) {
    novas[nome] = { consultas: 0, espera_ms: 0, execucao_ms: 0, requisicoes: 0, total_ms: 0, em_andamento: r.em_andamento, soma_em_andamento: 0 };
  }
  rotas = novas;
  amostras = { n: 0, esperando: 0 };
}

// Só conta os segundos com requisição em andamento, para não diluir com o início e o fim.
setInterval(() => {
  const lista = Object.values(rotas);
  if (lista.reduce((s, r) => s + r.em_andamento, 0) === 0) return;
  amostras.n += 1;
  amostras.esperando += pool.waitingCount;
  for (const r of lista) r.soma_em_andamento += r.em_andamento;
}, 1000).unref();

function relatorio() {
  const saida = { amostras: amostras.n, fila_pool_media: amostras.n ? amostras.esperando / amostras.n : 0, rotas: {} };
  for (const [nome, r] of Object.entries(rotas)) {
    saida.rotas[nome] = {
      requisicoes: r.requisicoes,
      consultas: r.consultas,
      tempo_medio_ms: r.requisicoes ? r.total_ms / r.requisicoes : 0,
      espera_pool_por_requisicao_ms: r.requisicoes ? r.espera_ms / r.requisicoes : 0,
      execucao_por_requisicao_ms: r.requisicoes ? r.execucao_ms / r.requisicoes : 0,
      espera_pool_por_consulta_ms: r.consultas ? r.espera_ms / r.consultas : 0,
      execucao_por_consulta_ms: r.consultas ? r.execucao_ms / r.consultas : 0,
      em_andamento_medio: amostras.n ? r.soma_em_andamento / amostras.n : 0,
    };
  }
  return saida;
}

async function consultar(sql, parametros = []) {
  const r = daRota((contexto.getStore() || {}).rota || 'outra');
  const t0 = agora();
  const cliente = await pool.connect();
  const t1 = agora();
  try {
    const resultado = await cliente.query(sql, parametros);
    r.consultas += 1;
    r.espera_ms += t1 - t0;
    r.execucao_ms += agora() - t1;
    return resultado.rows;
  } finally {
    cliente.release();
  }
}

module.exports = { consultar, contexto, daRota, agora, reiniciar, relatorio };
