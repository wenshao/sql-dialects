# Top-K 查询优化 (Top-K Query Optimization)

从 100 亿行明细中找出最大的 10 笔订单——朴素实现需要排序整张表（O(N log N)、磁盘溢出、长尾延迟），而 Top-K 优化只需 O(N log K) 时间、O(K) 内存、零磁盘溢出。`ORDER BY ... LIMIT N` 是关系数据库里最值得花心思优化的算子之一，也是区分"教科书 SQL 引擎"和"现代 SQL 引擎"的分水岭。

## 为什么 ORDER BY ... LIMIT N 是关键优化点

绝大多数面向用户的查询都遵循同一个模式：

```sql
SELECT * FROM orders
ORDER BY created_at DESC
LIMIT 20;
```

排行榜、首页 feed、最近订单、Top 卖家、慢查询日志、监控告警 Top N——这些查询的共同点是：**结果集很小（K 通常是 10、20、100），但候选集可能极大（N 是几亿到几百亿行）**。如果优化器看不出 LIMIT，它会先全量排序再丢弃 N-K 行，浪费 99.99% 的工作量。Top-K 优化的目标就是把这个"先排再丢"模式压缩成一次单遍扫描 + 小堆维护。

### 朴素 Sort+Limit 与 Top-K 堆排序的对比

| 维度 | 朴素 Sort + Limit | Top-K 堆 / 优先队列 |
|------|------------------|---------------------|
| 时间复杂度 | O(N log N) | O(N log K) |
| 内存复杂度 | O(N)（或溢出磁盘） | O(K) |
| 磁盘 I/O | 可能多轮归并 | 单次扫描 |
| 早停（early-stop） | 不支持 | 索引/有序输入下可早停 |
| 适用 K | 任意 | K << N 时收益最大 |
| 流水线友好 | 阻塞算子 | 半阻塞（K 大时变阻塞） |

当 N = 10^9、K = 10 时，O(N log N) ≈ 30N 而 O(N log K) ≈ 3.3N，差异接近 10 倍；更关键的是堆只占 K 个元素，完全在 L1/L2 cache 内，几乎不产生磁盘溢出。这就是 PostgreSQL "Top-N heapsort"、MySQL "filesort with priority queue"、Oracle "STOP KEY"、SQL Server "Top N Sort" 这一系列名字背后的同一个核心思想。

## 不是 SQL 标准——而是优化器的内部机制

`ORDER BY ... LIMIT/FETCH FIRST` 本身是 SQL 语法，但 **Top-K 优化并不在 SQL:2008/2016 标准中**——标准只规定了 `FETCH FIRST n ROWS ONLY` 的语义（"返回前 n 行"），并没有规定优化器如何执行。Top-K 是 100% 的物理执行层优化：同一份 SQL，不同引擎可能跑出 1000 倍的性能差。这意味着：

1. **不存在标准语法层差异**——所有引擎都接受 `ORDER BY ... LIMIT N`（或 Oracle 的 `ROWNUM <= N` / `FETCH FIRST N ROWS ONLY`）
2. **差异完全在 EXPLAIN 里**——是否出现 `Top-N heapsort`、`STOP KEY`、`partial sort`、`incremental sort` 等关键字
3. **优化器可能放弃 Top-K**——当 K 太大、ORDER BY 包含表达式、有 DISTINCT/聚合时，许多引擎会回退到全量排序

下文的所有矩阵都是基于 EXPLAIN 输出和官方文档的实际行为整理，而非语法支持。

## 支持矩阵

### 1. Top-N 排序（堆/优先队列，避免全排序）

| 引擎 | 是否支持 | 算子名 | 引入版本 |
|------|---------|--------|---------|
| PostgreSQL | 是 | `Top-N heapsort` | 8.3 (2008) |
| MySQL | 是 | `Using filesort` (priority queue) | 5.6.2 (2012) |
| MariaDB | 是 | `filesort` (priority queue) | 10.0+ |
| SQLite | 部分 | `B-TREE FOR ORDER BY` w/ LIMIT | 3.x |
| Oracle | 是 | `SORT ORDER BY STOPKEY` | 8i+ |
| SQL Server | 是 | `Top N Sort` | 2005+ |
| DB2 | 是 | `SORT ... TOP N` | 9.x+ |
| Snowflake | 是 | partial sort | GA |
| BigQuery | 是 | partial sort | GA |
| Redshift | 是 | `Top N` | GA |
| DuckDB | 是 | `Top N` (radix) | 0.5+ |
| ClickHouse | 是 | `partial_sorting` | 早期 |
| Trino | 是 | `TopN` operator | 早期 |
| Presto | 是 | `TopNOperator` | 0.x+ |
| Spark SQL | 是 | `TakeOrderedAndProject` | 1.x+ |
| Hive | 部分 | Tez vectorized TopN | 2.x+ |
| Flink SQL | 是 | `Rank` w/ `BatchPhysicalSortLimit` | 1.10+ |
| Databricks | 是 | `TakeOrderedAndProject` | GA |
| Teradata | 是 | `TOP N` 算子 | V2R5+ |
| Greenplum | 是 | `Limit + Sort` (Top-N) | 继承 PG |
| CockroachDB | 是 | `top-k sorter` | 2.1+ |
| TiDB | 是 | `TopN` 算子 | 1.0+ |
| OceanBase | 是 | `TOP-N SORT` | 2.x+ |
| YugabyteDB | 是 | Top-N heapsort | 继承 PG |
| SingleStore | 是 | `TopSort` | 早期 |
| Vertica | 是 | `TOP-K` algorithm | 早期 |
| Impala | 是 | `TOP-N` 节点 | 1.x+ |
| StarRocks | 是 | `TOP-N` 算子 | 早期 |
| Doris | 是 | `TOP-N` 算子 | 早期 |
| MonetDB | 部分 | `topn` operator | 早期 |
| CrateDB | 是 | `TopNDistinct` / `TopN` | 早期 |
| TimescaleDB | 是 | 继承 PG | 继承 PG |
| QuestDB | 是 | `Sort light` w/ LIMIT | 早期 |
| Exasol | 是 | `LIMIT` 优化 | 早期 |
| SAP HANA | 是 | `TOP N SORT` | 1.0+ |
| Informix | 是 | `Sort + FIRST N` | 11.x+ |
| Firebird | 是 | `SORT (TOP N)` | 3.0+ |
| H2 | 是 | sorted limit | 早期 |
| HSQLDB | 部分 | limited sort | 2.x+ |
| Derby | 部分 | 有限优化 | 10.x |
| Amazon Athena | 是 | 继承 Trino | GA |
| Azure Synapse | 是 | `Top N Sort` | GA |
| Google Spanner | 是 | `Sort Limit` | GA |
| Materialize | 是 | `TopK` operator | GA |
| RisingWave | 是 | `TopN` operator | GA |
| InfluxDB (SQL) | 是 | DataFusion `TopK` | 3.0+ |
| DatabendDB | 是 | DataFusion `TopK` | GA |
| Yellowbrick | 是 | `TOP-N` 算子 | GA |
| Firebolt | 是 | partial sort | GA |

