# 02 · Pool de conexões no lugar de uma conexão nova por consulta

- **Status:** aplicada e medida
- **Branch / commit da mudança:** `02-pool-conexoes` / `63b4693`
- **Comparada com:** a 01 remedida na mesma sessão (commit `466d0f5`, `main` depois do merge da 01)

## Hipótese

Hoje o `api/src/db.js` abre uma conexão nova com o banco a cada consulta e a fecha logo depois. No PostgreSQL, cada conexão nova cria um processo novo no servidor. O banco tem só 1 CPU e já está saturado, então parte dessa CPU vai para abrir e fechar conexões, e não para responder às consultas.

Trocar isso por um pool, que abre as conexões uma vez e as reaproveita, deve aumentar as requisições/s e reduzir o tempo de resposta, principalmente:
- nas rotas com consultas baratas (`/clientes/:id`, `/clientes?email=`), em que o custo da conexão pesa mais que o da consulta;
- em `/clientes/:id/pedidos`, que faz cerca de 20 consultas por requisição (o N+1) e, portanto, cerca de 20 conexões.

## Diagnóstico (antes)

Evidência: [`diagnostico/custo-conexao.txt`](../diagnostico/custo-conexao.txt), gerado por [`diagnostico/custo-conexao.js`](../diagnostico/custo-conexao.js).

**Como foi medido:**
- dentro do container da API, com o banco ocioso, sem carga;
- 500 consultas sequenciais de `GET /clientes/:id` por caminho;
- cada caminho medido duas vezes, intercalado.

| Caminho | Mediana por consulta | p95 |
|---|---|---|
| conexão nova por consulta (como o `db.js` original) | 5,981 ms / 5,681 ms | 7,815 ms / 6,786 ms |
| pool (conexão reaproveitada) | 0,228 ms / 0,194 ms | 0,409 ms / 0,354 ms |

- **Com o banco ocioso, abrir a conexão custa cerca de 25 a 30 vezes mais que a própria consulta.**
- Numa requisição de `/clientes/:id/pedidos` com cerca de 20 consultas, isso dá cerca de 120 ms só de conexões. Esse número é uma conta feita a partir da tabela acima, não uma medição.
- **Sob carga, o custo tende a ser maior.** A criação do processo concorre pela mesma CPU que já está a 99%. Não medi isso isoladamente.

## Alterações

Só [`api/src/db.js`](../api/src/db.js):

| Antes | Depois |
|---|---|
| `new Client(config)`, `connect()`, `query()`, `end()` a cada chamada de `consultar` | um `Pool` único do `pg`, criado quando o módulo carrega; `consultar` chama `pool.query()` |
| — | `max: 10` (o padrão do node-postgres, deixado explícito) |
| — | `pool.on('error', ...)` registra erro de conexão ociosa, em vez de derrubar o processo |

- A assinatura de `consultar(sql, parametros)` não mudou, e `rotas.js` não foi tocado.
- Nenhuma rota usa transação, então reaproveitar a conexão entre consultas não muda o resultado de nenhuma delas.

**Por que `max: 10`:**
- a carga usa 20 usuários virtuais, e o banco tem 1 CPU;
- mais conexões simultâneas não dão mais CPU ao banco, só mais processos disputando a mesma CPU;
- 10 é o padrão, e a própria documentação diz que costuma bastar (ver Fundamentação).
- **Não testei outros tamanhos.** Fica como experimento futuro.

**Aplicação:** `docker compose up -d --build`. Recriei o banco antes da série (`docker compose down -v`) para manter as mesmas condições da série "antes".

**Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta) e na verificação antes de medir.

## Fundamentação

Nenhum dos artigos de [`referencias/`](../referencias/) trata de pool de conexões (procurei por "connection pool" e "database connection" no texto dos 11 PDFs). Por isso, a fundamentação desta mudança vem da documentação oficial, salva como texto em [`referencias/documentacao/`](../referencias/documentacao/):

- **node-postgres, "Pooling":** *"Connecting a new client to the PostgreSQL server requires a handshake which can take 20-30 milliseconds."* e *"Incurring this cost every time we want to execute a query would substantially slow down our application."*
  - No diagnóstico acima, medi cerca de 6 ms, menos que os 20 a 30 ms da documentação. A diferença é esperada aqui: a conexão não tem senha nem SSL (`POSTGRES_HOST_AUTH_METHOD: trust`) e não sai da máquina.
- **PostgreSQL 16, seção 52.2, "How Connections Are Established":** *"PostgreSQL implements a 'process per user' client/server model"* e o supervisor *"spawns a new backend process every time a connection is requested"*. É por isso que o custo cai na CPU do banco, e não só na rede.
- **node-postgres, "Pool Sizing":** *"Typically, though, I don't bother setting it to anything other than the default of 10 as that's usually fine."* O mesmo texto diz que, quando a aplicação fica sem conexões, o melhor é deixar as consultas mais rápidas ou usar cache, e não aumentar o pool.
- **node-postgres, "pg.Pool":** documenta `max` (padrão 10) e `idleTimeoutMillis` (padrão 10 s, tempo depois do qual uma conexão ociosa é fechada).

Fato e opinião, separados:
- **Fato:** são documentação de software (fontes primárias técnicas sobre o comportamento do driver e do banco), não estudos revisados por pares.
- **Opinião minha:** a frase sobre o tamanho do pool é a experiência do autor do node-postgres, não uma medição. Uso como ponto de partida, não como prova.

## Resultado

Mesma sessão, 2026-11-06, notebook na tomada, perfil `balanced`, banco recriado antes de cada série. Mediana de 3 execuções:

