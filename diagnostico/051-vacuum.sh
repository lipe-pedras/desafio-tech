#!/usr/bin/env bash
# 05.1: só ANALYZE contra VACUUM ANALYZE no arquivo de banco/ da 05.1. Mostra o mapa de visibilidade e o plano
# das consultas de /pedidos?status=&pagina= (status pago, página 1000, e a contagem) em dois momentos:
#   1. logo depois de o banco ser criado (docker compose up --wait);
#   2. depois de o autovacuum passar por pedidos (espera até 3 min).
#
#   diagnostico/051-vacuum.sh <pasta-temporaria> <commit>:<rotulo> [<commit>:<rotulo> ...] > diagnostico/051-vacuum.txt
#
# Cada versão roda numa git worktree própria e num projeto compose próprio, com o banco criado do zero.
set -euo pipefail
TMP="$1"; shift

sql() {
  docker compose exec -T banco psql -U loja -d loja -X -q <<'EOF'
SELECT now()::time(0) AS agora, pg_postmaster_start_time()::time(0) AS banco_no_ar_desde,
       round(extract(epoch FROM now() - pg_postmaster_start_time())) AS segundos_no_ar;
SELECT c.relallvisible, c.relpages, s.last_vacuum, s.last_autovacuum, s.last_analyze, s.n_ins_since_vacuum
  FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid WHERE c.relname = 'pedidos';
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, cliente_id, status, criado_em FROM pedidos
 WHERE status = 'pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 19980;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT count(*) AS total FROM pedidos WHERE status = 'pago';
EOF
}

for par in "$@"; do
  c="${par%%:*}"; r="${par#*:}"; w="${TMP}/${c}"
  [[ -d "$w" ]] || git worktree add -q --detach "$w" "$c"
  (
    cd "$w"; export COMPOSE_PROJECT_NAME="vac-$c"
    docker compose down -v >/dev/null 2>&1
    echo "################ $r ($c)"
    echo "--- banco/05 deste commit:"; grep -vE '^\s*(--|\\echo|$)' banco/05-*.sql
    inicio=$(date +%s); docker compose up -d --build --wait >/dev/null 2>&1
    echo "--- criação do banco: $(( $(date +%s) - inicio )) s"
    echo "=== 1. logo depois da criação"; sql
    for _ in $(seq 36); do
      v=$(docker compose exec -T banco psql -U loja -d loja -Atc "SELECT coalesce(last_autovacuum::text, '') FROM pg_stat_user_tables WHERE relname = 'pedidos'")
      [[ -n "$v" ]] && break
      timeout 5 tail -f /dev/null || true
    done
    echo "=== 2. depois do autovacuum em pedidos"; sql
    docker compose down -v >/dev/null 2>&1
  )
  git worktree remove --force "$w"
done