> 统计：49/49 引擎都有某种形式的 Top-N 优化，这是几乎被业界普遍实现的优化。差异在于触发条件和 K 的上限。

### 2. 索引扫描提供有序输出（避免排序）

当 ORDER BY 列上有索引（B-tree、IOT、聚簇索引、Z-order），优化器可以直接按索引顺序扫描，遇到 LIMIT 立即停止。**根本不需要排序算子**，时间复杂度降到 O(K)。

| 引擎 | 支持 | 实现 |
|------|------|------|
| PostgreSQL | 是 | Index Scan + LIMIT，cost 模型自动选择 |
| MySQL | 是 | InnoDB B+ 树叶子按主键/二级索引顺序 |
| MariaDB | 是 | 同 MySQL |
| SQLite | 是 | rowid / B-tree 索引顺序 |
| Oracle | 是 | INDEX RANGE SCAN + STOPKEY |
| SQL Server | 是 | 聚簇/非聚簇索引顺序扫描 |
| DB2 | 是 | INDEX SCAN + STOP AFTER |
| Snowflake | 部分 | clustering key 排序 + 微分区裁剪 |
| BigQuery | 部分 | 聚簇表 / 分区裁剪 |
| Redshift | 部分 | sort key 提供顺序 |
| DuckDB | 是 | ART index 扫描（实验性） |
| ClickHouse | 是 | `optimize_read_in_order` (主键/order key) |
| Trino | 部分 | 依赖底层 connector |
| Presto | 部分 | 同 Trino |
| Spark SQL | 部分 | 分桶排序 / Iceberg sort order |
| Hive | 部分 | bucketed sorted table |
| Flink SQL | 部分 | LookupJoin 索引 |
| Databricks | 是 | Z-order / Liquid Clustering |
| Teradata | 是 | PI / SI 排序 |
| Greenplum | 是 | 继承 PG |
| CockroachDB | 是 | 主键/二级索引 |
| TiDB | 是 | TiKV index scan + Limit pushdown |
| OceanBase | 是 | 索引顺序扫描 |
| YugabyteDB | 是 | DocDB 索引扫描 |
| SingleStore | 是 | sort key + skip index |
| Vertica | 是 | projection sort order |
| Impala | 部分 | Parquet sort columns |
| StarRocks | 是 | sort key + prefix index |
| Doris | 是 | sort key + prefix index |
| MonetDB | 部分 | order index |
| CrateDB | 是 | Lucene doc values |
| TimescaleDB | 是 | chunk 时间排序 + LIMIT |
| QuestDB | 是 | designated timestamp，原生有序 |
| Exasol | 部分 | 分布键 |
| SAP HANA | 是 | 列存 inverted index |
| Informix | 是 | 索引扫描 |
| Firebird | 是 | 索引扫描 + FIRST N |
| H2 | 是 | B-tree 顺序 |
| HSQLDB | 是 | 索引顺序 |
| Derby | 是 | 索引顺序 |
| Amazon Athena | 部分 | 继承 Trino |
| Azure Synapse | 是 | clustered columnstore ordered scan |
| Google Spanner | 是 | 主键索引扫描 |
| Materialize | 是 | arrangement 已索引 |
| RisingWave | 是 | state table 索引 |
| InfluxDB (SQL) | 是 | 时间列原生有序 |
| DatabendDB | 部分 | cluster key |
| Yellowbrick | 部分 | shard 排序 |
| Firebolt | 部分 | primary index |

### 3. Partial Sort（部分有序输入）

当输入按 ORDER BY 列的**前缀**已经有序时，引擎只需在每个相同前缀的"组"内做小范围排序——这是 PostgreSQL 13 的 `Incremental Sort` 和 ClickHouse 的 `partial_sorting` 的核心思想。

