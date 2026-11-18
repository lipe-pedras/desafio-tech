# 03 · Eliminar o N+1 de `/clientes/:id/pedidos`

- **Status:** aplicada, medida e mantida, **fechada com `DB_POOL_MAX=1`** (ver [Decisão](#decisão))
- **Branch / commit da mudança:** `03-n-mais-1` / `958aad1` (JOIN), e `remedicao-desktop` / `c7dc4f3` (`DB_POOL_MAX=1`)
- **Comparada com:** o estado da `main` (02 com `DB_POOL_MAX=2`, commit `1fd2ae4`) e a 02 com `DB_POOL_MAX=1` (commit `d9ee2e5`), medidos na mesma sessão e no mesmo banco

> **Números oficiais: os do desktop (2026-11-10 e 2026-11-11).** As medições do notebook variaram demais entre sessões e entre execuções (a mesma versão deu 17,09 e 24,86 req/s em dias diferentes), então toda a sequência foi remedida num desktop, em rodízio (ver [`diagnostico/remedicao-desktop/`](../diagnostico/remedicao-desktop/README.md)). O resultado oficial está em [Resultado no desktop](#resultado-no-desktop-oficial). As seções do notebook ficam como histórico.

> **Correção (2026-11-09).** A medição em rodízio, com as versões num banco só, não confirmou o ganho de req/s desta ficha. Na comparação controlada, a 03 teve **23,23 req/s contra 24,86** (cerca de −7%), p95 −33%, p99 −41% e mediana cerca de 3,2× pior. Ver [`diagnostico/variacao-banco/`](../diagnostico/variacao-banco/README.md). Os números abaixo são da primeira medição, mantidos como registro.

## Hipótese

A rota faz uma consulta para o cliente, uma para os pedidos, uma para os itens de cada pedido e uma para o produto de cada item. Juntar pedidos, itens e produtos numa consulta só deve reduzir o trabalho do banco e as idas e voltas à fila do pool, aumentando as req/s e reduzindo a cauda (p95 e p99).

## Diagnóstico (antes)

Evidência: [`diagnostico/03-n-mais-1.txt`](../diagnostico/03-n-mais-1.txt), gerado por [`diagnostico/03-n-mais-1.sql`](../diagnostico/03-n-mais-1.sql).

| Consultas por requisição no código antigo (2 + pedidos + itens) | Valor |
|---|---|
| Média | 22,0 |
| Mediana | 22 |
| p95 | 32 |
| Máximo | 32 |

Com `DB_POOL_MAX=2`, cada uma dessas consultas entra separadamente na fila do pool.

## Alterações

Só o manipulador da rota em [`api/src/rotas.js`](../api/src/rotas.js):
- a consulta do cliente continua separada, para manter o 404;
- pedidos, itens e produtos vêm de uma consulta com `LEFT JOIN`, que mantém pedidos sem itens, ordenada por `p.criado_em DESC, p.id DESC, i.id`, a mesma ordem da resposta anterior;
- as linhas são agrupadas por pedido em JavaScript, e o total é somado como antes;
- a consulta traz só as colunas usadas, sem `SELECT *`.

A rota passa de 22 consultas em média para **2**. Com o cliente 31337 (5 pedidos, 10 itens), a consulta nova usa só índices existentes e levou 3,6 ms numa execução única com cache frio. Não foi preciso criar índice.

**No fechamento**, um segundo commit (`c7dc4f3`) muda só o `DB_POOL_MAX` de 2 para 1 no `docker-compose.yml`, com base na [03.1 no desktop](#031-no-desktop-tamanho-do-pool-com-o-código-da-03).

**Contrato:** mantido antes de medir e em todas as execuções, no notebook e no desktop.

## Fundamentação

Trechos localizados nos PDFs de [`referencias/`](../referencias/):

- **Shao et al. (2020), p. 4, AP-09:** descreve o antipadrão como *"Issuing one query to retrieve N objects from one table, and N other queries to retrieve information related to the N objects from another table"*, e a correção como *"Issuing one query with a join clause of the two tables"*. É o caso desta rota. O estudo cobre aplicações que escrevem SQL direto.
- **Yang et al. (2018), p. 7:** chama o padrão de *"N+1" query problem* e relata que ele continua frequente: *"it appears in 15 problematic actions and 9 performance issues in our study"*.
- **Chen et al. (2014), p. 8:** o impacto do processamento um a um cresce com os dados, *"because the data sizes directly affect the number of iterations in loops"*.
- **Yan et al. (2017), p. 5:** alerta o contrário: *"combined query may not be always faster than the original separated queries"*. Por isso a mudança foi medida, e não presumida.

Yang, Chen e Yan estudam aplicações com ORM; aqui a API escreve SQL direto. Tomo esses três como evidência da categoria do problema, não do caso exato.

## Resultado no desktop (oficial)

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. Em todas as séries, um banco único com os índices da 01 e as versões em rodízio, trocando só o container da API ([como foi medido](../diagnostico/remedicao-desktop/README.md#como-foi-remedido)). Contrato mantido, 0,00% de erros e `arquivos alterados sem commit: 0` em todas as execuções desta seção. Os números são medianas de 3 execuções, calculadas por [`analisar.py`](../diagnostico/analisar.py) com `--serie remedicao-desktop` ([`resumo.txt`](../diagnostico/remedicao-desktop/resumo.txt)).

### Fechamento: a 03 com pool 1 contra a 02 (2026-11-11)

Três versões em 3 rodadas, com a ordem deslocada: a 02 como está na `main` (pool 2), a 02 com pool 1 e a 03 com pool 1.

| Métrica | 02, pool 2 (`main`) | 02, pool 1 | 03, pool 1 |
|---|---|---|---|
| Requisições/s | 57,97 (56,60 / 59,10 / 57,97) | 61,86 (64,05 / 61,86 / 61,64) | **65,11** (65,11 / 63,37 / 65,17) |
| Média | 344,8 ms | 323,2 ms | 305,7 ms |
| Mediana | 97,3 ms | 77,4 ms | 218,0 ms |
| p95 | 1627,0 ms | 1602,5 ms | **792,9 ms** |
| p99 | 2779,1 ms | 2382,3 ms | **1093,3 ms** |
| CPU média do banco | 97,5% | 95,5% | 96,8% |
| Memória média do banco | 355,0 MiB | 168,3 MiB | 164,8 MiB |
| CPU média da API | 24,8% | 26,2% | 25,8% |
| Memória média da API | 34,5 MiB | 34,5 MiB | 34,1 MiB |

| Rota (mediana da rota nas 3) | 02, pool 2 | 02, pool 1 | 03, pool 1 |
|---|---|---|---|
| `cliente` | 10,9 ms | 14,3 ms | 141,8 ms |
| `cliente-por-email` | 10,3 ms | 14,0 ms | 149,9 ms |
| `pedidos-do-cliente` | 1083,9 ms | 1072,0 ms | 339,2 ms |
| `pedidos-por-status` | 104,4 ms | 87,9 ms | 332,1 ms |
| `busca-produtos` | 58,5 ms | 21,2 ms | 165,6 ms |
| `vendas-por-dia` | 157,4 ms | 95,2 ms | 222,1 ms |
| `top-produtos` | 803,8 ms | 401,4 ms | 509,4 ms |

**Pastas:** `resultados/20261111-0230…-03f-*-desktop` a `20261111-0242…-03f-*-desktop`, 3 por versão (lista completa no [`resumo.txt`](../diagnostico/remedicao-desktop/resumo.txt)).

**Ganho da 03 fechada (03 com pool 1) sobre a 02 da `main`:**

| | req/s | Média | Mediana | p95 | p99 |
|---|---|---|---|---|---|
| Total: 02 pool 2 → 03 pool 1 | +12% | −11% | 2,2× pior | −51% | −61% |
| Só o pool: 02 pool 2 → 02 pool 1 | +7% | −6% | −20% | −2% | −14% |
| Só o N+1, com pool 1: 02 pool 1 → 03 pool 1 | +5% | −5% | 2,8× pior | −51% | −54% |

- **O ganho em req/s vem mais do pool do que do N+1.** De pool 2 para 1, as execuções não se sobrepõem (56,60 a 59,10 contra 61,64 a 64,05). Do N+1 com pool 1, sim (61,64 a 64,05 contra 63,37 a 65,17): +5% é pequeno perto da variação entre execuções.
- **A cauda é ganho da 03.** O p95 cai cerca de 51% e o p99 cerca de 54 a 61%, porque `pedidos-do-cliente` cai de cerca de 1,08 s para 0,34 s.
- **A mediana piora**, como em todas as medições anteriores da 03. As rotas rápidas (`cliente`, `cliente-por-email`, `busca-produtos`) passam de 10 a 60 ms para 140 a 170 ms. Ver [Discussão](#discussão).

### A 03 com pool 2 contra a 02 com pool 2 (2026-11-10)

Do bloco B da remedição, mesma sessão e mesmo banco:

| Métrica | 02, pool 2 (`1fd2ae4`) | 03, pool 2 (`958aad1`) | Variação |
|---|---|---|---|
| Requisições/s | 59,89 | 59,41 | −1% |
| Média | 333,9 ms | 335,0 ms | – |
| Mediana | 96,4 ms | 254,1 ms | cerca de 2,6× pior |
| p95 | 1602,3 ms | 967,8 ms | −40% |
| p99 | 2603,4 ms | 1307,0 ms | −50% |
| Memória média do banco | 194,7 MiB | 181,1 MiB | – |

Com pool 2, a 03 empata em req/s e só ganha na cauda, o mesmo resultado do rodízio no notebook (−7% em req/s, p95 −33%). **O ganho de 1,33× em req/s da primeira medição no notebook não se repete.**

### 03.1 no desktop: tamanho do pool com o código da 03

**2026-11-10** (bloco B, mesma sessão):

| `max` | req/s | Mediana | p95 | p99 | Memória do banco |
|---|---|---|---|---|---|
| 2 | 59,41 | 254,1 ms | 967,8 ms | 1307,0 ms | 181,1 MiB |
| 5 | 47,28 | 312,4 ms | 997,3 ms | 2249,9 ms | 240,7 MiB |
| 10 | 39,17 | 298,5 ms | 1275,3 ms | 4797,0 ms | 335,3 MiB |

**2026-11-11** (rodízio só entre 1 e 2, banco novo; [`rodar-bloco-b.sh`](../diagnostico/remedicao-desktop/rodar-bloco-b.sh), título "031 pool 1"):

| `max` | req/s (3 execuções) | Mediana | p95 | p99 | Memória do banco |
|---|---|---|---|---|---|
| 1 | **65,37** (65,64 / 65,37 / 63,22) | 209,8 ms | 797,1 ms | 1100,4 ms | 179,5 MiB |
| 2 | 58,32 (58,05 / 58,52 / 58,32) | 280,7 ms | 916,5 ms | 1212,9 ms | 349,9 MiB |

- **Com o código da 03, o pool 1 também é o melhor:** +12% em req/s, sem sobreposição, −25% na mediana, −13% no p95 e −9% no p99. Todas as rotas ficaram mais rápidas, e `top-produtos` caiu de 981,6 para 513,9 ms.
- **A ordem 1 > 2 > 5 > 10 se mantém**, igual à da 02.1.
- O 03 com pool 2 se repetiu entre as duas sessões: 59,41 e 58,32 req/s.

**Pastas:** `resultados/20261110-*-03-n-mais-1-desktop`, `20261110-*-031-pool-max-{5,10}-desktop`, `20261111-*-031-pool-max-{1,2}-desktop`.

## Resultado no notebook (histórico)

Mesma sessão, 2026-11-08, notebook na tomada, perfil `balanced`, banco recriado antes de cada série, `DB_POOL_MAX=2`. Mediana de 3 execuções:

| Métrica | Antes | 03-n-mais-1 | Variação |
|---|---|---|---|
| Requisições/s | 17,09 | 22,74 | cerca de 1,33× |
| Média do tempo de resposta | 1168,0 ms | 877,0 ms | −25% |
| Mediana | 208,2 ms | 623,0 ms | **cerca de 3× pior** |
| p95 | 5904,6 ms | 2502,8 ms | −58% |
| p99 | 8161,4 ms | 3307,0 ms | −59% |
| Erros | 0,00% nas 3 | 0,00% nas 3 | – |
| CPU média do banco | 99,9% | 100,1% | – |
| Memória média do banco | 230,5 MiB | 193,8 MiB | −37 MiB |
| CPU média da API | 16,9% | 16,3% | – |
| Memória média da API | 123,8 MiB | 31,5 MiB | ver Discussão |

A média vem do campo `http_req_duration.avg` do `resumo-k6.json` de cada pasta.

**Por rota** (mediana da rota nas 3 execuções):

| Rota | Antes | Depois |
|---|---|---|
| `cliente` | 80,9 ms | 410,4 ms |
| `cliente-por-email` | 84,6 ms | 487,6 ms |
| `pedidos-do-cliente` | 4326,3 ms | 887,0 ms |
| `pedidos-por-status` | 311,2 ms | 1016,2 ms |
| `busca-produtos` | 93,4 ms | 497,8 ms |
| `vendas-por-dia` | 650,6 ms | 803,3 ms |
| `top-produtos` | 2445,0 ms | 2779,6 ms |

**Pastas de resultados:**
- antes: `resultados/20261108-224042-02-pool-2-antes-03`, `20261108-224207-…`, `20261108-224331-…`;
- depois: `resultados/20261108-224620-03-n-mais-1`, `20261108-224747-…`, `20261108-224910-…`.

**Custo:** nenhum recurso novo. Os limites dos containers não mudaram, não há índice ou serviço novo, e a memória do banco caiu.

## Discussão

- **A hipótese se confirmou para req/s, média e cauda.** A rota-alvo caiu cerca de 79% (de 4,3 s para 0,89 s), e o p95 e o p99 caíram mais da metade, porque ela era a principal responsável pela cauda.
- **A mediana geral piorou cerca de 3×, e as rotas rápidas ficaram mais lentas.** Esse efeito não estava na hipótese e não pode ficar de fora. `cliente`, por exemplo, foi de 80,9 para 410,4 ms.
- **A explicação foi testada em [um diagnóstico à parte](../diagnostico/03-mediana/README.md), que não é resultado oficial.** Ele confirmou o mecanismo: a fila do pool tem o mesmo tamanho, mas passou a ter consultas mais pesadas (execução média de 14,4 para 61,6 ms). A hipótese original era: a carga é de ciclo fechado (20 usuários, sem pausa entre requisições). Antes, muitos usuários ficavam presos em `pedidos-do-cliente`, enviando consultas minúsculas, uma por vez, e a fila do pool andava rápido. Agora eles saem dessa rota e voltam a chamar as outras, inclusive as pesadas. Cada consulta rápida tem mais chance de disputar o banco com `top-produtos`, `vendas-por-dia` ou a paginação de `/pedidos`. O banco segue a 100% de CPU: o trabalho ficou mais bem distribuído entre as requisições, não acabou. A variação do pool (abaixo) descartou a parte desta hipótese que culpava as 2 conexões.
- **O saldo é positivo para quem mede a cauda e o total atendido,** e negativo para a requisição típica. Dependendo do que importa no produto, isso muda a leitura. Os próximos passos atacam as consultas pesadas, que devem aliviar justamente essa fila.
- **O `DB_POOL_MAX=2` foi escolhido com o N+1 ainda presente.** A ficha da [02.1](02.1-tamanho-do-pool.md) previa medir de novo depois desta mudança; isso foi feito na seção seguinte, e o 2 continua o melhor.
- **Memória da API:** 123,8 MiB antes e 31,5 MiB depois. O mesmo padrão de cerca de 124 MiB já tinha aparecido em séries da 02.1, sem relação clara com o pool. Não investiguei, então não atribuo a queda a esta mudança.

## 03.1 · Tamanho do pool depois da 03 (notebook, histórico)

Mesmo código da 03, com `DB_POOL_MAX` de 2, 5 e 10, em 2026-11-08 (22h58 a 23h14), na tomada, perfil `balanced`, banco recriado antes de cada tamanho. Ordem: 5, 10 e 2. Contrato mantido e 0,00% de erros nas 9 execuções. Mediana de 3 execuções:

| `max` | req/s | Média | Mediana | p95 | p99 | Memória do banco |
|---|---|---|---|---|---|---|
| 2 | 23,50 | 848,8 ms | 672,9 ms | 2528,2 ms | 3679,7 ms | 189,2 MiB |
| 5 | 15,95 | 1244,3 ms | 984,9 ms | 3102,5 ms | 7816,3 ms | 237,7 MiB |
| 10 | 12,82 | 1509,7 ms | 800,7 ms | 4710,5 ms | 13112,8 ms | 279,1 MiB |

| Rota (mediana das 3) | `max=2` | `max=5` | `max=10` |
|---|---|---|---|
| `cliente` | 405,3 ms | 585,0 ms | 458,4 ms |
| `cliente-por-email` | 440,4 ms | 593,9 ms | 503,6 ms |
| `pedidos-do-cliente` | 991,6 ms | 1296,2 ms | 997,2 ms |
| `pedidos-por-status` | 1083,6 ms | 1599,4 ms | 1611,0 ms |
| `busca-produtos` | 502,4 ms | 794,0 ms | 804,7 ms |
| `vendas-por-dia` | 709,9 ms | 1519,6 ms | 3515,6 ms |
| `top-produtos` | 2691,6 ms | 8306,8 ms | 14452,4 ms |

**Pastas:** `resultados/20261108-225931-…` a `20261108-231319-031-pool-max-N` (3 por tamanho).

- **O 2 continua o melhor.** Contra 10: cerca de 1,83× em req/s, média −44%, mediana −16%, p95 −46%, p99 −72% e 90 MiB a menos no banco. Mantive `DB_POOL_MAX=2`.
- **A hipótese de que as 2 conexões travavam as rotas rápidas foi refutada.** Pools maiores não aceleraram nenhuma delas: `cliente` ficou em 405,3 ms com 2, 585,0 ms com 5 e 458,4 ms com 10. O limite é a CPU do banco, não o número de conexões.
- **A explicação pela mistura de rotas foi confirmada depois**, em [diagnóstico à parte](../diagnostico/03-mediana/README.md).
- **A série com `max=2` repete a da 03** (23,50 contra 22,74 req/s; p95 de 2528,2 contra 2502,8 ms), na mesma sessão.
- **Limite:** não testei 1 nem 3 nesta versão, e a série com 5 variou bastante entre execuções (12,74 a 17,37 req/s).

## Decisão

**A 03 está fechada: o JOIN fica, e o pool passa para `DB_POOL_MAX=1`** (commit `c7dc4f3`).

Contra a 02 da `main`, medida na mesma sessão e no mesmo banco no desktop ([Fechamento](#fechamento-a-03-com-pool-1-contra-a-02-2026-11-11)):
- **+12% em req/s** (57,97 → 65,11), **p95 −51%** (1627,0 → 792,9 ms), **p99 −61%** (2779,1 → 1093,3 ms) e média −11%;
- **mediana cerca de 2,2× pior** (97,3 → 218,0 ms): a requisição típica de uma rota rápida fica mais lenta;
- sem nenhum recurso novo: os limites dos containers não mudaram.

**Por que o pool 1:** com o código da 03, ele foi o melhor tamanho em req/s, mediana, p95 e p99, sem sobreposição com o 2 ([03.1 no desktop](#031-no-desktop-tamanho-do-pool-com-o-código-da-03)). O mesmo vale para a 02 ([02.1](02.1-tamanho-do-pool.md#resultado-no-desktop-oficial)). Os riscos de um pool de 1 estão na [02.1](02.1-tamanho-do-pool.md#riscos-de-um-pool-muito-pequeno): uma consulta lenta bloqueia todas as outras, e uma transação longa prende a única conexão.

**Por que o JOIN, se sozinho ele quase não muda as req/s** (+5% com pool 1, dentro da variação; −1% com pool 2): ele troca mediana por cauda, e reduz o p95 e o p99 pela metade. Além disso, há o argumento de escalabilidade, abaixo.

**Escalabilidade.** As consultas do tipo N+1 crescem com N: no código antigo, cada requisição fazia 2 + pedidos + itens consultas (22 em média e 32 no máximo, com os dados atuais), e cada uma entrava separadamente na fila do pool. Com a consulta única, são sempre 2, seja qual for o histórico do cliente. A consulta usa só varreduras por índice (`pedidos_cliente_id_criado_em_idx`, `itens_pedido_pedido_id_idx` e `produtos_pkey`; ver [`diagnostico/03-n-mais-1.txt`](../diagnostico/03-n-mais-1.txt)), e os índices já existiam desde a 01. Assim, o custo da rota passa a crescer só com as linhas do próprio cliente, encontradas por índice, sem novas idas ao banco.

**Limite:** o número de consultas por requisição foi medido, mas o ganho com mais dados não: todas as medições usam o volume atual. A escalabilidade é a razão da decisão, sustentada pelo plano e por Chen et al. (2014), não um resultado medido.

### De onde vem a alta da média (notebook; conta sobre o diagnóstico, não é resultado oficial)

Calculado a partir de [`diagnostico/03-mediana/resumo.txt`](../diagnostico/03-mediana/resumo.txt), com a mediana de cada valor nas 3 rodadas e 60 s de carga:

| Por requisição | Antes | Depois | Diferença |
|---|---|---|---|
| Espera na fila do pool (fila ÷ req/s) | 712 ms | 758 ms | +46 ms |
| Execução no banco (execução somada ÷ requisições) | 79,5 ms | 83,7 ms | +4 ms |
| Soma | 791 ms | 842 ms | +50 ms |
| Média medida pelo k6 | 796,4 ms | 844,1 ms | +48 ms |

- **Quase toda a alta aparece como espera na fila**, mas a fila não é a origem: seu tamanho é o mesmo (17,69 e 17,92), definido pelos 20 usuários em ciclo fechado.
- **A origem é a execução por requisição, cerca de 5% maior.** As 2 conexões ficam ocupadas quase o tempo todo (cerca de 118 s de 120 s), então req/s ≈ tempo disponível ÷ execução por requisição. Com menos req/s e a mesma fila, cada requisição espera mais.
- A 03 economiza execução em `pedidos-do-cliente` (de cerca de 43,7 para 14,5 ms por requisição), mas as outras rotas passaram a executar mais devagar, e a soma ficou maior. **Por que elas ficaram mais lentas não foi testado.**

## O que refutaria esta conclusão

- **Se repetir as séries não reproduzir a queda da cauda.** Ela já se repetiu em todas as comparações: no diagnóstico do notebook, no rodízio do notebook e nas duas sessões do desktop. O ganho de 1,33× em req/s da primeira medição não se repetiu e foi descartado.
- **Se o pool 1 perder para o 2 em outra máquina.** No desktop, o 1 venceu nas duas versões (02 e 03) e nas três sessões em que foi medido, sem sobreposição. No notebook, empatava dentro do ruído.
- **Se a carga tiver mais relatórios.** Com pool 1, uma consulta lenta bloqueia todas as outras. A carga do desafio tem só 10% de relatórios (8% `vendas-por-dia` e 2% `top-produtos`) e não testa esse caso.

## Próximo gargalo

O banco segue perto de 100% de CPU (96,8% na média com a 03 e pool 1). Com pool 1, toda consulta passa pela mesma fila, então reduzir o trabalho de qualquer rota acelera todas as outras. No desktop, as rotas mais lentas com a 03 fechada são `top-produtos` (509,4 ms), `pedidos-do-cliente` (339,2 ms) e `pedidos-por-status` (332,1 ms) ([Fechamento](#fechamento-a-03-com-pool-1-contra-a-02-2026-11-11)). Candidatas: 04 (refazer `vendas-por-dia`), 06 (pré-calcular `top-produtos`) e a contagem de `pedidos-por-status`.

## Referências

1. Shao, S. et al. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020. DOI 10.1109/ICSME46990.2020.00016. https://par.nsf.gov/servlets/purl/10277614
2. Yang, J. et al. *How not to structure your database-backed web applications: a study of performance bugs in the wild*. ICSE 2018. https://par.nsf.gov/servlets/purl/10067547
3. Chen, T.-H. et al. *Detecting Performance Anti-patterns for Applications Developed using Object-Relational Mapping*. ICSE 2014. https://ece.uwaterloo.ca/~wshang/pubs/peter_icse2014.pdf
4. Yan, C. et al. *Understanding Database Performance Inefficiencies in Real-world Web Applications*. CIKM 2017. https://www.cc.gatech.edu/~jarulraj/courses/8803-f18/papers/db_study.pdf
