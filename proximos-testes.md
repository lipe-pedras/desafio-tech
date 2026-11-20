# Próximos testes

Ideias que apareceram na pesquisa ou nas medições e que **não foram aplicadas nem medidas**. Nenhum número de ganho abaixo foi medido: o que está em "O que espero ganhar" é hipótese. Os números citados como evidência vêm de arquivos do repositório, com link. As mudanças aplicadas e medidas estão em [`experimentos.md`](experimentos.md).

Cada ficha traz: de onde veio a ideia, o que espero ganhar, como testaria e o que precisaria para testar. As fichas estão em ordem de prioridade: primeiro o que ataca o gargalo atual, depois o que reduz os custos que a solução criou, por fim o que só vale com outra carga ou outro contrato.

| # | Ideia | Por que importa agora | Prioridade |
|---|---|---|---|
| 1 | [Redistribuir a CPU entre API e banco, com o mesmo total](#1-redistribuir-a-cpu-entre-api-e-banco-com-o-mesmo-total) | Depois da 09.2, o gargalo é a API | Alta |
| 2 | [Menos trabalho por requisição na API](#2-menos-trabalho-por-requisição-na-api) | Idem | Média |
| 3 | [Contadores divididos nas tabelas de totais](#3-contadores-divididos-nas-tabelas-de-totais) | Reduz o custo de escrita da 05.2 e da 09.2 | Alta |
| 4 | [Totais por dia só para dias fechados](#4-totais-por-dia-só-para-dias-fechados) | Idem, só para a 09.2 | Média |
| 5 | [`pg_ivm` no lugar dos gatilhos escritos à mão](#5-pg_ivm-no-lugar-dos-gatilhos-escritos-à-mão) | Menos código para manter | Baixa |
| 6 | [Índice BRIN em `pedidos (criado_em)`](#6-índice-brin-em-pedidos-criado_em) | Alternativa barata se os gatilhos forem rejeitados; os dados do desafio não estão em ordem de data | Baixa |
| 7 | [`shared_buffers` e `work_mem`](#7-shared_buffers-e-work_mem) | Não testado em nenhum momento | Baixa |
| 8 | [GiST no lugar de GIN para a busca](#8-gist-no-lugar-de-gin-para-a-busca) | Custo de escrita em `produtos` | Baixa |
| 9 | [Pool de 1 conexão com outra mistura de rotas](#9-pool-de-1-conexão-com-outra-mistura-de-rotas) | Verifica o maior risco da solução | Alta |
| 10 | [Paginação por cursor em `/pedidos`](#10-paginação-por-cursor-em-pedidos) | Exige mudar o contrato | Fora do escopo |
| 11 | [Cache na API com invalidação](#11-cache-na-api-com-invalidação) | Exige lidar com dados desatualizados | Fora do escopo |

No fim, [medições que ficaram faltando](#medições-que-ficaram-faltando) e [ideias descartadas sem teste](#ideias-descartadas-sem-teste).

---

## 1. Redistribuir a CPU entre API e banco, com o mesmo total

**Status:** Pesquisada, teste futuro.

**De onde veio:** das medições da 09.2. Com ela, o banco caiu para 70,5% de CPU, enquanto a API foi a 49,7% do host, isto é, o limite de 0,5 CPU. Os contadores de cota mostram a API pausada em 63,7 a 67,2% dos períodos de 100 ms, contra 0 antes da 09.2 ([`diagnostico/09-resumo.txt`](diagnostico/09-resumo.txt), [ficha da 09.2](experimentos/09.2-total-por-dia.md#resultado)). McSherry et al. ([HotOS 2015](https://www.usenix.org/conference/hotos15/workshop-program/presentation/mcsherry)) defendem comparar um ganho com o recurso que ele gasta; aqui o total gasto não muda.

**O que espero ganhar:** hoje o conjunto paga 1,5 CPU, e a API usa só 0,5 delas, saturada. Passar para, por exemplo, 0,75 para a API e 0,75 para o banco mantém o custo e deve aumentar as req/s até o banco saturar de novo. O banco usou cerca de 0,70 CPU na 09.2, então a folga é pequena: o ponto ótimo pode estar entre 0,6 e 0,8 para a API.

**Como testaria:** mudar só os dois `cpus` no `docker-compose.yml`, em commits separados (0,6/0,9, 0,75/0,75, 0,9/0,6), e medir em rodízio com a `main` usando [`diagnostico/rodizio.sh`](diagnostico/rodizio.sh), com os contadores de cota de CPU dos dois containers. A conclusão sairia das req/s, do p95 e de quem passa a ser pausado.

**O que precisaria:** nada além do que já existe. O cuidado é apresentar o resultado como "mesmo custo, outra divisão", e não como CPU a mais.

## 2. Menos trabalho por requisição na API

**Status:** Pesquisada, teste futuro.

**De onde veio:** do mesmo diagnóstico da ficha 1. A documentação do node-postgres ([Queries](https://node-postgres.com/features/queries), salva em [`referencias/documentacao/node-postgres-queries.txt`](referencias/documentacao/node-postgres-queries.txt)) descreve duas opções:
- **consultas preparadas** (`name` na consulta): o PostgreSQL guarda o plano por conexão e pula a análise da consulta a partir da segunda vez;
- **`rowMode: 'array'`:** devolve cada linha como lista, sem montar um objeto por linha.

A mesma página avisa: *"Most of your queries will likely not benefit much, if at all, from using prepared statements."*

**O que espero ganhar:** pouco, e talvez nada. Com pool de 1 conexão, cada consulta preparada é analisada uma vez só, o que poupa CPU do banco, mas o banco já não é o gargalo. `rowMode: 'array'` poupa CPU da API, que é o gargalo, mas as respostas têm no máximo algumas dezenas de linhas. Só vale testar depois da ficha 1, se a API continuar saturada.

**Como testaria:** uma mudança por vez: primeiro `name` nas consultas das três rotas de maior peso (`/clientes/:id`, `/clientes/:id/pedidos` e `/clientes?email=`); depois `rowMode`. Contrato, rodízio com a `main` e CPU da API pelos contadores de cota.

**O que precisaria:** nada além do que já existe. Com `rowMode`, a montagem da resposta muda, e o contrato precisa ser conferido com atenção.

## 3. Contadores divididos nas tabelas de totais

**Status:** Pesquisada, teste futuro.

**De onde veio:** do custo de escrita medido. Com 8 clientes simultâneos, a 05.2 reduziu em 59% as transações/s de INSERT e em 71% as de UPDATE de status ([`diagnostico/052-custo-concorrente.txt`](diagnostico/052-custo-concorrente.txt)). A 09.2 reduziu em 74% os INSERTs simultâneos no mesmo dia ([`diagnostico/092-custo-concorrente.txt`](diagnostico/092-custo-concorrente.txt)). Nos dois casos, todas as escritas atualizam poucas linhas (4 status, 1 dia) e esperam umas pelas outras. A documentação do Cloud Firestore descreve a solução de mercado, o contador distribuído ([Distributed counters](https://firebase.google.com/docs/firestore/solutions/counters), salva em [`referencias/documentacao/firestore-distributed-counters.txt`](referencias/documentacao/firestore-distributed-counters.txt)): *"Write throughput increases linearly with the number of shards, so a distributed counter with 10 shards can handle 10x as many writes as a traditional counter."* É outro banco, mas o problema, várias escritas na mesma linha, é o mesmo.

**O que espero ganhar:** recuperar boa parte das transações/s perdidas, à custa de uma leitura um pouco mais cara (somar N linhas em vez de ler 1). Para as rotas lidas, espero diferença pequena: N linhas por status ou por dia continuam poucas.

**Como testaria:** acrescentar uma coluna `fatia` (0 a N−1) a `pedidos_por_status` e `vendas_por_dia`, com o gatilho escolhendo a fatia por `pg_backend_pid() % N`; a rota lê `sum(...)` agrupando por status ou por dia. Medir com N = 4 e 8:
- custo de escrita com [`diagnostico/052-custo-concorrente.sh`](diagnostico/052-custo-concorrente.sh) e [`092-custo-concorrente.sh`](diagnostico/092-custo-concorrente.sh), contra a `main`;
- leitura com o `medir.sh`, em rodízio;
- correção contra o recálculo completo, como em [`diagnostico/062-gatilho.txt`](diagnostico/062-gatilho.txt).

**O que precisaria:** nada além do que já existe.

## 4. Totais por dia só para dias fechados

**Status:** Pesquisada, teste futuro.

**De onde veio:** da [ficha da 09.2](experimentos/09.2-total-por-dia.md#alternativas-consideradas-e-não-testadas). A disputa da 09.2 acontece porque as compras de hoje atualizam a mesma linha. Gupta e Mumick ([1995](http://sites.computer.org/debull/95JUN-CD.pdf)) tratam a manutenção incremental como escolha entre recalcular e atualizar; aqui seriam as duas, por faixa de datas.

**O que espero ganhar:** escritas de hoje sem gatilho de total (a disputa medida some), com a leitura dos dias passados igual à da 09.2. O custo vai para as chamadas que incluem hoje, que voltariam a agregar um dia de pedidos pelos índices da 09.

**Como testaria:** um job (ou um gatilho na virada do dia) consolida o dia anterior em `vendas_por_dia`; a rota soma a tabela para os dias fechados e agrega só hoje. A carga do desafio não sorteia datas recentes (vai até 2025-12-31), então mediria a leitura com um script de carga próprio, fora de `carga/`, que inclua hoje. As escritas, com o [`092-custo-concorrente.sh`](diagnostico/092-custo-concorrente.sh).

**O que precisaria:** um agendador (cron no container ou `pg_cron`) e um script de carga com datas recentes.

## 5. `pg_ivm` no lugar dos gatilhos escritos à mão

**Status:** Pesquisada, teste futuro.

**De onde veio:** do README da extensão ([sraoss/pg_ivm](https://github.com/sraoss/pg_ivm), salvo em [`referencias/documentacao/pg-ivm-readme.txt`](referencias/documentacao/pg-ivm-readme.txt)). Ela cria visões materializadas que se atualizam sozinhas a cada escrita, com gatilhos gerados automaticamente. Suporta PostgreSQL 13 a 19 e os agregados `count`, `sum`, `avg`, `min` e `max`.

**O que espero ganhar:** a mesma leitura das versões 05.2, 06.2 e 09.2, com menos código próprio, que hoje são 3 arquivos de gatilhos, cada um com seu teste de correção. Não espero ganho de desempenho, e o custo de escrita pode ser maior que o dos gatilhos escritos à mão.

**Limites que já vi:** o README diz que *"Aggregate functions cannot be used with outer joins"* e não lista `count(DISTINCT ...)` entre os agregados aceitos. O total por dia da 09.2 usa `count(DISTINCT p.id)` ([`banco/09-total-vendas-por-dia.sql`](banco/09-total-vendas-por-dia.sql)), então provavelmente precisaria ser reescrito (por exemplo, contar pedidos numa visão e itens em outra).

**Como testaria:** trocar uma tabela de totais por vez (começando por `pedidos_por_status`, a mais simples), conferir o contrato e a correção contra o recálculo, medir leitura em rodízio e escrita com o `pgbench`, como na 05.2.

**O que precisaria:** uma imagem do PostgreSQL com a extensão compilada (um `Dockerfile` para o serviço `banco`), o que acrescenta uma dependência ao projeto.

## 6. Índice BRIN em `pedidos (criado_em)`

**Status:** Pesquisada, teste futuro.

**De onde veio:** da [ficha da 04](experimentos/04-vendas-por-dia.md#alternativas-consideradas-e-não-testadas) e da documentação do PostgreSQL ([71.1. BRIN](https://www.postgresql.org/docs/16/brin-intro.html), salva em [`referencias/documentacao/postgresql-16-brin-intro.txt`](referencias/documentacao/postgresql-16-brin-intro.txt)). O exemplo da própria documentação é este caso: *"a table storing a store's sale orders might have a date column on which each order was placed, and most of the time the entries for earlier orders will appear earlier in the table as well"*.

**O que espero ganhar:** um índice muito menor que o B-tree da 04.1 e mais barato de manter nas escritas, com leitura um pouco pior, porque o BRIN devolve faixas de páginas e o banco confere as linhas. Só faz sentido se a 09.2 for rejeitada pelo custo de escrita, porque com ela `vendas-por-dia` nem lê `pedidos`.

**Um obstáculo nos dados do desafio:** o [`banco/02-dados.sql`](banco/02-dados.sql) gera `criado_em` como `(i * 104729) % (731 dias)`, ou seja, as datas saem embaralhadas em relação à ordem em que os pedidos são inseridos. Numa loja real, os pedidos chegam em ordem de data; aqui, não. Com os dados como estão, espero que o BRIN quase não filtre páginas.

**Como testaria:**
1. Confirmar o obstáculo: `SELECT correlation FROM pg_stats WHERE tablename = 'pedidos' AND attname = 'criado_em'`, com a saída salva em `diagnostico/`. Espero um valor perto de 0.
2. Num `.sql` novo em `banco/`, reordenar a tabela por data (`CLUSTER pedidos USING` o índice de `criado_em`, seguido de `ANALYZE`). Isso não muda o conteúdo das respostas, só a posição física das linhas, mas é uma mudança por si só e seria medida sozinha antes do BRIN.
3. Trocar o B-tree da 04.1 pelo BRIN sobre a versão 09 (sem a 09.2) e medir em rodízio, comparando também o tamanho dos índices.

**O que precisaria:** nada além do que já existe. O `CLUSTER` precisa de cuidado na leitura do resultado, porque também muda a localidade de outras consultas em `pedidos`.

## 7. `shared_buffers` e `work_mem`

**Status:** Pesquisada, teste futuro.

**De onde veio:** da documentação do PostgreSQL ([20.4.1. Memory](https://www.postgresql.org/docs/16/runtime-config-resource.html), salva em [`referencias/documentacao/postgresql-16-runtime-config-resource-memoria.txt`](referencias/documentacao/postgresql-16-runtime-config-resource-memoria.txt)) e da [ficha da 09](experimentos/09-vendas-por-dia.md), que deixou em aberto se parte do ganho veio de cache. A documentação sugere 25% da memória como ponto de partida para `shared_buffers`, em servidores com 1 GB ou mais; o padrão é 128 MB. O `work_mem` padrão é 4 MB; na 06.1, a tabela de hash de `top-produtos` não coube nele e foi dividida em 4 lotes ([ficha da 06.1](experimentos/06.1-sem-paralelismo.md)).

**O que espero ganhar:** pouco na versão final. O banco tem 512 MB, e os 128 MB padrão já são 25% disso; a memória média medida ficou em cerca de 151 MiB. Depois da 06.2 e da 09.2, as consultas pesadas que usavam `work_mem` deixaram de existir. O teste serviria mais para confirmar que a configuração não é um gargalo escondido do que para ganhar desempenho.

**Como testaria:** `shared_buffers` em 64, 128 e 256 MB, um commit por valor, com `-c` no `command` do serviço `banco`, medindo em rodízio. Acompanharia a memória do banco no `recursos.csv`, porque 256 MB de `shared_buffers` num limite de 512 MB pode levar o container ao limite.

**O que precisaria:** nada além do que já existe.

## 8. GiST no lugar de GIN para a busca

**Status:** Pesquisada, teste futuro.

**De onde veio:** da [ficha da 07](experimentos/07-busca-trigramas.md), que escolheu GIN sem testar GiST. O `pg_trgm` aceita os dois ([F.35](https://www.postgresql.org/docs/16/pgtrgm.html)). Para busca textual, a documentação diz que *"GIN indexes are the preferred text search index type"* e que o GiST tem perdas (*"lossy"*), porque cada linha vira uma assinatura de tamanho fixo ([12.9](https://www.postgresql.org/docs/16/textsearch-indexes.html), salva em [`referencias/documentacao/postgresql-16-textsearch-indexes.txt`](referencias/documentacao/postgresql-16-textsearch-indexes.txt)). Esse trecho trata de `tsvector`, não de trigramas, então vale como indicação, não como prova.

**O que espero ganhar:** nada na leitura; provavelmente uma busca um pouco mais lenta. A vantagem possível do GiST está nas escritas em `produtos`, que a carga não faz.

**Como testaria:** trocar o índice da 07 por GiST, medir a leitura em rodízio e o custo de INSERT e UPDATE de nome em `produtos` com `pgbench`, como na 05.2.

**O que precisaria:** nada além do que já existe. Prioridade baixa: só vale se `produtos` passar a receber muitas escritas.

## 9. Pool de 1 conexão com outra mistura de rotas

**Status:** Pesquisada, teste futuro (verificação de um limite).

**De onde veio:** das fichas [02.1](experimentos/02.1-tamanho-do-pool.md), [03](experimentos/03-n-mais-1.md) e [08](experimentos/08-tamanho-do-pool.md). Com 1 conexão, uma consulta lenta faz todas as outras esperarem. O HikariCP defende o pool pequeno ([About Pool Sizing](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing)), mas o tamanho certo depende da carga, e a carga do desafio é fixa: só 10% de relatórios.

**O que espero ganhar:** não é um ganho, é saber até onde a escolha vale. Na versão final, todos os relatórios leem tabelas pequenas, então espero que o pool de 1 continue o melhor. Se uma consulta nova voltar a demorar centenas de milissegundos, o pool de 2 ou 3 deve passar a ganhar na cauda.

**Como testaria:** um script de carga próprio, fora de `carga/` (a régua não muda), com os mesmos 20 usuários e pesos diferentes:
- 30% de relatórios;
- uma rota lenta de propósito, por exemplo `vendas-por-dia` na versão 09, sem a tabela de totais.

Mediria `DB_POOL_MAX` = 1, 2, 3 e 5 em rodízio, olhando o p99 por rota.

**O que precisaria:** escrever esse script de carga e guardá-lo em `diagnostico/`, deixando claro que os resultados não são comparáveis com os do `medir.sh`.

## 10. Paginação por cursor em `/pedidos`

**Status:** Pesquisada, fora do escopo do contrato.

**De onde veio:** da [ficha da 05](experimentos/05-pedidos-por-status.md#alternativas-consideradas-e-não-testadas) e da documentação do PostgreSQL ([7.6. LIMIT and OFFSET](https://www.postgresql.org/docs/16/queries-limit.html), salva em [`referencias/documentacao/postgresql-16-queries-limit.txt`](referencias/documentacao/postgresql-16-queries-limit.txt)): *"The rows skipped by an OFFSET clause still have to be computed inside the server; therefore a large OFFSET might be inefficient."* A carga sorteia páginas de 1 a 1000, então até 20 mil linhas puladas por chamada.

**O que espero ganhar:** custo constante por página, em vez de crescer com o número da página. Hoje a rota já lê só do índice (05.1), então o ganho é menor do que seria na linha de base.

**Como testaria:** não dá para testar aqui sem mudar a resposta. Com cursor, a rota recebe "depois do pedido X" em vez de `pagina`, e o contrato pede `pagina`. Seria uma proposta de mudança de API, a negociar com quem consome a rota.

**O que precisaria:** autorização para mudar o contrato e um contrato novo gravado.

## 11. Cache na API com invalidação

**Status:** Pesquisada, fora do escopo escolhido.

**De onde veio:** de Nishtala et al. ([Scaling Memcache at Facebook, NSDI 2013](https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala)), que descrevem o cache na frente do banco (*look-aside*) e o custo de manter a consistência. A rota mais chamada, `/clientes/:id` (25% da carga), lê uma linha que muda pouco.

**O que espero ganhar:** como a carga só lê, um cache passaria no verificador de contrato e reduziria bastante o trabalho do banco. Mas a carga sorteia entre 100 mil clientes de forma uniforme ([`carga/teste-carga.js`](carga/teste-carga.js)), então a taxa de acerto cresce devagar ao longo de 60 s. E, depois da 09.2, o gargalo é a API, que é onde o cache gastaria CPU e memória.

**Como testaria:** um `Map` com limite de tamanho na API, só para `/clientes/:id`, invalidado por `LISTEN/NOTIFY` a cada UPDATE em `clientes`. Mediria leitura em rodízio e o tempo entre uma escrita e a invalidação.

**O que precisaria:** decidir quanto tempo de dado desatualizado é aceitável, o que é decisão de produto. Por isso não entrou na solução: preferi totais sempre exatos (ver a seção 4 do [artigo](artigo/artigo.md)).

---

## Medições que ficaram faltando

Custos das mudanças aplicadas que a carga do desafio não mede e que não medi à parte:

- **Gatilhos com DELETE e TRUNCATE** (05.2, 06.2, 09.2): atualizam os totais, mas só INSERT e UPDATE foram medidos ([ficha da 05.2](experimentos/05.2-total-por-status.md)).
- **Escrita com os índices com `INCLUDE`** (05.1, 09): cada INSERT ou UPDATE grava também as colunas incluídas ([ficha da 09](experimentos/09-vendas-por-dia.md)).
- **Escrita em `produtos` com o índice de trigramas** (07) ([ficha da 07](experimentos/07-busca-trigramas.md)).
- **Mapa de visibilidade sob escrita contínua** (05.1, 09): o *index-only scan* depende de páginas marcadas como visíveis, e escritas frequentes desmarcam as páginas até o próximo vacuum ([ficha da 05](experimentos/05-pedidos-por-status.md)).
- **Outra máquina e outro volume de dados:** todas as medições foram feitas num único desktop, com os dados que o `02-dados.sql` gera.

## Ideias descartadas sem teste

| Ideia | Por que foi descartada | Onde está a discussão |
|---|---|---|
| Visão materializada com `REFRESH` periódico | Resposta desatualizada entre um `REFRESH` e outro; cada `REFRESH` refaz a agregação inteira | [06.2](experimentos/06.2-total-por-produto.md), [09.2](experimentos/09.2-total-por-dia.md) |
| Cache com expiração por tempo | Resposta desatualizada até expirar; uma cópia por instância da API | [05.2](experimentos/05.2-total-por-status.md), [06.2](experimentos/06.2-total-por-produto.md) |
| Total estimado (`pg_class.reltuples`) | Não é exato; mudaria o contrato | [05.2](experimentos/05.2-total-por-status.md) |
| Gatilho por linha (`FOR EACH ROW`) | Uma carga em massa atualizaria a mesma linha de total uma vez por item | [05.2](experimentos/05.2-total-por-status.md), [09.2](experimentos/09.2-total-por-dia.md) |
| Índice de expressão em `criado_em::date` | Resolve só o índice, não a agregação na API, que foi o maior ganho da 04 | [04](experimentos/04-vendas-por-dia.md) |
| Índice parcial `WHERE status <> 'cancelado'` | Ganho esperado pequeno: cancelados são 10% dos pedidos | [04](experimentos/04-vendas-por-dia.md) |
| Somar todos os itens e subtrair os cancelados em `top-produtos` | Tempo próximo ao da 06 num EXPLAIN exploratório, sem registro em arquivo; equivalência mais delicada | [06](experimentos/06-top-produtos.md) |
| Mais CPU e memória | Paga sempre; com as leituras inteiras, o banco continuaria saturado | [artigo, seção 4](artigo/artigo.md#4-alternativas-consideradas) |
