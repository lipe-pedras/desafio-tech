#!/usr/bin/env python3
"""DIAGNÓSTICO da mediana da 03: resume diagnostico/03-mediana/saida/. Não é resultado oficial.
Uso, a partir da raiz do desafio: python3 diagnostico/03-mediana/analisar.py > diagnostico/03-mediana/resumo.txt"""
import json
import statistics as st

D = 'diagnostico/03-mediana/saida/'
R = ['cliente', 'cliente-por-email', 'pedidos-do-cliente', 'pedidos-por-status', 'busca-produtos', 'vendas-por-dia', 'top-produtos']
med = st.median


def k6(p):
    return json.load(open(p + '/resumo-k6.json'))['metrics']


print('DIAGNÓSTICO, não é resultado oficial (não usa scripts/medir.sh). Mediana de 3 rodadas.\n')
print('TESTE 1: código antigo (1fd2ae4), carga sem pedidos-do-cliente')
print('usuarios  req/s  media_ms  mediana_ms  p95_ms  | mediana por rota: cliente  email  status  busca  vendas  top | erros')
for v in (2, 5, 8, 14, 20):
    ms = [k6(f'{D}teste1/vus-{v}/r{r}') for r in (1, 2, 3)]
    g = lambda c: med(m['http_req_duration']['values'][c] for m in ms)
    rota = lambda k: med(m[f'http_req_duration{{rota:{k}}}']['values']['med'] for m in ms)
    print(f"{v:>8} {med(m['http_reqs']['values']['rate'] for m in ms):6.2f} {g('avg'):9.1f} {g('med'):11.1f} {g('p(95)'):7.1f}  |",
          ' '.join(f'{rota(k):8.1f}' for k in R if k != 'pedidos-do-cliente'),
          '|', max(m['http_req_failed']['values']['rate'] for m in ms))

print('\nTESTE 2: carga oficial, API instrumentada, versões alternadas sem recriar o banco')
for ver in ('antes', 'depois'):
    ds = [json.load(open(f'{D}teste2/{ver}/r{r}/diag.json')) for r in (1, 2, 3)]
    ms = [k6(f'{D}teste2/{ver}/r{r}') for r in (1, 2, 3)]
    print(f'\n== {ver}')
    print('req/s por rodada', [round(m['http_reqs']['values']['rate'], 2) for m in ms])
    for c, n in (('avg', 'media'), ('med', 'mediana'), ('p(95)', 'p95'), ('p(99)', 'p99')):
        v = [round(m['http_req_duration']['values'][c], 1) for m in ms]
        print(f'{n} por rodada', v, 'mediana', med(v))
    print('erros', [m['http_req_failed']['values']['rate'] for m in ms])
    print('requisicoes esperando o pool (media por segundo), por rodada', [round(d['fila_pool_media'], 2) for d in ds])
    cons, exe, serv = [], [], []
    for d in ds:
        c = sum(r['consultas'] for r in d['rotas'].values())
        e = sum(r['execucao_por_consulta_ms'] * r['consultas'] for r in d['rotas'].values())
        cons.append(c); exe.append(e); serv.append(e / c)
    print('consultas no total, por rodada', cons)
    print('tempo de execucao somado (ms), por rodada', [round(e) for e in exe])
    print('execucao media por consulta, todas as rotas (ms), por rodada', [round(s, 1) for s in serv])
    prev = [d['fila_pool_media'] * s / 2 for d, s in zip(ds, serv)]
    print('espera prevista = fila x execucao media / 2 conexoes (ms), por rodada', [round(p, 1) for p in prev])
    print('rota                  em_andamento  espera/consulta  execucao/consulta  mediana_k6  consultas/req')
    for k in R:
        f = lambda c: med(d['rotas'][k][c] for d in ds)
        print(f"{k:20} {f('em_andamento_medio'):12.2f} {f('espera_pool_por_consulta_ms'):16.1f} {f('execucao_por_consulta_ms'):18.2f}"
              f" {med(m[f'http_req_duration{{rota:{k}}}']['values']['med'] for m in ms):11.1f}"
              f" {med(d['rotas'][k]['consultas'] / d['rotas'][k]['requisicoes'] for d in ds):14.1f}")
