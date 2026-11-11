#!/usr/bin/env python3
"""Compara as respostas de /pedidos?status=&pagina= entre duas versões da API, pela própria API.
Pede os 4 status e as páginas de 1 a 1251, que cobrem as páginas da carga (carga/teste-carga.js: 1 a 1000),
a última página de 'pendente' (25.000 pedidos, página 1250) e uma página vazia depois dela.
Guarda o status HTTP e o MD5 do corpo de cada resposta.
Uso, a partir da raiz do desafio, com a aplicação no ar:
  python3 diagnostico/05-equivalencia.py gravar <arquivo>       # com a versão de referência
  python3 diagnostico/05-equivalencia.py comparar <arquivo>     # com a versão nova"""
import hashlib, sys, urllib.error, urllib.request

def pedir(status, pagina):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:3000/pedidos?status={status}&pagina={pagina}') as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

linhas = []
for status in ['pago', 'entregue', 'cancelado', 'pendente']:
    for pagina in range(1, 1252):
        codigo, corpo = pedir(status, pagina)
        linhas.append(f'{status} {pagina} {codigo} {hashlib.md5(corpo).hexdigest()}')

modo, arquivo = sys.argv[1], sys.argv[2]
if modo == 'gravar':
    open(arquivo, 'w').write('\n'.join(linhas) + '\n')
    print(f'{len(linhas)} respostas gravadas em {arquivo}')
else:
    referencia = open(arquivo).read().splitlines()
    diferentes = [(a, b) for a, b in zip(referencia, linhas) if a != b]
    for a, b in diferentes:
        print('DIFERENTE', a, '|', b)
    print(f'{len(linhas)} respostas comparadas com {arquivo} ({len(referencia)} gravadas), {len(diferentes)} diferentes')
