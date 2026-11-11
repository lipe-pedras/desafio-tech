# 05 · Página de `/pedidos?status=&pagina=` lida só do índice

- **Status:** 05 e 05.1 aplicadas e medidas; 05.1 fechada com `VACUUM (ANALYZE)`
- **Branch / commits:** `05-pedidos-por-status` / `9a4968d` (05, consulta), `855b116` (05.1, índice, só `ANALYZE`) e `6596279` (05.1 com `VACUUM (ANALYZE)`)
- **Comparada com:** a `main` com a 04 fechada (commit `f7d250c`), medida na mesma sessão, em rodízio

## Hipótese

**05.** A rota busca a página com `SELECT *`, que traz `observacoes`, e a resposta só usa 4 colunas. Trazer só `id`, `cliente_id`, `status` e `criado_em` deve reduzir um pouco o trabalho do banco. O ganho esperado é pequeno: a página tem só 20 linhas.

**05.1.** A carga sorteia a página entre 1 e 1000, então o `OFFSET` chega a 19.980. O PostgreSQL percorre o índice da 01 em `(status, criado_em DESC, id DESC)` e, para cada linha pulada, vai à tabela buscar a linha inteira. Se o índice também guardar `cliente_id` (`INCLUDE`), a consulta da 05 pode ser respondida só pelo índice (*Index Only Scan*), sem ir à tabela, e o banco gasta menos CPU nessa rota.

**05.1, VACUUM.** O *Index Only Scan* só evita a tabela nas páginas marcadas no mapa de visibilidade, e quem marca é o `VACUUM`, não o `ANALYZE`. Os arquivos de `banco/` rodavam só `ANALYZE`. Hipótese: trocar por `VACUUM (ANALYZE)` faz o índice funcionar desde a criação do banco. Pela documentação, o autovacuum faria isso sozinho pouco depois; o teste mostra quando a diferença aparece.

## Diagnóstico (antes)

Evidência: [`diagnostico/05-pedidos-por-status.txt`](../diagnostico/05-pedidos-por-status.txt), gerado por [`diagnostico/05-pedidos-por-status.sql`](../diagnostico/05-pedidos-por-status.sql). Uma execução de cada consulta com o banco ocioso e depois do autovacuum, status `pago` (300 mil pedidos, o maior). Servem como diagnóstico, não como resultado.

| Consulta (status `pago`) | Plano | Blocos lidos | Tempo |
|---|---|---|---|
| Contagem atual | Parallel Index Only Scan no índice da 01, 0 leituras da tabela | 1.484 | 9,7 ms |
| Página 1, `SELECT *` | Index Scan | 23 | 0,08 ms |
| Página 500, `SELECT *` | Index Scan | 10.052 | 6,2 ms |
| Página 1000, `SELECT *` | Index Scan | 20.101 | 5,2 ms |
| Página 1000, 4 colunas (05) | Index Scan | 20.101 | 3,3 ms |
| Página 1000, 4 colunas, índice com `INCLUDE (cliente_id)` (05.1) | Index Only Scan, 0 leituras da tabela | 102 | 1,4 ms |

- **A contagem já não vai à tabela.** Ela já usa *Index Only Scan* desde a 01, e a 05.1 não muda isso.
- **A página é que vai à tabela:** cerca de uma leitura de bloco por linha pulada.
- **O índice com `INCLUDE` tem o mesmo tamanho do índice da 01: 21 MB.** Por isso a 05.1 substitui o índice da 01 em vez de criar um segundo, e não custa disco. Uma explicação possível, que não verifiquei, é o alinhamento das entradas do B-tree, que já deixava espaço livre para os 4 bytes de `cliente_id`.

## Alterações

**05:** só a consulta da página em [`api/src/rotas.js`](../api/src/rotas.js), que passa de `SELECT *` para `SELECT id, cliente_id, status, criado_em`. A contagem não muda.

**05.1:** só o arquivo novo [`banco/05-indice-pedidos-status-include.sql`](../banco/05-indice-pedidos-status-include.sql). Ele apaga `pedidos_status_criado_em_idx`, da 01, e cria `pedidos_status_criado_em_inc_idx ON pedidos (status, criado_em DESC, id DESC) INCLUDE (cliente_id)`.
- Primeira versão (`855b116`): seguida de `ANALYZE pedidos`, como nos arquivos anteriores.
- Versão final (`6596279`): seguida de `VACUUM (ANALYZE) pedidos`.