| 引擎 | 支持 | 算子 / 关键字 |
|------|------|-------------|
| PostgreSQL | 是 | `Incremental Sort` (13+) |
| MySQL | 否 | -- |
| MariaDB | 否 | -- |
| SQLite | 否 | -- |
| Oracle | 是 | `SORT ORDER BY STOPKEY` w/ index prefix |
| SQL Server | 部分 | merge interval 优化 |
| DB2 | 部分 | -- |
| Snowflake | 是 | partial sort（自动） |
| BigQuery | 部分 | -- |
| Redshift | 是 | sort key 上的 partial sort |
| DuckDB | 是 | radix partial sort |
| ClickHouse | 是 | `optimize_read_in_order` + partial sort |
| Trino | 是 | partial sort（部分情况） |
| Presto | 部分 | -- |
| Spark SQL | 部分 | bucketed sorted table |
| Hive | 否 | -- |
| Flink SQL | 是 | `SortMergeJoin` 中的局部排序 |
| Databricks | 是 | -- |
| Teradata | 部分 | -- |
| Greenplum | 是 | 继承 PG 13+ |
| CockroachDB | 是 | partial ordering |
| TiDB | 部分 | index prefix + sort |
| OceanBase | 部分 | -- |
| YugabyteDB | 是 | 继承 PG 13+ |
| SingleStore | 部分 | -- |
| Vertica | 是 | merge sort over projections |
| Impala | 否 | -- |
| StarRocks | 是 | sort key prefix |
| Doris | 是 | sort key prefix |
| MonetDB | 否 | -- |
| CrateDB | 否 | -- |
| TimescaleDB | 是 | chunk 内已序 + Incremental Sort |
| QuestDB | 是 | 时间线天然有序 |
| Exasol | 否 | -- |
| SAP HANA | 部分 | -- |
| Informix | 否 | -- |
| Firebird | 否 | -- |
| H2 | 否 | -- |
| HSQLDB | 否 | -- |
| Derby | 否 | -- |
| Amazon Athena | 是 | 继承 Trino |
| Azure Synapse | 部分 | -- |
| Google Spanner | 部分 | -- |
| Materialize | 是 | arrangement 维护顺序 |
| RisingWave | 是 | state 内有序 |
| InfluxDB (SQL) | 是 | 时间序天然 |
| DatabendDB | 部分 | -- |
| Yellowbrick | 部分 | -- |
| Firebolt | 部分 | -- |

### 4. LIMIT 穿透子查询下推（Limit Pushdown through Subqueries）

```sql
SELECT * FROM (SELECT * FROM t ORDER BY c) sub LIMIT 10;
```

理想情况下应该把 LIMIT 推到子查询里，让子查询变成 Top-10 而不是全排序。

| 引擎 | 支持 | 备注 |
|------|------|------|
| PostgreSQL | 是 | 内嵌子查询自动展平 |
| MySQL | 是 | derived table merge (5.7+) |
| MariaDB | 是 | -- |
| SQLite | 是 | view flattening |
| Oracle | 是 | view merging |
| SQL Server | 是 | view substitution |
| DB2 | 是 | -- |
| Snowflake | 是 | -- |
| BigQuery | 是 | -- |
| Redshift | 是 | -- |
| DuckDB | 是 | -- |
| ClickHouse | 是 | `enable_optimize_predicate_expression` |
| Trino | 是 | LimitPushDown 优化器规则 |
| Presto | 是 | -- |
| Spark SQL | 是 | `LimitPushDown` Catalyst 规则 |
| Hive | 部分 | -- |
| Flink SQL | 是 | `FlinkLimitPushDown` |
| Databricks | 是 | -- |
| Teradata | 是 | -- |
| Greenplum | 是 | -- |
| CockroachDB | 是 | -- |
| TiDB | 是 | `TopN/Limit pushdown` |
| OceanBase | 是 | -- |
| YugabyteDB | 是 | -- |
| SingleStore | 是 | -- |
| Vertica | 是 | -- |
| Impala | 是 | -- |
| StarRocks | 是 | LimitPushDown |
| Doris | 是 | LimitPushDown |
| MonetDB | 部分 | -- |
| CrateDB | 是 | -- |
| TimescaleDB | 是 | -- |
| QuestDB | 是 | -- |
| Exasol | 是 | -- |
| SAP HANA | 是 | -- |
| Informix | 部分 | -- |
| Firebird | 部分 | -- |
| H2 | 部分 | -- |
| HSQLDB | 部分 | -- |
| Derby | 否 | -- |
| Amazon Athena | 是 | -- |
| Azure Synapse | 是 | -- |
| Google Spanner | 是 | -- |
| Materialize | 是 | -- |
| RisingWave | 是 | -- |
| InfluxDB (SQL) | 是 | -- |
| DatabendDB | 是 | -- |
| Yellowbrick | 是 | -- |
| Firebolt | 是 | -- |

### 5. LIMIT 穿透 JOIN 下推

最复杂的一类下推：`SELECT * FROM a JOIN b ... ORDER BY a.c LIMIT 10`，能不能把 Top-10 推到 `a` 这边？需要满足"join 不过滤、不放大行数"等条件，绝大多数引擎只在外连接 / 一对多确定的场景做。

