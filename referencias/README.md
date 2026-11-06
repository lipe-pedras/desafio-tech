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
