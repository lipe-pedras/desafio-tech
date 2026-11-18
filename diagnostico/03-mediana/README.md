# Por que a mediana geral subiu na mudança 03

> **Isto é diagnóstico, não resultado.** Estes testes não usam o `scripts/medir.sh` nem o formato oficial de medição: não geram pasta em `resultados/`, usam uma carga modificada (teste 1) ou uma API instrumentada (teste 2), e o código instrumentado não vai para a `main`. Servem para entender um mecanismo. Os resultados oficiais da 03 continuam sendo os de [`experimentos/03-n-mais-1.md`](../../experimentos/03-n-mais-1.md).

**Condições:** 2026-11-09, na tomada, perfil `balanced`, `DB_POOL_MAX=2`, 60 s por rodada, semente 42, com aquecimento de 15 s. Cada valor é a mediana de 3 rodadas. Números em [`resumo.txt`](resumo.txt), gerado por `python3 diagnostico/analisar.py --serie 03-mediana` ([`analisar.py`](../analisar.py)) a partir de `saida/`. Tudo roda com [`rodar.sh`](rodar.sh).

**O que se quer explicar:** nos resultados oficiais, a mediana geral foi de 208,2 para 623,0 ms depois da 03, e `cliente` foi de 80,9 para 410,4 ms, embora o código dessa rota não tenha mudado.

## Teste 1: mais usuários nas outras rotas, sem a 03

**Hipótese.** As rotas rápidas ficaram lentas porque a 03 liberou usuários que estavam presos no N+1, e eles passaram a concorrer nas outras rotas. Se for isso, a lentidão aparece no código **antigo**, sem nenhuma mudança, bastando colocar mais usuários nas outras rotas. Previsão para `cliente`: perto de 81 ms com 5 usuários (cerca de 4,8 fora do N+1 antes da 03) e perto de 410 ms com 14 (cerca de 14,4 depois).

**Teste.** Código antigo (`1fd2ae4`, sem instrumentação), com [`carga-sem-n1.js`](carga-sem-n1.js): cópia da carga oficial sem a rota `pedidos-do-cliente`, e os demais pesos iguais. Usuários: 2, 5, 8, 14 e 20, em 3 rodadas alternando os níveis.

**Resultados.**

| Usuários | req/s | Mediana geral | `cliente` | `cliente-por-email` | `busca-produtos` |
|---|---|---|---|---|---|
| 2 | 15,31 | 15,7 ms | 1,5 ms | 1,5 ms | 29,9 ms |
| 5 | 16,76 | 113,4 ms | 74,2 ms | 74,8 ms | 100,0 ms |
| 8 | 19,26 | 231,3 ms | 134,3 ms | 165,0 ms | 196,1 ms |
| 14 | 18,03 | 487,6 ms | 374,0 ms | 332,8 ms | 371,1 ms |
| 20 | 18,99 | 695,4 ms | 528,5 ms | 511,8 ms | 586,6 ms |

**Conclusão.** A hipótese se confirmou. Com 5 usuários, `cliente` ficou em 74,2 ms (previsão: perto de 81) e, com 14, em 374,0 ms (previsão: perto de 410). A concorrência sozinha, com o código antigo, reproduz a lentidão. As req/s praticamente não sobem a partir de 8 usuários: o sistema já está saturado, e cada usuário a mais só aumenta a espera.

## Teste 2: onde o tempo é gasto

**Hipótese.** O tempo a mais das rotas rápidas é espera por uma conexão do pool, e não execução no banco. Previsão: a espera sobe muito, a execução sobe pouco, e o número de requisições em andamento na rota do N+1 cai de cerca de 15 para cerca de 6.

**Teste.** Carga oficial (`carga/teste-carga.js`, 20 usuários), com a API instrumentada ([`instrumentacao/`](instrumentacao/)) para medir, em cada consulta, a espera no pool e a execução, e para amostrar a cada segundo as requisições em andamento por rota e o tamanho da fila do pool. Versões `1fd2ae4` (antes) e `958aad1` (depois), alternadas em 3 rodadas, sem recriar o banco entre elas.

**Resultados.**