**Equivalência:** além do contrato, que tem poucos casos dessa rota, pedi à API as páginas de 1 a 1251 dos 4 status: 5004 respostas, que cobrem todas as páginas da carga, a última página de `pendente` e uma página vazia. Comparei o status HTTP e o MD5 do corpo de cada uma com os da `main` ([`diagnostico/05-equivalencia.py`](../diagnostico/05-equivalencia.py), referência em [`05-equivalencia-main.txt`](../diagnostico/05-equivalencia-main.txt)). Na 05 e na 05.1: **5004 respostas, 0 diferentes**. A ordem não depende do plano, porque `ORDER BY criado_em DESC, id DESC` termina na chave primária.

**Contrato:** mantido antes de medir e em todas as execuções.

## Fundamentação

- **PostgreSQL 16, seção 11.9 (Index-Only Scans and Covering Indexes):**
  - um *index-only scan* exige que a consulta *"reference only columns stored in the index"*, o que a 05 garante;
  - o `INCLUDE` serve para isso: guarda colunas que são só *"payload"*, não parte da chave de busca;
  - e só compensa nas páginas da tabela marcadas no mapa de visibilidade: se o bit não estiver ligado, *"the heap entry must be visited to find out whether it's visible, so no performance advantage is gained over a standard index scan"*.
- **PostgreSQL 16, seção 11.9, contra o excesso:** *"non-key columns duplicate data from the index's table and bloat the size of the index"*. Aqui o índice não cresceu, e a coluna incluída é um `integer`.
- **Shao et al. (2020), p. 4, Tabela II:** AP-14, *Unnecessary column retrieval* (*"Retrieving more columns than needed"*), para a 05, e AP-19, *Missing indexes*, para a 05.1.

O que a documentação diz sobre VACUUM, com o teste de cada ponto, está em [05.1: só `ANALYZE` contra `VACUUM (ANALYZE)`](#051-só-analyze-contra-vacuum-analyze).

## Resultado

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. Rodízio com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh): cada versão tem o seu banco, criado do zero a partir dos arquivos de `banco/` do seu commit. Os bancos são ligados um por vez, com aquecimento de 60 s, em 3 rodadas com a ordem deslocada. 2026-11-11, 16h21 a 16h44. Contrato mantido, 0,00% de erros e `arquivos alterados sem commit: 0` nas 9 execuções.

Antes de cada medição, o rodízio registrou o mapa de visibilidade ([`diagnostico/rodizio-registro.txt`](../diagnostico/rodizio-registro.txt)). Em todas as 9, o autovacuum já tinha passado por `pedidos` e quase todas as páginas estavam marcadas (20.832 ou 20.834 de 20.834). Ou seja, a 05.1 com só `ANALYZE` foi medida com o mapa de visibilidade pronto.

Mediana de 3 execuções ([`diagnostico/05-resumo.txt`](../diagnostico/05-resumo.txt), gerado por [`diagnostico/analisar.py`](../diagnostico/analisar.py)):

| Métrica | Antes (`main`) | 05 (colunas) | 05.1 (+ índice com `INCLUDE`) |
|---|---|---|---|
| Requisições/s | 84,68 (84,68 / 84,69 / 84,33) | 85,12 (85,12 / 85,13 / 85,11) | **94,11** (93,92 / 94,12 / 94,11) |
| Média | 236,0 ms | 234,6 ms | 212,4 ms |
| Mediana | 108,7 ms | 108,2 ms | 91,0 ms |
| p95 | 666,6 ms | 683,3 ms | 570,1 ms |
| p99 | 969,0 ms | 978,3 ms | 914,2 ms |
| CPU média do banco | 99,6% | 99,5% | 99,2% |
| Memória média do banco | 183,0 MiB | 175,2 MiB | 177,2 MiB |
| CPU média da API | 2,8% | 2,7% | 3,2% |
| Memória média da API | 28,5 MiB | 28,6 MiB | 28,5 MiB |

