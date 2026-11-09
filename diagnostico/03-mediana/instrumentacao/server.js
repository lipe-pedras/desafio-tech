// DIAGNÓSTICO, não vai para a main. Igual ao api/src/server.js, com o registro por rota.
const express = require('express');
const rotas = require('./rotas');

const app = express();
const porta = Number(process.env.PORT || 3000);

const diag = require('./db');

function nomeDaRota(caminho) {
  if (/^\/clientes\/[^/]+\/pedidos$/.test(caminho)) return 'pedidos-do-cliente';
  if (/^\/clientes\/[^/]+$/.test(caminho)) return 'cliente';
  if (caminho === '/clientes') return 'cliente-por-email';
  if (caminho === '/pedidos') return 'pedidos-por-status';
  if (caminho === '/produtos/busca') return 'busca-produtos';
  if (caminho === '/relatorios/vendas-por-dia') return 'vendas-por-dia';
  if (caminho === '/relatorios/top-produtos') return 'top-produtos';
  return 'outra';
}

app.get('/__diag', (req, res) => res.json(diag.relatorio()));
app.post('/__diag/reiniciar', (req, res) => { diag.reiniciar(); res.json({ ok: true }); });

app.use((req, res, next) => {
  const rota = nomeDaRota(req.path);
  const inicio = diag.agora();
  diag.daRota(rota).em_andamento += 1;
  res.on('close', () => {
    const r = diag.daRota(rota);
    r.em_andamento -= 1;
    r.requisicoes += 1;
    r.total_ms += diag.agora() - inicio;
  });
  diag.contexto.run({ rota }, next);
});

app.use((req, res, next) => {
  const inicio = Date.now();
  const enviarJson = res.json.bind(res);
  res.json = (corpo) => {
    console.log(JSON.stringify({
      metodo: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      duracao_ms: Date.now() - inicio,
      resposta: corpo,
    }));
    return enviarJson(corpo);
  };
  next();
});

app.use(rotas);

app.use((req, res) => {
  res.status(404).json({ erro: 'rota nao encontrada' });
});

app.use((erro, req, res, next) => {
  console.error(erro);
  res.status(500).json({ erro: 'erro interno' });
});

app.listen(porta, () => {
  console.log(`API ouvindo na porta ${porta}`);
});