| 引擎 | 支持 | 备注 |
|------|------|------|
| PostgreSQL | 部分 | 仅在 outer join 不放大时 |
| MySQL | 否 | -- |
| MariaDB | 否 | -- |
| SQLite | 否 | -- |
| Oracle | 是 | `JOIN ELIMINATION` + STOPKEY |
| SQL Server | 部分 | -- |
| DB2 | 部分 | -- |
| Snowflake | 是 | join + limit pushdown |
| BigQuery | 部分 | -- |
| Redshift | 部分 | -- |
| DuckDB | 是 | filter/limit 下推 |
| ClickHouse | 部分 | join 后做 partial sort |
| Trino | 是 | `PushTopNThroughJoin` (Iterative Optimizer) |
| Presto | 是 | -- |
| Spark SQL | 部分 | AQE 下的 LimitPushDownThroughJoin |
| Hive | 否 | -- |
| Flink SQL | 部分 | -- |
| Databricks | 是 | Photon TopN through join |
| Teradata | 部分 | -- |
| Greenplum | 部分 | -- |
| CockroachDB | 部分 | -- |
| TiDB | 部分 | TopN through join (有限) |
| OceanBase | 部分 | -- |
| YugabyteDB | 部分 | -- |
| SingleStore | 是 | -- |
| Vertica | 是 | -- |
| Impala | 部分 | -- |
| StarRocks | 是 | TopNPushDownJoin |
| Doris | 部分 | -- |
| MonetDB | 否 | -- |
| CrateDB | 否 | -- |
| TimescaleDB | 部分 | -- |
| QuestDB | 否 | -- |
| Exasol | 部分 | -- |
| SAP HANA | 部分 | -- |
| Informix | 否 | -- |
| Firebird | 否 | -- |
| H2 | 否 | -- |
| HSQLDB | 否 | -- |
| Derby | 否 | -- |
| Amazon Athena | 是 | -- |
| Azure Synapse | 部分 | -- |
| Google Spanner | 部分 | -- |
| Materialize | 部分 | -- |
| RisingWave | 部分 | -- |
| InfluxDB (SQL) | 部分 | -- |
| DatabendDB | 部分 | -- |
| Yellowbrick | 部分 | -- |
| Firebolt | 部分 | -- |

### 6. Skyline 算子（多目标 Top-K）

Skyline 是 2001 年 Börzsönyi 等人提出的多目标 Top-K——找出"在所有维度上都不被其他点支配"的元组（如"最便宜且最近"的酒店）。它不是传统 Top-K，但是高级 Top-K 优化的方向之一。**目前几乎没有主流商业引擎原生支持 Skyline**，是一个学术为主的特性。

| 引擎 | 原生 SKYLINE | 备注 |
|------|-------------|------|
| PostgreSQL | 否 | 需 `pg_skyline` 第三方扩展（实验性） |
| Oracle | 否 | -- |
| SQL Server | 否 | -- |
| MySQL / MariaDB | 否 | -- |
| DB2 | 否 | 早期研究原型支持 SKYLINE OF |
| Snowflake | 否 | -- |
| BigQuery | 否 | -- |
| 其他 40+ 引擎 | 否 | 全部需要用 NOT EXISTS 自连接模拟 |

> 综合：**0/49 主流引擎原生支持 SQL `SKYLINE OF` 语法**——这是一个值得关注的"标准提案但未落地"的能力。所有引擎都可以用 `NOT EXISTS` 等价改写。

### 7. LATERAL Top-K（Top-K per group）

经典的"每个用户最近 5 个订单"问题，最优解是 `LATERAL JOIN`（也叫 CROSS APPLY），让外层每行驱动一次小 Top-5。

| 引擎 | LATERAL/APPLY | LATERAL + LIMIT 优化 |
|------|---------------|--------------------|
| PostgreSQL | `LATERAL` | 是（9.3+） |
| MySQL | `LATERAL` (8.0.14+) | 是 |
| MariaDB | 否 | -- |
| SQLite | 否 | -- |
| Oracle | `CROSS APPLY` (12c+) / `LATERAL` | 是 |
| SQL Server | `CROSS APPLY` | 是 |
| DB2 | `LATERAL` | 是 |
| Snowflake | `LATERAL` | 是 |
| BigQuery | `UNNEST` 子查询 | 部分 |
| Redshift | 否 (PG fork 但禁用) | -- |
| DuckDB | `LATERAL` | 是 |
| ClickHouse | `ARRAY JOIN` (语义不同) | 用 LIMIT BY 代替 |
| Trino | 否 (用窗口函数) | -- |
| Presto | 否 | -- |
| Spark SQL | `LATERAL VIEW` (语义不同) | 否 |
| Hive | `LATERAL VIEW` | -- |
| Flink SQL | `LATERAL TABLE` | 部分 |
| Databricks | `LATERAL` | 部分 |
| Teradata | `LATERAL` | 是 |
| Greenplum | `LATERAL` | 是 |
| CockroachDB | `LATERAL` | 是 |
| TiDB | 否 | -- |
| OceanBase | `LATERAL` | 部分 |
| YugabyteDB | `LATERAL` | 是 |
| SingleStore | 否 | -- |
| Vertica | `LATERAL` | 是 |
| Impala | 否 | -- |
| StarRocks | 否 | 用窗口函数 |
| Doris | 否 | 用 `LATERAL VIEW` (Hive 语义) |
| MonetDB | `LATERAL` | 部分 |
| CrateDB | 否 | -- |
| TimescaleDB | `LATERAL` | 是 |
| QuestDB | 否 | -- |
| Exasol | 否 | -- |
| SAP HANA | `LATERAL` | 是 |
| Informix | 否 | -- |
| Firebird | 否 | -- |
| H2 | 否 | -- |
| HSQLDB | 否 | -- |
| Derby | 否 | -- |
| Amazon Athena | 否 | -- |
| Azure Synapse | `CROSS APPLY` | 是 |
| Google Spanner | 否 | -- |
| Materialize | 部分 | -- |
| RisingWave | 部分 | -- |
| InfluxDB (SQL) | 否 | -- |
| DatabendDB | 否 | -- |
| Yellowbrick | `LATERAL` | 部分 |
| Firebolt | 否 | -- |

### 8. INCREMENTAL_SORT（PostgreSQL 13+ 风格）

