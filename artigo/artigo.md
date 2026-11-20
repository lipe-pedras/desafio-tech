# A loja era lenta porque o banco lia demais: com os mesmos limites, a API foi de 7,42 para 2563,74 req/s

## 1. Resumo

A API de uma loja fictícia (Node.js e PostgreSQL, limitados a 0,5 e 1 CPU) atendia 7,42 requisições por segundo, e o banco ficava em 100% de CPU. Faltavam índices, cada consulta abria uma conexão nova e os relatórios somavam milhões de linhas a cada chamada. Com índices, um pool de 1 conexão, consultas mais enxutas e totais mantidos por gatilhos, a versão final atendeu 2563,74 req/s, com p95 de 13,7 ms (era 9,5 s), sem aumentar CPU nem memória. As duas versões foram medidas na mesma sessão. O custo foi para as escritas, que a carga não mede.

## 2. Contexto e diagnóstico

A linha de base ([1](../resultados/20261110-210120-00-linha-de-base-desktop/), [2](../resultados/20261110-210926-00-linha-de-base-desktop/), [3](../resultados/20261110-211212-00-linha-de-base-desktop/)) mostrou o banco no limite, a 99,5% da CPU que ele tem, enquanto a API usava pouco da dela. Para saber onde o banco gastava, rodei `EXPLAIN ANALYZE`, que executa a consulta e mostra o plano e o tempo de cada passo, na consulta de cada rota ([`explain-linha-de-base.txt`](../diagnostico/explain-linha-de-base.txt)). Quase todas leem tabelas inteiras (*Seq Scan*): `top-produtos` leva 2386 ms, a página 500 de `/pedidos` leva 1515 ms e `vendas-por-dia` leva 673 ms. A busca por e-mail lê os 100 mil clientes para achar um. Seis passos dos planos usam 2 processos auxiliares (*parallel query*) num banco que só tem 1 CPU.

Duas medições isoladas completaram o quadro:
- abrir uma conexão por consulta, como o código original fazia, custou 5,98 ms de mediana, contra 0,23 ms com uma conexão reaproveitada ([`custo-conexao.txt`](../diagnostico/custo-conexao.txt));
- `/clientes/:id/pedidos` faz em média 22 consultas por requisição, uma por pedido e uma por item, e até 32 ([`03-n-mais-1.txt`](../diagnostico/03-n-mais-1.txt)).

Hipóteses de causa:
- **Índices faltando:** os filtros e as chaves estrangeiras não têm índice, então cada consulta lê a tabela inteira.
- **Conexão por consulta:** cada consulta abre uma conexão, e com ela um processo novo no PostgreSQL.
- **N+1:** os pedidos de um cliente são montados com uma consulta por item.
- **Relatórios e contagens:** são recalculados a cada chamada, sobre centenas de milhares de linhas.
- **Paralelismo:** com 1 CPU, os auxiliares só disputam a mesma CPU.

## 3. Estado da arte

### Acesso a dados: índices e consultas que leem só o necessário

Estudos com aplicações reais apontam as mesmas causas. Yan et al. [1] analisaram 27 aplicações web e agrupam os problemas em projeto físico ruim, como índices faltando, consultas ineficientes geradas pelo código e falta de cache. Yang et al. [2] chegam a uma taxonomia parecida, com as correções e os ganhos medidos. Shao et al. [3] catalogam anti-padrões em aplicações que escrevem SQL direto, como esta: índices faltando (AP-19), colunas a mais (AP-14) e cálculo que deveria ir para o banco (AP-02). Chen et al. [4] descrevem o "N+1": uma consulta por item, dentro de um laço. Kossmann et al. [5] lembram que cada índice custa espaço e escrita em troca da leitura mais rápida. A documentação do PostgreSQL descreve o índice que cobre a consulta (`INCLUDE`), que dispensa ir à tabela [6], e o índice de trigramas, que atende `ILIKE '%termo%'` [7].

### Conexões e CPU: reaproveitar e limitar

O PostgreSQL cria um processo por conexão [8], e o node-postgres estima de 20 a 30 ms para abrir cada uma [9]; por isso se usa um *pool*, um conjunto de conexões abertas e reaproveitadas. A Wiki do PostgreSQL descreve um "joelho": o desempenho sobe com o número de conexões até o servidor saturar e depois cai [10]. O HikariCP defende um pool pequeno [11], e a Oracle, no máximo cinco conexões por núcleo [12]. Sobri et al. [13], com o banco sem saturar, viram mais conexões ganharem (10 > 5 > 1). Na minha leitura, essas fontes não dão um número; o tamanho certo depende da folga do banco e precisa ser medido. A mesma lógica vale para a consulta paralela, que ajuda quando há CPUs livres [18].

