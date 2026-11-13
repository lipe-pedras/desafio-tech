# 08 · Tamanho do pool depois da 07 (`DB_POOL_MAX` 1, 2, 3 e 5)

- **Status:** medida; mantido `DB_POOL_MAX=1` (merge na `main` sem mudar o pool)
- **Branch / commits:** `08-tamanho-do-pool`, a partir da `main` com a 07 (`7a0baaf`) / `a835ee4` (2), `879d362` (3), `5991028` (5); o tamanho 1 é a própria `main`, e `1d44cd4` volta a branch para 1
- **Comparada com:** `DB_POOL_MAX=1` (`main`), medido na mesma sessão, em rodízio

## Hipótese

O tamanho do pool foi escolhido na [02.1](02.1-tamanho-do-pool.md) e revisto na [03](03-n-mais-1.md), sempre com o banco saturado (100% de CPU). Ali, mais conexões só dividiam a mesma CPU e pioravam tudo, e o fechamento da 03 ficou com 1 conexão.

Depois da 06 e da 07, o banco ficou em cerca de 92% de CPU, e a cota de 1 CPU quase não pausa o banco ([`07-resumo.txt`](../diagnostico/07-resumo.txt)). Com uma conexão só, o banco fica ocioso enquanto espera a ida e volta de cada consulta: a resposta vai até a API, e a próxima consulta só depois sai da fila do pool. Com 2 ou mais conexões, uma consulta pode começar enquanto a anterior volta, e essa folga deve ser aproveitada.

Também queria saber se o gargalo passou para a API. A CPU dela chegou a 39% do limite de 0,5 CPU na 07.

## Alterações

Só `DB_POOL_MAX` no [`docker-compose.yml`](../docker-compose.yml), um commit por valor.

O rodízio passou a registrar também os contadores de cota de CPU da API, além dos do banco (commit `61062bd`, em [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh)). A cota da API é de 50 ms a cada 100 ms (`cpu.max` = `50000 100000`).

## Resultado

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. Rodízio de 4 versões com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh): cada versão tem o seu banco, criado do zero, com aquecimento de 60 s, 3 rodadas com a ordem deslocada. 2026-11-12, 20h53 a 21h27 (horário local). Contrato mantido, 0,00% de erros e `arquivos alterados sem commit: 0` nas 12 execuções.

Mediana de 3 execuções ([`diagnostico/08-resumo.txt`](../diagnostico/08-resumo.txt), gerado por [`diagnostico/analisar.py`](../diagnostico/analisar.py)):

| Métrica | 1 (`main`) | 2 | 3 | 5 |
|---|---|---|---|---|
| Requisições/s | 899,17 (898,80 a 901,99) | **950,95** (938,52 a 954,66) | 921,74 (918,72 a 924,50) | 878,35 (876,48 a 892,22) |
| Variação | | +5,8% | +2,5% | −2,3% |
| Média | 22,2 ms | 21,0 ms | 21,7 ms | 22,7 ms |
| Mediana | 20,5 ms | 12,2 ms (−41%) | 7,7 ms (−63%) | 4,7 ms (−77%) |
| p95 | **47,1 ms** | 65,9 ms (+40%) | 77,9 ms (+66%) | 87,8 ms (+87%) |
| p99 | **62,6 ms** | 74,5 ms (+19%) | 84,3 ms (+35%) | 92,8 ms (+48%) |
| CPU média do banco | 91,6% | 99,9% | 99,7% | 99,8% |
| Memória média do banco | 151,7 MiB | 154,8 MiB | 157,9 MiB | 163,8 MiB |
| CPU média da API | 19,4% | 20,7% | 19,3% | 18,4% |

| Rota (mediana da rota nas 3) | 1 | 2 | 3 | 5 |
|---|---|---|---|---|
| `cliente` | 14,6 ms | 7,1 ms | 4,4 ms | 2,9 ms |
| `cliente-por-email` | 14,6 ms | 7,0 ms | 4,4 ms | 2,9 ms |
| `pedidos-do-cliente` | 29,3 ms | 16,6 ms | 11,3 ms | 6,1 ms |
| `pedidos-por-status` | 29,7 ms | 17,2 ms | 12,0 ms | 6,5 ms |
| `busca-produtos` | 15,5 ms | 7,9 ms | 5,3 ms | 3,8 ms |
| `vendas-por-dia` | 23,8 ms | 19,9 ms | 17,1 ms | 86,0 ms |
| `top-produtos` | 14,6 ms | 6,8 ms | 4,4 ms | 3,0 ms |