| 引擎 | 支持 | 引入版本 |
|------|------|---------|
| PostgreSQL | 是 | 13 (2020) |
| Greenplum | 是 | 7.0 (基于 PG 12+) |
| TimescaleDB | 是 | 继承 PG 13+ |
| YugabyteDB | 是 | 2.13+ |
| Citus | 是 | 继承 PG |
| Snowflake | 等价 | partial sort |
| ClickHouse | 等价 | `optimize_read_in_order` |
| DuckDB | 等价 | radix partial sort |
| Trino | 等价 | -- |
| 其他 40 个引擎 | 否 | 大多走全排序或 Top-N 堆 |

> Incremental Sort 是 PG 13 最重要的 OLAP 优化之一，把"前缀已序"的输入从 O(N log N) 降到 O(N log k)，k 是组内行数。

### 9. TOP N + 关联子查询优化

```sql
SELECT *, (SELECT MAX(c) FROM t2 WHERE t2.id = t1.id) FROM t1 LIMIT 10;
```

理想情况：LIMIT 10 应该让外层只迭代 10 次外层表，对应只执行 10 次关联子查询，而不是先全表算关联子查询再 LIMIT。

| 引擎 | 支持 | 备注 |
|------|------|------|
| PostgreSQL | 是 | nested loop + limit early stop |
| MySQL | 部分 | 5.6+ 部分支持 |
| Oracle | 是 | STOPKEY 串联 |
| SQL Server | 是 | TOP w/ correlated subquery |
| DB2 | 是 | -- |
| Snowflake | 部分 | 子查询 unnest 后再优化 |
| BigQuery | 部分 | -- |
| Redshift | 部分 | -- |
| DuckDB | 是 | -- |
| ClickHouse | 部分 | -- |
| Trino | 部分 | 子查询 decorrelation |
| Spark SQL | 部分 | -- |
| 其他 | 部分/否 | 大量引擎需手工改写为 LATERAL |

## 详细引擎讲解

### PostgreSQL：Top-N heapsort + INCREMENTAL_SORT

PostgreSQL 8.3 (2008) 引入 `Top-N heapsort`，从此 `ORDER BY ... LIMIT N` 不再溢出磁盘：

```sql
EXPLAIN ANALYZE
SELECT * FROM orders ORDER BY created_at DESC LIMIT 10;
--                                     QUERY PLAN
-- Limit  (cost=...) (actual rows=10 ...)
--   ->  Sort  (cost=...) (actual rows=10 ...)
--         Sort Key: created_at DESC
--         Sort Method: top-N heapsort  Memory: 27kB
--         ->  Seq Scan on orders ...
```

关键点：

- `Sort Method: top-N heapsort` 表明用了优先队列，内存只 27kB（不是几 GB）
- 触发条件：K * row_size <= `work_mem`，否则退回 external merge sort
- 当 ORDER BY 列存在 B-tree 索引时，连排序都省了：

```sql
CREATE INDEX ON orders(created_at DESC);
EXPLAIN SELECT * FROM orders ORDER BY created_at DESC LIMIT 10;
-- Limit
--   ->  Index Scan using orders_created_at_idx on orders
```

PG 13 (2020) 引入 `Incremental Sort`，处理"索引提供前缀有序"但 ORDER BY 列更多的情况：

```sql
-- 索引在 (a)，但 ORDER BY a, b
CREATE INDEX ON t(a);
EXPLAIN SELECT * FROM t ORDER BY a, b LIMIT 10;
-- Limit
--   ->  Incremental Sort
--         Sort Key: a, b
--         Presorted Key: a
--         ->  Index Scan using t_a_idx on t
```

`Incremental Sort` 按 `a` 分批，每批内对 `b` 做小排序，组合 LIMIT 后只读取必要的几个组。在时序场景（按时间索引、按 (时间, 标签) 排序）收益巨大。

### Oracle：STOP KEY 操作

Oracle 没有 LIMIT 关键字，传统上用 `ROWNUM <= N`，12c+ 支持 `FETCH FIRST N ROWS ONLY`。**两种写法在执行计划里都对应 `STOPKEY`**：

```sql
-- 传统 ROWNUM 写法
SELECT * FROM (
    SELECT * FROM orders ORDER BY created_at DESC
) WHERE ROWNUM <= 10;
-- Plan:
-- COUNT STOPKEY
--   VIEW
--     SORT ORDER BY STOPKEY    <-- 关键！
--       TABLE ACCESS FULL ORDERS

-- 12c+ 现代写法
SELECT * FROM orders ORDER BY created_at DESC FETCH FIRST 10 ROWS ONLY;
-- Plan:
-- VIEW
--   WINDOW SORT PUSHED RANK    <-- 注意：用窗口函数实现
--     TABLE ACCESS FULL ORDERS
```

注意 **`FETCH FIRST` 的执行计划是 `WINDOW SORT PUSHED RANK`**，内部用 `ROW_NUMBER()` 实现，与 `ROWNUM` 写法的 `SORT ORDER BY STOPKEY` 不完全一样——大多数情况下两者性能相同，但极少数 corner case 下 ROWNUM 写法更快（已知现象）。带索引时：

```sql
CREATE INDEX ix ON orders(created_at DESC);
SELECT * FROM orders WHERE ROWNUM <= 10 ORDER BY created_at DESC;
-- COUNT STOPKEY
--   INDEX RANGE SCAN DESCENDING ix    <-- 完全无排序
```

### SQL Server：Top N Sort + OPTIMIZE FOR

