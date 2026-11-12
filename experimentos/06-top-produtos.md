# 06 · `top-produtos` agrega por `produto_id` antes de juntar `produtos`

- **Status:** aplicada e medida na branch `06-top-produtos`; o merge não foi feito
- **Branch / commits:** `06-top-produtos`, a partir da `main` com a 05.2 (`bc83df2`) / `ea59e24` (API)
- **Comparada com:** a `main` (commit `bc83df2`), medida na mesma sessão, em rodízio

## Hipótese

Com `DB_POOL_MAX=1`, as consultas de todas as rotas passam por uma conexão só. A rota que mais ocupa o banco por requisição média é a que mais atrasa as outras. Medi o tempo de execução no banco de cada rota, ponderado pelo peso na carga ([`diagnostico/06-custo-por-rota.txt`](../diagnostico/06-custo-por-rota.txt), gerado por [`06-custo-por-rota.sql`](../diagnostico/06-custo-por-rota.sql); banco ocioso, mediana de 3 rodadas):

| Rota | Peso | ms por chamada | ms por 100 requisições da carga | % do tempo do banco |
|---|---|---|---|---|
| `top-produtos` | 2 | 446,2 | 892,3 | **79,5%** |
| `vendas-por-dia` | 8 | 13,9 | 111,6 | 9,9% |
| `busca-produtos` | 15 | 7,1 | 107,1 | 9,5% |
| `pedidos-por-status` | 15 | 0,54 | 8,0 | 0,7% |
| `pedidos-do-cliente` | 20 | 0,13 | 2,6 | 0,2% |
| `cliente-por-email` | 15 | 0,07 | 1,1 | 0,1% |
| `cliente` | 25 | 0,005 | 0,1 | 0,0% |

O tempo medido é só o de execução da consulta, sem rede, parse nem o trabalho da API.

`top-produtos` é 2% das requisições e quase 80% do tempo de execução no banco. No plano atual ([`diagnostico/06-top-produtos.txt`](../diagnostico/06-top-produtos.txt)), o banco:
1. junta 1,35 milhão de itens (de pedidos não cancelados) com `pedidos`;
2. junta o resultado com `produtos`, para ter `nome` e `categoria` em cada linha;
3. agrupa por produto (19.206 grupos), ordena e fica com 10.

O passo 2 só serve para as 10 linhas da resposta. Agrupar por `i.produto_id` e buscar nome e categoria só dos produtos que entram no `LIMIT` deve tirar uma parte do custo da rota e, pela fila da conexão única, acelerar as outras.

## Diagnóstico (antes)

[`diagnostico/06-top-produtos.txt`](../diagnostico/06-top-produtos.txt), banco ocioso, uma execução registrada de cada (depois de 2 de aquecimento):

| Consulta | Plano | Tempo |
|---|---|---|
| Atual | Parallel Hash Join itens × pedidos → Hash Join com `produtos` (1,35 milhão de linhas) → HashAggregate por `pr.id` | 596,1 ms |
| Proposta da 06 | Parallel Hash Join itens × pedidos → HashAggregate por `i.produto_id` → top 10 → Index Scan em `produtos` 10 vezes | 407,5 ms |

Os dois planos usam 2 processos auxiliares além do principal (`max_parallel_workers_per_gather = 2`), com o banco limitado a 1 CPU.

## Alterações

**API:** só a consulta de `/relatorios/top-produtos` em [`api/src/rotas.js`](../api/src/rotas.js). Uma CTE agrupa os itens de pedidos não cancelados por `i.produto_id`, ordena por `receita_centavos DESC, i.produto_id` e aplica o `LIMIT`. Depois, a consulta junta `produtos` só a essas linhas e mantém a mesma ordem. As expressões das somas não mudam.

**Banco:** nada.

**Equivalência:** [`diagnostico/06-equivalencia.txt`](../diagnostico/06-equivalencia.txt), gerado por [`06-equivalencia.sql`](../diagnostico/06-equivalencia.sql). Comparei a resposta inteira (linhas e ordem) da consulta antiga e da nova para todos os limites que a rota aceita, de 1 a 50: **0 diferentes**, com o mesmo MD5 das 50 respostas. A troca é segura porque `itens_pedido.produto_id` tem chave estrangeira para `produtos(id)`, então cada grupo por `produto_id` corresponde a exatamente um produto. Contrato mantido antes de medir e em todas as execuções.

## Fundamentação

- **Fato:** não abri artigo nem documentação específica para esta mudança. A ideia vem do diagnóstico: o plano junta `produtos` a todas as linhas antes de agrupar.
- **Opinião minha:** é a regra geral de reduzir as linhas antes de um JOIN que só serve à saída.