### Resultados pré-calculados: visões materializadas e cache

Gupta e Mumick [14] tratam de guardar o resultado de uma consulta (visão materializada) e atualizá-lo a cada mudança nos dados. No PostgreSQL, isso se faz com gatilhos (*triggers*), que rodam a cada escrita [15]. O Facebook usa um cache na frente do banco e descreve o custo de mantê-lo consistente [16]. Minha leitura: os dois caminhos trocam leitura barata por escrita mais cara ou por dados possivelmente desatualizados.

## 4. Alternativas consideradas

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| A. Índices e consultas enxutas | Disco (66 MB na 01) e escrita mais lenta | Alto: tira as leituras de tabela inteira | Baixo: o resultado não muda | Baixo |
| B. Pool de conexões pequeno | Nenhum recurso novo | Alto com o banco saturado | Uma consulta lenta segura as outras | Baixo |
| C. Totais mantidos por gatilhos | Escrita mais cara e mais disputada | Muito alto nos relatórios | Total errado se uma escrita escapar do gatilho | Médio a alto |
| D. Visão materializada com `REFRESH` | Refaz a agregação inteira a cada `REFRESH` | Alto | Total desatualizado entre um `REFRESH` e outro | Baixo |
| E. Cache na API | Memória e CPU na API, uma cópia por instância | Alto | Resposta desatualizada; invalidação | Médio |
| F. Mais CPU e memória | Paga sempre, em dinheiro | Incerto: as leituras inteiras continuariam | Baixo | Muito baixo |

A, B e C atacam causas do diagnóstico; D, E e F contornam essas causas. D e E dariam o mesmo ganho de C nos relatórios com menos código, e, como a carga só lê, passariam no verificador de contrato. Não as descartei pelo verificador, e sim pelo que elas fariam numa loja com escritas: entre um `REFRESH` ou uma expiração e outra, devolveriam um total antigo, e decidir quanto atraso é aceitável é uma decisão de produto que o desafio não dá. C mantém o total sempre exato e paga por isso na escrita, um custo que pude medir. E ainda gastaria CPU da API, que no fim virou o gargalo. F só faria sentido depois de esgotar A a C: McSherry et al. [17] argumentam que um ganho só vale quando comparado ao recurso que ele gasta.

## 5. Solução escolhida e por quê

Escolhi aplicar A e B primeiro, uma mudança por vez, porque atacam causas confirmadas no diagnóstico, não mudam o resultado e não custam recurso novo. O tamanho do pool foi medido, não copiado de uma fórmula: com o banco limitado a 1 CPU, 1 conexão venceu 2, 3, 5, 10 e 20, e continuou vencendo depois das outras mudanças.

C entrou só onde A não bastou: no total de `/pedidos` e nos dois relatórios, que ainda agregavam centenas de milhares de linhas. Usei gatilhos por comando, e não por linha, para que uma carga em massa atualize cada total uma vez. Cada versão teve a correção conferida contra o recálculo completo, inclusive com escritas simultâneas ([`062-gatilho.txt`](../diagnostico/062-gatilho.txt), [`092-custo-concorrente.txt`](../diagnostico/092-custo-concorrente.txt)). Descartei D e E pelo risco de total desatualizado e F pelo custo.

## 6. Experimento e resultado

Cada linha é a mediana de 3 execuções do `medir.sh` com os parâmetros padrão, num desktop (i7-14700K), com o "antes" medido na mesma sessão, em rodízio. CPU e memória são as do banco; 100% é 1 CPU inteira. O p95 é o tempo que 95% das requisições não ultrapassam. Por convenção, os links levam à 2ª execução de cada lado; as três estão em [`experimentos.md`](../experimentos.md).