```sql
SELECT TOP 10 * FROM Orders ORDER BY CreatedAt DESC;
-- 或标准写法：
SELECT * FROM Orders ORDER BY CreatedAt DESC OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

执行计划里出现 `Sort` 算子带 `Top` 属性，或独立的 `Top N Sort` 物理算子（视版本而定）。SQL Server 还提供 `OPTIMIZE FOR` hint 帮助优化器在参数化查询里选择 Top-N 计划：

```sql
SELECT TOP (@n) * FROM Orders ORDER BY CreatedAt DESC
OPTION (OPTIMIZE FOR (@n = 10));
```

### MySQL：filesort with priority queue

MySQL 5.6.2 (2012) 引入 priority queue filesort——**在此之前 MySQL 的 ORDER BY ... LIMIT N 是全排序**。优化触发条件严格：

- LIMIT 必须是常量
- ORDER BY 列总长度 ≤ `sort_buffer_size`
- 没有 `Using temporary`

```sql
EXPLAIN FORMAT=JSON
SELECT * FROM orders ORDER BY created_at DESC LIMIT 10;
-- "ordering_operation": {
--   "using_filesort": true,
--   "filesort_priority_queue_optimization": { "limit": 10, "chosen": true },
--   ...
-- }
```

`filesort_priority_queue_optimization.chosen: true` 是关键标志。配合 ICP（Index Condition Pushdown，5.6+），可以在二级索引扫描的同时把 WHERE 条件下推到存储引擎，进一步减少回表。

### ClickHouse：ORDER BY + LIMIT BY（语义不同！）

ClickHouse 同时有 `ORDER BY ... LIMIT N` 和 `LIMIT N BY column` 两种语法，**它们语义完全不同**：

```sql
-- 普通 Top-10：全局前 10 行
SELECT * FROM events ORDER BY ts DESC LIMIT 10;

-- LIMIT BY：每个 user_id 取前 10 行（per-group Top-N）
SELECT * FROM events
ORDER BY ts DESC
LIMIT 10 BY user_id;

-- 与 LIMIT 组合：每个 user 前 10，整体最多 1000
SELECT * FROM events
ORDER BY ts DESC
LIMIT 10 BY user_id
LIMIT 1000;
```

`LIMIT BY` 是 ClickHouse 独有的、很优雅的 per-group Top-K 语法——对应 PostgreSQL 需要写 `LATERAL JOIN` 或窗口函数。配合 `optimize_read_in_order` 设置（默认开启），当 ORDER BY 列恰好是表的主键时，ClickHouse 直接按 part 顺序流式扫描，遇到 LIMIT 立即停。

### DuckDB：radix partial sort

DuckDB 的 Top-N 用 **radix sort**（基数排序）实现，对数值类型尤其快：

```sql
EXPLAIN SELECT * FROM big ORDER BY x DESC LIMIT 100;
-- TOP_N
--   Top: 100
--   Order: x DESC
--   ...
```

`TOP_N` 算子内部是 K 大小的堆 + 向量化批处理。对于固定大小数值类型，DuckDB 用 radix partition 把数据快速归到 K 大小的桶里，比传统比较排序快 2-5 倍。

### Snowflake：自适应 partial sort

Snowflake 不暴露算子名，但优化器会自动：

1. 用 micro-partition 元数据（min/max）裁剪不可能进入 Top-K 的 partition
2. 在每个 partition 内做 partial sort
3. 全局 merge K 个候选

```sql
SELECT * FROM huge_table ORDER BY ts DESC LIMIT 100;
-- 配置 clustering key (ts) 后，micro-partition 已按 ts 排好
-- 优化器只需读最新的 1-2 个 partition
```

`CLUSTER BY (ts)` 是关键——没有 clustering，Snowflake 仍要扫所有 partition；有 clustering，Top-100 几乎是 O(K)。

## LATERAL + LIMIT 深度剖析：Top-K per group 的经典模式

"每个用户最近 5 个订单"是 OLTP/OLAP 都常见的需求。有四种实现方式：

### 方案 1：窗口函数（最通用，但常常最慢）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts DESC) rn
    FROM orders
) WHERE rn <= 5;
```

问题：必须**对全表分组排序**，即使每组只要前 5。在亿级表上是灾难。

### 方案 2：LATERAL JOIN（最优）

```sql
-- PostgreSQL / Oracle / SQL Server (CROSS APPLY) / DB2 / Snowflake
SELECT u.user_id, o.*
FROM users u
CROSS JOIN LATERAL (
    SELECT * FROM orders
    WHERE orders.user_id = u.user_id
    ORDER BY ts DESC
    LIMIT 5
) o;
```

执行：对每个用户独立做一次 Top-5。配合 `(user_id, ts DESC)` 索引，**每个用户只读 5 行**——总 I/O 是 `users * 5`，而不是 `orders` 全表。在 100 万用户 / 10 亿订单上，性能差异可达 1000 倍以上。

### 方案 3：ClickHouse LIMIT BY

```sql
SELECT * FROM orders
ORDER BY ts DESC
LIMIT 5 BY user_id;
```

CH 独有的语法糖，内部按 user_id 分组流式取前 5，性能与 LATERAL 相当。

### 方案 4：相关子查询（旧式）

```sql
SELECT * FROM orders o1
WHERE (
    SELECT COUNT(*) FROM orders o2
    WHERE o2.user_id = o1.user_id AND o2.ts > o1.ts
) < 5;
```

可读性差、性能差，不推荐，只在不支持窗口函数的旧系统里出现。

### 实测对比（PostgreSQL，1M 用户 × 100M 订单 × `(user_id, ts)` 索引）