| Variação | req/s | Média | Mediana | p95 | p99 |
|---|---|---|---|---|---|
| 05 contra antes | +0,5% | −0,6% | −0,4% | +2,5% | +1,0% |
| 05.1 contra 05 | +10,6% | −9,4% | −15,9% | −16,6% | −6,5% |
| 05.1 contra antes | +11,1% | −10,0% | −16,3% | −14,5% | −5,6% |

| Rota (mediana da rota nas 3) | Antes | 05 | 05.1 | 05.1 contra antes |
|---|---|---|---|---|
| `cliente` | 81,2 ms | 76,9 ms | 67,7 ms | −17% |
| `cliente-por-email` | 83,4 ms | 79,2 ms | 66,3 ms | −21% |
| `pedidos-do-cliente` | 187,4 ms | 174,6 ms | 125,7 ms | −33% |
| `pedidos-por-status` | 201,2 ms | 199,5 ms | 146,9 ms | −27% |
| `busca-produtos` | 90,2 ms | 87,3 ms | 74,2 ms | −18% |
| `vendas-por-dia` | 92,7 ms | 87,9 ms | 78,5 ms | −15% |
| `top-produtos` | 476,1 ms | 472,4 ms | 456,3 ms | −4% |

**Pastas de resultados:**
- antes: `resultados/20261111-162139-05-antes-desktop`, `20261111-163448-…`, `20261111-164003-…`;
- 05: `resultados/20261111-162417-05-pedidos-por-status-desktop`, `20261111-162932-…`, `20261111-164241-…`;
- 05.1: `resultados/20261111-162655-051-indice-include-desktop`, `20261111-163210-…`, `20261111-163726-…`.

**Custo:**
- **05:** nenhum.
- **05.1:** nenhum em disco, porque o índice novo substitui o da 01 com o mesmo tamanho (21 MB). Cada `INSERT` em `pedidos` continua atualizando um índice nessa posição, agora com 4 bytes a mais por entrada. A carga do desafio, só de leitura, não mede isso.

## 05.1: só `ANALYZE` contra `VACUUM (ANALYZE)`

### O que a documentação diz

| # | Afirmação | Fonte |
|---|---|---|
| D1 | `ANALYZE` só coleta estatísticas para o planejador: *"ANALYZE collects statistics about the contents of tables in the database, and stores the results in the pg_statistic system catalog"*. | PostgreSQL 16, ANALYZE |
| D2 | Atualizar o mapa de visibilidade é tarefa do `VACUUM`: entre os motivos para rodá-lo, *"To update the visibility map, which speeds up index-only scans"*. Na 25.1.4: *"Vacuum maintains a visibility map for each table"*. | PostgreSQL 16, 25.1.1 e 25.1.4 |
| D3 | Sem o bit do mapa de visibilidade, o *index-only scan* vai à tabela e não ganha nada: *"it will be a win only if a significant fraction of the table's heap pages have their all-visible map bits set"*. | PostgreSQL 16, 11.9 |
| D4 | O autovacuum também faz `VACUUM` numa tabela que recebeu muitas inserções: *"The table is also vacuumed if the number of tuples inserted since the last vacuum has exceeded the defined insert threshold"*, com limiar de `autovacuum_vacuum_insert_threshold` (padrão 1000) + `autovacuum_vacuum_insert_scale_factor` (padrão 0,2) × linhas da tabela. Para `pedidos`, 1000 + 0,2 × 500.000 = 101.000 inserções; a criação do banco insere 500.000. | PostgreSQL 16, 25.1.6 e 20.10 |
| D5 | O autovacuum examina cada banco a cada `autovacuum_naptime`, com padrão de 1 minuto. | PostgreSQL 16, 20.10 |
| D6 | `VACUUM ANALYZE` faz as duas coisas: *"performs a VACUUM and then an ANALYZE for each selected table"*. E *"VACUUM cannot be executed inside a transaction block"*. Os arquivos de `banco/` rodam fora de bloco de transação, então ele funciona ali. | PostgreSQL 16, VACUUM |

