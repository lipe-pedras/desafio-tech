# 01 · Índices nas chaves estrangeiras e nos filtros das rotas

- **Status:** aplicada e medida
- **Branch / commit da mudança:** `01-indices` / `5f09d7e`
- **Comparada com:** a linha de base (commit `d29146f`)

> **Números oficiais: os do desktop (2026-11-10).** As medições do notebook variaram até cerca de 50% entre sessões e cerca de 13% entre execuções da mesma série, então toda a sequência foi remedida num desktop, em rodízio (ver [`diagnostico/remedicao-desktop/`](../diagnostico/remedicao-desktop/README.md)). O resultado oficial está em [Resultado no desktop](#resultado-no-desktop-oficial). As seções do notebook ficam como histórico.

## Hipótese

Mudar o banco para usar índices nas colunas filtradas pelas rotas deve aumentar as requisições/s e reduzir o p95 geral. Hoje todas as consultas, menos as buscas por chave primária, leem tabelas inteiras (`Seq Scan`). Somadas, elas saturam a única CPU do banco.

## Diagnóstico (antes)

Evidência: [`diagnostico/explain-linha-de-base.txt`](../diagnostico/explain-linha-de-base.txt), gerado por [`diagnostico/explain.sql`](../diagnostico/explain.sql). Os tempos vêm de uma execução única com o banco ocioso. Servem como diagnóstico, não como resultado.

- **Índices existentes:** só os 4 de chave primária. O PostgreSQL não cria índice para chave estrangeira sozinho.
- **Na linha de base**, o banco ficou com cerca de 99% de CPU média, enquanto a API usou cerca de 6% ([recursos.txt](../resultados/20261105-104137-00-linha-de-base/recursos.txt)).

| Consulta (rota) | Plano | Tempo |
|---|---|---|
| itens de um pedido (`/clientes/:id/pedidos`, roda uma vez por pedido) | Seq Scan em `itens_pedido`, descarta 1,5 milhão de linhas | 185,7 ms |
| pedidos do cliente (`/clientes/:id/pedidos`) | Parallel Seq Scan em `pedidos` | 110,0 ms |
| `lower(email)` (`/clientes?email=`) | Seq Scan em `clientes`, descarta 99.999 linhas | 61,6 ms |
| contagem do status (`/pedidos`) | Parallel Seq Scan em `pedidos` | 199,7 ms |
| página 500 do status (`/pedidos`) | Seq Scan, ordena cerca de 300 mil linhas | 1515,3 ms |

## Alterações

Foi criado só um arquivo novo, [`banco/03-indices.sql`](../banco/03-indices.sql), sem mudança no código da API:

| Índice | Atende |
|---|---|
| `itens_pedido (pedido_id)` | itens de cada pedido; também o JOIN de `vendas-por-dia` |
| `pedidos (cliente_id, criado_em DESC, id DESC)` | pedidos do cliente, já na ordem da resposta, o que dispensa a ordenação |
| `clientes (lower(email))` | índice de expressão; a consulta compara `lower(email)` e não pode usar um índice simples em `email` |
| `pedidos (status, criado_em DESC, id DESC)` | filtro de status na ordem da paginação; serve também ao `count(*)` |

O arquivo termina com `ANALYZE`, porque o índice de expressão precisa de estatísticas próprias.

**Aplicação:** `docker compose down -v && docker compose up -d --build`. Os arquivos de `banco/` só rodam quando o banco é criado do zero.

**Contrato:** mantido nas 3 execuções (`contrato.txt` de cada pasta).

## Fundamentação

Trechos localizados nos PDFs de [`referencias/`](../referencias/):

- **Yang et al. (2018), p. 8:** *"missing index is the most common performance problem reported in ORM application's bug tracking systems"*. Os autores sugerem que os desenvolvedores adicionam índices de forma incremental, conforme as consultas viram problema depois da implantação.
- **Yan et al. (2017), p. 7:** *"the poor default physical design produced by ORM frameworks is one of the major causes for performance inefficiencies"*.
- **Kossmann et al. (2020), p. 2:** *"there is a trade-off between improved performance and elevated storage consumption"* e *"inserts or updates require expensive maintenance operations on the index structures"*.

Fato e opinião, separados:
- **Fato:** os dois primeiros estudos analisaram aplicações em Ruby on Rails com ORM.
- **Opinião minha:** esta API escreve SQL direto, sem ORM, mas o problema é da mesma categoria, um projeto físico sem índices para os filtros usados. Por isso tomo os estudos como evidência da categoria, não do caso exato.
- **Uso de Kossmann et al.:** sustenta que o índice não é de graça (espaço e custo de escrita), o que entra no custo abaixo.

## Resultado no desktop (oficial)

2026-11-10, desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites ([como foi medido](../diagnostico/remedicao-desktop/README.md#como-foi-remedido)). Cada versão tem o seu banco, e as duas foram ligadas uma por vez, em 3 rodadas com a ordem alternada, com aquecimento de 60 s. Contrato mantido e 0,00% de erros nas 6 execuções.

Mediana de 3 execuções:

| Métrica | Linha de base | 01-indices | Variação |
|---|---|---|---|
| Requisições/s | 7,47 | 26,70 | cerca de 3,6× |
| Média | 2620,5 ms | 739,0 ms | −72% |
| Mediana | 698,8 ms | 217,6 ms | −69% |
| p95 | 9403,1 ms | 3185,4 ms | −66% |
| p99 | 11887,5 ms | 4018,4 ms | −66% |
| CPU média do banco | 99,5% | 99,9% | – |
| Memória média do banco | 236,4 MiB | 228,7 MiB | – |
| CPU média da API | 5,6% | 17,1% | sobe porque atende mais requisições |
| Memória média da API | 37,3 MiB | 40,1 MiB | – |

As req/s por execução foram 7,43, 7,47 e 7,50 na linha de base e 26,95, 26,67 e 26,70 na 01.

| Rota (mediana da rota nas 3) | Linha de base | 01 |
|---|---|---|
| `cliente` | 194,5 ms | 100,0 ms |
| `cliente-por-email` | 698,7 ms | 100,6 ms |
| `pedidos-do-cliente` | 8248,4 ms | 2197,9 ms |
| `pedidos-por-status` | 2841,0 ms | 410,5 ms |
| `busca-produtos` | 397,4 ms | 201,9 ms |
| `vendas-por-dia` | 2813,0 ms | 520,4 ms |
| `top-produtos` | 14452,2 ms | 3755,8 ms |

**Pastas de resultados:**
- antes: `resultados/20261110-210120-00-linha-de-base-desktop`, `20261110-210926-…`, `20261110-211212-…`;
- depois: `resultados/20261110-210403-01-indices-desktop`, `20261110-210644-…`, `20261110-211455-…`.

**Leitura:**
- **O ganho se repete na terceira máquina e sessão:** cerca de 3,6× em req/s e −66% no p95, contra 3,2× e 3,5× no notebook. O banco continua saturado.
- **`top-produtos` caiu de 14,5 s para 3,8 s, embora o plano dela não tenha mudado** (ver [EXPLAIN depois](#explain-depois)). A consulta é a mesma; o ganho vem de ela disputar a CPU do banco com consultas mais leves. São poucas amostras: 6 chamadas de `top-produtos` por execução na linha de base e 24 a 26 na 01.

## Resultado no notebook (histórico)

Primeira rodada, 2026-11-05, com o notebook na bateria. A remedição na tomada está na seção [Repetibilidade](#repetibilidade-remedição-com-banco-recriado-e-na-tomada).

Mediana de 3 execuções:

| Métrica | Linha de base | 01-indices | Variação |
|---|---|---|---|
| Requisições/s | 1,81 | 5,81 | cerca de 3,2× |
| Mediana | 2156,1 ms | 1096,0 ms | −49% |
| p95 | 35082,7 ms | 12222,6 ms | −65% |
| p99 | 41481,8 ms | 17537,1 ms | −58% |
| Erros | 0,00% / 0,74% / 0,00% | 0,00% nas 3 | – |
| CPU média do banco | 99,0% | 98,7% | – |
| Memória média do banco | 227,7 MiB | 227,6 MiB | – |
| CPU média da API | 6,0% | 14,3% | sobe porque atende mais requisições |
| Memória média da API | 30,1 MiB | 38,4 MiB | – |

**Pastas de resultados:**
- antes: `resultados/20261105-104137-00-linha-de-base`, `20261105-104334-00-linha-de-base`, `20261105-104532-00-linha-de-base`;
- depois: `resultados/20261105-113726-01-indices`, `20261105-113906-01-indices`, `20261105-114041-01-indices`.

**Custo:** os índices novos ocupam 66 MB de disco ([`diagnostico/tamanho-indices-01.txt`](../diagnostico/tamanho-indices-01.txt)). Os limites de CPU e memória dos containers não mudaram.

## EXPLAIN depois

Evidência: [`diagnostico/explain-01-indices.txt`](../diagnostico/explain-01-indices.txt). Mesmas consultas e parâmetros, uma execução com o banco ocioso.

| Consulta | Antes | Depois |
|---|---|---|
| itens de um pedido | Seq Scan, 185,7 ms | Index Scan, 0,079 ms |
| pedidos do cliente | Seq Scan, 110,0 ms | Index Scan, 15,2 ms |
| `lower(email)` | Seq Scan, 61,6 ms | Index Scan, 0,117 ms |
| contagem do status | Seq Scan, 199,7 ms | Parallel Index Only Scan, 38,6 ms |
| página 500 do status | 1515,3 ms | Index Scan, 16,9 ms |
| `vendas-por-dia` (7 dias) | 673,1 ms | 222,3 ms: os itens usam o índice, mas `pedidos` continua em Seq Scan |
| `top-produtos` | 2386,2 ms | 2503,5 ms: sem mudança, continua agregando todos os itens |
| `busca` | Seq Scan, 18,8 ms | Seq Scan, 64,1 ms: mesmo plano; sem índice nesta mudança |

A variação da busca, com o mesmo plano, parece ruído de execução única com o cache frio logo depois de recriar o banco. Não foi investigada.

## Discussão

- **A hipótese se confirmou em parte.** O p95 e as req/s melhoraram muito, mas o banco **continua saturado** (98,7% de CPU). Os índices tiraram os Seq Scans das rotas frequentes, e o custo passou a ficar concentrado no que os índices não resolvem:
  - **`/clientes/:id/pedidos`:** mediana por rota de cerca de 9,2 a 9,6 s. Cada consulta ficou barata, mas ainda são cerca de 20 consultas por requisição, cada uma abrindo uma conexão nova ao banco (N+1).
  - **`top-produtos`:** cerca de 21 s. Agrega 1,35 milhão de linhas a cada chamada; nenhum índice evita isso.
  - **`vendas-por-dia`:** cerca de 4 a 6 s. O filtro `criado_em::date` impede o uso de um índice em `criado_em`, e a consulta traz `observacoes` sem usar.
- **Rotas que agora custam menos de 1 ms no banco continuam com mediana de cerca de 400 a 500 ms sob carga.** É o caso de `cliente` e `cliente-por-email`. Minha hipótese, ainda não verificada, é que elas esperam na fila de um banco saturado, somando o custo de abrir uma conexão por consulta.
- **Custo:**
  - 66 MB de disco, cerca de 22% do tamanho das tabelas (cerca de 295 MB);
  - custo de escrita em `INSERT` e `UPDATE` (Kossmann et al., 2020). **A carga do desafio só faz leituras**, então esse custo não aparece aqui. Numa loja real, com pedidos entrando o tempo todo, apareceria.

## Repetibilidade: remedição com banco recriado e na tomada

> Histórico do notebook. Esta seção levou à remedição no desktop: ver [`diagnostico/remedicao-desktop/`](../diagnostico/remedicao-desktop/README.md).

A primeira rodada levantou uma dúvida: parte do ganho podia vir do estado do banco (cache) e não dos índices. Para testar, medi os dois lados de novo em 2026-11-06, recriando o banco do zero (`docker compose down -v`) imediatamente antes de cada série:
- a linha de base no commit `8da289c` (`main`, sem o `03-indices.sql`);
- a 01 no commit `63b6a8c`.

O ambiente de cada dia está em [`diagnostico/ambiente.txt`](../diagnostico/ambiente.txt):
- **2026-11-05:** perfil `balanced`, notebook **na bateria**. Esse estado foi informado pela autora; não foi registrado por comando.
- **2026-11-06:** perfil `balanced`, notebook **na tomada**. Conferido por comando ao fim das medições.

Mediana de 3 execuções em cada série:

| Métrica | Base 11-05 (bateria) | Base 11-06 (tomada) | 01 11-05 (bateria) | 01 11-06 (tomada) |
|---|---|---|---|---|
| Requisições/s | 1,81 | 2,52 | 5,81 | 8,82 |
| Mediana | 2156,1 ms | 1502,3 ms | 1096,0 ms | 701,1 ms |
| p95 | 35082,7 ms | 26538,7 ms | 12222,6 ms | 8087,2 ms |
| p99 | 41481,8 ms | 32199,8 ms | 17537,1 ms | 10865,6 ms |
| CPU média do banco | 99,0% | 98,0% | 98,7% | 100,2% |
| Memória média do banco | 227,7 MiB | 231,8 MiB | 227,6 MiB | 230,5 MiB |
| CPU média da API | 6,0% | 5,4% | 14,3% | 13,9% |
| Memória média da API | 30,1 MiB | 96,2 MiB | 38,4 MiB | 45,1 MiB |

**Pastas de 2026-11-06:**
- linha de base: `resultados/20261106-025518-00-linha-de-base-banco-recriado`, `20261106-025653-…`, `20261106-025835-…`;
- 01: `resultados/20261106-030111-01-indices-banco-recriado`, `20261106-030243-…`, `20261106-030410-…`.

**Ganho relativo da 01 em cada dia:**

| | 11-05 (bateria) | 11-06 (tomada) |
|---|---|---|
| Requisições/s | cerca de 3,2× | cerca de 3,5× |
| p95 | −65% | −70% |

**Leitura:**
- **O ganho dos índices se repete**, com o mesmo sentido e tamanho parecido, nos dois dias.
- **A hipótese de cache não explica a primeira rodada.** As medições de 11-05 também foram feitas logo depois de criar o banco: a linha de base na primeira subida e a 01 depois do `down -v`.
- **Os valores absolutos subiram cerca de 40 a 50% nos dois lados de 11-05 para 11-06.** A explicação mais provável é a fonte de energia: na bateria, o notebook tende a limitar a potência da CPU, e o banco está limitado justamente por CPU. Não isolei essa variável. Horário, temperatura e carga de fundo também mudaram entre os dias.
- **Uma anomalia sem explicação:** a memória da API na linha de base de 11-06 (cerca de 96 MiB) ficou cerca de 3× acima da de 11-05 (cerca de 30 MiB), com o mesmo código. Não foi investigada e não muda o tempo de resposta.
- **Consequência para as próximas mudanças:** só comparar séries medidas nas mesmas condições, ou seja, na tomada, com o perfil `balanced` e de preferência na mesma sessão. Números absolutos de dias diferentes não devem ser comparados entre si (Laaber et al., 2019, sobre a variabilidade de medições de desempenho).

## O que refutaria esta conclusão

- **Se repetir as medições** na mesma máquina não reproduzir a diferença. Isso já foi feito duas vezes: no notebook, em outro dia e com outra fonte de energia, e num desktop, em rodízio. O ganho relativo se manteve nas duas (3,5× e 3,6× em req/s).
- **Se o ganho vier do banco recriado** e não dos índices. Isso foi descartado: nos dois dias, os dois lados foram medidos com o banco recém-criado.
- **Um limite da medição:** o `recursos.txt` às vezes mostra `cpu_max` menor que `cpu_media` (por exemplo 100,0% contra 100,6%). Parece que o script compara os valores como texto. Por isso usei só a `cpu_media`.

## Próximo gargalo

Candidatas, na ordem: eliminar o N+1 de `/clientes/:id/pedidos` (mudança 03), pool de conexões (02) e pré-cálculo de `top-produtos` (06).

## Referências

1. Yang, J.; Subramaniam, P.; Lu, S.; Yan, C.; Cheung, A. *How not to structure your database-backed web applications: a study of performance bugs in the wild*. ICSE 2018. https://par.nsf.gov/servlets/purl/10067547
2. Yan, C.; Cheung, A.; Yang, J.; Lu, S. *Understanding Database Performance Inefficiencies in Real-world Web Applications*. CIKM 2017. https://www.cc.gatech.edu/~jarulraj/courses/8803-f18/papers/db_study.pdf
3. Kossmann, J.; Halfpap, S.; Jankrift, M.; Schlosser, R. *Magic mirror in my hand, which is the best in the land? An Experimental Evaluation of Index Selection Algorithms*. PVLDB 13(11), 2020. https://www.vldb.org/pvldb/vol13/p2382-kossmann.pdf
4. Laaber, C.; Scheuner, J.; Leitner, P. *Software Microbenchmarking in the Cloud. How Bad is it Really?* Empirical Software Engineering 24(4), 2019. https://research.chalmers.se/publication/511491/file/511491_Fulltext.pdf
