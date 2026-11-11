# Remedição de todas as versões num desktop

> **A partir de 2026-11-10, os números oficiais do trabalho são os desta remedição.** As medições do notebook continuam no repositório e nas fichas, como histórico, mas não devem ser comparadas com as do desktop: a máquina é outra, e os valores absolutos mudam muito (a linha de base foi de cerca de 2 para 7,47 req/s).

Arquivos desta pasta:
- [`ambiente.txt`](ambiente.txt): CPU, memória, perfil de energia e versões do desktop;
- [`rodar.sh`](rodar.sh): remedição completa (blocos A e B), 2026-11-10;
- [`rodar-031-pool-1.sh`](rodar-031-pool-1.sh): 03 com pool 1 contra pool 2, 2026-11-11;
- [`rodar-03-fechamento.sh`](rodar-03-fechamento.sh): fechamento da 03 (02 com pool 2, 02 com pool 1 e 03 com pool 1), 2026-11-11;
- [`registro.txt`](registro.txt): log de cada passo, com perfil de energia, carga da máquina e a fixação dos núcleos;
- [`analisar.py`](analisar.py) e [`resumo.txt`](resumo.txt): medianas por rótulo e a repetibilidade de cada série.

## Por que remedir

As medições do notebook variaram demais, entre execuções e entre sessões, para sustentar algumas conclusões.

**Entre execuções da mesma série**, a amplitude das req/s, (máx − mín) ÷ mediana, teve mediana de **12,6%** e chegou a **29,1%** (`031-pool-max-5`). Calculado por `analisar.py` a partir de `resultados/`. A linha `01-indices` (49,7%) junta duas sessões com o mesmo rótulo e não conta como série.

**Entre sessões**, o mesmo código deu números bem diferentes:

| Mesmo código | Sessão | req/s | Onde |
|---|---|---|---|
| Linha de base | 2026-11-05, bateria / 2026-11-06, tomada | 1,81 / 2,52 | [ficha 01](../../experimentos/01-indices.md#repetibilidade-remedição-com-banco-recriado-e-na-tomada) |
| 02 com `max=10` | 2026-11-06 / 2026-11-07 | 12,81 / 14,48 | [ficha 02.1](../../experimentos/02.1-tamanho-do-pool.md) |
| 02 com `max=2` (`1fd2ae4`) | 2026-11-07 / 2026-11-08 / 2026-11-09 | 23,01 / 17,09 / 24,86 | [variação do banco](../variacao-banco/README.md) |

A série lenta de 2026-11-08 foi o "antes" da 03 e produziu um ganho de 1,33× em req/s que a medição em rodízio depois não confirmou.

**O que foi descartado e o que ficou sem explicação:**
- **Recriar o banco não explica a variação.** Foi testado: 3 bancos recriados deram 24,73 a 25,23 req/s ([variação do banco](../variacao-banco/README.md)).
- **A fonte de energia explica parte.** Bateria contra tomada mudou os valores absolutos em cerca de 40 a 50% ([ficha 01](../../experimentos/01-indices.md#repetibilidade-remedição-com-banco-recriado-e-na-tomada)).
- **Hipótese para o resto, não testada:** o gerenciamento de energia e de temperatura do notebook (Ryzen 5 6600H, perfil `balanced`, governor `powersave`; ver [`../ambiente.txt`](../ambiente.txt)) muda a frequência da CPU de uma execução para outra. Como o banco está limitado a 1 CPU e passa a carga toda a cerca de 100%, qualquer mudança de frequência vira mudança direta de req/s.

## Como foi remedido

**Máquina:** desktop com Intel Core i7-14700K, 20 núcleos (8 de desempenho, "P", com 2 threads cada, e 12 de eficiência, "E"), 31 GiB de memória, perfil de energia `performance`, ligado na tomada ([`ambiente.txt`](ambiente.txt)).

**Fixação nos núcleos P.** Os núcleos P e E têm desempenho diferente. Com o limite de 1 CPU, o banco poderia rodar ora num tipo, ora no outro, e isso traria de volta a variação. Por isso, antes de cada medição, os containers `banco` e `api` foram fixados nos núcleos P (CPUs 0 a 15) com `docker update --cpuset-cpus`.
- **Não muda o custo.** Os limites do `docker-compose.yml` continuam 1 CPU e 512 MB para o banco e 0,5 CPU e 256 MB para a API. Isso aparece no `contexto.txt` de cada pasta e no `registro.txt` (`nanocpus`).
- **Fica fora do repositório.** É uma configuração da máquina de medição, como fechar outros programas, e não da aplicação. O k6 roda sem fixação.

**Rodízio, no formato oficial.** Toda medição usa `scripts/medir.sh` com os parâmetros padrão (20 VUs, 60 s, semente 42), no commit limpo de cada versão (`arquivos alterados sem commit: 0`). O contrato é verificado antes de cada medição e mantido em todas. Cada versão roda numa `git worktree` própria.
- **Bloco A (linha de base contra 01):** cada uma com o seu banco, porque a 01 depende de `banco/03-indices.sql`. Os dois bancos foram criados uma vez e ligados um por vez, com aquecimento de 60 s, em 3 rodadas com a ordem alternada. Rótulos `00-linha-de-base-desktop` e `01-indices-desktop`.
- **Bloco B (versões que só mudam a API):** um banco único com os índices, aquecido por 60 s. As 11 versões foram medidas em 3 rodadas, com a ordem deslocada a cada rodada, trocando só o container da API. Rótulos `*-desktop`.
- **Séries de 2026-11-11:** no mesmo formato do bloco B, com banco novo.

## Repetibilidade no desktop

A amplitude das req/s entre execuções da mesma série teve mediana de **1,3%** e máximo de **5,8%** (`021-pool-max-20-desktop`), contra 12,6% e 29,1% no notebook ([`resumo.txt`](resumo.txt)).

O mesmo código também se repete entre séries diferentes:

| Mesmo código | Séries | req/s |
|---|---|---|
| 01 (`466d0f5`) | bloco A / bloco B | 26,70 / 25,69 |
| 02 com `max=10` (`63b4693` e `acb84a7`) | dois commits, mesma configuração | 38,96 / 38,38 |
| 03 com `max=2` (`958aad1`) | 2026-11-10 / 2026-11-11 | 59,41 / 58,32 |

Mesmo assim, as comparações das fichas usam só versões medidas **na mesma sessão e no mesmo banco**.

## Limites

- **Uma máquina só.** A ordem das versões se repetiu no notebook e no desktop, mas os valores absolutos dependem do hardware. Num servidor com outra CPU, os números seriam outros.
- **A fixação nos núcleos P favorece a estabilidade, não a representatividade.** Num servidor real, o banco não estaria fixado.
- **O pool 20 teve erros** em `top-produtos` (1, 4 e 2 falhas nas 3 execuções; 0,04% a 0,17% do total). O contrato foi mantido. A causa não foi investigada.