**Previsão a partir de D1 a D5:** com só `ANALYZE`, logo depois da criação do banco, o *index-only scan* da 05.1 vai à tabela em toda linha. Menos de um minuto depois, o autovacuum marca as páginas, e a diferença some. Com `VACUUM (ANALYZE)`, o índice funciona desde o início.

### Teste 1: o plano logo depois da criação e depois do autovacuum

[`diagnostico/051-vacuum.txt`](../diagnostico/051-vacuum.txt), gerado por [`diagnostico/051-vacuum.sh`](../diagnostico/051-vacuum.sh): banco criado do zero para cada variante, as consultas da rota (status `pago`, página 1000, e a contagem) com `EXPLAIN ANALYZE` em dois momentos. Uma execução de cada, com o banco ocioso.

| Variante e momento | Páginas marcadas em `pedidos` | Página 1000 | Contagem |
|---|---|---|---|
| Só `ANALYZE`, 2 s depois de o banco subir | 0 de 20.834 | Index Only Scan, **20.000 leituras da tabela** (*Heap Fetches*), 10,7 ms | **Parallel Seq Scan**, 23,4 ms |
| Só `ANALYZE`, 48 s depois (o autovacuum acabou de passar) | 20.834 de 20.834 | Index Only Scan, 0 leituras da tabela, 1,6 ms | Parallel Index Only Scan, 11,5 ms |
| `VACUUM (ANALYZE)`, 6 s depois de o banco subir | 20.834 de 20.834 | Index Only Scan, 0 leituras da tabela, 1,7 ms | Parallel Index Only Scan, 13,0 ms |
| `VACUUM (ANALYZE)`, 189 s depois | 20.834 de 20.834; o autovacuum não rodou (0 inserções desde o vacuum) | 0 leituras da tabela, 2,3 ms | Parallel Index Only Scan, 14,7 ms |

- **D1, D2 e D3 confirmados.** Com só `ANALYZE`, as estatísticas estão prontas (`last_analyze` preenchido), mas nenhuma página está marcada, e o *index-only scan* vai à tabela em cada uma das 20.000 linhas.
- **Um efeito que eu não tinha previsto:** sem as páginas marcadas, o planejador escolheu ler a tabela inteira (Seq Scan) para a contagem, em vez do índice. Ele usa a fração de páginas marcadas (`relallvisible`) na estimativa de custo. Isso eu não conferi na documentação; é o que o plano mostra.
- **D4 e D5 confirmados.** O autovacuum passou por `pedidos` 48 s depois de o banco subir, sem nenhum comando, e o plano ficou igual ao da variante com `VACUUM`.
- **Custo do `VACUUM (ANALYZE)`:** a criação do banco levou 26 s, contra 21 s com só `ANALYZE` (uma execução de cada).

### Teste 2: sob carga, com aquecimento (o protocolo das outras medições)

Rodízio com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh), 2026-11-11, 16h52 a 17h06. Antes de cada medição, o registro mostra todas as páginas de `pedidos` marcadas nas duas variantes: na de só `ANALYZE`, pelo autovacuum, durante o aquecimento de 60 s.

| Métrica | Só `ANALYZE` | `VACUUM (ANALYZE)` | Diferença |
|---|---|---|---|
| Requisições/s | 93,67 (93,35 / 94,11 / 93,67) | 93,90 (93,65 / 93,90 / 94,20) | +0,2% |
| Mediana | 91,6 ms | 91,9 ms | +0,4% |
| p95 | 573,2 ms | 569,7 ms | −0,6% |
| p99 | 912,6 ms | 903,4 ms | −1,0% |
| Memória média do banco | 178,8 MiB | 175,3 MiB | |

**Empate:** as execuções se sobrepõem. Com o aquecimento, o autovacuum já tinha feito o trabalho do `VACUUM`.

### Teste 3: sob carga, a frio (logo depois de criar o banco)

[`diagnostico/051-frio.sh`](../diagnostico/051-frio.sh): em cada vez, o banco é criado do zero e `scripts/medir.sh` começa logo em seguida, sem o aquecimento de 60 s do rodízio. Só o aquecimento de 15 s do próprio `medir.sh` fica fora da medição. 2026-11-11, 17h07 a 17h18, 3 rodadas alternando as variantes.