| Mudança | Hipótese | p95 antes → depois | req/s antes → depois | CPU/memória | Pastas de resultados | Conclusão |
|---|---|---|---|---|---|---|
| 01 índices | Sem *Seq Scan*, o banco atende mais | 9403,1 → 3185,4 ms | 7,47 → 26,70 | 99,5 → 99,9% / 236,4 → 228,7 MiB | [antes](../resultados/20261110-210926-00-linha-de-base-desktop/) · [depois](../resultados/20261110-210644-01-indices-desktop/) | 3,6× em req/s |
| 02 pool | Conexão reaproveitada poupa o banco | 3302,8 → 1815,8 ms | 25,69 → 38,96 | 100,1 → 99,7% / 223,3 → 331,7 MiB | [antes](../resultados/20261110-214642-01-indices-rodizio-desktop/) · [depois](../resultados/20261110-214819-02-pool-conexoes-desktop/) | 1,5×; p99 sobe 7% |
| 02.1 pool de 1 | Menos conexões, menos disputa | 1811,8 → 1554,0 ms | 38,38 → 64,03 | 99,9 → 96,2% / 335,7 → 162,5 MiB | [max=10](../resultados/20261110-213838-021-pool-max-10-desktop/) · [max=1](../resultados/20261110-214955-021-pool-max-1-desktop/) | 1 vence 2, 3, 5, 10 e 20 |
| 03 N+1 com JOIN | Uma consulta por requisição | 1627,0 → 792,9 ms | 57,97 → 65,11 | 97,5 → 96,8% / 355,0 → 164,8 MiB | [antes](../resultados/20261111-023758-03f-02-pool-2-desktop/) · [depois](../resultados/20261111-023624-03f-03-pool-1-desktop/) | Cauda −51%; mediana 2,2× **pior** |
| 04 agregar no banco | Menos linhas para a API | 803,2 → 653,6 ms | 65,50 → 79,43 | 96,1 → 99,7% / 173,0 → 178,7 MiB | [antes](../resultados/20261111-132433-04-antes-desktop/) · [depois](../resultados/20261111-131918-04-vendas-por-dia-desktop/) | +21%; CPU da API 26,4 → 2,8% |
| 04.1 índice em `criado_em` | Período sem ler a tabela | 653,6 → 658,3 ms | 79,43 → 83,35 | 99,7 → 99,6% / 178,7 → 180,4 MiB | [antes](../resultados/20261111-131918-04-vendas-por-dia-desktop/) · [depois](../resultados/20261111-132156-041-indice-criado-em-desktop/) | +5%; p95 igual |
| 05 só 4 colunas | Pré-requisito da 05.1 | 666,6 → 683,3 ms | 84,68 → 85,12 | 99,6 → 99,5% / 183,0 → 175,2 MiB | [antes](../resultados/20261111-163448-05-antes-desktop/) · [depois](../resultados/20261111-162932-05-pedidos-por-status-desktop/) | **Sem ganho**, como esperado |
| 05.1 índice com `INCLUDE` | Página lida só do índice | 683,3 → 570,1 ms | 85,12 → 94,11 | 99,5 → 99,2% / 175,2 → 177,2 MiB | [antes](../resultados/20261111-162932-05-pedidos-por-status-desktop/) · [depois](../resultados/20261111-163210-051-indice-include-desktop/) | +11% |
| 05.2 total por status | Ler uma linha em vez de contar | 575,5 → 510,7 ms | 94,17 → 108,20 | 99,2 → 99,3% / 172,1 → 181,1 MiB | [antes](../resultados/20261111-174150-052-antes-desktop/) · [depois](../resultados/20261111-173912-052-total-por-status-desktop/) | +14,9%; escrita mais cara |
| 06 agregar antes do JOIN | Menos linhas no JOIN | 517,0 → 406,9 ms | 110,13 → 133,78 | 99,7 → 100,1% / 177,5 → 179,4 MiB | [antes](../resultados/20261111-222614-06-antes-desktop/) · [depois](../resultados/20261111-222337-06-top-produtos-desktop/) | +21,5% |
| 06.1 sem paralelismo | Auxiliares só disputam a CPU | 400,8 → 413,3 ms | 132,70 → 133,63 | 100,0 → 98,1% / 174,6 → 158,2 MiB | [antes](../resultados/20261111-230656-06x-antes-desktop/) · [depois](../resultados/20261111-230143-061-sem-paralelismo-desktop/) | **Sem ganho** sozinha |
| 06.2 vendas por produto | Ranking lido de um índice | 400,8 → 97,2 ms | 132,70 → 412,21 | 100,0 → 99,7% / 174,6 → 154,0 MiB | [antes](../resultados/20261111-230656-06x-antes-desktop/) · [depois](../resultados/20261111-230420-062-total-por-produto-desktop/) | 3,1× |
| 06.1 sobre 06.2 | Idem, sem o relatório pesado | 96,6 → 71,1 ms | 411,34 → 531,15 | 99,3 → 94,6% / 154,5 → 151,6 MiB | [antes](../resultados/20261111-233935-0621-antes-desktop/) · [depois](../resultados/20261111-233659-0621-062-sem-paralelismo-desktop/) | +29%; pausas da cota 98% → 2,5% |
| 07 trigramas | Busca sem ler os produtos | 71,9 → 47,0 ms | 528,16 → 902,65 | 94,8 → 91,5% / 151,1 → 151,6 MiB | [antes](../resultados/20261112-203018-07-antes-desktop/) · [depois](../resultados/20261112-202743-07-busca-trigramas-desktop/) | +70,9% |
| 08 pool 2, 3, 5 | Banco com folga aceita mais conexões | 47,1 → 65,9 / 77,9 / 87,8 ms | 899,17 → 950,95 / 921,74 / 878,35 | 91,6 → 99,9 / 99,7 / 99,8% / 151,7 → 154,8 / 157,9 / 163,8 MiB | [resumo](../diagnostico/08-resumo.txt) | **Rejeitada**: p95 +40% |
| 09 índices com `INCLUDE` | Relatório lido só de índices | 46,9 → 37,3 ms | 904,50 → 1096,89 | 91,8 → 89,9% / 151,8 → 151,3 MiB | [antes](../resultados/20261113-123938-09-antes-desktop/) · [depois](../resultados/20261113-123426-09-indices-vendas-por-dia-desktop/) | +21,3% |
| 09.2 vendas por dia | Ler 7 linhas por chamada | 37,3 → 14,0 ms | 1096,89 → 2543,16 | 89,9 → 70,5% / 151,3 → 150,8 MiB | [antes](../resultados/20261113-123426-09-indices-vendas-por-dia-desktop/) · [depois](../resultados/20261113-123702-092-total-por-dia-desktop/) | 2,3×; gargalo vai para a API |
| **Original → final** | Tudo junto, em rodízio | **9501,3 → 13,7 ms** | **7,42 → 2563,74** | 100,0 → 71,1% / 228,5 → 150,7 MiB | [antes](../resultados/20261120-023848-10-original-desktop/) · [depois](../resultados/20261120-023609-10-final-desktop/) | **345×**, sem sobreposição |

