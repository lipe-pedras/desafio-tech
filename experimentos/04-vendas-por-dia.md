# 04 · Refazer a consulta de `/relatorios/vendas-por-dia`

- **Status:** 04 e 04.1 aplicadas e medidas
- **Branch / commits:** `04-vendas-por-dia` / `96365fe` (04, consulta) e `95755c1` (04.1, índice)
- **Comparada com:** a `main` com a 03 fechada (commit `1e1ba20`, `DB_POOL_MAX=1`), medida na mesma sessão, em rodízio

## Hipótese

**04.** A rota pede ao banco todas as linhas de itens do período, com a coluna `observacoes`, e soma por dia em JavaScript. Além disso, o filtro `criado_em::date BETWEEN` converte cada linha antes de comparar. Somar no banco, trazer só as colunas usadas e filtrar por intervalo direto em `criado_em` deve reduzir o trabalho do banco e da API, aumentando as req/s e reduzindo o tempo de `vendas-por-dia`.

**04.1.** Com o filtro por intervalo da 04, um índice em `pedidos (criado_em)` deve evitar a leitura dos 500 mil pedidos a cada chamada (Seq Scan) e liberar CPU do banco para as outras rotas.

## Diagnóstico (antes)

Evidência: [`diagnostico/04-vendas-por-dia.txt`](../diagnostico/04-vendas-por-dia.txt), gerado por [`diagnostico/04-vendas-por-dia.sql`](../diagnostico/04-vendas-por-dia.sql). Uma execução de cada consulta com o banco ocioso, período de 7 dias (o mesmo da carga). Servem como diagnóstico, não como resultado.

- **Volume:** 7 dias têm cerca de 4.800 pedidos, e a consulta devolve **12.945 linhas**, uma por item. Cada linha traz `observacoes`, com **274 bytes em média**, que a rota não usa. São cerca de 3,5 MB por chamada só dessa coluna, uma conta feita a partir desses dois números.
- **Plano atual:** Parallel Seq Scan em `pedidos`, com o filtro `(criado_em)::date >= ... AND (criado_em)::date <= ...`, que descarta cerca de 495 mil linhas.
- **Consulta reescrita (B), sem índice novo:** o filtro vira `criado_em >= '2024-01-01' AND criado_em < '2024-01-08'`, mas o plano continua em Seq Scan, porque não existe índice cuja primeira coluna seja `criado_em`. O índice da 01 começa por `status`.
- **Consulta reescrita com um índice em `criado_em` (C)**, criado só dentro de uma transação desfeita (`ROLLBACK`): o plano passa a Bitmap Index Scan, que lê 4.792 pedidos em vez de 500 mil.

## Alterações

**04:** só o manipulador da rota em [`api/src/rotas.js`](../api/src/rotas.js):
- o filtro passa a `p.criado_em >= $1::date AND p.criado_em < $2::date + 1`, equivalente a `criado_em::date BETWEEN $1 AND $2`;
- o banco agrupa por `p.criado_em::date` e devolve uma linha por dia: `count(DISTINCT p.id)`, `sum(i.quantidade)` e `sum(i.quantidade::bigint * i.preco_unitario_centavos)`;
- `observacoes` sai da consulta;
- a API só converte as somas para número, porque o `pg` devolve `bigint` e `numeric` como texto.

**04.1:** só o arquivo novo [`banco/04-indice-pedidos-criado-em.sql`](../banco/04-indice-pedidos-criado-em.sql), com `CREATE INDEX pedidos_criado_em_idx ON pedidos (criado_em)` e `ANALYZE pedidos`.

**Equivalência:** além do contrato, que tem 3 períodos válidos, comparei a lógica antiga e a nova direto no banco nos **725 períodos de 7 dias que a carga pode sortear**, mais 5 bordas de 1 a 31 dias, inclusive virada de ano e 29 de fevereiro. Resultado: **730 períodos, 0 diferentes** ([`diagnostico/04-equivalencia.txt`](../diagnostico/04-equivalencia.txt), gerado por [`04-equivalencia.py`](../diagnostico/04-equivalencia.py)).

**Contrato:** mantido antes de medir e em todas as execuções.

## Fundamentação

- **Shao et al. (2020), p. 4, Tabela II**, catálogo de antipadrões de acesso a banco reunidos da literatura. A rota tinha três deles:
  - **AP-02, *Moving computation to the DBMS*:** *"Computing with the results of multiple queries, where the computation can also be done by the DBMS"*, com a correção *"Moving the computation to the DBMS"*;
  - **AP-14, *Unnecessary column retrieval*:** *"Retrieving more columns than needed"*;
  - **AP-19, *Missing indexes*:** *"Appropriate indexes are not included in table schema"*.