| Rota | Em andamento, antes → depois | Espera no pool por consulta | Execução por consulta | Mediana (k6) |
|---|---|---|---|---|
| `cliente` | 0,92 → 3,50 | 132,4 → 559,1 ms | 2,95 → 5,62 ms | 70,8 → 396,2 ms |
| `cliente-por-email` | 0,48 → 1,98 | 117,2 → 535,2 ms | 5,05 → 8,16 ms | 69,8 → 403,9 ms |
| `pedidos-do-cliente` | **15,02 → 5,65** | 132,4 → 562,1 ms | 2,06 → 7,27 ms | 2653,0 → 898,9 ms |
| `pedidos-por-status` | 1,18 → 3,93 | 126,5 → 558,6 ms | 36,68 → 46,58 ms | 222,9 → 1002,0 ms |
| `busca-produtos` | 0,59 → 2,35 | 137,8 → 605,9 ms | 30,95 → 39,27 ms | 100,6 → 501,7 ms |
| `vendas-por-dia` | 0,65 → 1,53 | 136,8 → 542,2 ms | 260,83 → 307,79 ms | 376,5 → 725,5 ms |
| `top-produtos` | 0,90 → 1,08 | 96,8 → 545,0 ms | 2191,00 → 2241,22 ms | 2280,5 → 2616,2 ms |

| Geral (mediana das rodadas) | Antes | Depois |
|---|---|---|
| Consultas nos 60 s | 8266 | 1924 |
| Execução média por consulta, todas as rotas | 14,4 ms | 61,6 ms |
| Tempo de execução somado | 118481 ms | 118739 ms |
| Requisições esperando o pool (média) | 17,69 | 17,92 |
| Espera prevista: fila × execução média ÷ 2 conexões | 126,7 a 127,9 ms | 541,7 a 559,8 ms |

**Conclusão.** A hipótese se confirmou, e o mecanismo ficou mais preciso:

- **As rotas rápidas gastam quase todo o tempo esperando.** Em `cliente`, a espera é de 559,1 ms e a execução, de 5,62 ms. A execução dobrou, mas em valor absoluto é irrelevante.
- **A fila não ficou maior; ficou mais pesada.** Ela tem cerca de 18 requisições nas duas versões, porque há 20 usuários sem pausa e só 2 conexões. Antes, a maior parte da fila era de consultas de cerca de 2 ms do N+1; depois, ela é uma amostra das rotas pesadas. A execução média por consulta subiu de 14,4 para 61,6 ms.
- **A conta fecha.** Fila × execução média ÷ 2 conexões prevê uma espera de 126,7 a 127,9 ms antes e de 541,7 a 559,8 ms depois; o medido por consulta foi de cerca de 130 e 560 ms.
- **O banco fez a mesma quantidade de trabalho.** A soma do tempo de execução é quase igual (cerca de 118 s nos 60 s, ou seja, as 2 conexões ocupadas quase o tempo todo). A 03 eliminou 77% das consultas, mas elas eram as mais baratas.

## Uma divergência com o resultado oficial

Neste teste 2, em que as versões foram alternadas, **o ganho de req/s não apareceu**:

| | Antes | Depois |
|---|---|---|
| req/s por rodada | 25,15 / 24,85 / 24,78 | 23,63 / 23,33 / 23,76 |
| Média | 796,4 ms | 844,1 ms |
| Mediana | 188,8 ms | 599,8 ms |
| p95 | 3938,4 ms | 2295,8 ms |
| p99 | 6198,4 ms | 3489,7 ms |

- O oficial tinha dado 17,09 → 22,74 req/s e média de 1168,0 → 877,0 ms. Aqui, a série "antes" foi bem mais rápida, e a média **subiu**.
- O aumento da mediana (cerca de 3×) e a queda do p95 e do p99 se repetem.
- As condições diferem: API instrumentada, versões alternadas, banco não recriado entre rodadas. O "antes" oficial já variou entre sessões com o mesmo código (17,09 e 23,01 req/s), o que indica ruído entre sessões maior que o ganho medido. **Não sei a causa da diferença, e estes números não substituem os oficiais.** Para decidir, é preciso repetir as duas versões no formato oficial, alternadas na mesma sessão.

## Limites

- A instrumentação troca `pool.query` por `pool.connect` mais `query`, e as duas versões a usam. Pode alterar um pouco os tempos.
- A "execução" é medida na API: inclui a rede interna e a disputa de CPU dentro do banco.
- `pedidos-do-cliente` e a carga do teste 1 não são a carga oficial.
