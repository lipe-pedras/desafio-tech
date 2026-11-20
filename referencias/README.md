# Referências baixadas

Artigos científicos e técnicos de acesso aberto, baixados em 2026-11-05 dos links abaixo. Cada PDF teve o título e os autores conferidos na primeira página. A coluna "Por que interessa" é uma leitura inicial, feita antes dos experimentos: ainda precisa ser confirmada pela leitura do artigo e pelas medições.

## Anti-padrões de acesso a banco em aplicações web

| Arquivo | Referência | Link | Por que interessa |
|---|---|---|---|
| `chen-2014-orm-performance-anti-patterns-icse.pdf` | Chen, T.-H.; Shang, W.; Jiang, Z. M.; Hassan, A. E.; Nasser, M.; Flora, P. *Detecting Performance Anti-patterns for Applications Developed using Object-Relational Mapping*. ICSE 2014, p. 1001–1012. | https://ece.uwaterloo.ca/~wshang/pubs/peter_icse2014.pdf | Define e mede anti-padrões como "uma consulta por item em laço", o padrão N+1 de `/clientes/:id/pedidos`. |
| `yan-2017-db-performance-inefficiencies-web-apps-cikm.pdf` | Yan, C.; Cheung, A.; Yang, J.; Lu, S. *Understanding Database Performance Inefficiencies in Real-world Web Applications*. CIKM 2017, p. 1299–1308. DOI 10.1145/3132847.3132954 | https://www.cc.gatech.edu/~jarulraj/courses/8803-f18/papers/db_study.pdf | Estudo de 27 aplicações reais. Agrupa os problemas em projeto físico ruim (índices), consultas ineficientes geradas pelo código e falta de cache. |
| `yang-2018-how-not-to-structure-db-web-apps-icse.pdf` | Yang, J.; Subramaniam, P.; Lu, S.; Yan, C.; Cheung, A. *How not to structure your database-backed web applications: a study of performance bugs in the wild*. ICSE 2018, p. 800–810. DOI 10.1145/3180155.3180194 | https://par.nsf.gov/servlets/purl/10067547 | Taxonomia de bugs de performance (consultas redundantes, índices faltando, dados desnecessários) com as correções e os ganhos medidos. |
| `shao-2020-database-access-performance-antipatterns-icsme.pdf` | Shao, S.; Qiu, Z.; Yu, X.; Yang, W.; Jin, G.; Xie, T.; Wu, X. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020, p. 58–69. DOI 10.1109/ICSME46990.2020.00016 | https://par.nsf.gov/servlets/purl/10277614 | Foca em aplicações que escrevem SQL direto, sem ORM, como esta API. Cataloga 24 anti-padrões conhecidos e 10 novos. |
| `muse-2022-data-access-anti-patterns-arxiv.pdf` | Muse, B. A.; Nafi, K. W.; Khomh, F.; Antoniol, G. *Data-access performance anti-patterns in data-intensive systems*. Preprint arXiv:2208.08918, 2022. | https://arxiv.org/abs/2208.08918 | Revisão mais recente de anti-padrões de acesso a dados. É um preprint, sem revisão por pares indicada no arXiv. |

## Índices e configuração do banco

| Arquivo | Referência | Link | Por que interessa |
|---|---|---|---|
| `kossmann-2020-index-selection-evaluation-pvldb.pdf` | Kossmann, J.; Halfpap, S.; Jankrift, M.; Schlosser, R. *Magic mirror in my hand, which is the best in the land? An Experimental Evaluation of Index Selection Algorithms*. PVLDB 13(11), 2020, p. 2382–2395. DOI 10.14778/3407790.3407832 | https://www.vldb.org/pvldb/vol13/p2382-kossmann.pdf | Compara algoritmos de escolha de índices e discute o custo de cada índice (espaço e escrita) contra o ganho de leitura. |
| `vanaken-2017-ottertune-dbms-tuning-sigmod.pdf` | Van Aken, D.; Pavlo, A.; Gordon, G. J.; Zhang, B. *Automatic Database Management System Tuning Through Large-scale Machine Learning*. SIGMOD 2017. DOI 10.1145/3035918.3064029 | https://www.cs.purdue.edu/homes/csjgwang/CloudNativeDB/OtterTuneSIGMOD17.pdf (cópia hospedada na Purdue) | Mostra o efeito de parâmetros do SGBD em relação à configuração padrão. Base para justificar ajustes como `shared_buffers` e `work_mem`. |

