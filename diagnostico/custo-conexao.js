// Diagnóstico da mudança 02: quanto custa abrir uma conexão nova por consulta.
// Roda dentro do container da API, com o banco ocioso (sem carga):
//   docker compose exec -T api node - < diagnostico/custo-conexao.js
// Compara N consultas iguais e sequenciais feitas de dois jeitos:
//   1. como o db.js original: new Client, connect, query, end a cada consulta;
//   2. com um pg.Pool que reaproveita as conexões.
// A consulta é a de GET /clientes/:id, que custa menos de 1 ms no banco.
const { Client, Pool } = require('/app/node_modules/pg');

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
};
const N = 500;
const SQL = 'SELECT * FROM clientes WHERE id = $1';

function resumo(nome, tempos) {
  const ordenados = [...tempos].sort((a, b) => a - b);
  const q = (p) => ordenados[Math.min(ordenados.length - 1, Math.floor(p * ordenados.length))];
  const media = tempos.reduce((s, t) => s + t, 0) / tempos.length;
  console.log(`${nome.padEnd(28)} n=${tempos.length}  media=${media.toFixed(3)} ms  mediana=${q(0.5).toFixed(3)} ms  p95=${q(0.95).toFixed(3)} ms`);
}

async function conexaoPorConsulta(id) {
  const cliente = new Client(config);
  await cliente.connect();
  try {
    return (await cliente.query(SQL, [id])).rows;
  } finally {
    await cliente.end();
  }
}

async function medir(fn) {
  const tempos = [];
  for (let i = 0; i < N; i++) {
    const inicio = process.hrtime.bigint();
    await fn((i % 100000) + 1);
    tempos.push(Number(process.hrtime.bigint() - inicio) / 1e6);
  }
  return tempos;
}

(async () => {
  const pool = new Pool({ ...config, max: 10 });
  // aquecimento dos dois caminhos (não entra na conta)
  for (let i = 0; i < 20; i++) { await conexaoPorConsulta(1); await pool.query(SQL, [1]); }

  console.log(`data: ${new Date().toISOString()}  consultas sequenciais por caminho: ${N}`);
  resumo('conexao nova por consulta', await medir(conexaoPorConsulta));
  resumo('pool (conexao reaproveitada)', await medir((id) => pool.query(SQL, [id])));
  resumo('conexao nova por consulta', await medir(conexaoPorConsulta));
  resumo('pool (conexao reaproveitada)', await medir((id) => pool.query(SQL, [id])));
  await pool.end();
})().catch((erro) => { console.error(erro); process.exit(1); });
