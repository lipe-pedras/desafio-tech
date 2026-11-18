#!/usr/bin/env python3
"""Resume as medições de resultados/: mediana das execuções de cada rótulo.

Uso, a partir da raiz do desafio:
  python3 diagnostico/analisar.py <rotulo> [<rotulo> ...]
  python3 diagnostico/analisar.py --serie remedicao-desktop > diagnostico/remedicao-desktop/resumo.txt
  python3 diagnostico/analisar.py --serie variacao-banco    > diagnostico/variacao-banco/resumo.txt
  python3 diagnostico/analisar.py --serie 03-mediana        > diagnostico/03-mediana/resumo.txt

Com rótulos medidos por diagnostico/rodizio.sh, também mostra os contadores de cota de CPU
registrados em diagnostico/rodizio-registro.txt.
"""
import argparse
import json
import re
import statistics
from pathlib import Path

RESULTADOS = Path('resultados')
REGISTRO_RODIZIO = Path('diagnostico/rodizio-registro.txt')
SAIDA_03_MEDIANA = Path('diagnostico/03-mediana/saida')

ROTAS = ['cliente', 'cliente-por-email', 'pedidos-do-cliente', 'pedidos-por-status',
         'busca-produtos', 'vendas-por-dia', 'top-produtos']
METRICAS_GERAIS = ('rps', 'avg', 'med', 'p95', 'p99', 'cpu_b', 'mem_b', 'cpu_a', 'mem_a')

mediana = statistics.median


# ---------- leitura de resultados/ ----------

def ler_json(caminho):
    return json.loads(Path(caminho).read_text())


def metricas_k6(pasta):
    return ler_json(Path(pasta) / 'resumo-k6.json')['metrics']


def mediana_da_rota(metricas, rota):
    return metricas[f'http_req_duration{{rota:{rota}}}']['values']['med']


def recursos_do_servico(recursos, servico):
    """CPU (%) e memória (MiB) médias de um serviço, da tabela de recursos.txt."""
    padrao = rf'{servico}-1\s+\d+\s+([\d.]+)%\s+[\d.]+%\s+([\d.]+) MiB'
    cpu, memoria = re.search(padrao, recursos).groups()
    return float(cpu), float(memoria)


def ler_execucao(pasta):
    pasta = Path(pasta)
    metricas = metricas_k6(pasta)
    duracao = metricas['http_req_duration']['values']
    recursos = (pasta / 'recursos.txt').read_text()
    contexto = (pasta / 'contexto.txt').read_text()
    cpu_banco, memoria_banco = recursos_do_servico(recursos, 'banco')
    cpu_api, memoria_api = recursos_do_servico(recursos, 'api')
    contrato_mantido = 'Contrato mantido' in (pasta / 'contrato.txt').read_text()
    return {
        'pasta': pasta.name,
        'rps': metricas['http_reqs']['values']['rate'],
        'avg': duracao['avg'],
        'med': duracao['med'],
        'p95': duracao['p(95)'],
        'p99': duracao['p(99)'],
        'err': metricas['http_req_failed']['values']['rate'],
        'cpu_b': cpu_banco,
        'mem_b': memoria_banco,
        'cpu_a': cpu_api,
        'mem_a': memoria_api,
        'commit': re.search(r'commit: (\w+)', contexto).group(1),
        'sujo': re.search(r'sem commit: (\d+)', contexto).group(1),
        'contrato': 'mantido' if contrato_mantido else 'QUEBRADO',
        **{rota: mediana_da_rota(metricas, rota) for rota in ROTAS},
    }


def rotulo_da_pasta(nome):
    """'20261111-131125-04-antes-desktop' -> '04-antes-desktop'."""
    return re.sub(r'^\d{8}-\d{6}-', '', nome)


def pastas_do_rotulo(rotulo):
    return sorted(p for p in RESULTADOS.glob(f'*-{rotulo}') if rotulo_da_pasta(p.name) == rotulo)


def execucoes_do_rotulo(rotulo):
    return [ler_execucao(pasta) for pasta in pastas_do_rotulo(rotulo)]


# ---------- impressão por rótulo ----------

def mediana_de(execucoes, campo):
    return mediana(e[campo] for e in execucoes)


