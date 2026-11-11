#!/usr/bin/env python3
"""Resume as séries var-banco-N (etapa 1) e ab-* (etapa 2). Mediana de 3 execuções."""
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
for l in ['var-banco-1', 'var-banco-2', 'var-banco-3', 'ab-01-indices', 'ab-02-pool-10', 'ab-02-pool-2', 'ab-03-n-mais-1']:
    ds = sorted(glob.glob(f'resultados/*-{l}')); x = [ler(d) for d in ds]
    print(f'== {l} ({len(ds)} execuções) commit {x[0]["commit"]} sujo {[i["sujo"] for i in x]} erros {[i["err"] for i in x]} contrato {set(i["contrato"] for i in x)}')
    print('   pastas', ' '.join(d.split('/')[1][:15] for d in ds))
    print('   req/s por execução', [round(i['rps'], 2) for i in x])
    print('   ' + ' '.join(f'{c}={st.median(i[c] for i in x):.1f}' for c in ('rps', 'avg', 'med', 'p95', 'p99', 'cpu_b', 'mem_b', 'cpu_a', 'mem_a')).replace('rps=', 'rps='), f'rps2={st.median(i["rps"] for i in x):.2f}')
    print('   rotas', ' '.join(f'{k}={st.median(i[k] for i in x):.1f}' for k in R))