| 方案 | 时间 | 备注 |
|------|------|------|
| 窗口函数 ROW_NUMBER | ~120 s | 全表分组排序 |
| LATERAL JOIN | ~0.8 s | 每用户 5 行 index range scan |
| 相关子查询 | 超时 | -- |

差距 ~150x。这就是为什么"LATERAL Top-K"被很多 DBA 称作 PostgreSQL 最被低估的特性。

## Index-Only Top-K 扫描

当 ORDER BY 列上有索引、且 SELECT 列全部包含在索引里时，可以做 **index-only scan**——根本不访问主表。配合 LIMIT N，一次只读 N 条索引项：

```sql
-- PostgreSQL: 覆盖索引 + LIMIT
CREATE INDEX ix ON orders (created_at DESC) INCLUDE (id, amount);

EXPLAIN SELECT id, amount, created_at
FROM orders ORDER BY created_at DESC LIMIT 10;
-- Limit
--   ->  Index Only Scan using ix on orders
--         Heap Fetches: 0     <-- 关键！完全不访问表
```

### WHERE + ORDER BY + LIMIT 的快路径

```sql
-- 索引: (status, created_at DESC)
SELECT * FROM orders
WHERE status = 'paid'
ORDER BY created_at DESC
LIMIT 10;
-- Index Range Scan (status='paid') 已天然按 created_at DESC 有序
-- → 直接读前 10 行，无排序
```

这种"WHERE 等值过滤 + ORDER BY 索引后缀 + LIMIT"是 PostgreSQL/MySQL/Oracle 共同的快路径，被称为 **index for ORDER BY**。它的成立条件是：

1. WHERE 是等值过滤（或范围过滤但 ORDER BY 在范围列后）
2. ORDER BY 列是索引的后续列
3. ORDER BY 方向与索引方向一致（或可反向扫描）

#### PostgreSQL `abs()` / 表达式索引 + LIMIT 的极端例子

```sql
-- 找 0 附近最接近的 10 个值
CREATE INDEX ON measurements (abs(temperature));

SELECT * FROM measurements ORDER BY abs(temperature) LIMIT 10;
-- Index Scan using ... 直接按 abs() 顺序读前 10
```

PostgreSQL 的表达式索引让 Top-K 优化扩展到任意确定性函数——对于地理 KNN（`ORDER BY pt <-> 'POINT(0 0)' LIMIT 10`），借助 GiST/SP-GiST 索引同样适用。

## 关键发现

1. **49/49 引擎都做 Top-N 优化**——这是几乎被业界统一实现的优化。区别只在算子名字、触发阈值和文档暴露程度。完全没有 Top-N 优化的引擎在过去 15 年已经退出主流。

2. **"Top-N 算子"和"索引顺序扫描"是两个独立优化**——前者优化排序，后者完全消除排序。索引顺序扫描更便宜但更"挑剔"（需要正确的索引方向 + 覆盖列）。生产中要让两者**同时**工作才能榨干 Top-K 性能。

3. **PostgreSQL 13 的 Incremental Sort 是过去十年最被低估的 OLAP 优化**——它把 PG 在时序场景的性能拉到了与 ClickHouse 同一档次。Greenplum 7、TimescaleDB、YugabyteDB 都因此受益。其他数据库里只有 ClickHouse 的 `optimize_read_in_order`、Snowflake 的 partial sort、DuckDB 的 radix partial sort 提供等价能力。

4. **MySQL 的 priority queue filesort（5.6.2，2012）来得很晚**——在此之前 MySQL 的 ORDER BY ... LIMIT N 一直在做全排序，是 MySQL 早期被 PostgreSQL 性能碾压的核心原因之一。它至今仍受 `sort_buffer_size` 限制，对宽行不友好。

5. **Oracle `ROWNUM <= N` 比 `FETCH FIRST N ROWS ONLY` 在某些场景下更快**——前者直接产生 `SORT ORDER BY STOPKEY`，后者用 `WINDOW SORT PUSHED RANK`（基于 ROW_NUMBER），偶尔会出现计划差异。从 12c 起两者大多数情况下等价，但老 DBA 仍偏爱 ROWNUM 写法。

6. **ClickHouse 的 `LIMIT BY` 是极其优雅的 per-group Top-K**——其他数据库需要写 LATERAL JOIN 或窗口函数。可惜没有第二个引擎抄这个语法。

7. **LATERAL JOIN 是"每组 Top-K"的圣杯**——PostgreSQL/Oracle/SQL Server/DB2/Snowflake/DuckDB/CockroachDB 等都正确实现。MySQL 8.0.14 才补上 `LATERAL`。**Trino/Presto 至今不支持 LATERAL**——只能用窗口函数代替，性能往往差几十倍。这是 Trino 在 OLTP-style 查询上落后的硬伤之一。

8. **LIMIT 穿透 JOIN 下推是优化器成熟度的试金石**——只有 Trino、Snowflake、DuckDB、Oracle、Vertica、StarRocks、SingleStore 等少数引擎做得比较彻底。Spark Catalyst 在 AQE 之前做不到，3.0+ 才补齐。MySQL/MariaDB 至今不支持。

9. **Skyline 算子（多目标 Top-K）几乎全军覆没**——0/49 主流引擎原生支持 SQL `SKYLINE OF` 语法。这是一个 2001 年提出、学术热门、但工业界未采纳的特性。所有 Skyline 查询都得用 `NOT EXISTS` 自连接模拟，K 大时性能极差。

10. **DuckDB 的 radix partial sort 是 OLAP Top-K 的新方向**——对数值类型比传统比较排序快 2-5 倍。InfluxDB 3.0、DatabendDB 共享 DataFusion 的 `TopK` 算子也走类似路线。预期会有更多新引擎跟进。

