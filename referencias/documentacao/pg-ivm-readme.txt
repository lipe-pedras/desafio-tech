Fonte: https://github.com/sraoss/pg_ivm
Acessado em: 2026-11-20
Trecho do README (Markdown, sem edição do conteúdo): README do repositório: versões suportadas, criação de IMMV, definições suportadas e restrições de agregados.

# pg_ivm

The `pg_ivm` module provides Incremental View Maintenance (IVM) feature for PostgreSQL.

The extension supports PostgreSQL 13-19.

## Description


pgivm.create_immv(immv text, view_definition text) RETURNS bigint
```
`create_immv` defines a new IMMV of a query. A table of the name `immv_name` is created and a query specified by `view_definition` is executed and used to populate the IMMV. The query is stored in `pg_ivm_immv`, so that it can be refreshed later upon incremental view maintenance. `create_immv` returns the number of rows in the created IMMV.

When an IMMV is created, some triggers are automatically created so that the view's contents are immediately updated when its base tables are modified. In addition, a unique index is created on the IMMV automatically if unique keys can be derived from the view definition.  For example, if the view definition query has a GROUP BY clause, a unique index is created on the columns of GROUP BY expressions. Also, if the view has DISTINCT clause, a unique index is created on all columns in the target list. Otherwise, if the IMMV contains all primary key attributes of its base tables in the target list, a unique index is created on these attributes.

`create_immv` acquires an `AccessExclusiveLock` on the view. However, even if we are able to acquire the lock, a concurrent transaction may have already incrementally updated and committed the view before we can acquire it. In the `REPEATABLE READ` or `SERIALIZABLE` isolation levels, this could lead to an inconsistent state of the view. Unfortunately, this situation cannot be detected during the creation of the view. As a result, `create_immv` raises a warning in these isolation levels, suggesting that the command be used in `READ COMMITTED` or that `refresh_immv` be executed afterward to make the view's contents remain consistent.

## Supported View Definitions and Restriction

Currently, IMMV's view definition can contain inner and outer joins, DISTINCT clause, some built-in aggregate functions, simple sub-queries in `FROM` clause, EXISTS sub-queries, and simple CTE (`WITH` query). Inner joins including self-join are supported. Supported aggregate functions are count, sum, avg, min and max. Other aggregates, sub-queries which contain an aggregate or `DISTINCT` clause, sub-queries in other than `FROM` clause, window functions, `HAVING`, `ORDER BY`, `LIMIT`/`OFFSET`, `UNION`/`INTERSECT`/`EXCEPT`, `DISTINCT ON`, `TABLESAMPLE`, `VALUES`, and `FOR UPDATE`/`SHARE` can not be used in view definition.

The base tables must be simple tables. Views, materialized views, inheritance parent tables, partitioned tables, partitions, and foreign tables can not be used.

Any system column cannot be included in the view definition query.
The target list cannot columns whose name starts with `__ivm_`.

Data type used in the target list in the view must have default operator class for access method btree. For example, `json`, `xml`, or `point` type cannot be in the target list.

Logical replication is not supported, that is, even when a base table at a publisher node is modified, IMMVs at subscriber nodes defined on these base tables are not updated.

## Notes

### Aggregates

Supported aggregate functions are `count`, `sum`, `avg`, `min`, and `max`. Currently, only built-in aggregate functions are supported and user defined aggregates cannot be used.

When an IMMV including aggregate is created, some extra columns whose name start with `__ivm` are automatically added to the target list. `__ivm_count__` contains the number of tuples aggregated in each group. In addition, more than one extra columns for each column of aggregated value  are added in order to maintain the value. For example, columns named like  `__ivm_count_avg__` and `__ivm_sum_avg__` are added for maintaining an average value. When a base table is modified, the new aggregated values are incrementally calculated using the old aggregated values and values of related extra  columns stored in the IMMV.

Note that for `min` or `max`, the new values could be re-calculated from base tables with regard to the affected groups when a tuple containing the current minimal or maximal values are deleted from a base table. Therefore, it can takes a long time to update an IMMV containing these functions.

Also, note that using `sum` or `avg` on `real` (`float4`) type or `double precision` (`float8`) type in IMMV is unsafe, because aggregated values in IMMV can become different from results calculated from base tables due to the limited precision of these types. To avoid this problem, use the `numeric` type instead.

#### Restrictions on Aggregate

If we have a `GROUP BY` clause, expressions specified in `GROUP BY` must appear in the target list. This is how tuples to be updated in the IMMV are identified. These attributes are used as scan keys for searching tuples in the IMMV, so indexes on them are required for efficient IVM.

Targetlist cannot contain expressions which contain an aggregate in it.

### Outer Joins

Outer joins are supported with the following restrictions.

#### Restrictions on Outer Joins

Only simple equijoin is supported. The join condition must be a single equality comparison between columns of two base tables.

All attributes used in join conditions must be included in the target list. These attributes are used as scan keys for searching tuples in the `IMMV`, so indexes on them are required for efficient IVM.

The target list cannot contain non-strict functions that may return a non-NULL results for NULL inputs. For example, `CASE` expressions cannot be used.

`WHERE` clauses cannot contain non-null-rejecting predicates that can return true for NULL inputs.  For example, `IS NULL` cannot be used.

Aggregate functions cannot be used with outer joins.

Subqueries cannot be used with outer joins.

### Subqueries

Simple subqueries in `FROM` clause and `EXISTS` subqueries in 'WHERE' clause are supported.