**Contadores de cota de CPU** durante cada `medir.sh` (cerca de 760 períodos de 100 ms; tabela completa em [`08-resumo.txt`](../diagnostico/08-resumo.txt)):

| Pool | Banco: períodos pausados | Banco: `throttled_usec` somado | Banco: CPU usada | API: períodos pausados | API: CPU usada |
|---|---|---|---|---|---|
| 1 | 2,5% | 0,3 s | 69,0 a 69,1 s | 0 | 14,4 a 14,6 s |
| 2 | 98,4 a 98,6% | 66,4 a 66,7 s | 75,1 a 75,2 s | 0 | 15,3 a 15,8 s |
| 3 | 98,7 a 98,8% | 137,1 a 137,9 s | 75,2 s | 0 | 14,5 a 14,7 s |
| 5 | 98,3 a 98,7% | 270,6 a 272,4 s | 75,2 a 75,3 s | 0 | 13,8 a 14,0 s |

- **O `throttled_usec` passa da duração da medição** (cerca de 76 s) com 3 e 5 conexões. Pelos números, ele soma o tempo pausado de cada processo do banco que estava pronto para rodar, e não o tempo de relógio. Não confirmei isso na documentação do kernel. Compare só entre as linhas.
- **A API nunca foi pausada,** em nenhum tamanho de pool, e usou cerca de 19% de uma CPU (38% da cota dela).

**Pastas de resultados:** `resultados/20261112-*-08-pool-{1,2,3,5}-desktop`, 3 por tamanho (lista em [`08-resumo.txt`](../diagnostico/08-resumo.txt)).

## Discussão

- **A vazão tem um máximo em 2 conexões: +5,8% em req/s**, sem sobreposição com 1 conexão. Com 3, o ganho cai para +2,5%; com 5, vira −2,3%.
- **A folga do banco foi usada.** Com 1 conexão, o banco ficava em 91,6% de CPU e quase não era pausado. Com 2 ou mais, ele vai a 99,9%, e a cota pausa o banco em 98% dos períodos, como acontecia com o paralelismo antes da 06.1.
- **A distribuição das latências muda muito.**
  - **As rotas curtas caem pela metade com 2 conexões** e continuam caindo com mais. Por isso a mediana cai 41%, 63% e 77%.
  - **A cauda sobe:** p95 +40% com 2 conexões, +87% com 5.
  - **Com 5 conexões, `vendas-por-dia` vai de 24 para 86 ms.**
- **Minha interpretação, não verificada:** com 1 conexão, as consultas são atendidas em fila, na ordem de chegada. Com várias, o banco divide a CPU entre as que estão em execução. As curtas terminam logo, mas as longas (`vendas-por-dia`, cerca de 9 ms de CPU) disputam a CPU com as outras, e a cota pausa todas juntas. É a troca entre atender em fila única e dividir o tempo de CPU.
- **A API não é o gargalo:** nunca foi pausada e usou 38% da cota.
- **Custo:** cada conexão a mais custa cerca de 3 MiB no banco nesta faixa (151,7 → 163,8 MiB de 1 para 5).

## Decisão

Mantido `DB_POOL_MAX=1`. O merge na `main` leva o registro da cota de CPU da API no rodízio, as medições e esta ficha, mas não muda o pool.

| Critério | Melhor |
|---|---|
| Requisições/s | 2 conexões (+5,8%) |
| Mediana | 5 conexões (−77%), mas com p95 +87% |
| p95, p99 e memória | 1 conexão (`main`) |

O ganho de vazão com 2 conexões é pequeno (+5,8%), e a cauda piora bem mais (p95 +40%, p99 +19%). Além disso, com 2 conexões o banco volta a ser pausado pela cota em quase todo período.

## O que refutaria esta conclusão

- **Se reduzir `vendas-por-dia` (a próxima rota mais cara) mudar o quadro:** com as consultas mais curtas, várias conexões poderiam ganhar vazão sem piorar a cauda.
- **Se outra sessão não repetir a diferença de vazão** (+5,8%), que é pequena, embora sem sobreposição nesta sessão.