O "antes" de cada linha é a versão anterior, não a linha de base; por isso os ganhos se multiplicam. A última linha compara a aplicação original com a final, em rodízio na mesma sessão ([`10-ponta-a-ponta-resumo.txt`](../diagnostico/10-ponta-a-ponta-resumo.txt)). A pior execução da final atendeu 335 vezes mais que a melhor da original.

Três mudanças não funcionaram como eu esperava. A 05 só tirou colunas e serviu de pré-requisito da 05.1. A 06.1 não ganhou sozinha, porque o tempo continuava no relatório pesado; sobre a 06.2, deu +29%, e as pausas da cota de CPU do banco caíram de 98% para 2,5% dos períodos. A 08 aumentou as req/s em até 5,8%, mas o p95 subiu 40%, e ficou fora. Na 03, a cauda caiu pela metade, mas a mediana piorou: as rotas rápidas passaram a esperar na fila do pool atrás de consultas mais pesadas.

Na versão final, o banco usa 71% da sua CPU, e a API é pausada pela cota em cerca de 60% dos períodos: o próximo gargalo é a API.

## 7. Limites e testes futuros

- **Escritas:** a carga só lê, então o custo dos gatilhos foi medido à parte, com `pgbench`. Com 8 clientes simultâneos, a 05.2 reduziu em 59% as transações/s de INSERT e em 71% as de UPDATE de status ([`052-custo-concorrente.txt`](../diagnostico/052-custo-concorrente.txt)); a 09.2 reduziu em 74% os INSERTs simultâneos no mesmo dia ([`092-custo-concorrente.txt`](../diagnostico/092-custo-concorrente.txt)). DELETE, TRUNCATE e a escrita nos índices novos não foram medidos.
- **Pool de 1:** uma consulta lenta faz todas as outras esperarem. Hoje todas as consultas são curtas; não testei uma carga com mais relatórios, porque a carga do desafio é fixa.
- **Ambiente:** tudo foi medido numa só máquina, com o volume de dados que o script gera e 20 usuários simultâneos.

O que derrubaria a conclusão: uma loja em que as escritas simultâneas pesem mais que as leituras, porque aí a perda de 59% a 74% nas escritas superaria o ganho nas leituras; ou uma carga com consultas longas, em que o pool de 1 vire fila. Os índices continuariam valendo; os gatilhos e o pool de 1, não necessariamente.

As ideias pesquisadas e não testadas estão em [`proximos-testes.md`](../proximos-testes.md). As principais: redividir a mesma 1,5 CPU entre API e banco, agora que a API é o gargalo, e contadores divididos para reduzir a disputa nas escritas.

