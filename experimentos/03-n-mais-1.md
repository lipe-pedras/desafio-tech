# 03 · Eliminar o N+1 de `/clientes/:id/pedidos`

- **Status:** aplicada e medida
- **Branch / commit da mudança:** `03-n-mais-1` / `958aad1`
- **Comparada com:** o estado da `main` com `DB_POOL_MAX=2` (commit `1fd2ae4`), medido na mesma sessão

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

**Contrato:** mantido antes de medir e nas 3 execuções.

## Fundamentação

Trechos localizados nos PDFs de [`referencias/`](../referencias/):

- **Shao et al. (2020), p. 4, AP-09:** descreve o antipadrão como *"Issuing one query to retrieve N objects from one table, and N other queries to retrieve information related to the N objects from another table"*, e a correção como *"Issuing one query with a join clause of the two tables"*. É o caso desta rota. O estudo cobre aplicações que escrevem SQL direto.
- **Yang et al. (2018), p. 7:** chama o padrão de *"N+1" query problem* e relata que ele continua frequente: *"it appears in 15 problematic actions and 9 performance issues in our study"*.
- **Chen et al. (2014), p. 8:** o impacto do processamento um a um cresce com os dados, *"because the data sizes directly affect the number of iterations in loops"*.
- **Yan et al. (2017), p. 5:** alerta o contrário: *"combined query may not be always faster than the original separated queries"*. Por isso a mudança foi medida, e não presumida.

Yang, Chen e Yan estudam aplicações com ORM; aqui a API escreve SQL direto. Tomo esses três como evidência da categoria do problema, não do caso exato.

## Resultado

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
- **Minha hipótese para isso, ainda não verificada:** a carga é de ciclo fechado (20 usuários, sem pausa entre requisições). Antes, muitos usuários ficavam presos em `pedidos-do-cliente`, enviando consultas minúsculas, uma por vez, e a fila do pool andava rápido. Agora eles saem dessa rota e voltam a chamar as outras, inclusive as pesadas. Cada consulta rápida tem mais chance de ficar atrás de `top-produtos`, `vendas-por-dia` ou da paginação de `/pedidos`, ocupando uma das 2 conexões. O banco segue a 100% de CPU: o trabalho ficou mais bem distribuído entre as requisições, não acabou.
- **O saldo é positivo para quem mede a cauda e o total atendido,** e negativo para a requisição típica. Dependendo do que importa no produto, isso muda a leitura. Os próximos passos atacam as consultas pesadas, que devem aliviar justamente essa fila.
- **O `DB_POOL_MAX=2` foi escolhido com o N+1 ainda presente.** A ficha da [02.1](02.1-tamanho-do-pool.md) já previa medir de novo depois desta mudança, e isso ainda não foi feito.
- **Memória da API:** 123,8 MiB antes e 31,5 MiB depois. O mesmo padrão de cerca de 124 MiB já tinha aparecido em séries da 02.1, sem relação clara com o pool. Não investiguei, então não atribuo a queda a esta mudança.

## O que refutaria esta conclusão

- **Se repetir as séries em outro dia** não reproduzir a diferença. Ainda não repeti.
- **Se a explicação da fila estiver errada.** Um teste seria medir as rotas rápidas depois de resolver as consultas pesadas, ou variar o tamanho do pool com esta versão.

## Próximo gargalo

O banco segue a 100% de CPU. `top-produtos` (2,8 s) e `vendas-por-dia` (0,8 s) ocupam as conexões do pool por mais tempo. Candidatas: 04 (refazer `vendas-por-dia`) e 06 (pré-calcular `top-produtos`).

## Referências

1. Shao, S. et al. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020. DOI 10.1109/ICSME46990.2020.00016. https://par.nsf.gov/servlets/purl/10277614
2. Yang, J. et al. *How not to structure your database-backed web applications: a study of performance bugs in the wild*. ICSE 2018. https://par.nsf.gov/servlets/purl/10067547
3. Chen, T.-H. et al. *Detecting Performance Anti-patterns for Applications Developed using Object-Relational Mapping*. ICSE 2014. https://ece.uwaterloo.ca/~wshang/pubs/peter_icse2014.pdf
4. Yan, C. et al. *Understanding Database Performance Inefficiencies in Real-world Web Applications*. CIKM 2017. https://www.cc.gatech.edu/~jarulraj/courses/8803-f18/papers/db_study.pdf
