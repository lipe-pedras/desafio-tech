# 07 · Índice de trigramas para `busca-produtos`

- **Status:** aplicada e medida na branch `07-busca-trigramas`; o merge não foi feito
- **Branch / commits:** `07-busca-trigramas`, a partir da `main` com a 06 fechada (`92207db`) / `72bd33f` (banco)
- **Comparada com:** a `main` (commit `92207db`), medida na mesma sessão, em rodízio

## Hipótese

Depois da 06, o tempo de execução no banco ficou concentrado em duas rotas ([`diagnostico/07-custo-por-rota.txt`](../diagnostico/07-custo-por-rota.txt), gerado por [`07-custo-por-rota.sql`](../diagnostico/07-custo-por-rota.sql); mesmo método do diagnóstico da 06):

| Rota | Peso | ms por chamada | % do tempo do banco |
|---|---|---|---|
| `busca-produtos` | 15 | 7,48 | **58,2%** |
| `vendas-por-dia` | 8 | 8,85 | 36,7% |
| `pedidos-por-status` | 15 | 0,50 | 3,9% |
| as outras quatro | 62 | ≤ 0,09 | 1,2% juntas |

`busca-produtos` filtra com `nome ILIKE '%' || $1 || '%'`. Com o `%` no começo, nenhum índice B-tree serve, e o banco lê os 20 mil produtos a cada chamada.

A documentação do PostgreSQL diz que os índices de trigramas da extensão `pg_trgm` *"support trigram-based index searches for LIKE, ILIKE"*, e que, *"Unlike B-tree based searches, the search string need not be left-anchored"*. Um índice GIN de trigramas em `produtos (nome)` deve trocar a leitura da tabela inteira pela leitura dos produtos que contêm os trigramas do termo. Pela fila da conexão única, isso deve acelerar também as outras rotas.

## Alterações