## Cache e visões materializadas

| Arquivo | Referência | Link | Por que interessa |
|---|---|---|---|
| `gupta-1995-materialized-views-debull-edicao-completa.pdf` | Gupta, A.; Mumick, I. S. *Maintenance of Materialized Views: Problems, Techniques, and Applications*. IEEE Data Engineering Bulletin 18(2), 1995, p. 3–18. | http://sites.computer.org/debull/95JUN-CD.pdf | Clássico sobre visões materializadas, uma alternativa para os relatórios. **O PDF é a edição inteira do boletim; o artigo começa na página 5 do arquivo.** |
| `nishtala-2013-scaling-memcache-facebook-nsdi.pdf` | Nishtala, R. et al. *Scaling Memcache at Facebook*. NSDI 2013, p. 385–398. | https://www.usenix.org/conference/nsdi13/technical-sessions/presentation/nishtala | Caso de mercado de cache na frente do banco (*look-aside*), com os problemas de invalidação e consistência que isso traz. |

## Medição e custo

| Arquivo | Referência | Link | Por que interessa |
|---|---|---|---|
| `laaber-2019-microbenchmarking-cloud-emse.pdf` | Laaber, C.; Scheuner, J.; Leitner, P. *Software Microbenchmarking in the Cloud. How Bad is it Really?* Empirical Software Engineering 24(4), 2019, p. 2469–2508. | https://research.chalmers.se/publication/511491/file/511491_Fulltext.pdf | Variabilidade de medições de desempenho e como comparar execuções com confiança. Apoia a regra de medir 3 vezes e usar a mediana. |
| `mcsherry-2015-scalability-at-what-cost-hotos.pdf` | McSherry, F.; Isard, M.; Murray, D. G. *Scalability! But at what COST?* HotOS XV, 2015. | https://www.usenix.org/conference/hotos15/workshop-program/presentation/mcsherry | Argumenta que ganho de desempenho tem de ser comparado com o recurso gasto. Conversa com a regra "recurso a mais é custo". |

## Pesquisada, sem PDF baixado

- Dean, J.; Barroso, L. A. *The Tail at Scale*. Communications of the ACM 56(2), 2013, p. 74–80. DOI 10.1145/2408776.2408794. Texto em https://cacm.acm.org/magazines/2013/2/160173-the-tail-at-scale/fulltext. Ajuda a explicar por que olhar p95/p99, e não só a média. Não encontrei um PDF de acesso aberto que desse para conferir.

## Documentação oficial (pasta `documentacao/`)

Páginas abertas em 2026-11-06 e salvas como texto (HTML convertido, sem edição do conteúdo), para que as citações das fichas possam ser conferidas mesmo se a página mudar.

