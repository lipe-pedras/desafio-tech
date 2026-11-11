#!/usr/bin/env python3
"""Compara a lógica antiga e a nova de /relatorios/vendas-por-dia direto no banco.
Antiga: as linhas de itens do período (filtro criado_em::date BETWEEN) agregadas aqui, como a API fazia.
Nova: a consulta agregada da mudança 04. Períodos: os 725 de 7 dias que a carga sorteia
(carga/teste-carga.js: inicio de 2024-01-01 + 0..724 dias) e algumas bordas de 1 e 31 dias.
Uso, a partir da raiz do desafio, com a aplicação no ar: python3 diagnostico/04-equivalencia.py"""
import datetime as dt, subprocess
def psql(sql):
    r = subprocess.run(['docker', 'compose', 'exec', '-T', 'banco', 'psql', '-U', 'loja', '-d', 'loja', '-AtF', ',', '-c', sql],
                       capture_output=True, text=True, check=True)
    return [l.split(',') for l in r.stdout.splitlines() if l]
base = dt.date(2024, 1, 1)
periodos = [(base + dt.timedelta(d), base + dt.timedelta(d + 6)) for d in range(725)]
periodos += [(dt.date(2023, 12, 31), dt.date(2024, 1, 1)), (dt.date(2024, 2, 29), dt.date(2024, 2, 29)),
             (dt.date(2025, 12, 1), dt.date(2025, 12, 31)), (dt.date(2025, 12, 31), dt.date(2026, 1, 30)),
             (dt.date(2024, 12, 15), dt.date(2025, 1, 14))]
ini, fim = min(p[0] for p in periodos), max(p[1] for p in periodos)
# Antiga: todas as linhas uma vez só; agregadas por dia como a API (Set de pedidos, soma de itens e receita).
dias = {}
for pid, dia, q, preco in psql(f"""SELECT p.id, p.criado_em::date, i.quantidade, i.preco_unitario_centavos
    FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
   WHERE p.criado_em::date BETWEEN '{ini}' AND '{fim}' AND p.status <> 'cancelado'"""):
    a = dias.setdefault(dia, [set(), 0, 0]); a[0].add(pid); a[1] += int(q); a[2] += int(q) * int(preco)
diferentes = 0
for a, b in periodos:
    antiga = [[d, str(len(v[0])), str(v[1]), str(v[2])] for d, v in sorted(dias.items()) if str(a) <= d <= str(b)]
    nova = psql(f"""SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade),
                           sum(i.quantidade::bigint * i.preco_unitario_centavos)
                      FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
                     WHERE p.criado_em >= '{a}'::date AND p.criado_em < '{b}'::date + 1 AND p.status <> 'cancelado'
                     GROUP BY p.criado_em::date ORDER BY p.criado_em::date""")
    if antiga != nova:
        diferentes += 1; print('DIFERENTE', a, b)
print(f'{len(periodos)} períodos comparados, {diferentes} diferentes')