| Métrica | 01 (antes) | 02-pool-conexoes | Variação |
|---|---|---|---|
| Requisições/s | 8,52 | 14,25 | cerca de 1,7× |
| Mediana | 788,2 ms | 409,5 ms | −48% |
| p95 | 8361,2 ms | 5498,9 ms | −34% |
| p99 | 11243,5 ms | 10698,0 ms | −5% |
| Erros | 0,00% nas 3 | 0,00% nas 3 | – |
| CPU média do banco | 99,0% | 99,6% | – |
| Memória média do banco | 226,7 MiB | 281,8 MiB | +55 MiB |
| CPU média da API | 13,9% | 15,8% | – |
| Memória média da API | 44,9 MiB | 39,0 MiB | – |

**Pastas de resultados:**
- antes: `resultados/20261106-033945-01-indices-antes-02`, `20261106-034114-…`, `20261106-034245-…`;
- depois: `resultados/20261106-034611-02-pool-conexoes`, `20261106-034737-…`, `20261106-034906-…`.

**Por rota, na execução mediana de cada série** (`034114` antes, `034906` depois). São poucas amostras por rota, só para ver onde o ganho aparece:

| Rota | Mediana antes | Mediana depois |
|---|---|---|
| `cliente` | 345,3 ms | 194,3 ms |
| `cliente-por-email` | 378,4 ms | 192,6 ms |
| `pedidos-do-cliente` | 6000,5 ms | 2694,0 ms |
| `pedidos-por-status` | 1406,4 ms | 800,0 ms |
| `busca-produtos` | 698,7 ms | 397,9 ms |
| `vendas-por-dia` | 2770,6 ms | 2175,2 ms |
| `top-produtos` | 12048,8 ms | 12849,7 ms |

**Custo:**
- **Memória do banco:** +55 MiB na média (de 226,7 para 281,8 MiB, dentro do limite de 512 MB). Minha hipótese, ainda não verificada, é que são as até 10 conexões que agora ficam abertas, cada uma um processo do PostgreSQL com memória e cache de catálogo próprios. Antes, cada processo durava uma consulta só.
- **Conexões ocupadas:** até 10 das 100 permitidas (`max_connections`) ficam presas à API enquanto houver carga.
- Os limites de CPU e memória dos containers não mudaram, e não há serviço novo.

## Discussão

- **A hipótese se confirmou.** As req/s subiram cerca de 1,7× e a mediana geral caiu quase pela metade, com o mesmo banco a 99% de CPU. A CPU que ia para criar processos passou a responder consultas.
- **O ganho aparece onde a conexão pesava mais:**
  - `cliente` e `cliente-por-email`, cuja consulta custa menos de 1 ms, caíram cerca de 45 a 50%;
  - `pedidos-do-cliente`, com cerca de 20 conexões por requisição, caiu mais da metade.
- **`top-produtos` não melhorou, e é por isso que o p99 quase não mudou (−5%).** É uma consulta só, de cerca de 2,5 s no banco ocioso. O custo de uma conexão a mais ou a menos não aparece ali, e ela domina a cauda da distribuição.
- **A rota `cliente` ainda tem mediana de cerca de 200 ms sob carga, para uma consulta de menos de 1 ms.** O banco continua saturado, e o tempo é de fila. O próximo passo é reduzir o trabalho do banco, não o da API.
- **A primeira execução de cada série foi a mais lenta** (7,62 antes e 11,26 depois, contra 8,5 a 8,7 e 14,3 a 14,4 nas outras). As duas vieram logo depois de recriar o banco, o que sugere cache frio. Como as duas séries foram feitas do mesmo jeito, a comparação pela mediana não é afetada, mas o efeito existe e vale registrar.

## O que refutaria esta conclusão

- **Se repetir as séries** não reproduzir a diferença. Ainda não repeti em outro dia.
- **Se o ganho vier de outra coisa que mudou entre as séries.** Entre elas mudou só o `db.js` (commits `466d0f5` → `63b4693`, ver `contexto.txt`), na mesma sessão, com o banco recriado nos dois lados.
- **Se um pool maior ou menor der resultado bem diferente.** Isso não invalida o pool, mas mostraria que 10 não é o tamanho certo para este caso. Não testei.

## Próximo gargalo

O banco segue a 99% de CPU. Pelo tempo por rota e pelo peso na carga:
1. **o N+1 de `/clientes/:id/pedidos`** (mudança 03): 20% da carga e ainda cerca de 2,7 s de mediana;
2. **`top-produtos`** (06): poucas chamadas, mas cerca de 12 s cada, e domina o p99;
3. **`vendas-por-dia`** (04).

## Referências

1. node-postgres. *Pooling*. https://node-postgres.com/features/pooling (acesso em 2026-11-06; cópia em texto: [`referencias/documentacao/node-postgres-pooling.txt`](../referencias/documentacao/node-postgres-pooling.txt))
2. node-postgres. *pg.Pool*. https://node-postgres.com/apis/pool (acesso em 2026-11-06; [`node-postgres-api-pool.txt`](../referencias/documentacao/node-postgres-api-pool.txt))
3. node-postgres. *Pool Sizing*. https://node-postgres.com/guides/pool-sizing (acesso em 2026-11-06; [`node-postgres-pool-sizing.txt`](../referencias/documentacao/node-postgres-pool-sizing.txt))
4. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 52.2. How Connections Are Established*. https://www.postgresql.org/docs/16/connect-estab.html (acesso em 2026-11-06; [`postgresql-16-connect-estab.txt`](../referencias/documentacao/postgresql-16-connect-estab.txt))