- **O mesmo catálogo traz o caso contrário, AP-03:** às vezes calcular no banco *"is less performant compared with computing by the server"*. Por isso a mudança foi medida, e não presumida.
- **PostgreSQL 16, seção 11.2 (Index Types):** o planejador considera um índice B-tree *"whenever an indexed column is involved in a comparison"*. Em `criado_em::date BETWEEN ...`, o que está na comparação é uma expressão, e não a coluna `criado_em`. Por isso um índice em `criado_em` só serve depois da 04, que compara a coluna diretamente.
- **PostgreSQL 16, seção 11.7 (Indexes on Expressions):** a alternativa seria um índice na expressão `(criado_em::date)`, que mantém a consulta antiga. A documentação diz que esses índices *"are relatively expensive to maintain, because the derived expression(s) must be computed for each row insertion and non-HOT update"*.
- **Kossmann et al. (2020), p. 2:** índices trazem *"a trade-off between improved performance and elevated storage consumption"*, e as escritas pagam a manutenção. Isso vale para o custo da 04.1.

Fato e opinião, separados:
- **Fato:** Shao et al. estudam aplicações que escrevem SQL direto, como esta.
- **Opinião minha:** o AP-02 fala em "múltiplas consultas", e aqui é uma consulta só, cujo resultado é agregado na API. Tomo o AP-02 como evidência da categoria (computação que o banco poderia fazer), não do caso exato.

## Resultado

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. Rodízio com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh): cada versão tem o seu banco, criado do zero a partir dos arquivos de `banco/` do seu commit. Os bancos são ligados um por vez, com aquecimento de 60 s, em 3 rodadas com a ordem deslocada. 2026-11-11, 13h11 a 13h33. Contrato mantido, 0,00% de erros e `arquivos alterados sem commit: 0` nas 9 execuções.

Mediana de 3 execuções ([`diagnostico/04-resumo.txt`](../diagnostico/04-resumo.txt), gerado por [`diagnostico/analisar.py`](../diagnostico/analisar.py)):

| Métrica | Antes (`main`) | 04 (consulta) | 04.1 (+ índice) |
|---|---|---|---|
| Requisições/s | 65,50 (66,24 / 63,66 / 65,50) | 79,43 (79,78 / 78,68 / 79,43) | **83,35** (83,34 / 83,35 / 84,53) |
| Média | 304,9 ms | 251,7 ms | 239,8 ms |
| Mediana | 211,3 ms | 128,0 ms | 110,7 ms |
| p95 | 803,2 ms | 653,6 ms | 658,3 ms |
| p99 | 1108,5 ms | 988,9 ms | 976,0 ms |
| CPU média do banco | 96,1% | 99,7% | 99,6% |
| Memória média do banco | 173,0 MiB | 178,7 MiB | 180,4 MiB |
| CPU média da API | 26,4% | 2,8% | 2,7% |
| Memória média da API | 34,7 MiB | 28,6 MiB | 28,9 MiB |

| Variação | req/s | Média | Mediana | p95 | p99 |
|---|---|---|---|---|---|
| 04 contra antes | +21% | −17% | −39% | −19% | −11% |
| 04.1 contra 04 | +5% | −5% | −14% | +1% | −1% |
| 04.1 contra antes | +27% | −21% | −48% | −18% | −12% |

| Rota (mediana da rota nas 3) | Antes | 04 | 04.1 |
|---|---|---|---|
| `cliente` | 146,8 ms | 94,0 ms | 82,8 ms |
| `cliente-por-email` | 150,6 ms | 95,2 ms | 81,5 ms |
| `pedidos-do-cliente` | 334,5 ms | 208,0 ms | 184,4 ms |
| `pedidos-por-status` | 330,2 ms | 223,4 ms | 207,5 ms |
| `busca-produtos` | 171,6 ms | 104,2 ms | 89,6 ms |
| `vendas-por-dia` | 210,7 ms | 106,4 ms | 92,2 ms |
| `top-produtos` | 502,9 ms | 483,6 ms | 478,4 ms |

**Pastas de resultados:**
- antes: `resultados/20261111-131125-04-antes-desktop`, `20261111-132433-…`, `20261111-132948-…`;
- 04: `resultados/20261111-131403-04-vendas-por-dia-desktop`, `20261111-131918-…`, `20261111-133226-…`;
- 04.1: `resultados/20261111-131640-041-indice-criado-em-desktop`, `20261111-132156-…`, `20261111-132711-…`.

**Custo:**
- **04:** nenhum. Os limites dos containers não mudaram, e não há índice nem serviço novo.
- **04.1:** o índice ocupa **11 MB** de disco, contra 163 MB da tabela `pedidos` ([`diagnostico/041-indice-criado-em.txt`](../diagnostico/041-indice-criado-em.txt)). Também há um custo de escrita a cada `INSERT` em `pedidos`, que a carga do desafio, só de leitura, não mede.

## Discussão