Pelo registro ([`diagnostico/rodizio-registro.txt`](../diagnostico/rodizio-registro.txt)):
- **Só `ANALYZE`:** a medição começou com 0 páginas marcadas, e o autovacuum passou por `pedidos` cerca de 45 a 47 s depois de o banco subir. Isso dá, pela hora do registro, cerca de 25 s depois do início da janela de 60 s.
- **`VACUUM (ANALYZE)`:** todas as páginas marcadas desde o início, e o autovacuum não rodou.

| Métrica | Só `ANALYZE`, a frio | `VACUUM (ANALYZE)`, a frio | Diferença |
|---|---|---|---|
| Requisições/s | 80,55 (80,55 / 80,81 / 76,08) | **92,62** (92,59 / 92,62 / 93,55) | +15,0% |
| Média | 248,1 ms | 215,7 ms | −13,1% |
| Mediana | 118,9 ms | 91,6 ms | −23,0% |
| p95 | 735,9 ms | 583,0 ms | −20,8% |
| p99 | 995,8 ms | 922,4 ms | −7,4% |
| `pedidos-por-status` (mediana da rota) | 291,4 ms | 143,4 ms | |
| `pedidos-do-cliente` (mediana da rota) | 243,1 ms | 127,9 ms | |
| Memória média do banco | 189,4 MiB | 185,0 MiB | |

- **A frio, a diferença aparece e não se sobrepõe:** 76,08 a 80,81 contra 92,59 a 93,55.
- **Ela vem quase toda da variante com só `ANALYZE`.** Contra a mesma variante com aquecimento, ela cai 14,0%. A de `VACUUM (ANALYZE)` cai só 1,4%.
- **E vale só para os primeiros segundos.** Mesmo com o autovacuum passando no meio da janela, a perda média na janela inteira foi de 13%.
- **`pedidos-do-cliente` também piorou a frio**, e essa rota não usa o índice da 05.1. Hipótese, não verificada: sem o `VACUUM`, as primeiras leituras de cada linha recém-inserida ainda precisam conferir e gravar o estado da transação que a inseriu. Também pode ser só a fila da conexão única, atrasada pela `pedidos-por-status` mais lenta. Não tenho fonte aberta para a primeira explicação.

### Conclusão sobre o VACUUM na 05.1

- **Confirmado na documentação e nos testes:** `ANALYZE` não prepara a tabela para o *index-only scan*; `VACUUM` prepara.
- **Sem o `VACUUM` no arquivo, o autovacuum faz o mesmo trabalho em menos de um minuto**, porque a criação do banco insere 500.000 pedidos, acima do limiar de 101.000 inserções.
- **No protocolo de medição deste desafio, com aquecimento, o `VACUUM (ANALYZE)` não muda nada:** 93,67 contra 93,90 req/s. Os números da 05.1 da seção anterior, medidos com só `ANALYZE`, valem para a versão final.
- **Logo depois de criar o banco, ele vale +15% em req/s e −21% no p95**, até o autovacuum passar.
- **Custo:** cerca de 5 s a mais na criação do banco (uma execução de cada).
- **Decisão:** fechar a 05.1 com `VACUUM (ANALYZE) pedidos`. O ganho só aparece no primeiro minuto, mas o comportamento passa a não depender de quando o autovacuum roda, e o custo é pequeno e só na criação.

## Discussão

- **A hipótese da 05 se confirmou como esperado: ganho desprezível.**
  - O resultado foi +0,5% em req/s. As execuções não se sobrepõem, mas a diferença é menor que 1%.
  - No diagnóstico, trocar `SELECT *` pelas 4 colunas reduziu o tempo da página 1000 de 5,2 para 3,3 ms, mas não os blocos lidos: a linha inteira continua sendo lida na tabela.
  - A 05 vale como pré-requisito da 05.1: sem ela, o *index-only scan* é impossível, porque `SELECT *` pede `observacoes`.
- **A 05.1 deu +11% em req/s e −16% na mediana,** com as execuções sem sobreposição (85,11 a 85,13 contra 93,92 a 94,12).
- **O ganho se espalhou por todas as rotas,** como na 04. `pedidos-por-status` caiu 27%, mas `pedidos-do-cliente` caiu ainda mais, 33%, e `cliente-por-email` caiu 21%.
  - **Hipótese, a mesma da 04 e não verificada:** com `DB_POOL_MAX=1`, toda consulta passa pela mesma conexão. Cada milissegundo que `pedidos-por-status` deixa de ocupar o banco sai da fila de todas as outras rotas.
