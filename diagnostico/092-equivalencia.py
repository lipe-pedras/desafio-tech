#!/usr/bin/env python3
"""09.2: compara a resposta de /relatorios/vendas-por-dia (que lê vendas_por_dia) com a consulta anterior (09),
rodada no mesmo banco e convertida como a API convertia (Number() em pedidos, itens e receita).
Períodos: os 725 de 7 dias que a carga sorteia (carga/teste-carga.js: inicio de 2024-01-01 + 0..724 dias)
e bordas de 1 a 31 dias, inclusive fora dos dados (2023 e 2026). Com a aplicação no ar e o banco recém-criado:
  python3 diagnostico/092-equivalencia.py > diagnostico/092-equivalencia.txt"""
import datetime as dt, json, subprocess, urllib.request
def psql(sql):
    r = subprocess.run(['docker', 'compose', 'exec', '-T', 'banco', 'psql', '-U', 'loja', '-d', 'loja', '-AtF', ',', '-c', sql],
                       capture_output=True, text=True, check=True)
    return [l.split(',') for l in r.stdout.splitlines() if l]
base = dt.date(2024, 1, 1)
periodos = [(base + dt.timedelta(d), base + dt.timedelta(d + 6)) for d in range(725)]
periodos += [(dt.date(2023, 12, 31), dt.date(2024, 1, 1)), (dt.date(2024, 2, 29), dt.date(2024, 2, 29)),
             (dt.date(2025, 12, 1), dt.date(2025, 12, 31)), (dt.date(2025, 12, 31), dt.date(2026, 1, 30)),
             (dt.date(2024, 12, 15), dt.date(2025, 1, 14)), (dt.date(2023, 11, 1), dt.date(2023, 11, 30)),
             (dt.date(2024, 1, 1), dt.date(2024, 1, 1))]
# Consulta anterior, uma vez só para todo o intervalo (é agregada por dia, então cada período é um recorte).
dias = {d: {'dia': d, 'pedidos': int(p), 'itens': int(i), 'receita_centavos': int(r)} for d, p, i, r in psql(
    """SELECT to_char(p.criado_em::date, 'YYYY-MM-DD'), count(DISTINCT p.id), sum(i.quantidade),
              sum(i.quantidade::bigint * i.preco_unitario_centavos)
         FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id
        WHERE p.status <> 'cancelado' GROUP BY p.criado_em::date""")}
diferentes = 0
for a, b in periodos:
    esperado = [dias[d] for d in sorted(dias) if str(a) <= d <= str(b)]
    with urllib.request.urlopen(f'http://127.0.0.1:3000/relatorios/vendas-por-dia?inicio={a}&fim={b}') as r:
        api = json.load(r)
    if api != esperado:
        diferentes += 1; print('DIFERENTE', a, b)
print(f'{len(periodos)} períodos comparados, {diferentes} diferentes')