11. **覆盖索引（INCLUDE columns）+ Top-K 是 OLTP 高频查询的最后一公里**——PostgreSQL 11+、SQL Server 2005+、MySQL 8.0.13+ 都支持，可以让"分页 + 排序"查询从几百 ms 降到亚毫秒级。

12. **K 不再是常量时，优化通常失效**——`LIMIT @n` 参数化查询或 `LIMIT (subquery)` 在大多数引擎里会**禁用 Top-N 堆**，回退到全排序。SQL Server 的 `OPTIMIZE FOR` 是极少数能在参数化场景下保留 Top-N 的方案。

13. **TOP N + 关联子查询的优化非常脆弱**——只有 PostgreSQL/Oracle/SQL Server/DB2/DuckDB 做得彻底。其他引擎建议手工改写为 LATERAL JOIN 或预先 JOIN + 窗口函数。

14. **流式引擎（Materialize、RisingWave、Flink SQL）的 Top-K 是有状态算子**——它们维护一个增量更新的 K 大小堆，新事件流入时 O(log K) 决定是否替换，可以以毫秒延迟输出"实时 Top-100"。这是流式 SQL 相对批式 SQL 的少数原生优势之一。

15. **不要忘记 `EXPLAIN`**——同一份 SQL 在不同版本、不同 work_mem、不同 index、不同统计信息下 Top-K 的优化路径可能完全不同。在做性能优化前，先看 EXPLAIN 里有没有 `Top-N heapsort` / `STOPKEY` / `Top N Sort` / `partial sort` / `Incremental Sort` / `TopN` / `LIMIT BY` / `Index Only Scan` 这些关键字——它们是 Top-K 路径正确触发的唯一证据。

## 总结对比矩阵

### Top-K 能力总览

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | ClickHouse | DuckDB | Snowflake | Trino | Spark SQL |
|------|-----------|-------|--------|------------|-----------|--------|-----------|-------|-----------|
| Top-N 堆 | 8.3+ | 5.6.2+ | STOPKEY | Top N Sort | 是 | radix | 是 | 是 | TakeOrdered |
| Index 顺序扫描 | 是 | 是 | 是 | 是 | optimize_read_in_order | ART | clustering | 部分 | 部分 |
| Incremental/Partial Sort | 13+ | 否 | 部分 | 部分 | 是 | 是 | 是 | 是 | 部分 |
| LIMIT 子查询下推 | 是 | 5.7+ | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| LIMIT JOIN 下推 | 部分 | 否 | 是 | 部分 | 部分 | 是 | 是 | 是 | AQE |
| LATERAL Top-K | 9.3+ | 8.0.14+ | 12c+ | CROSS APPLY | LIMIT BY | 是 | 是 | 否 | LATERAL VIEW |
| Skyline | 否 | 否 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| 关联子查询 + LIMIT | 是 | 部分 | 是 | 是 | 部分 | 是 | 部分 | 部分 | 部分 |

### 引擎选型建议

| 场景 | 推荐引擎 | 原因 |
|------|---------|------|
| 时序 Top-K（最近 N 条） | TimescaleDB / ClickHouse / QuestDB | 时间索引 + Incremental Sort |
| 每组 Top-K (per-group) | PostgreSQL LATERAL / ClickHouse LIMIT BY | 原生最快路径 |
| 高并发 OLTP Top-10 | PostgreSQL / Oracle / SQL Server + 覆盖索引 | 亚毫秒级 |
| OLAP 大表 Top-100 | Snowflake / DuckDB / ClickHouse | radix/partial sort + clustering |
| 流式实时 Top-N | Materialize / RisingWave / Flink SQL | 有状态增量 Top-K |
| 多维 Skyline | 全部需手写 NOT EXISTS | 没有原生支持 |
| 参数化 LIMIT | SQL Server + OPTIMIZE FOR | 少数能保留 Top-N 计划 |

## 参考资料

- PostgreSQL: [Sort Methods (Top-N heapsort)](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- PostgreSQL: [Incremental Sort (PG 13)](https://www.postgresql.org/docs/13/release-13.html)
- MySQL: [LIMIT Query Optimization](https://dev.mysql.com/doc/refman/8.0/en/limit-optimization.html)
- MySQL: [filesort with priority queue (5.6.2)](https://dev.mysql.com/doc/relnotes/mysql/5.6/en/news-5-6-2.html)
- Oracle: [COUNT STOPKEY / SORT ORDER BY STOPKEY](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/)
- Oracle: [Row Limiting Clause for Top-N Queries](https://oracle-base.com/articles/12c/row-limiting-clause-for-top-n-queries-12cr1)
- SQL Server: [TOP (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql)
- ClickHouse: [LIMIT BY Clause](https://clickhouse.com/docs/en/sql-reference/statements/select/limit-by)
- ClickHouse: [optimize_read_in_order](https://clickhouse.com/docs/en/operations/settings/settings)
- DuckDB: [Top-N optimization](https://duckdb.org/2021/08/27/external-sorting.html)
- Trino: [TopN operator](https://trino.io/docs/current/optimizer.html)
- Snowflake: [Clustering and Partial Sort](https://docs.snowflake.com/en/user-guide/tables-clustering-keys)
- Spark SQL: [TakeOrderedAndProject](https://spark.apache.org/docs/latest/sql-performance-tuning.html)
- Börzsönyi, S., Kossmann, D., Stocker, K. "The Skyline Operator" (ICDE 2001)
- Ilyas, I., Beskales, G., Soliman, M. "A Survey of Top-k Query Processing Techniques" (ACM Computing Surveys, 2008)