| Arquivo | Referência | Link | Usada em |
|---|---|---|---|
| `documentacao/node-postgres-pooling.txt` | node-postgres. *Pooling*. | https://node-postgres.com/features/pooling | 02: custo de abrir conexão por consulta |
| `documentacao/node-postgres-api-pool.txt` | node-postgres. *pg.Pool* (API). | https://node-postgres.com/apis/pool | 02: parâmetros `max` e `idleTimeoutMillis` |
| `documentacao/node-postgres-pool-sizing.txt` | node-postgres. *Pool Sizing*. | https://node-postgres.com/guides/pool-sizing | 02: tamanho do pool |
| `documentacao/postgresql-16-connect-estab.txt` | PostgreSQL 16 Documentation, *52.2. How Connections Are Established*. | https://www.postgresql.org/docs/16/connect-estab.html | 02: um processo do servidor por conexão |
| `documentacao/postgresql-16-indexes-types.txt` | PostgreSQL 16 Documentation, *11.2. Index Types* (aberta em 2026-11-11; trecho: B-Tree e BRIN). | https://www.postgresql.org/docs/16/indexes-types.html | 04: o B-tree só é considerado quando a própria coluna indexada está na comparação; BRIN como alternativa |
| `documentacao/postgresql-16-indexes-expressional.txt` | PostgreSQL 16 Documentation, *11.7. Indexes on Expressions* (aberta em 2026-11-11). | https://www.postgresql.org/docs/16/indexes-expressional.html | 04: índice de expressão (`criado_em::date`) como alternativa ao filtro por intervalo |
| `documentacao/postgresql-16-indexes-index-only-scans.txt` | PostgreSQL 16 Documentation, *11.9. Index-Only Scans and Covering Indexes* (aberta em 2026-11-11). | https://www.postgresql.org/docs/16/indexes-index-only-scans.html | 05.1: *index-only scan*, `INCLUDE` e a dependência do mapa de visibilidade |
| `documentacao/postgresql-16-routine-vacuuming.txt` | PostgreSQL 16 Documentation, *25.1. Routine Vacuuming* (aberta em 2026-11-11; trechos de 25.1.1, 25.1.3, 25.1.4 e 25.1.6). | https://www.postgresql.org/docs/16/routine-vacuuming.html | 05.1: o `VACUUM` atualiza o mapa de visibilidade; limiar de inserções do autovacuum |
| `documentacao/postgresql-16-runtime-config-autovacuum.txt` | PostgreSQL 16 Documentation, *20.10. Automatic Vacuuming* (aberta em 2026-11-11; trecho). | https://www.postgresql.org/docs/16/runtime-config-autovacuum.html | 05.1: valores padrão de `autovacuum_naptime` e do limiar de inserções |
| `documentacao/postgresql-16-sql-analyze.txt` | PostgreSQL 16 Documentation, *ANALYZE* (aberta em 2026-11-11; trecho). | https://www.postgresql.org/docs/16/sql-analyze.html | 05.1: o `ANALYZE` só coleta estatísticas |
| `documentacao/postgresql-16-sql-vacuum.txt` | PostgreSQL 16 Documentation, *VACUUM* (aberta em 2026-11-11; trecho). | https://www.postgresql.org/docs/16/sql-vacuum.html | 05.1: `VACUUM ANALYZE` e a restrição a bloco de transação |
| `documentacao/postgresql-16-sql-createtrigger.txt` | PostgreSQL 16 Documentation, *CREATE TRIGGER* (aberta em 2026-11-11; trecho). | https://www.postgresql.org/docs/16/sql-createtrigger.html | 05.2: gatilhos por comando, tabelas de transição e um evento por gatilho |
| `documentacao/postgresql-16-trigger-definition.txt` | PostgreSQL 16 Documentation, *39.1. Overview of Trigger Behavior* (aberta em 2026-11-11; trecho). | https://www.postgresql.org/docs/16/trigger-definition.html | 05.2: gatilhos por linha e por comando |
| `documentacao/postgresql-16-runtime-config-resource.txt` | PostgreSQL 16 Documentation, *20.4. Resource Consumption* (aberta em 2026-11-11; trecho de 20.4.6: `max_parallel_workers_per_gather`). | https://www.postgresql.org/docs/16/runtime-config-resource.html | 06.1: o valor 0 desliga as consultas paralelas; cada processo auxiliar consome recursos como uma sessão a mais |
| `documentacao/postgresql-16-parallel-query.txt` | PostgreSQL 16 Documentation, *Chapter 15. Parallel Query* e *15.1. How Parallel Query Works* (abertas em 2026-11-11; trechos). | https://www.postgresql.org/docs/16/parallel-query.html e https://www.postgresql.org/docs/16/how-parallel-query-works.html | 06.1: paralelismo usa várias CPUs; papel do processo principal (*leader*) |
| `documentacao/postgresql-16-pgtrgm.txt` | PostgreSQL 16 Documentation, *F.35. pg_trgm* (aberta em 2026-11-12; trechos: introdução, F.35.1 e F.35.4). | https://www.postgresql.org/docs/16/pgtrgm.html | 07: índice GIN de trigramas acelera `ILIKE '%termo%'`; padrão sem trigramas vira leitura do índice inteiro |
| `documentacao/postgresql-16-brin-intro.txt` | PostgreSQL 16 Documentation, *71.1. BRIN: Introduction* (aberta em 2026-11-20). | https://www.postgresql.org/docs/16/brin-intro.html | `proximos-testes.md`, ficha 6: BRIN depende da correlação entre a coluna e a posição física |
| `documentacao/postgresql-16-runtime-config-resource-memoria.txt` | PostgreSQL 16 Documentation, *20.4.1. Memory* (aberta em 2026-11-20; trechos de `shared_buffers`, `work_mem` e `hash_mem_multiplier`). | https://www.postgresql.org/docs/16/runtime-config-resource.html | `proximos-testes.md`, ficha 7 |
| `documentacao/postgresql-16-textsearch-indexes.txt` | PostgreSQL 16 Documentation, *12.9. Preferred Index Types for Text Search* (aberta em 2026-11-20). | https://www.postgresql.org/docs/16/textsearch-indexes.html | `proximos-testes.md`, ficha 8: GIN contra GiST |
| `documentacao/postgresql-16-queries-limit.txt` | PostgreSQL 16 Documentation, *7.6. LIMIT and OFFSET* (aberta em 2026-11-20). | https://www.postgresql.org/docs/16/queries-limit.html | `proximos-testes.md`, ficha 10: as linhas puladas pelo `OFFSET` são calculadas mesmo assim |
| `documentacao/node-postgres-queries.txt` | node-postgres. *Queries*, seção *Prepared statements* (aberta em 2026-11-20). | https://node-postgres.com/features/queries | `proximos-testes.md`, ficha 2 |
| `documentacao/pg-ivm-readme.txt` | sraoss. *pg_ivm*, README (aberto em 2026-11-20; trechos). | https://github.com/sraoss/pg_ivm | `proximos-testes.md`, ficha 5: visões materializadas incrementais e suas restrições |
| `documentacao/firestore-distributed-counters.txt` | Google Cloud Firestore. *Distributed counters* (aberta em 2026-11-20; trecho). | https://firebase.google.com/docs/firestore/solutions/counters | `proximos-testes.md`, ficha 3: contadores divididos contra a disputa por uma linha |