def imprimir_rotulo(rotulo, commit_unico=False):
    execucoes = execucoes_do_rotulo(rotulo)
    if commit_unico:
        commit = execucoes[0]['commit']
    else:
        commit = sorted({e['commit'] for e in execucoes})
    sujo = [e['sujo'] for e in execucoes]
    erros = [e['err'] for e in execucoes]
    contrato = sorted({e['contrato'] for e in execucoes})
    rps = [round(e['rps'], 2) for e in execucoes]
    p95 = [round(e['p95'], 1) for e in execucoes]
    gerais = ' '.join(f'{c}={mediana_de(execucoes, c):.2f}' for c in METRICAS_GERAIS)
    rotas = ' '.join(f'{r}={mediana_de(execucoes, r):.1f}' for r in ROTAS)

    print(f'== {rotulo} ({len(execucoes)} execuções) commit {commit} sujo {sujo} erros {erros} contrato {contrato}')
    print('   pastas', ' '.join(e['pasta'] for e in execucoes))
    print('   req/s por execução', rps, ' p95 por execução', p95)
    print('   medianas: ' + gerais)
    print('   rotas (mediana da rota, ms): ' + rotas + '\n')


def imprimir_rotulo_compacto(rotulo):
    """Formato curto, usado só na série variacao-banco."""
    execucoes = execucoes_do_rotulo(rotulo)
    sujo = [e['sujo'] for e in execucoes]
    erros = [e['err'] for e in execucoes]
    contrato = {e['contrato'] for e in execucoes}
    gerais = ' '.join(f'{c}={mediana_de(execucoes, c):.1f}' for c in METRICAS_GERAIS)
    rotas = ' '.join(f'{r}={mediana_de(execucoes, r):.1f}' for r in ROTAS)

    print(f'== {rotulo} ({len(execucoes)} execuções) commit {execucoes[0]["commit"]} '
          f'sujo {sujo} erros {erros} contrato {contrato}')
    print('   pastas', ' '.join(e['pasta'][:15] for e in execucoes))
    print('   req/s por execução', [round(e['rps'], 2) for e in execucoes])
    print('   ' + gerais, f'rps2={mediana_de(execucoes, "rps"):.2f}')
    print('   rotas', rotas)


# ---------- contadores de cota de CPU (diagnostico/rodizio-registro.txt) ----------

CONTADORES = r'usage_usec (\d+) nr_periods (\d+) nr_throttled (\d+) throttled_usec (\d+)'


def ler_contadores(texto):
    """{'banco': (...), 'api': (...)}; as linhas antigas só têm o banco, sem o nome do serviço."""
    blocos = re.findall(rf'(?:(banco|api): )?{CONTADORES}', texto)
    return {servico or 'banco': tuple(map(int, valores)) for servico, *valores in blocos}


def medicoes_de_cota(rotulos):
    """Diferença (depois - antes) dos contadores de cada medição, na ordem do registro."""
    if not REGISTRO_RODIZIO.exists():
        return []
    medicoes, antes = [], {}
    for linha in REGISTRO_RODIZIO.read_text().splitlines():
        achado = re.search(r'cota (antes|depois) de medir (\S+): (.*)', linha)
        if not achado or achado.group(2) not in rotulos:
            continue
        momento, rotulo, contadores = achado.groups()
        if momento == 'antes':
            antes[rotulo] = ler_contadores(contadores)
            continue
        depois = ler_contadores(contadores)
        for servico, valores in depois.items():
            diferenca = [d - a for d, a in zip(valores, antes[rotulo][servico])]
            medicoes.append((rotulo, servico, *diferenca))
    return medicoes


def imprimir_cota(rotulos):
    medicoes = medicoes_de_cota(rotulos)
    if not medicoes:
        return
    com_api = any(servico == 'api' for _, servico, *_ in medicoes)
    largura = max(len(r) for r in rotulos) + 6
    colunas = 'periodos  pausados %pausados  pausado_s    cpu_s'
    explicacao = 'durante o medir.sh (depois menos antes; inclui o aquecimento de 15 s do medir.sh)'
    if com_api:
        print(f'contadores de cota de CPU {explicacao}')
        print(f'{"rotulo":{largura}s}{"svc":7s}{colunas}')
    else:
        print(f'contadores de cota de CPU do banco {explicacao}')
        print(f'{"rotulo":{largura}s}{colunas}')
    for rotulo, servico, uso, periodos, pausados, pausado_us in medicoes:
        servico_coluna = f'{servico:7s}' if com_api else ''
        print(f'{rotulo:{largura}s}{servico_coluna}{periodos:8d}{pausados:10d}{pausados / periodos * 100:10.1f}'
              f'{pausado_us / 1e6:11.2f}{uso / 1e6:9.2f}')