## Resultado

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. Rodízio com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh): cada versão tem o seu banco, criado do zero, com aquecimento de 60 s, 3 rodadas com a ordem deslocada. 2026-11-11, 22h16 a 22h33. Contrato mantido, 0,00% de erros e `arquivos alterados sem commit: 0` nas 6 execuções. As páginas das tabelas estavam marcadas no mapa de visibilidade antes de cada medição ([`diagnostico/rodizio-registro.txt`](../diagnostico/rodizio-registro.txt)).

Mediana de 3 execuções ([`diagnostico/06-resumo.txt`](../diagnostico/06-resumo.txt), gerado por [`diagnostico/analisar.py`](../diagnostico/analisar.py)):

| Métrica | Antes (`main`) | 06 | Variação |
|---|---|---|---|
| Requisições/s | 110,13 (110,33 / 110,13 / 109,54) | **133,78** (133,78 / 134,47 / 132,97) | +21,5% |
| Média | 181,5 ms | 149,4 ms | −17,7% |
| Mediana | 67,8 ms | 71,3 ms | +5,3% |
| p95 | 517,0 ms | 406,9 ms | −21,3% |
| p99 | 878,3 ms | 674,3 ms | −23,2% |
| CPU média do banco | 99,7% | 100,1% | |
| Memória média do banco | 177,5 MiB | 179,4 MiB | |
| CPU média da API | 3,3% | 3,5% | |
| Memória média da API | 29,2 MiB | 29,4 MiB | |

| Rota (mediana da rota nas 3) | Antes | 06 | Variação |
|---|---|---|---|
| `cliente` | 37,5 ms | 43,8 ms | +17% |
| `cliente-por-email` | 39,1 ms | 41,0 ms | +5% |
| `pedidos-do-cliente` | 95,4 ms | 102,0 ms | +7% |
| `pedidos-por-status` | 93,6 ms | 99,8 ms | +7% |
| `busca-produtos` | 53,9 ms | 57,8 ms | +7% |
| `vendas-por-dia` | 60,8 ms | 64,5 ms | +6% |
| `top-produtos` | 415,7 ms | 303,2 ms | −27% |

**Pastas de resultados:**
- antes: `resultados/20261111-221824-06-antes-desktop`, `20261111-222614-…`, `20261111-222851-…`;
- 06: `resultados/20261111-222100-06-top-produtos-desktop`, `20261111-222337-…`, `20261111-223127-…`.

## Discussão

- **A hipótese se confirmou em parte: +21,5% em req/s, p95 −21% e p99 −23%**, sem sobreposição (109,54 a 110,33 contra 132,97 a 134,47). `top-produtos` caiu 27%.
- **A cauda melhorou mais que o meio.** O p99 é dominado por `top-produtos`, que agora segura a conexão por menos tempo.
- **As outras rotas ficaram de 5 a 17% mais lentas, e a mediana geral subiu 5%.** O contrário do que a hipótese da fila previa.
  - **Minha interpretação, não verificada:** o k6 roda 20 usuários em ciclo fechado. Com `top-produtos` mais rápida, cada usuário volta antes à fila e faz mais requisições por segundo. O banco continua em 100% de CPU, e a fila das rotas curtas fica mais cheia. O ganho aparece em req/s e na cauda, não na latência das rotas curtas.
- **Custo:** nenhum recurso novo. A memória do banco variou dentro do que já se via entre execuções.

## Próximos passos considerados

| Alternativa | Situação |
|---|---|
| Tabela de resumo por produto (unidades e receita), mantida por gatilhos em `itens_pedido` e `pedidos` (versão agressiva, como a 05.2) | Não feita. Tiraria quase toda a rota do banco, mas com custo em toda escrita de itens e de status de pedido. |
| `max_parallel_workers_per_gather = 0`: o plano usa 3 processos num banco limitado a 1 CPU | Não testada. Muda um parâmetro do PostgreSQL no `docker-compose.yml`. |
| Somar todos os itens e subtrair os de pedidos cancelados, sem o JOIN com os 450 mil pedidos | Testada só num EXPLAIN exploratório, sem registro em arquivo; o tempo ficou próximo ao da 06. A equivalência é mais delicada (produtos só com pedidos cancelados). Descartada. |

## O que refutaria esta conclusão

- **Se outra sessão não repetir a diferença.** As 6 execuções foram feitas numa sessão só.
- **Se a piora das rotas curtas não vier do ciclo fechado do k6.** Um teste com taxa de chegada fixa separaria os dois efeitos, mas mudaria a régua; não fiz.
