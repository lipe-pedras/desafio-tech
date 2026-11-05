# Experimentos

Uma linha por ideia aplicada. Os detalhes de cada uma (hipótese, alterações, fundamentação, resultado e discussão) ficam na ficha da pasta [`experimentos/`](experimentos/).

**Como os números foram obtidos:**
- Todos vêm de `scripts/medir.sh`, com os parâmetros padrão: 20 usuários virtuais, 60 s, semente 42.
- Cada valor é a **mediana de 3 execuções**.
- O "antes" de cada mudança está indicado na própria linha.

| # | Mudança | Fonte da ideia | Status | Antes | p95 antes → depois | req/s antes → depois | CPU / memória do banco (média) | Pastas de resultados | Conclusão |
|---|---|---|---|---|---|---|---|---|---|
| 01 | [Índices nas chaves estrangeiras e nos filtros das rotas](experimentos/01-indices.md) | Yang et al. 2018; Yan et al. 2017; Kossmann et al. 2020 | Aplicada e medida | linha de base | 35082,7 → 12222,6 ms | 1,81 → 5,81 | 99,0% → 98,7% / 227,7 → 227,6 MiB | antes: [1](resultados/20261105-104137-00-linha-de-base/resumo.txt), [2](resultados/20261105-104334-00-linha-de-base/resumo.txt), [3](resultados/20261105-104532-00-linha-de-base/resumo.txt) · depois: [1](resultados/20261105-113726-01-indices/resumo.txt), [2](resultados/20261105-113906-01-indices/resumo.txt), [3](resultados/20261105-114041-01-indices/resumo.txt) | Ganho grande (p95 −65%, cerca de 3,2× em req/s), com custo de 66 MB de disco. O banco continua saturado; o próximo gargalo é o N+1 e os relatórios. |
