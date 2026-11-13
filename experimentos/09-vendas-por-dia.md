# 09 · Índices que cobrem `vendas-por-dia`

- **Status:** aplicada e medida; entrou na `main` junto com a 09.2. Os índices desta ficha continuam no banco, e a consulta da rota foi substituída pela da [09.2](09.2-total-por-dia.md)
- **Branch / commits:** `09-vendas-por-dia`, a partir da `main` com a 08 (`93a6cd9`) / `a4a7821` (banco)
- **Comparada com:** a `main` (commit `93a6cd9`), medida na mesma sessão, em rodízio com a [09.2](09.2-total-por-dia.md)

## Hipótese

Depois da 07, `vendas-por-dia` passou a ser a rota mais cara no banco: era 37% do tempo de execução antes da 07 ([`07-custo-por-rota.txt`](../diagnostico/07-custo-por-rota.txt)), e a busca, que tinha 58%, caiu 6 a 11 vezes.

A consulta lê cerca de 4.300 pedidos de 7 dias pelo índice de `criado_em` e, para cada um, os itens pelo índice de `pedido_id`. Os dois passos vão às tabelas buscar `id` e `status` dos pedidos e `quantidade` e `preco_unitario_centavos` dos itens. As duas tabelas somam 235 MB, e não cabem nos 128 MB de `shared_buffers`.

A documentação do PostgreSQL diz que um índice com `INCLUDE` pode responder a consulta sozinho (*index-only scan*), desde que as páginas estejam marcadas no mapa de visibilidade. Com os dois índices cobrindo a consulta, ela deve ler só índices, menores que as tabelas.

## Alterações

**Banco:** só o arquivo novo [`banco/09-indices-vendas-por-dia.sql`](../banco/09-indices-vendas-por-dia.sql), que troca dois índices por versões com `INCLUDE`, como a [05.1](05-pedidos-por-status.md) fez com o de status:

| Índice antigo | Índice novo | Tamanho |
|---|---|---|
| `itens_pedido (pedido_id)`, da 01 | `itens_pedido (pedido_id) INCLUDE (quantidade, preco_unitario_centavos)` | 21 → 45 MB |
| `pedidos (criado_em)`, da 04.1 | `pedidos (criado_em) INCLUDE (id, status)` | 11 → 19 MB |

O arquivo termina com `VACUUM (ANALYZE)` nas duas tabelas, para marcar as páginas no mapa de visibilidade já na criação do banco, como na 05.1. A API não muda.

**Exploração** ([`diagnostico/09-vendas-por-dia.txt`](../diagnostico/09-vendas-por-dia.txt), gerado por [`09-vendas-por-dia.sql`](../diagnostico/09-vendas-por-dia.sql)): tempo médio de 300 períodos de 7 dias sorteados como na carga, medido dentro do banco depois de uma passada de aquecimento.

| Passo | Plano | Tempo médio |
|---|---|---|
| A. `main` | Bitmap Heap Scan em `pedidos` + Index Scan em `itens_pedido` | 29,2 ms |
| B. só `VACUUM` em `itens_pedido` | igual | 28,8 ms |
| C. índice de itens com `INCLUDE` | Index Only Scan em itens, `Heap Fetches: 0` | 8,3 ms |
| D. C + índice de pedidos com `INCLUDE` (a 09) | Index Only Scan nos dois, `Heap Fetches: 0` | 6,5 ms |

- **Limite da exploração:** os passos rodaram em sequência, no mesmo banco, então o passo A pode ter pago parte do aquecimento. O rodízio abaixo é a medida que vale.
- **Equivalência:** o resultado dos 725 períodos de 7 dias que a carga pode sortear teve o mesmo MD5 em A, C e D.
- **Outras rotas:** `pedidos-do-cliente` usa o índice novo de itens com Index Scan, porque precisa de `produto_id`, que não está no índice.

## Fundamentação

- **PostgreSQL 16, 11.9:** *"PostgreSQL allows you to create an index in which some columns are just “payload” and are not part of the search key. This is done by adding an INCLUDE clause listing the extra columns."* O mesmo texto avisa que o ganho depende do mapa de visibilidade: *"it will be a win only if a significant fraction of the table's heap pages have their all-visible map bits set"*. É a mesma fonte da 05.1.
- **Shao et al. 2020, AP-19 (índices faltando):** a mesma referência da [04](04-vendas-por-dia.md).

## Resultado

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. O rodízio de três versões (`main`, 09 e 09.2) foi feito com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh): cada versão tem o seu banco, criado do zero, com aquecimento de 60 s, e são 3 rodadas com a ordem deslocada. A sessão foi em 2026-11-13, das 12h23 às 12h49. Nas 9 execuções, o contrato foi mantido, com 0,00% de erros e `arquivos alterados sem commit: 0`.