- **O p99 mudou pouco (−6%).** A cauda é de `top-produtos` (cerca de 460 ms), que esta mudança não toca.
- **A contagem é o que sobrou desta rota.** No diagnóstico, ela leva cerca de 10 ms para `pago`, contra 1,4 ms da página 1000 com o índice novo. É a alternativa "agressiva" da tabela abaixo.

## Alternativas consideradas e não testadas

| Alternativa | Por que não agora |
|---|---|
| Paginação por cursor (*keyset*: `WHERE (criado_em, id) < (...)`) | Elimina o `OFFSET`, mas a rota recebe `pagina`, e não um cursor. Mudaria o contrato. |
| Tabela com o total de pedidos por status, mantida por *trigger* | A contagem (cerca de 10 ms para `pago`, com 3 processos em paralelo) passaria a ler uma linha. Exige um *trigger* em toda escrita em `pedidos`. É a candidata seguinte para esta rota. |
| Manter os dois índices (o da 01 e o com `INCLUDE`) | O índice da 01 só era usado por esta rota, e o novo atende a contagem e a página. Seriam 21 MB a mais sem uso. |
| `VACUUM` em todas as tabelas nos arquivos de `banco/` | Só `pedidos` tem uma consulta que depende do mapa de visibilidade e que esta mudança alterou. Não testado. |

## O que refutaria esta conclusão

- **Se a tabela recebesse muitas escritas.** Com `UPDATE`s e `INSERT`s frequentes, as páginas alteradas saem do mapa de visibilidade até o próximo vacuum, e o *Index Only Scan* volta a ir à tabela. A carga do desafio só lê.
- **Se outra sessão não repetir a ordem antes ≈ 05 < 05.1.** As 9 execuções foram feitas numa sessão só.

## Próximo gargalo

O banco continua perto de 100% de CPU (99,2% com a 05.1). As rotas mais lentas são:
- `top-produtos` (456,3 ms), que agrega todos os itens a cada chamada;
- `pedidos-por-status` (146,9 ms), em que sobra a contagem;
- `pedidos-do-cliente` (125,7 ms).

Candidatas: o total por status mantido por *trigger* (versão agressiva desta rota) e a 06 (pré-calcular `top-produtos`).

## Referências

1. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.9. Index-Only Scans and Covering Indexes*. https://www.postgresql.org/docs/16/indexes-index-only-scans.html (acesso em 2026-11-11; [`referencias/documentacao/postgresql-16-indexes-index-only-scans.txt`](../referencias/documentacao/postgresql-16-indexes-index-only-scans.txt))
2. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 25.1. Routine Vacuuming*. https://www.postgresql.org/docs/16/routine-vacuuming.html (acesso em 2026-11-11; [`postgresql-16-routine-vacuuming.txt`](../referencias/documentacao/postgresql-16-routine-vacuuming.txt))
3. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 20.10. Automatic Vacuuming*. https://www.postgresql.org/docs/16/runtime-config-autovacuum.html (acesso em 2026-11-11; [`postgresql-16-runtime-config-autovacuum.txt`](../referencias/documentacao/postgresql-16-runtime-config-autovacuum.txt))
4. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, ANALYZE*. https://www.postgresql.org/docs/16/sql-analyze.html (acesso em 2026-11-11; [`postgresql-16-sql-analyze.txt`](../referencias/documentacao/postgresql-16-sql-analyze.txt))
5. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, VACUUM*. https://www.postgresql.org/docs/16/sql-vacuum.html (acesso em 2026-11-11; [`postgresql-16-sql-vacuum.txt`](../referencias/documentacao/postgresql-16-sql-vacuum.txt))
6. Shao, S. et al. *Database-Access Performance Antipatterns in Database-Backed Web Applications*. ICSME 2020. DOI 10.1109/ICSME46990.2020.00016. https://par.nsf.gov/servlets/purl/10277614