# ---------- séries ----------

def serie_rotulos(rotulos):
    for rotulo in rotulos:
        imprimir_rotulo(rotulo)
    imprimir_cota(rotulos)


BLOCOS_REMEDICAO = {
    'Bloco A (bancos separados, linha de base x 01)': [
        '00-linha-de-base-desktop', '01-indices-desktop'],
    'Bloco B (banco único com índices, só a API muda)': [
        '01-indices-rodizio-desktop', '02-pool-conexoes-desktop',
        '021-pool-max-1-desktop', '021-pool-max-2-desktop', '021-pool-max-3-desktop',
        '021-pool-max-5-desktop', '021-pool-max-10-desktop', '021-pool-max-20-desktop',
        '03-n-mais-1-desktop', '031-pool-max-5-desktop', '031-pool-max-10-desktop'],
    'Rodízio 03: pool 1 x pool 2 (2026-11-11)': [
        '031-pool-max-1-desktop', '031-pool-max-2-desktop'],
    'Fechamento da 03 (2026-11-11)': [
        '03f-02-pool-2-desktop', '03f-02-pool-1-desktop', '03f-03-pool-1-desktop'],
}


def imprimir_amplitudes(filtro):
    """Amplitude das req/s entre execuções do mesmo rótulo: (máx - mín) / mediana."""
    rotulos = sorted({rotulo_da_pasta(p.name) for p in RESULTADOS.glob('*-*') if filtro(p.name)})
    linhas = []
    for rotulo in rotulos:
        rps = [metricas_k6(p)['http_reqs']['values']['rate'] for p in pastas_do_rotulo(rotulo)]
        if len(rps) >= 3:
            amplitude = (max(rps) - min(rps)) / mediana(rps) * 100
            linhas.append((rotulo, len(rps), min(rps), max(rps), amplitude))
    for rotulo, n, minimo, maximo, amplitude in linhas:
        print(f'   {rotulo:36s} n={n} req/s {minimo:6.2f} a {maximo:6.2f}  amplitude {amplitude:5.1f}%')
    amplitudes = [linha[4] for linha in linhas]
    print(f'   mediana das amplitudes: {mediana(amplitudes):.1f}%  máxima: {max(amplitudes):.1f}%\n')


def serie_remedicao_desktop():
    for bloco, rotulos in BLOCOS_REMEDICAO.items():
        print(f'##### {bloco}\n')
        for rotulo in rotulos:
            imprimir_rotulo(rotulo, commit_unico=True)
    print('##### Repetibilidade: amplitude das req/s entre execuções do mesmo rótulo\n')
    print('Desktop (rótulos *-desktop):')
    imprimir_amplitudes(lambda nome: nome.endswith('-desktop'))
    print('Notebook (todos os outros rótulos com 3 ou mais execuções):')
    imprimir_amplitudes(lambda nome: not nome.endswith('-desktop') and not nome.endswith('.gitkeep'))


ROTULOS_VARIACAO_BANCO = ['var-banco-1', 'var-banco-2', 'var-banco-3', 'ab-01-indices',
                          'ab-02-pool-10', 'ab-02-pool-2', 'ab-03-n-mais-1']


def serie_variacao_banco():
    for rotulo in ROTULOS_VARIACAO_BANCO:
        imprimir_rotulo_compacto(rotulo)


# ---------- série 03-mediana (diagnóstico, lê diagnostico/03-mediana/saida/) ----------

RODADAS = (1, 2, 3)


def mediana_geral(metricas_por_rodada, campo):
    return mediana(m['http_req_duration']['values'][campo] for m in metricas_por_rodada)


def mediana_rota(metricas_por_rodada, rota):
    return mediana(mediana_da_rota(m, rota) for m in metricas_por_rodada)