**Banco:** só o arquivo novo [`banco/07-indice-produtos-nome-trgm.sql`](../banco/07-indice-produtos-nome-trgm.sql):

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX produtos_nome_trgm_idx ON produtos USING gin (nome gin_trgm_ops);
VACUUM (ANALYZE) produtos;
```

- **Tamanho do índice:** 1144 kB, para uma tabela de 1520 kB.
- **Por que o resultado não muda:** o índice só aponta os candidatos, e o `ILIKE` continua conferido em cada linha encontrada (`Bitmap Heap Scan` com recheck).
- **O que não muda:** a API e a consulta.

## Diagnóstico e equivalência

[`diagnostico/07-busca.txt`](../diagnostico/07-busca.txt), gerado por [`07-busca.sql`](../diagnostico/07-busca.sql):
- **Como medi:** cada termo rodou com e sem o índice; sem o índice, desliguei o `enable_bitmapscan` para o plano voltar ao Seq Scan.
- **Tempo:** média de 50 execuções de cada forma, com o banco ocioso.
- **Resultado:** as 20 linhas, na ordem, comparadas por MD5.

| Termos | Sem índice | Com índice | Resultado |
|---|---|---|---|
| os 12 termos da carga | 5,65 a 6,33 ms | 0,56 a 1,03 ms (6,0 a 11,4× mais rápido) | igual nos 12 |
| `ado` (3 letras) | 5,94 ms | 0,97 ms | igual |
| `CADEIRA` (maiúsculas) | 5,86 ms | 0,63 ms | igual |
| `xyzw` (sem resultado) | 5,22 ms | 0,03 ms | igual |
| `o 1`, `50%`, `a_b` | 5,41 a 6,29 ms | 4,76 a 5,71 ms | igual |

- **Termos com poucos trigramas aproveitáveis quase não ganham** (`o 1`, `50%`, `a_b`). A documentação avisa: *"a pattern with no extractable trigrams will degenerate to a full-index scan"*. Mesmo assim, não ficam mais lentos que antes. A carga não usa termos assim.
- **A ordenação continua:** os termos da carga trazem de 1000 a 2000 produtos cada (1111 em `modelo 12`) ([`07-busca-e-vendas.txt`](../diagnostico/07-busca-e-vendas.txt)), que ainda são ordenados por `nome, id` antes do `LIMIT 20` (top-N heapsort).

Contrato mantido antes de medir e em todas as execuções.

## Fundamentação

- **PostgreSQL 16, F.35 (`pg_trgm`):** os índices GIN e GiST de trigramas atendem `LIKE` e `ILIKE` sem âncora no começo, e um padrão sem trigramas vira uma leitura do índice inteiro ([`referencias/documentacao/postgresql-16-pgtrgm.txt`](../referencias/documentacao/postgresql-16-pgtrgm.txt)).
- **GIN em vez de GiST:** a documentação remete a comparação a outro capítulo, que não abri. Escolhi GIN porque `produtos` não recebe escritas na carga. Não testei GiST.

## Resultado

Desktop (i7-14700K), perfil `performance`, banco e API fixados nos núcleos P, sem mudar os limites. Rodízio com [`diagnostico/rodizio.sh`](../diagnostico/rodizio.sh): cada versão tem o seu banco, criado do zero, com aquecimento de 60 s, 3 rodadas com a ordem deslocada. 2026-11-12, 20h20 a 20h37 (horário local). Contrato mantido, 0,00% de erros e `arquivos alterados sem commit: 0` nas 6 execuções.

Mediana de 3 execuções ([`diagnostico/07-resumo.txt`](../diagnostico/07-resumo.txt), gerado por [`diagnostico/analisar.py`](../diagnostico/analisar.py)):

| Métrica | Antes (`main`) | 07 | Variação |
|---|---|---|---|
| Requisições/s | 528,16 (528,16 / 529,01 / 526,25) | **902,65** (900,67 / 902,65 / 902,71) | +70,9% |
| Média | 37,8 ms | 22,1 ms | −41,5% |
| Mediana | 35,2 ms | 20,5 ms | −41,7% |
| p95 | 71,9 ms | 47,0 ms | −34,5% |
| p99 | 88,5 ms | 59,7 ms | −32,6% |
| CPU média do banco | 94,8% | 91,5% | |
| Memória média do banco | 151,1 MiB | 151,6 MiB | |
| CPU média da API | 12,1% | 19,5% | |
| Memória média da API | 30,6 MiB | 30,8 MiB | |

| Rota (mediana da rota nas 3) | Antes | 07 | Variação |
|---|---|---|---|
| `cliente` | 26,1 ms | 14,6 ms | −44% |
| `cliente-por-email` | 26,4 ms | 14,7 ms | −44% |
| `pedidos-do-cliente` | 51,9 ms | 29,4 ms | −43% |
| `pedidos-por-status` | 51,8 ms | 29,8 ms | −42% |
| `busca-produtos` | 32,3 ms | 15,5 ms | −52% |
| `vendas-por-dia` | 35,6 ms | 23,9 ms | −33% |
| `top-produtos` | 26,3 ms | 14,6 ms | −44% |

**Contadores de cota de CPU do banco** durante cada `medir.sh` (em [`07-resumo.txt`](../diagnostico/07-resumo.txt)): 2,2% a 2,6% dos períodos pausados nas duas versões, com 0,24 a 0,36 s de pausa. A CPU usada pelo banco foi 69,0 s na 07, contra 71,1 s na `main`, com 71% mais requisições.

**Pastas de resultados:**
- antes: `resultados/20261112-202231-07-antes-desktop`, `20261112-203018-…`, `20261112-203254-…`;
- 07: `resultados/20261112-202507-07-busca-trigramas-desktop`, `20261112-202743-…`, `20261112-203530-…`.

## Discussão

- **A hipótese se confirmou: +70,9% em req/s, com mediana −42% e p95 −35%**, sem sobreposição (526,25 a 529,01 contra 900,67 a 902,71).
- **Todas as rotas caíram 33 a 52%,** e a mais rápida a cair foi a própria `busca-produtos`. É o mesmo padrão de fila das mudanças anteriores: o tempo de banco liberado pela busca acelera todo o resto.
- **O banco gasta menos CPU no total** (69,0 contra 71,1 s) para atender bem mais requisições. A cota quase não pausa nas duas versões, e o banco ficou em 91,5% de CPU.
- **O próximo limite pode estar fora do banco.** A CPU da API foi de 12,1% para 19,5% do host, o que é 39% do limite de 0,5 CPU. Com o banco abaixo de 100%, o gargalo pode estar migrando para a API ou para a conexão única. Não verifiquei; os contadores de cota da API mostrariam se ela já é pausada.
- **Custo:** 1,1 MB de disco e uma extensão do próprio PostgreSQL. Escritas em `produtos` também atualizam o índice; a carga não escreve ali, e não medi esse custo.

## O que refutaria esta conclusão

- **Se os termos reais de busca tivessem poucos trigramas** (2 letras com espaço, símbolos). Para eles, o índice não ajuda; o diagnóstico mostra isso.
- **Se outra sessão não repetir a diferença.** As 6 execuções foram feitas numa sessão só, com uma diferença muito acima da variação entre execuções.

## Referências

1. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, F.35. pg_trgm*. https://www.postgresql.org/docs/16/pgtrgm.html (acesso em 2026-11-12; [`referencias/documentacao/postgresql-16-pgtrgm.txt`](../referencias/documentacao/postgresql-16-pgtrgm.txt))
