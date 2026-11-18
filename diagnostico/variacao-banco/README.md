# Recriar o banco muda o resultado?

> **A etapa 1 é diagnóstico.** A etapa 2 usa o formato oficial (`scripts/medir.sh`, commit limpo, contrato verificado) e seus resultados estão em `resultados/`. Números em [`resumo.txt`](resumo.txt), gerado por `python3 diagnostico/analisar.py --serie variacao-banco` ([`analisar.py`](../analisar.py)).

**Motivo:** o mesmo código, com `DB_POOL_MAX=2`, deu 17,09 req/s numa série (2026-11-08) e 23,01 em outra (2026-11-07).

## Etapa 1: o mesmo código com 3 bancos recriados

**Hipótese.** Cada `docker compose down -v` gera um `ANALYZE` novo, com amostragem, e isso muda os planos e as req/s.

**Teste.** Código `1fd2ae4`, banco recriado 3 vezes, 3 medições por banco, em 2026-11-09. Em cada banco, gravei uma soma de controle de `pedidos` e o `EXPLAIN` de todas as consultas.

**Resultados.**

| Banco | req/s por execução | Mediana das 3 | Mediana do tempo | p95 |
|---|---|---|---|---|
| 1 | 22,00 / 25,53 / 25,23 | 25,23 | 197,6 ms | 3960,6 ms |
| 2 | 22,28 / 25,49 / 25,21 | 25,21 | 196,9 ms | 3890,4 ms |
| 3 | 22,21 / 24,73 / 25,26 | 24,73 | 195,7 ms | 3994,9 ms |

Os dados são idênticos nos 3 bancos (`dados-banco-N.txt`) e os tipos de nó dos planos também (`explain-banco-N.txt`).

**Conclusão.** A hipótese foi **refutada**: recriar o banco não explica a diferença. A única diferença sistemática é a primeira execução depois de recriar, cerca de 12% mais lenta (cache frio). A causa das séries lentas de sessões anteriores (cerca de 17 req/s) continua desconhecida; nesta sessão, nenhuma execução chegou perto disso.

## Etapa 2: as versões em rodízio, num banco só

**Hipótese.** Comparando as versões na mesma sessão e no mesmo banco, a diferença entre sessões sai da conta.

**Teste.** Um único banco, sem recriar, aquecido por 60 s. As versões `466d0f5` (01), `63b4693` (02, pool 10), `1fd2ae4` (02, pool 2) e `958aad1` (03) foram medidas em rodízio, 3 rodadas, com a ordem deslocada a cada rodada. Trocou-se só o container da API. Contrato mantido e 0,00% de erros nas 12 execuções.

**Resultados** (mediana de 3 execuções):

| Versão | req/s | Média | Mediana | p95 | p99 | Memória do banco |
|---|---|---|---|---|---|---|
| 01 | 8,29 | 2327,6 ms | 742,0 ms | 8769,5 ms | 12145,1 ms | 227,8 MiB |
| 02, pool 10 | 13,41 | 1454,9 ms | 404,4 ms | 6054,5 ms | 12012,5 ms | 274,8 MiB |
| 02, pool 2 | 24,86 | 798,1 ms | 190,5 ms | 4015,1 ms | 5984,7 ms | 184,7 MiB |
| 03 | 23,23 | 860,0 ms | 617,1 ms | 2686,5 ms | 3538,3 ms | 189,0 MiB |

**Conclusão.**
- **O pool se confirma.** De 01 para 02 com pool 2: cerca de 3,0× em req/s, p95 −54%, p99 −51%.
- **O pool menor se confirma.** De 10 para 2: cerca de 1,85× em req/s, p95 −34%, p99 −50%.
- **A 03 não aumentou as req/s.** Elas caíram cerca de 7% (22,79 a 23,76 contra 24,73 a 24,97, sem sobreposição), e a média subiu 8%. O ganho é só na cauda: p95 −33% e p99 −41%. A mediana ficou cerca de 3,2× pior.
- **O 1,33× registrado na primeira medição da 03 não se sustenta.** Aquela série "antes" foi uma das sessões lentas.