def imprimir_teste1():
    print('TESTE 1: código antigo (1fd2ae4), carga sem pedidos-do-cliente')
    print('usuarios  req/s  media_ms  mediana_ms  p95_ms  | '
          'mediana por rota: cliente  email  status  busca  vendas  top | erros')
    rotas = [r for r in ROTAS if r != 'pedidos-do-cliente']
    for usuarios in (2, 5, 8, 14, 20):
        ms = [metricas_k6(SAIDA_03_MEDIANA / f'teste1/vus-{usuarios}/r{r}') for r in RODADAS]
        rps = mediana(m['http_reqs']['values']['rate'] for m in ms)
        erros = max(m['http_req_failed']['values']['rate'] for m in ms)
        print(f"{usuarios:>8} {rps:6.2f} {mediana_geral(ms, 'avg'):9.1f} {mediana_geral(ms, 'med'):11.1f} "
              f"{mediana_geral(ms, 'p(95)'):7.1f}  |",
              ' '.join(f'{mediana_rota(ms, r):8.1f}' for r in rotas),
              '|', erros)


def imprimir_teste2_versao(versao):
    pastas = [SAIDA_03_MEDIANA / f'teste2/{versao}/r{r}' for r in RODADAS]
    diags = [ler_json(p / 'diag.json') for p in pastas]
    ms = [metricas_k6(p) for p in pastas]

    print(f'\n== {versao}')
    print('req/s por rodada', [round(m['http_reqs']['values']['rate'], 2) for m in ms])
    for campo, nome in (('avg', 'media'), ('med', 'mediana'), ('p(95)', 'p95'), ('p(99)', 'p99')):
        valores = [round(m['http_req_duration']['values'][campo], 1) for m in ms]
        print(f'{nome} por rodada', valores, 'mediana', mediana(valores))
    print('erros', [m['http_req_failed']['values']['rate'] for m in ms])
    print('requisicoes esperando o pool (media por segundo), por rodada',
          [round(d['fila_pool_media'], 2) for d in diags])

    consultas = [sum(r['consultas'] for r in d['rotas'].values()) for d in diags]
    execucao = [sum(r['execucao_por_consulta_ms'] * r['consultas'] for r in d['rotas'].values()) for d in diags]
    por_consulta = [e / c for e, c in zip(execucao, consultas)]
    espera_prevista = [d['fila_pool_media'] * s / 2 for d, s in zip(diags, por_consulta)]
    print('consultas no total, por rodada', consultas)
    print('tempo de execucao somado (ms), por rodada', [round(e) for e in execucao])
    print('execucao media por consulta, todas as rotas (ms), por rodada', [round(s, 1) for s in por_consulta])
    print('espera prevista = fila x execucao media / 2 conexoes (ms), por rodada',
          [round(e, 1) for e in espera_prevista])

    print('rota                  em_andamento  espera/consulta  execucao/consulta  mediana_k6  consultas/req')
    for rota in ROTAS:
        def campo(nome):
            return mediana(d['rotas'][rota][nome] for d in diags)
        consultas_por_req = mediana(d['rotas'][rota]['consultas'] / d['rotas'][rota]['requisicoes'] for d in diags)
        print(f"{rota:20} {campo('em_andamento_medio'):12.2f} {campo('espera_pool_por_consulta_ms'):16.1f} "
              f"{campo('execucao_por_consulta_ms'):18.2f} {mediana_rota(ms, rota):11.1f} {consultas_por_req:14.1f}")


def serie_03_mediana():
    print('DIAGNÓSTICO, não é resultado oficial (não usa scripts/medir.sh). Mediana de 3 rodadas.\n')
    imprimir_teste1()
    print('\nTESTE 2: carga oficial, API instrumentada, versões alternadas sem recriar o banco')
    for versao in ('antes', 'depois'):
        imprimir_teste2_versao(versao)


SERIES = {
    'remedicao-desktop': serie_remedicao_desktop,
    'variacao-banco': serie_variacao_banco,
    '03-mediana': serie_03_mediana,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    grupo = parser.add_mutually_exclusive_group(required=True)
    grupo.add_argument('rotulos', nargs='*', default=[], help='rótulos de resultados/')
    grupo.add_argument('--serie', choices=SERIES, help='uma das séries com resumo próprio')
    args = parser.parse_args()
    if args.serie:
        SERIES[args.serie]()
    else:
        serie_rotulos(args.rotulos)


if __name__ == '__main__':
    main()
