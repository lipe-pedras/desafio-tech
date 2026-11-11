#!/usr/bin/env python3
"""Resume as séries *-desktop da remedição no desktop. Mediana de 3 execuções por rótulo.
Uso, a partir da raiz do desafio: python3 diagnostico/remedicao-desktop/analisar.py > diagnostico/remedicao-desktop/resumo.txt"""
import glob, json, re, statistics as st
R = ['cliente', 'cliente-por-email', 'pedidos-do-cliente', 'pedidos-por-status', 'busca-produtos', 'vendas-por-dia', 'top-produtos']
def ler(d):
    m = json.load(open(d + '/resumo-k6.json'))['metrics']; g = m['http_req_duration']['values']
    rc = open(d + '/recursos.txt').read(); cx = open(d + '/contexto.txt').read()
    b = re.search(r'banco-1\s+\d+\s+([\d.]+)%\s+[\d.]+%\s+([\d.]+) MiB', rc).groups()
    a = re.search(r'api-1\s+\d+\s+([\d.]+)%\s+[\d.]+%\s+([\d.]+) MiB', rc).groups()
    return dict(rps=m['http_reqs']['values']['rate'], avg=g['avg'], med=g['med'], p95=g['p(95)'], p99=g['p(99)'], err=m['http_req_failed']['values']['rate'],
                cpu_b=float(b[0]), mem_b=float(b[1]), cpu_a=float(a[0]), mem_a=float(a[1]), commit=re.search(r'commit: (\w+)', cx).group(1), sujo=re.search(r'sem commit: (\d+)', cx).group(1),
                contrato='mantido' if 'Contrato mantido' in open(d + '/contrato.txt').read() else 'QUEBRADO', **{k: m[f'http_req_duration{{rota:{k}}}']['values']['med'] for k in R})
BLOCOS = {'Bloco A (bancos separados, linha de base x 01)': ['00-linha-de-base-desktop', '01-indices-desktop'],
          'Bloco B (banco único com índices, só a API muda)': ['01-indices-rodizio-desktop', '02-pool-conexoes-desktop', '021-pool-max-1-desktop', '021-pool-max-2-desktop',
              '021-pool-max-3-desktop', '021-pool-max-5-desktop', '021-pool-max-10-desktop', '021-pool-max-20-desktop', '03-n-mais-1-desktop', '031-pool-max-5-desktop', '031-pool-max-10-desktop'],
          'Rodízio 03: pool 1 x pool 2 (2026-11-11)': ['031-pool-max-1-desktop', '031-pool-max-2-desktop'],
          'Fechamento da 03 (2026-11-11)': ['03f-02-pool-2-desktop', '03f-02-pool-1-desktop', '03f-03-pool-1-desktop']}
for bloco, rotulos in BLOCOS.items():
    print(f'##### {bloco}\n')
    for l in rotulos:
        ds = sorted(glob.glob(f'resultados/*-{l}')); x = [ler(d) for d in ds]
        print(f'== {l} ({len(ds)} execuções) commit {x[0]["commit"]} sujo {[i["sujo"] for i in x]} erros {[i["err"] for i in x]} contrato {sorted(set(i["contrato"] for i in x))}')
        print('   pastas', ' '.join(d.split('/')[1] for d in ds))
        print('   req/s por execução', [round(i['rps'], 2) for i in x], ' p95 por execução', [round(i['p95'], 1) for i in x])
        print('   medianas: ' + ' '.join(f'{c}={st.median(i[c] for i in x):.2f}' for c in ('rps', 'avg', 'med', 'p95', 'p99', 'cpu_b', 'mem_b', 'cpu_a', 'mem_a')))
        print('   rotas (mediana da rota, ms): ' + ' '.join(f'{k}={st.median(i[k] for i in x):.1f}' for k in R) + '\n')

# Repetibilidade: amplitude das req/s entre as execuções de cada rótulo, (máx − mín) / mediana.
def amplitude(filtro):
    rotulos = sorted(set(re.sub(r'^\d{8}-\d{6}-', '', d.split('/')[1]) for d in glob.glob('resultados/*-*') if filtro(d)))
    linhas = []
    for l in rotulos:
        ds = sorted(glob.glob(f'resultados/[0-9]*-{l}'))
        r = [json.load(open(d + '/resumo-k6.json'))['metrics']['http_reqs']['values']['rate'] for d in ds]
        if len(r) >= 3:
            linhas.append((l, len(r), min(r), max(r), (max(r) - min(r)) / st.median(r) * 100))
    for l, n, a, b, p in linhas:
        print(f'   {l:36s} n={n} req/s {a:6.2f} a {b:6.2f}  amplitude {p:5.1f}%')
    print(f'   mediana das amplitudes: {st.median(x[4] for x in linhas):.1f}%  máxima: {max(x[4] for x in linhas):.1f}%\n')
print('##### Repetibilidade: amplitude das req/s entre execuções do mesmo rótulo\n')
print('Desktop (rótulos *-desktop):')
amplitude(lambda d: d.endswith('-desktop'))
print('Notebook (todos os outros rótulos com 3 ou mais execuções):')
amplitude(lambda d: not d.endswith('-desktop') and not d.endswith('.gitkeep'))