- **A hipótese da 04 se confirmou, mas o ganho apareceu num lugar diferente do esperado.**
  - **O que eu esperava:** reduzir o trabalho do banco.
  - **O que aconteceu:** o banco continua lendo `pedidos` inteira na 04 (o plano B ainda é Seq Scan), e a CPU dele *subiu*, de 96,1% para 99,7%. O que caiu foi a CPU da API: de 26,4% para 2,8% na média.
  - **Por quê:** a API usava CPU para receber e converter as 12.945 linhas de cada chamada.
- **A API encostava no limite dela.** Antes da 04, as amostras de CPU da API no `recursos.csv` chegaram a 49,69%, perto do limite de 0,5 CPU. Depois, ficaram entre 0,3% e 5,8%.
  - O `cpu_max` de 9,1% que aparece no `recursos.txt` está errado: é o problema de comparação como texto já registrado na [01](01-indices.md#o-que-refutaria-esta-conclusão).
- **Todas as rotas ficaram mais rápidas com a 04, não só `vendas-por-dia`.** `cliente` caiu de 146,8 para 94,0 ms, por exemplo.
  - **Minha hipótese, não verificada:** enquanto a API convertia as linhas de um relatório, as respostas das outras rotas esperavam na mesma thread do Node.js. Além disso, com `DB_POOL_MAX=1`, a única conexão ficava presa enquanto o banco enviava as linhas.
  - **A favor dela:** a CPU do banco subiu de 96,1% para 99,7%, ou seja, o banco passou menos tempo ocioso esperando a API.
- **A 04.1 tem ganho pequeno, mas fora do ruído.** As execuções não se sobrepõem (79,78 no máximo contra 83,34 no mínimo): +5% em req/s e −14% na mediana. `vendas-por-dia` caiu de 106,4 para 92,2 ms.
- **O p95 e o p99 não mudam com a 04.1.** A cauda é dominada por `top-produtos` (cerca de 480 ms) e `pedidos-por-status` (cerca de 210 ms), que o índice não toca.
- **Uma execução da 04.1 teve p95 de 793,7 ms, contra 613,3 e 658,2 nas outras.** Não investiguei. A mediana das 3 não é afetada.

## Alternativas consideradas e não testadas

| Alternativa | Por que não agora |
|---|---|
| Índice de expressão em `(criado_em::date)`, mantendo o filtro antigo | Resolve só o índice, não a agregação na API, que foi o maior ganho. A documentação aponta custo maior de manutenção nas escritas. |
| Índice BRIN em `criado_em` | Muito menor que um B-tree, mas só funciona bem se `criado_em` acompanhar a ordem física das linhas (PostgreSQL 16, 11.2.6). Não verifiquei essa correlação. Fica para o `proximos-testes.md`. |
| Índice parcial `WHERE status <> 'cancelado'` | Menor, e já filtra os cancelados. Ganho esperado pequeno, porque cancelados são 10% dos pedidos. Não testado. |
| Tabela de resumo por dia, pré-calculada | Leitura de no máximo 31 linhas, mas exige manter a tabela atualizada a cada pedido novo. Faz mais sentido para `top-produtos` (06). |

## O que refutaria esta conclusão

- **Se a carga usasse períodos longos.** A carga pede sempre 7 dias. Com 31 dias, são cerca de 4,4 vezes mais linhas. A agregação no banco continuaria valendo, mas o índice ficaria menos seletivo. Não testei.
- **Se outra sessão não repetir a ordem antes < 04 < 04.1.** As 9 execuções foram feitas numa sessão só.
- **Se o ganho da 04 nas outras rotas tiver outra causa** além da API e da conexão liberadas mais cedo. A explicação acima é uma hipótese; testá-la exigiria instrumentar a API, como no [diagnóstico da 03](../diagnostico/03-mediana/README.md).

## Próximo gargalo

O banco está a cerca de 100% de CPU. A API ficou quase ociosa. A rota mais lenta agora é `top-produtos` (478,4 ms), que agrega todos os itens a cada chamada; depois vêm `pedidos-por-status` (207,5 ms) e `pedidos-do-cliente` (184,4 ms). Candidata: 06 (pré-calcular `top-produtos`).

## Referências

1. Shao, S. et al. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020. DOI 10.1109/ICSME46990.2020.00016. https://par.nsf.gov/servlets/purl/10277614
2. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.2. Index Types*. https://www.postgresql.org/docs/16/indexes-types.html (acesso em 2026-11-11; [`referencias/documentacao/postgresql-16-indexes-types.txt`](../referencias/documentacao/postgresql-16-indexes-types.txt))
3. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.7. Indexes on Expressions*. https://www.postgresql.org/docs/16/indexes-expressional.html (acesso em 2026-11-11; [`postgresql-16-indexes-expressional.txt`](../referencias/documentacao/postgresql-16-indexes-expressional.txt))
4. Kossmann, J.; Halfpap, S.; Jankrift, M.; Schlosser, R. *Magic mirror in my hand, which is the best in the land? An Experimental Evaluation of Index Selection Algorithms*. PVLDB 13(11), 2020. https://www.vldb.org/pvldb/vol13/p2382-kossmann.pdf