## Tamanho do pool de conexões

Encontradas em 2026-11-06, para fundamentar a variação do `max` do pool (mudança 02).

| Arquivo | Referência | Link | Por que interessa |
|---|---|---|---|
| `sobri-2022-database-connection-pool-microservice-joiv.pdf` | Sobri, N. A. N.; Abas, M. A. H.; Yassin, I. M.; Megat Ali, M. S. A.; Tahir, N. M.; Zabidi, A.; Rizman, Z. I. *A Study of Database Connection Pool in Microservice Architecture*. JOIV: International Journal on Informatics Visualization 6(2-2), 2022, p. 566–571. DOI 10.30630/joiv.6.2-2.1094 | https://joiv.org/index.php/joiv/article/view/1094 | Artigo revisado por pares. Mede a latência com pools de 1, 5 e 10 conexões no PostgreSQL, com uma e com três instâncias do serviço. PDF baixado pela autora pelo navegador, porque o site bloqueia downloads automáticos. |
| `agrawal-2026-dbtunesuite-arxiv.pdf` | Agrawal, A.; Wang, T.; Shasha, D. *DBTuneSuite: An Extendible Experimental Suite to Test the Time Performance of Multi-layer Tuning Options on Database Management Systems*. Preprint arXiv:2601.20015, 2026. | https://arxiv.org/abs/2601.20015 | Seção 20 e apêndice V: conexão simples contra pool de 25, 50 e 100 no PostgreSQL, MySQL, MariaDB e DuckDB. É um preprint, e a carga é só de `INSERT`. |
| `documentacao/postgresql-wiki-number-of-database-connections.txt` | PostgreSQL Wiki. *Number Of Database Connections* (última edição em 2014-03-14). | https://wiki.postgresql.org/wiki/Number_Of_Database_Connections | O "joelho" da curva de desempenho por número de conexões e a fórmula `(núcleos × 2) + discos efetivos` como ponto de partida. |
| `documentacao/hikaricp-wiki-about-pool-sizing.txt` | HikariCP Wiki. *About Pool Sizing* (editada em 2021-12-07). | https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing | Explica por que um pool pequeno costuma ganhar ("You want a small pool, saturated with threads waiting for connections") e sugere pools separados para consultas longas e curtas. |
| `documentacao/oracle-ucp-26-pool-sizes.txt` | Oracle. *Universal Connection Pool Developer's Guide 26*, seção 5.3, *Real-World Performance Considerations with Respect to Connection Pool Sizes*. | https://docs.oracle.com/en/database/oracle/oracle-database/26/jjucp/optimizing-real-world-performance.html | Abrir conexões em rajada esgota a CPU do banco; recomenda no máximo 5 conexões por núcleo. |