## 8. Referências

1. Yan, C.; Cheung, A.; Yang, J.; Lu, S. *Understanding Database Performance Inefficiencies in Real-world Web Applications*. CIKM 2017. https://www.cc.gatech.edu/~jarulraj/courses/8803-f18/papers/db_study.pdf. Acesso em 2026-11-05.
2. Yang, J.; Subramaniam, P.; Lu, S.; Yan, C.; Cheung, A. *How not to structure your database-backed web applications: a study of performance bugs in the wild*. ICSE 2018. https://par.nsf.gov/servlets/purl/10067547. Acesso em 2026-11-05.
3. Shao, S. et al. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020. https://par.nsf.gov/servlets/purl/10277614. Acesso em 2026-11-05.
4. Chen, T.-H. et al. *Detecting Performance Anti-patterns for Applications Developed using Object-Relational Mapping*. ICSE 2014. https://ece.uwaterloo.ca/~wshang/pubs/peter_icse2014.pdf. Acesso em 2026-11-05.
5. Kossmann, J.; Halfpap, S.; Jankrift, M.; Schlosser, R. *Magic mirror in my hand, which is the best in the land? An Experimental Evaluation of Index Selection Algorithms*. PVLDB 13(11), 2020. https://www.vldb.org/pvldb/vol13/p2382-kossmann.pdf. Acesso em 2026-11-05.
6. PostgreSQL 16 Documentation. *11.9. Index-Only Scans and Covering Indexes*. https://www.postgresql.org/docs/16/indexes-index-only-scans.html. Acesso em 2026-11-11.
7. PostgreSQL 16 Documentation. *F.35. pg_trgm*. https://www.postgresql.org/docs/16/pgtrgm.html. Acesso em 2026-11-12.
8. PostgreSQL 16 Documentation. *52.2. How Connections Are Established*. https://www.postgresql.org/docs/16/connect-estab.html. Acesso em 2026-11-06.
9. node-postgres. *Pooling*. https://node-postgres.com/features/pooling. Acesso em 2026-11-06.
10. PostgreSQL Wiki. *Number Of Database Connections*. https://wiki.postgresql.org/wiki/Number_Of_Database_Connections. Acesso em 2026-11-06.
11. HikariCP Wiki. *About Pool Sizing*. https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing. Acesso em 2026-11-06.
12. Oracle. *Universal Connection Pool Developer's Guide 26*, 5.3. https://docs.oracle.com/en/database/oracle/oracle-database/26/jjucp/optimizing-real-world-performance.html. Acesso em 2026-11-06.
13. Sobri, N. A. N. et al. *A Study of Database Connection Pool in Microservice Architecture*. JOIV 6(2-2), 2022. https://joiv.org/index.php/joiv/article/view/1094. Acesso em 2026-11-06.
14. Gupta, A.; Mumick, I. S. *Maintenance of Materialized Views: Problems, Techniques, and Applications*. IEEE Data Engineering Bulletin 18(2), 1995. http://sites.computer.org/debull/95JUN-CD.pdf. Acesso em 2026-11-05.
15. PostgreSQL 16 Documentation. *CREATE TRIGGER*. https://www.postgresql.org/docs/16/sql-createtrigger.html. Acesso em 2026-11-11.
16. Nishtala, R. et al. *Scaling Memcache at Facebook*. NSDI 2013. https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala. Acesso em 2026-11-05.
17. McSherry, F.; Isard, M.; Murray, D. G. *Scalability! But at what COST?* HotOS XV, 2015. https://www.usenix.org/conference/hotos15/workshop-program/presentation/mcsherry. Acesso em 2026-11-05.
18. PostgreSQL 16 Documentation. *Chapter 15. Parallel Query* e *15.1. How Parallel Query Works*. https://www.postgresql.org/docs/16/parallel-query.html. Acesso em 2026-11-11.

## 9. Uso de IA

Usei o Claude Code para escrever e revisar o código das mudanças e dos scripts de diagnóstico, organizar as medições, pesquisar referências e auxiliar na escrita das fichas dos experimentos, do `proximos-testes.md` e deste artigo. Verifiquei o resultado lendo o código e as saídas, com o verificador de contrato e com testes de correção dos gatilhos contra o recálculo completo; cada fonte citada foi aberta e salva em `referencias/`. Os resultados de carga vêm do `medir.sh`; os de diagnóstico, de arquivos em `diagnostico/`.
