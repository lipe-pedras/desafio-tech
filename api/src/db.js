const { Pool } = require('pg');

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
  // Um pool único para a API: as conexões são abertas uma vez e reaproveitadas,
  // em vez de uma conexão nova (e um processo novo no PostgreSQL) por consulta.
  // 10 é o padrão do node-postgres, deixado explícito.
  max: 10,
};

const pool = new Pool(config);

// Erro numa conexão ociosa do pool (banco reiniciado, rede): registra e segue;
// o pool descarta essa conexão e abre outra na próxima consulta.
pool.on('error', (erro) => {
  console.error('erro em conexao ociosa do pool', erro);
});

async function consultar(sql, parametros = []) {
  const resultado = await pool.query(sql, parametros);
  return resultado.rows;
}

module.exports = { consultar };