Mediana de 3 execuções ([`diagnostico/09-resumo.txt`](../diagnostico/09-resumo.txt), gerado por [`diagnostico/analisar.py`](../diagnostico/analisar.py)):

| Métrica | Antes (`main`) | 09 | Variação |
|---|---|---|---|
| Requisições/s | 904,50 (904,50 / 903,64 / 904,69) | **1096,89** (1097,90 / 1096,89 / 1096,13) | +21,3% |
| Média | 22,1 ms | 18,2 ms | −17,6% |
| Mediana | 20,5 ms | 17,3 ms | −15,6% |
| p95 | 46,9 ms | 37,3 ms | −20,5% |
| p99 | 59,3 ms | 46,9 ms | −20,9% |
| CPU média do banco | 91,8% | 89,9% | |
| Memória média do banco | 151,8 MiB | 151,3 MiB | |
| CPU média da API | 19,5% | 23,3% | |
| Memória média da API | 31,2 MiB | 31,0 MiB | |

| Rota (mediana da rota nas 3) | Antes | 09 | Variação |
|---|---|---|---|
| `cliente` | 14,6 ms | 12,2 ms | −16% |
| `cliente-por-email` | 14,6 ms | 12,2 ms | −16% |
| `pedidos-do-cliente` | 29,3 ms | 24,4 ms | −17% |
| `pedidos-por-status` | 29,7 ms | 24,8 ms | −17% |
| `busca-produtos` | 15,4 ms | 13,0 ms | −16% |
| `vendas-por-dia` | 23,8 ms | 19,0 ms | −20% |
| `top-produtos` | 14,6 ms | 12,4 ms | −15% |

**Contadores de cota de CPU** durante cada `medir.sh` (cerca de 760 períodos de 100 ms; tabela completa em [`09-resumo.txt`](../diagnostico/09-resumo.txt)):

| Versão | Banco: períodos pausados | Banco: CPU usada | API: períodos pausados | API: CPU usada |
|---|---|---|---|---|
| `main` | 2,2 a 2,6% | 68,9 a 69,2 s | 0 | 14,4 a 14,7 s |
| 09 | 2,4 a 2,6% | 67,7 a 67,9 s | 0 | 17,0 a 17,3 s |

**Pastas de resultados:**
- antes: `resultados/20261113-122638-09-antes-desktop`, `20261113-123938-…`, `20261113-124450-…`;
- 09: `resultados/20261113-122914-09-indices-vendas-por-dia-desktop`, `20261113-123426-…`, `20261113-124726-…`.

## Custo

- **Disco:** +24 MB no índice de itens e +8 MB no de pedidos. A memória média do banco não mudou (151,8 → 151,3 MiB).
- **Escrita:** cada INSERT ou UPDATE grava também as colunas incluídas nos índices. Não medi esse custo; a carga do desafio só lê.
- **Mapa de visibilidade:** o ganho depende de as páginas estarem marcadas. Numa tabela com muitas escritas, o autovacuum precisa acompanhar; senão, a consulta volta a ir às tabelas.

## Discussão

- **A hipótese se confirmou: +21,3% em req/s, p95 −20,5% e p99 −20,9%**, sem sobreposição (903,64 a 904,69 contra 1096,13 a 1097,90).
- **Todas as rotas caíram de 15% a 20%,** não só `vendas-por-dia`. É o mesmo efeito de fila da conexão única das mudanças anteriores: com a rota mais curta, as outras esperam menos. Essa é a hipótese de sempre, ainda não verificada.
- **O banco gastou um pouco menos de CPU (67,8 contra 69,1 s)** atendendo 21% mais requisições.
- **A API ainda não foi pausada,** mas a CPU dela subiu de 19,5% para 23,3%.

## O que refutaria esta conclusão

- **Se o ganho vier do cache, e não do *index-only scan*:** o efeito é o mesmo (menos páginas lidas), mas, com um `shared_buffers` maior, a diferença para a `main` encolheria. Não testei com outro `shared_buffers`.
- **Se outra sessão não repetir a diferença,** que nesta sessão não teve sobreposição.

## Referências

1. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.9. Index-Only Scans and Covering Indexes*. https://www.postgresql.org/docs/16/indexes-index-only-scans.html (acesso em 2026-11-11; [`referencias/documentacao/postgresql-16-indexes-index-only-scans.txt`](../referencias/documentacao/postgresql-16-indexes-index-only-scans.txt))
2. Shao, S. et al. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020. ([`referencias/shao-2020-database-access-performance-antipatterns-icsme.pdf`](../referencias/shao-2020-database-access-performance-antipatterns-icsme.pdf))
