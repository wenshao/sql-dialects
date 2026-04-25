# 并行 DML (Parallel INSERT / UPDATE / DELETE)

一个 1000 万行的 UPDATE 在单线程下跑 40 分钟，换成并行 DML 后只要 90 秒——这不是夸张，而是 Oracle DBA 日常的数字。然而并行 DML 的门槛远高于并行 SELECT：写操作要对付 undo log 的并发分配、redo log 的顺序写入、行锁与 gap 锁的分布式协调、以及最麻烦的幂等性与提交语义。正因如此，即使是 2026 年的今天，仍有大量主流引擎的 UPDATE/DELETE 是严格单线程执行的。

> 姊妹篇：[`parallel-query-execution.md`](./parallel-query-execution.md) 聚焦 SELECT 的 intra-query 并行；本文专门讨论写路径的并行化。

## 为什么并行 DML 比并行 SELECT 难得多

并行 SELECT 本质是把只读扫描切分给多个线程，worker 之间没有共享可变状态，最多需要一个 Gather/Exchange 汇总结果。并行 DML 面临的问题完全不同：

### 1. 写入热点与锁冲突

`UPDATE t SET c = c + 1 WHERE id BETWEEN 1 AND 1000000;` 被拆成 8 个 worker 后：

- 如果按范围切，worker 1 处理 [1, 125000]，worker 2 处理 [125001, 250000]——表面上无冲突，但底层 B+ 树的内部节点、free space map、visibility map 全是共享写入点。
- 如果有 UNIQUE 索引，多个 worker 同时往同一棵二级索引树里插/改条目，叶子页分裂、中间节点锁升级都要协调。
- InnoDB 的 auto-increment 锁、PG 的 HOT update chain、MySQL 的 gap lock 在并发 DML 下语义变得复杂，保证正确性远比串行难。

### 2. Redo Log / WAL 的顺序写

绝大多数 OLTP 引擎的 WAL 必须保持全局顺序（fsync 的粒度、崩溃恢复要求）：

- PostgreSQL 的 WAL 是单一 stream，多个 worker 写入必须竞争 `XLogInsertLock`。
- InnoDB 的 redo log buffer 是全局的，`log_sys.mutex` 曾是著名热点，8.0 才切到 lock-free 设计。
- 即使 worker 本身能并行跑，只要所有写最终走一条 redo pipeline，瓶颈就在那里。

这就是为什么 Oracle 11g+ 要求 redo 日志组分多组、且 PARALLEL DML 下每个 worker 有独立的 Private Strand (Log Buffer)。

### 3. Undo / Rollback 段

MVCC 引擎需要 undo 来实现回滚和一致性读：

- Oracle 需要给每个 DML worker 分配独立的 undo segment（否则 undo header 成热点）。
- PG 的老版本用 heap fork 做 MVCC，没有独立 undo 段，但 autovacuum 要处理的死元组数量会暴涨。
- InnoDB 的 undo 表空间在 8.0 已经拆成独立的 undo tablespaces，但并行 DML 并未因此解锁。

### 4. 原子性与部分回滚

单条 DML 是一个 statement，失败必须整体回滚。Oracle PARALLEL DML 的 worker 崩溃后要求整个 statement 回滚——这引出 "DML Slave Coordinator" 角色，需要分布式事务式的两阶段协调。

### 5. 触发器、约束、外键

- 行级触发器：如果在并行 worker 中触发，触发器内又做 UPDATE，递归并行问题即刻出现。
- 外键检查：子表的 UPDATE 要查父表，父表锁的获取顺序会产生死锁风险。
- CHECK 约束：本身可并行，但错误信息的行号/位置报告在并行下难以精确。

大量引擎因此选择一个简单路径：**DML 永远单线程执行，只把底层的扫描并行化**（比如 DELETE 里的 SELECT 部分并行，但实际的删除操作由 coordinator 串行做）。

## SQL 标准不存在

ANSI/ISO SQL:2023 对并行 DML 没有任何规范。所有的并行 DML 语法——`/*+ PARALLEL */` 提示、`ENABLE PARALLEL DML` session 开关、`max_parallel_workers` 配置——都是各引擎自行设计的。甚至"并行 DML"一词本身，在 Oracle 文档里特指 `INSERT ... SELECT` / `UPDATE` / `DELETE` / `MERGE` 的 slave 执行，而在 SQL Server 里叫 "Parallel Data Modification"，在 PostgreSQL 里统称 "Parallel Write"，在 Spark 里则是 "Parallel File Write"——术语本身就缺乏共识。

这也意味着应用代码很难做到"写一次到处跑"——并行 DML 的提示语法、session 开关、甚至是否支持某种 DML 的并行，都高度依赖引擎。

## 支持矩阵（45+）

### 并行 INSERT (SELECT-based)

即 `INSERT INTO t SELECT ... FROM ...`，下层 SELECT 是否并行，以及 INSERT 本身是否多 worker 并行写入。

| 引擎 | 下层 SELECT 并行 | 并行插入 | 需要提示/开关 | 版本 |
|------|----------------|---------|--------------|------|
| Oracle | 是 | 是 | `ALTER SESSION ENABLE PARALLEL DML` + `/*+ PARALLEL */` | 7.3 (INSERT SELECT, 1996) / 8i (UPDATE/DELETE, 1999) |
| SQL Server | 是 | 是 (batch mode / CCI) | 自动，MAXDOP>1 | 2016+ |
| PostgreSQL | 是 | 是 | 自动（`max_parallel_workers_per_gather`） | 14 (2021) |
| MySQL (InnoDB) | 仅主键扫描 | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | 不支持 |
| DB2 LUW | 是 | 是 | `INTRA_PARALLEL` | 早期 |
| Snowflake | 是 | 是（自动并行） | 自动 | GA |
| BigQuery | 是 | 是（slot 分配） | 自动 | GA |
| Redshift | 是 | 是（slice 并行） | 自动 | GA |
| DuckDB | 是 | 是（morsel-driven） | 自动 | 0.7+ |
| ClickHouse | 是 | 是（按 block 并行写入） | `max_insert_threads` | 20.x+ |
| Trino | 是 | 是（connector 支持） | 自动 | GA |
| Presto | 是 | 是 | 自动 | GA |
| Spark SQL | 是 | 是（partition 并行写文件） | 自动 | 早期 |
| Hive | 是 | 是（mapper 并行） | 自动 | 早期 |
| Flink SQL | 是 | 是（sink 并行度） | 自动 | GA |
| Databricks (Photon) | 是 | 是 | 自动 | GA |
| Teradata | 是 | 是（AMP 并行） | 自动 | V2 早期 |
| Greenplum | 是 | 是（segment 并行） | 自动 | 早期 |
| CockroachDB | 是 (DistSQL) | 部分（批量插入） | 自动 | 19.x+ |
| TiDB | 是 | 是 (region 并行) | `tidb_dml_type = 'bulk'` (7.5+) | 7.5+ |
| OceanBase | 是 | 是 (PX 框架) | `ENABLE_PARALLEL_DML` | 2.x+ |
| YugabyteDB | 是 | 部分 (batched nested loop) | 自动 | 2.14+ |
| SingleStore | 是 | 是（partition 并行） | 自动 | 早期 |
| Vertica | 是 | 是（节点并行） | 自动 | 早期 |
| Impala | 是 | 是 (INSERT INTO / CTAS) | 自动 | 早期 |
| StarRocks | 是 | 是 (pipeline) | 自动 | 2.0+ |
| Doris | 是 | 是 (pipeline) | 自动 | 1.2+ |
| MonetDB | 是 | 有限 | -- | 早期 |
| CrateDB | 是 | 是（shard 并行） | 自动 | GA |
| TimescaleDB | 是 | 是 (chunk 并行写) | 继承 PG | PG14+ |
| QuestDB | -- | 单写入线程 | -- | 不支持 |
| Exasol | 是 | 是 | 自动 | 早期 |
| SAP HANA | 是 | 是 | 自动 | 早期 |
| Informix | 是 (PDQ) | 是 | `PDQPRIORITY` | 早期 |
| Firebird | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | 是 (继承 Trino) | CTAS/INSERT 并行 | 自动 | GA |
| Azure Synapse | 是 | 是 (distribution 并行) | 自动 | GA |
| Google Spanner | -- | 单线程 DML（Partitioned DML 例外） | `PARTITIONED UPDATE/DELETE` | GA |
| Materialize | 流式 | 不适用（流增量更新） | -- | 不适用 |
| RisingWave | 流式 | 不适用 | -- | 不适用 |
| DatabendDB | 是 | 是 | 自动 | GA |
| Yellowbrick | 是 | 是（MPP） | 自动 | GA |
| Firebolt | 是 | 是 | 自动 | GA |

### 并行 UPDATE

这是最难的一类——必须对现有行做就地修改，涉及行锁、索引维护、undo。

| 引擎 | 并行 UPDATE | 限制 | 版本 |
|------|------------|------|------|
| Oracle | 是 | 需 `ENABLE PARALLEL DML`；部分分区/全局索引限制 | 8i (1999) |
| SQL Server | 部分 | 计划并行，但实际写入序列化（少数 CCI 场景例外） | -- |
| PostgreSQL | -- | UPDATE/DELETE 本身**不并行**，仅下层 SELECT 部分可并行 | 不支持 |
| MySQL (InnoDB) | -- | -- | 不支持 |
| MariaDB | -- | -- | 不支持 |
| SQLite | -- | -- | 不支持 |
| DB2 LUW | 是 | `INTRA_PARALLEL=YES` | 早期 |
| Snowflake | 是 | 自动并行（但底层是 micro-partition 重写） | GA |
| BigQuery | 是 | DML 按 slot 并行，每天有配额限制 | GA |
| Redshift | 是 | slice 并行 | GA |
| DuckDB | 是 | 扫描并行，写入 vector-at-a-time | 0.9+ |
| ClickHouse | mutation | `ALTER TABLE ... UPDATE` 异步 mutation，按 part 并行 | 早期 |
| Trino / Presto | 连接器相关 | Iceberg/Delta connector 支持，行存通常不支持 | GA |
| Spark SQL | 依赖格式 | Delta Lake / Iceberg 支持，Hive 格式重写分区 | 早期 |
| Flink SQL | 流更新 | upsert sink 按 key 并行 | GA |
| Databricks (Photon) | 是 | Delta Lake 下重写受影响文件 | GA |
| Teradata | 是 | AMP 并行 | V2 早期 |
| Greenplum | 是 | segment 并行 | 早期 |
| CockroachDB | 是 (DistSQL) | 跨节点并行，但每行 2PC 代价 | 19.x+ |
| TiDB | 有限 | `tidb_dml_type = 'bulk'` 下批量写入；默认仍走两阶段单协调 | 7.5+ |
| OceanBase | 是 | PX 框架（Oracle 模式接近原生 PARALLEL DML） | 2.x+ |
| YugabyteDB | 有限 | 仅在 batched nested loop 下提升 | 2.14+ |
| SingleStore | 是 | partition 并行 | 早期 |
| Vertica | 是 | 节点并行；UPDATE 实际是 delete+insert | 早期 |
| Impala | -- | UPDATE 仅 Kudu/Iceberg 表支持 | 早期 |
| StarRocks | 主键模型 | 主键模型并行更新；明细模型不支持 UPDATE | 2.3+ |
| Doris | 主键模型 | Unique key 表并行更新 | 1.2+ |
| MonetDB | 有限 | -- | 早期 |
| CrateDB | 是 | shard 并行 | GA |
| TimescaleDB | 是 (chunk) | 每个 chunk 独立 UPDATE | 继承 PG |
| QuestDB | -- | UPDATE 受限 | -- |
| Exasol | 是 | 自动并行 | 早期 |
| SAP HANA | 是 | 自动并行 | 早期 |
| Informix | 是 | PDQ | 早期 |
| Azure Synapse | 是 | distribution 并行 | GA |
| Google Spanner | `PARTITIONED UPDATE` | 需显式切为 Partitioned DML，幂等要求严 | GA |

### 并行 DELETE

| 引擎 | 并行 DELETE | 限制 | 版本 |
|------|------------|------|------|
| Oracle | 是 | 同 UPDATE；分区表效果最佳 | 9i |
| SQL Server | 部分 | 计划并行，写入序列化 | -- |
| PostgreSQL | -- | 仅下层 SELECT 并行 | 不支持 |
| MySQL (InnoDB) | -- | -- | 不支持 |
| DB2 LUW | 是 | -- | 早期 |
| Snowflake | 是 | micro-partition 重写 | GA |
| BigQuery | 是 | 受 DML 配额限制 | GA |
| Redshift | 是 | slice 并行 | GA |
| DuckDB | 是 | 并行扫描 + 删除 | 0.9+ |
| ClickHouse | 是 | lightweight delete (22.8+) 并行执行 mutation | 22.8+ |
| Trino / Presto | 连接器相关 | Iceberg / Delta 支持 | GA |
| Spark SQL | 依赖格式 | Delta / Iceberg / Hudi 支持 | 早期 |
| Databricks (Photon) | 是 | Delta Lake 并行删除 | GA |
| Teradata | 是 | AMP 并行 | V2 早期 |
| Greenplum | 是 | segment 并行 | 早期 |
| CockroachDB | 是 (DistSQL) | 跨节点并行 | 19.x+ |
| TiDB | 有限 | `tidb_dml_type = 'bulk'` 下批量；大表 DELETE 常需手工分批 | 7.5+ |
| OceanBase | 是 | PX 框架 | 2.x+ |
| SingleStore | 是 | partition 并行 | 早期 |
| Vertica | 是 | DELETE 标记，后台合并 | 早期 |
| Impala | Kudu/Iceberg | 明细表不支持 DELETE | 早期 |
| StarRocks | 主键模型 | 明细模型不支持 DELETE，仅 Unique key | 2.3+ |
| Doris | 主键模型 | Unique key 表 | 1.2+ |
| TimescaleDB | 是 (chunk) | 按 chunk 并行 drop 更快 | 继承 PG |
| Exasol | 是 | 自动 | 早期 |
| SAP HANA | 是 | 自动 | 早期 |
| Azure Synapse | 是 | distribution 并行 | GA |
| Google Spanner | `PARTITIONED DELETE` | 必须是 Partitioned DML | GA |

### 并行 CREATE TABLE AS SELECT (CTAS)

CTAS 是最容易并行的 DML——新表没有旧数据，不涉及锁冲突，很多引擎即使不支持并行 UPDATE/DELETE 也支持并行 CTAS。

| 引擎 | 并行 CTAS | 版本 |
|------|----------|------|
| Oracle | 是 | 9i |
| SQL Server | 是 (SELECT INTO 并行度提升) | 2014+ (Azure SQL DW) |
| PostgreSQL | 是 | 11 (2018) |
| MySQL | -- | 不支持 |
| MariaDB | -- | 不支持 |
| DB2 LUW | 是 | 早期 |
| Snowflake | 是 | GA |
| BigQuery | 是 | GA |
| Redshift | 是 | GA |
| DuckDB | 是 | 早期 |
| ClickHouse | 是 | 早期 |
| Trino / Presto | 是 | GA |
| Spark SQL | 是 (RTAS 也支持) | 早期 |
| Hive | 是 | 早期 |
| Flink SQL | 是 | GA |
| Databricks | 是 | GA |
| Teradata | 是 | V2 早期 |
| Greenplum | 是 | 早期 |
| CockroachDB | 是 | 19.2+ |
| TiDB | 是 | 4.0+ |
| OceanBase | 是 | 2.x+ |
| YugabyteDB | 继承 PG | 2.0+ |
| SingleStore | 是 | 早期 |
| Vertica | 是 | 早期 |
| Impala | 是 | 早期 |
| StarRocks | 是 | 2.0+ |
| Doris | 是 | 1.2+ |
| SAP HANA | 是 | 早期 |
| Azure Synapse | 是 | GA |
| Amazon Athena | 是 (Iceberg) | GA |

### 并行 DML 提示 / 开关语法

| 引擎 | 语法 |
|------|------|
| Oracle | `ALTER SESSION ENABLE PARALLEL DML;` + `INSERT /*+ PARALLEL(t, 8) */ ...` |
| Oracle | `ALTER TABLE t PARALLEL 8;` (表级默认) |
| SQL Server | `UPDATE t WITH (TABLOCK) SET ... OPTION (MAXDOP 8)` |
| SQL Server | `INSERT INTO t WITH (TABLOCK) SELECT ... OPTION (MAXDOP 8)` |
| PostgreSQL | `SET max_parallel_workers_per_gather = 4;` (会话) |
| PostgreSQL | `ALTER TABLE t SET (parallel_workers = 4);` (表级) |
| DB2 | `SET CURRENT DEGREE = 'ANY';` |
| Snowflake | 无显式 hint，按 warehouse 大小自动 |
| BigQuery | 无显式 hint，按 slot 自动 |
| Redshift | `SET wlm_query_slot_count = N;` |
| ClickHouse | `SET max_insert_threads = 8;` `SET parallel_distributed_insert_select = 1;` |
| Trino | `SET SESSION task_writer_count = 4;` `SET SESSION task_partitioned_writer_count = 8;` |
| Spark SQL | `SET spark.sql.shuffle.partitions = 200;` |
| Teradata | 通过 PDL (Parallel Data Language) 或默认 AMP 并行 |
| Greenplum | `SET gp_autostats_mode = on_change;` (隐式) |
| TiDB | `SET tidb_dml_type = 'bulk';` (7.5+) |
| OceanBase | `SET ob_parallel_max_servers = 16;` + `/*+ PARALLEL(8) ENABLE_PARALLEL_DML */` |
| SingleStore | 自动，按 partition 并行 |
| Vertica | 自动，按节点并行 |
| Informix | `SET PDQPRIORITY HIGH;` |

## 各引擎深入

### Oracle（并行 DML 的事实标准）

Oracle 7.1 (1994) 引入 Parallel Query Option (PQO)；7.3 (1996) 支持 parallel INSERT ... SELECT；8i (1999) 引入 parallel UPDATE/DELETE；9i (2001) 进一步成熟，支持分区级 DML。关键特点：

1. **必须显式开启 session 开关**：`ALTER SESSION ENABLE PARALLEL DML;`（默认 DISABLED，防误用）
2. **PARALLEL 提示 or 表级属性**：`/*+ PARALLEL(t, 8) */` 或 `ALTER TABLE t PARALLEL 8;`
3. **按 ROWID 范围切分**：Query Coordinator 把表按 block range（或分区）切成 N 份分给 PX slaves
4. **每个 slave 有独立 undo segment 和 private redo strand**
5. **提交语义特殊**：并行 DML 语句结束时，所有 PX slave 必须先提交各自的私有事务；整个语句作为一个分布式事务。这意味着并行 DML 之后**必须 COMMIT 或 ROLLBACK**，才能在同一会话里对同一张表再做任何操作（包括 SELECT）。

```sql
-- 必须第一步
ALTER SESSION ENABLE PARALLEL DML;

-- 并行 INSERT SELECT
INSERT /*+ PARALLEL(sales_2026, 16) APPEND */
INTO sales_2026
SELECT /*+ PARALLEL(sales_raw, 16) */ *
FROM sales_raw
WHERE order_date >= DATE '2026-01-01';

COMMIT;  -- 必须提交才能继续操作 sales_2026

-- 并行 UPDATE（分区表上效果最佳）
UPDATE /*+ PARALLEL(orders, 8) */ orders
SET status = 'archived'
WHERE order_date < ADD_MONTHS(SYSDATE, -24);

COMMIT;

-- 并行 DELETE
DELETE /*+ PARALLEL(log_events, 12) */ FROM log_events
WHERE event_time < SYSDATE - 365;

COMMIT;
```

Oracle 的 APPEND 提示与并行 DML 的组合是 ETL 黄金搭档：

- 直接路径写入（direct-path insert），绕过 buffer cache
- 在高水位线之上分配空间，不复用已删除的 block
- 每个 slave 在自己的私有 extent 中工作，最后高水位线一次性推进
- 配合 `NOLOGGING` 可以跳过 redo（代价是不能恢复，需要再做备份）

#### 多表 INSERT（Multi-Table INSERT）

Oracle 独有的 `INSERT ALL` / `INSERT FIRST` 也可以并行：

```sql
ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ PARALLEL(8) */ ALL
  WHEN amount > 10000 THEN INTO large_orders VALUES (id, amount, dt)
  WHEN amount > 1000  THEN INTO medium_orders VALUES (id, amount, dt)
  ELSE                     INTO small_orders  VALUES (id, amount, dt)
SELECT id, amount, order_date AS dt FROM orders_staging;

COMMIT;
```

每条目标表都由自己的 slave 集合处理，源表扫描也并行。

#### PARALLEL DML 的限制

- 有触发器的表：PARALLEL DML 被降级为串行（12c 起部分放宽）
- 外键引用自身的表：自引用 FK 会导致串行
- 分布式事务中：DBLINK 写入通常不并行
- LOB 列：LOB 的并行写入受限
- 小表：优化器会忽略 PARALLEL 提示（`PARALLEL_MIN_ROWS_PCT` 控制）

### SQL Server（2016 引入批量模式并行 INSERT）

SQL Server 的并行 DML 历史是"SELECT 早已并行，DML 长期单写入线程"。关键节点：

1. **2000 ~ 2014**：SELECT 部分并行，但 UPDATE/DELETE/INSERT 的写入算子串行
2. **2014 (Azure SQL DW)**：引入 Columnstore 批量模式并行 INSERT
3. **2016**：box product 也支持 batch mode on columnstore index，`INSERT ... SELECT` 可并行写入
4. **2019**：batch mode on rowstore 引入——不再强制要求 CCI 就能用向量化并行

```sql
-- 确保走批量模式并行插入：
-- 1) 目标表有 CCI (Clustered Columnstore Index) 或开启 batch mode on rowstore
-- 2) TABLOCK 提示允许并行插入
-- 3) MAXDOP > 1
INSERT INTO dbo.fact_sales WITH (TABLOCK)
SELECT * FROM dbo.sales_staging
OPTION (MAXDOP 8);

-- UPDATE 并行：计划会显示并行（Parallelism 算子），但最终 Clustered Index Update 是序列化的
-- 真正的并行 UPDATE 需要分区切换 + TABLOCK
UPDATE dbo.orders WITH (TABLOCK)
SET status = 'closed'
WHERE order_date < DATEADD(year, -2, GETDATE())
OPTION (MAXDOP 8);
```

#### SQL Server 的行存 vs 列存

- **行存 rowstore 表**：`INSERT INTO ... WITH (TABLOCK)` 可并行，但只有一个 worker 做 heap 分配，其他 worker 把数据送过去
- **列存 CCI**：每个 worker 独立构建 rowgroup（1,048,576 行），真正并行写入
- `sys.dm_exec_query_stats` 中的 `total_dop` 和 `degree_of_parallelism` 用来观察

#### Intelligent Query Processing (IQP) / Adaptive Joins

SQL Server 2019+ 在并行 DML 场景中加入自适应：运行时如果发现基数估计偏差大，会动态调整 worker 数量。但这主要针对 SELECT 部分。

### PostgreSQL（循序渐进的并行化）

PG 的并行能力是一步一步加的：

| 版本 | 年份 | 并行能力 |
|------|------|---------|
| 9.6 | 2016 | 并行 Seq Scan、并行 Hash Join、并行聚合（部分） |
| 10 | 2017 | 并行 Index Scan、并行 Bitmap Heap Scan、并行 Merge Join |
| 11 | 2018 | **并行 CREATE TABLE AS / CREATE MATERIALIZED VIEW / SELECT INTO**、并行 Hash Join build、并行 B-tree index build |
| 12 | 2019 | 并行化改进（不是新语句） |
| 13 | 2020 | 并行 VACUUM（针对索引） |
| 14 | 2021 | **并行 INSERT ... SELECT**（里程碑！） |
| 15 | 2022 | -- |
| 16 | 2023 | 并行 string aggregation、并行 array aggregation |
| 17 | 2024 | 并行 bitmap heap scan 优化 |

PG 15/16/17 仍然**没有并行 UPDATE 和并行 DELETE**——这是社区的已知限制。核心原因是 PG 的行更新需要锁 tuple、更新 HOT chain、维护 visibility map，在并行 worker 之间协调这些极其复杂。

```sql
-- PG 11+ 并行 CTAS
SET max_parallel_workers_per_gather = 8;

CREATE TABLE sales_2026 AS
SELECT * FROM sales_raw WHERE order_year = 2026;
-- EXPLAIN 会显示 Gather -> Parallel Seq Scan

-- PG 14+ 并行 INSERT ... SELECT
INSERT INTO fact_sales
SELECT * FROM staging.sales_raw WHERE order_year = 2026;
-- 默认自动并行（受 max_parallel_workers_per_gather 限制）

-- 显式要求目标表支持并行
ALTER TABLE fact_sales SET (parallel_workers = 8);

-- 但 UPDATE/DELETE 的下层 SELECT 可以并行，写入还是串行
UPDATE orders SET processed = TRUE
WHERE order_date = CURRENT_DATE - 1;
-- 下层 Parallel Seq Scan 可能并行，ModifyTable 算子串行
```

#### PG 14 并行 INSERT SELECT 深入

PG 14 的关键 commit（2021-03，Greg Nancarrow、Amit Kapila）让 `INSERT INTO ... SELECT` 能在满足以下条件时并行：

1. 目标表不是分区的（14 里还不支持分区表并行插入，15/16 有改进但仍受限）
2. 目标表没有 FOREIGN KEY（14 限制）
3. 目标表没有非并行安全的索引表达式或约束
4. 目标表没有 AFTER ROW 触发器
5. `max_parallel_workers_per_gather > 0` 且表级 `parallel_workers` 允许

实现上，并行 worker 各自执行 `INSERT` 的 tuple 组装和 heap insert，每个 worker 使用自己的 xmin/cmax，但共享同一个顶层 XID（父事务 ID）。WAL 写入仍通过中心的 `XLogInsertLock`，所以在 WAL flush 密集的工作负载下，瓶颈容易出现在 WAL。

```sql
-- 观察并行 INSERT 的执行计划
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
INSERT INTO target_table
SELECT * FROM source_table WHERE x > 1000;

-- 典型输出：
--  Gather  (cost=... rows=...)
--    Workers Planned: 4
--    Workers Launched: 4
--    ->  Parallel Seq Scan on source_table
--  Insert on target_table
```

注意 PG 把 `Gather` 放在 `Insert` **下面**——这是 PG 14 的关键设计，每个 worker 单独跑 scan，但所有 worker 在一个共享的 `Insert` 算子里协作写入，避免多个 INSERT 节点各自提交带来的可见性混乱。

#### PG 的并行限制总结

- **并行 UPDATE/DELETE**：仍未实现（17 也没有）
- **并行 INSERT 分区表**：16 才有限支持，仍有较多 corner case
- **并行 COPY**：到 16 才有 `COPY FROM` 并行（单文件拆分给 worker）
- **foreign table**：postgres_fdw 14 起支持部分并行 INSERT，但不是单表并行而是跨表并行

### MySQL / MariaDB（并行 DML 基本缺席）

MySQL 的并行能力极其有限：

- **8.0.14 (2019)**：仅 `SELECT COUNT(*) FROM t`（并行主键扫描）可多线程
- **8.0.x 后续**：小幅扩展到 check table 等 utility
- **并行 DML**：InnoDB 到 MySQL 9.0 也**没有**并行 INSERT/UPDATE/DELETE

MySQL 的单线程 DML 哲学来自其 OLTP 基因：每个连接一个线程，连接多时天然并行，单 SQL 不需要用多线程。这在批量 ETL 场景下成为致命短板：

```sql
-- MySQL 唯一一种"并行"：并行主键扫描做 COUNT
SELECT COUNT(*) FROM large_table;
-- 8.0.14+ InnoDB 会用多个线程扫不同主键范围，汇总结果

-- 但这只对 COUNT 有效，UPDATE 仍单线程：
UPDATE large_table SET col = col + 1 WHERE id BETWEEN 1 AND 10000000;
-- 单线程，1 亿行可能跑数小时
```

MariaDB 有 parallel replication 但没有 parallel query/DML。

实务中，MySQL 的批量 UPDATE/DELETE 解决方案只能手工切分：

```sql
-- 应用层手工并行：多连接各自 UPDATE 一段
-- 连接 1
UPDATE orders SET status = 'archived' WHERE id BETWEEN 1 AND 1000000;
-- 连接 2
UPDATE orders SET status = 'archived' WHERE id BETWEEN 1000001 AND 2000000;
-- ... 8 个连接并行
```

### Snowflake（自动并行 DML）

Snowflake 的 virtual warehouse 天然按 micro-partition 并行：

- 一个 warehouse 由 N 个 server 组成（X-Small=1, Small=2, Medium=4, ..., 6X-Large=512）
- 每个 server 内部还有多线程
- INSERT / UPDATE / DELETE / MERGE 都自动并行，用户无需任何 hint

```sql
-- 只要 warehouse 足够大，SQL 就自动并行
USE WAREHOUSE BIG_WH;  -- 16 servers * 8 cores = 128 并发

INSERT INTO fact_sales
SELECT * FROM staging.raw_sales WHERE load_date = CURRENT_DATE();

UPDATE fact_sales SET region = 'APAC'
WHERE country IN ('CN', 'JP', 'KR', 'SG', 'IN');
```

底层实现：每个 micro-partition (16MB 压缩，约 50-500 MB 未压缩) 是一个可并行单元。UPDATE 实际是 "rewrite affected micro-partitions"——Snowflake 是真正的 copy-on-write 存储，受影响的 micro-partition 被整体重写，旧的作为 time-travel 保留。

这也解释了为什么 Snowflake 的 UPDATE 可以完全并行：每个 worker 重写自己负责的一批 micro-partitions，无锁、无 undo、无 redo 协调问题。

### BigQuery（slot 调度的自动并行）

BigQuery 的 DML 也自动并行，但有重要限制：

- 每张表每天最多 1500 次 DML 语句（长期限制，到 2024 才放宽到 ~ unlimited 但仍有成本）
- Streaming insert 不受此限（通过 Storage Write API）
- 每张表每秒最多 5 次并发 UPDATE/DELETE/MERGE

```sql
-- BigQuery 并行 INSERT SELECT（全自动）
INSERT INTO `project.dataset.fact_sales`
SELECT * FROM `project.dataset.staging_sales`
WHERE PARTITION_DATE = CURRENT_DATE();

-- 并行 UPDATE（按 partitioned slot 分配）
UPDATE `project.dataset.orders`
SET status = 'closed'
WHERE order_date < DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY);
```

BigQuery 的 DML 底层用 Capacitor 列存格式，每次 DML 生成新的 column file，后台 compact 合并。这种 append-only 式的存储让并行 DML 在理论上很自然——但同一行的多次 DML 冲突时会出错（需要 `MERGE` 或重试）。

### Spark（自然并行，但要看目标格式）

Spark SQL 天然按 RDD partition 并行写入。INSERT 的并行度等于目标表的 partition 数（或 `spark.sql.shuffle.partitions`）：

```sql
-- Spark 写 Parquet / ORC / Delta / Iceberg 都天然并行
INSERT OVERWRITE TABLE fact_sales
SELECT * FROM staging_sales WHERE load_date = '2026-04-23';

-- Delta Lake 支持 UPDATE / DELETE / MERGE（并行）
UPDATE delta.`/path/to/orders`
SET status = 'closed'
WHERE order_date < '2024-04-23';

DELETE FROM delta.`/path/to/log_events`
WHERE event_time < '2025-04-23';

-- Hive 格式（ORC/Parquet 不在 Delta/Iceberg/Hudi 中）不支持 UPDATE/DELETE
-- 必须重写分区：
INSERT OVERWRITE TABLE orders PARTITION(dt='2026-04-23')
SELECT *, CASE WHEN status = 'pending' THEN 'closed' ELSE status END
FROM orders WHERE dt = '2026-04-23';
```

Spark 的并行度调优：`spark.sql.shuffle.partitions` 默认 200，通常随数据量调到 N*CPU 左右。

### ClickHouse（块级并行插入 + mutation）

ClickHouse 的并行 DML 与其 LSM-like 架构深度绑定：

- **INSERT**：每批 INSERT 生成一个独立 part（目录），多个 INSERT 可完全并发，后台 merge 合并
- **UPDATE / DELETE**：称为 "mutation"，是**异步的、重写整个 part 的操作**
- **Lightweight DELETE** (22.8+)：立即生效的删除标记，后台实际清理

```sql
-- 并行 INSERT（每个线程独立 part）
SET max_insert_threads = 16;
INSERT INTO events SELECT * FROM source_events;

-- 异步 UPDATE (mutation)
ALTER TABLE events UPDATE level = 'info' WHERE level IS NULL;
-- 返回极快，但后台 merge worker 才真正执行

-- Lightweight DELETE (22.8+)
DELETE FROM events WHERE event_time < '2025-01-01';
-- 标记为删除，立即对查询生效；后台 merge 清理

-- 检查 mutation 进度
SELECT * FROM system.mutations WHERE is_done = 0;
```

ClickHouse 的 `max_insert_threads` 控制 INSERT SELECT 时插入端的并行度。由于 ClickHouse 按 part 粒度存储，每个 part 的写入是独立文件组，并行度可以开得很高。

副本间的并行：对 ReplicatedMergeTree，`parallel_distributed_insert_select` 让 INSERT ... SELECT 在每个 shard 上本地执行（而不是所有数据 shuffle 到 initiator 节点）。

### TiDB（7.5 引入批量 DML 模式）

TiDB 5.0 引入 MPP 并行 SELECT（基于 TiFlash 列存），但 DML 长期是"两阶段提交单协调节点"模型。7.5（2023 底）引入关键开关：

```sql
-- 7.5+ 批量 DML 模式
SET tidb_dml_type = 'bulk';

-- 启用后，大表 UPDATE/DELETE 按 region 并行执行
UPDATE orders SET status = 'archived' WHERE order_date < '2024-04-23';
```

- `tidb_dml_type = 'standard'` (默认)：单协调节点，两阶段提交
- `tidb_dml_type = 'bulk'`：按 region 分片并行，每个 region 的数据在对应 TiKV 节点上本地写入
- `tidb_dml_type = 'bulk'` 的取舍：不保证语句级 ACID（事务内可能部分成功部分失败，需要应用层处理）

TiDB 的并行 INSERT 早在 4.x 就通过 region 分片天然并行（INSERT 只要 key 分布在不同 region，就会送到不同 TiKV 节点）。瓶颈主要在客户端连接和 SQL 层的事务协调。

### OceanBase（PX 框架 + Oracle 模式兼容）

OceanBase 的并行执行框架（PX，Parallel eXecution）直接对标 Oracle：

```sql
-- Oracle 模式下可以用 Oracle 的 hint
INSERT /*+ PARALLEL(t, 16) ENABLE_PARALLEL_DML */ INTO t
SELECT /*+ PARALLEL(s, 16) */ * FROM s;

-- MySQL 模式
SET ob_parallel_max_servers = 16;
SET _enable_parallel_dml = 1;
INSERT INTO t SELECT * FROM s;
```

分布式版本（OceanBase 社区版/企业版 4.x）还额外有"跨节点并行"：PX 可以调度多个 zone/unit 上的线程并行执行 DML。

### CockroachDB（DistSQL 天然并行）

CockroachDB 的 DistSQL（Distributed SQL）把所有查询（包括 DML）都表达为一个 flow graph，每个节点是一个 processor：

- 大部分 INSERT/UPDATE/DELETE 会被 DistSQL 拆解
- 按 range（CockroachDB 的分片单位，默认 512MB）并行
- 每行需要走 Raft 一致性协议，所以并行的收益主要在 CPU 侧，而不是 I/O 侧

```sql
-- Cockroach 自动并行
UPDATE orders SET status = 'closed'
WHERE order_date < now() - INTERVAL '2 years';

-- 查看执行计划
EXPLAIN (DISTSQL, VEC)
UPDATE orders SET status = 'closed' WHERE ...;
```

注意 Cockroach 对大 UPDATE/DELETE 有建议的模式：使用 `BATCH UPDATE` / chunked delete 模式，避免单事务过大：

```sql
-- 推荐：分批 DELETE（事务小）
DELETE FROM orders
WHERE order_date < '2024-01-01'
LIMIT 1000
RETURNING id;
-- 循环直到 0 行
```

### Greenplum / Vertica（MPP 原生并行）

这两个 MPP 引擎从设计第一天就是并行的：

- **Greenplum**：segment（每节点多个）并行，coordinator (master) 只做分发
- **Vertica**：节点并行，每节点内部 ROS/WOS 并行

```sql
-- Greenplum：天然并行，无 hint
INSERT INTO fact_sales
SELECT * FROM ext.raw_sales;
-- 每个 segment 并行处理各自分片

-- Vertica
DELETE FROM events WHERE event_time < '2025-04-23';
-- 每个节点并行标记删除，后台 Tuple Mover 合并
```

Vertica 的 UPDATE/DELETE 实际上是 "add delete vector entry"，与 Snowflake 类似；真正的数据清理由后台 merge 完成。

### Flink SQL / Materialize / RisingWave（流式不适用）

流处理引擎没有传统意义的 UPDATE/DELETE——它们用 changelog 表达更新：

- `INSERT` 对应 `+I` (insert)
- `UPDATE` 对应 `-U` / `+U` 或 upsert
- `DELETE` 对应 `-D`

Sink 的并行度决定写入 speedometer：

```sql
-- Flink SQL：sink 并行度由 PARALLELISM 决定
CREATE TABLE kafka_sink (...) WITH (
    'connector' = 'upsert-kafka',
    'sink.parallelism' = '16'
);
INSERT INTO kafka_sink SELECT ...;
```

### Google Spanner（Partitioned DML）

Spanner 默认的 DML 是单事务执行（全局强一致，跨 tablet 两阶段提交成本很高）。要做大表 UPDATE/DELETE，必须显式用 Partitioned DML：

```sql
-- 普通 DML（受事务行数限制，约 2 万行）
UPDATE orders SET status = 'closed' WHERE id = 123;

-- Partitioned DML（可处理数亿行，但要求幂等）
PARTITIONED UPDATE orders
SET status = 'closed'
WHERE order_date < DATE '2024-04-23';

PARTITIONED DELETE FROM log_events
WHERE event_time < TIMESTAMP '2025-04-23T00:00:00Z';
```

Partitioned DML 要求：

1. **幂等**：语句多次执行结果相同（因为 Spanner 可能重试某个 partition）
2. **全表可分区**：WHERE 条件可按 partition key 切分
3. **不支持 JOIN / 子查询**
4. **每个 partition 独立事务**：不保证语句整体原子性

## Oracle PARALLEL DML 深度剖析

Oracle 的 PARALLEL DML 是所有引擎中最成熟、设计最完整的一套，值得单独深入。

### 开关为什么必须显式

`ALTER SESSION ENABLE PARALLEL DML` 是 Oracle 的一个"大开关"——它不是性能提示，而是语义开关。启用后：

1. 该 session 内所有后续 DML 都**有资格**并行（是否真的并行还要看提示和表设置）
2. 并行执行后，**直到下一次 COMMIT/ROLLBACK**，这张表不能被同一 session 再次访问（包括 SELECT）
3. PX slaves 之间用分布式事务语义协调

不默认开启的原因：防止意外的并行 DML 破坏批处理脚本的一致性假设（例如 INSERT 完立刻 SELECT 验证，在 PARALLEL DML 下会报 ORA-12838）。

### DML slave 的工作模型

```
    Query Coordinator (QC)
        |
        v
  +-----+-----+-----+
  |     |     |     |
 PX1   PX2   PX3   PX4     <- parallel slaves
  |     |     |     |
  v     v     v     v
 ROWID range A..D of partitioned heap
```

- QC 解析 SQL，决定 DOP（Degree of Parallelism）
- 对堆表：按 ROWID range 切分
- 对分区表：按 partition 切分（每个 slave 负责一个或多个分区）
- 每个 slave 在自己的 undo segment 里独立做 DML
- 所有 slave 的 redo 走各自的 Private Strand
- 语句结束时，QC 收集各 slave 的 "statement-level" commit

### 12838 错误的真实含义

```
ORA-12838: cannot read/modify an object after modifying it in parallel
```

触发场景：
```sql
ALTER SESSION ENABLE PARALLEL DML;
INSERT /*+ PARALLEL */ INTO t SELECT * FROM s;
SELECT COUNT(*) FROM t;   -- ORA-12838!
-- 必须先 COMMIT 或 ROLLBACK
COMMIT;
SELECT COUNT(*) FROM t;   -- 现在可以
```

原因：并行 INSERT 的多个 slave 生成的数据在 QC 看来属于"未完成的分布式事务"，一致性读取需要合并来自多个 slave 的 undo，成本太高，Oracle 直接禁止。

### PARALLEL DML 的可用性矩阵

Oracle 官方文档中的限制表：

| DML 类型 | 分区表 | 非分区表 | 触发器 | 自引用 FK | LOB 列 |
|---------|-------|---------|-------|----------|--------|
| INSERT SELECT | 是 | 是 | 串行化 | 串行化 | 受限 |
| UPDATE | 是 | 是 (19c+) | 串行化 | 串行化 | 受限 |
| DELETE | 是 | 是 (19c+) | 串行化 | 串行化 | 受限 |
| MERGE | 是 | 是 | 串行化 | 串行化 | 受限 |

19c 之前，非分区表的 UPDATE/DELETE 能否并行取决于索引结构（全局索引会导致串行化），19c 起放宽。

### DOP 自动计算

Oracle 从 11g 起有 Automatic DOP：

```sql
-- 表级
ALTER TABLE sales PARALLEL (DEGREE AUTO);

-- 或参数控制
ALTER SYSTEM SET PARALLEL_DEGREE_POLICY = AUTO;
```

AUTO 模式下 Oracle 根据：
- 表大小与 `PARALLEL_MIN_TIME_THRESHOLD`（默认 10 秒估算时长）
- 可用 PX slave 数（`PARALLEL_MAX_SERVERS`）
- I/O 校准结果（`DBMS_RESOURCE_MANAGER.CALIBRATE_IO`）

综合决定实际 DOP。这避免了 DBA 到处手工设 PARALLEL(n)。

## PostgreSQL 14 并行 INSERT 深度剖析

PG 14 的并行 INSERT ... SELECT 是 PostgreSQL 社区长达 5 年的工作成果，由 Greg Nancarrow 主导实现（patch 追溯到 2020）。

### 实现架构

```
  Postmaster
      |
      v
  Backend (leader, 接收 SQL)
      |
      v
  Gather 节点
      |
     /|\
    / | \
   /  |  \
  W1  W2  W3   <- parallel workers
   \  |  /
    \ | /
     \|/
  共享的 ModifyTable (Insert)
```

关键差异（与 Oracle）：
- 并行 worker 与 leader 共享 XID（单事务）
- 每个 worker 有独立的 CurrentMemoryContext，tuple 构造独立
- heap_insert 调用在 worker 本地完成，但 WAL 写入走中央 `XLogInsertLock`
- 不需要 `ENABLE PARALLEL DML` 这样的大开关——PG 的事务模型能处理并行写入的一致性

### 为什么 14 才实现

历史原因：
- 12 前：worker 进程看不到 target table（parallel-safe 检查不通过）
- 12-13：parallel-unsafe function 的传播规则不够精细，导致很多表被误判为 unsafe
- 14：重构了 parallel-safety 判断，允许 INSERT 的插入路径并行

并且，**UPDATE/DELETE 至今（17）未实现**，因为这两者需要：
- 定位要修改的 tuple（通常通过 index lookup）
- 锁定该 tuple
- 更新 HOT chain
- 维护 visibility map 和 free space map

这些操作的并行协调成本大概率会抵消并行收益，PG 社区的共识是"不值得"。

### parallel-safe 的判断

PG 14 引入了细致的 parallel-safety 级别：

- `PROPARALLEL_SAFE`：可以在任何并行 worker 中运行
- `PROPARALLEL_RESTRICTED`：只能在 leader 中运行（读 temp table 等）
- `PROPARALLEL_UNSAFE`：不能在任何并行 context 中运行（write to temp table、某些 PL/pgSQL 函数）

查询表的 parallel-safety：

```sql
-- 看函数的 parallel-safety
SELECT proname, proparallel FROM pg_proc WHERE proname = 'my_function';

-- 用户自定义函数默认是 UNSAFE，必须显式声明：
CREATE OR REPLACE FUNCTION safe_upper(text) RETURNS text AS $$
    SELECT upper($1);
$$ LANGUAGE SQL PARALLEL SAFE IMMUTABLE;
```

### 观察并行 INSERT 的性能

```sql
SET max_parallel_workers_per_gather = 4;
SET max_parallel_workers = 8;

EXPLAIN (ANALYZE, VERBOSE, BUFFERS, WAL, TIMING)
INSERT INTO fact_sales
SELECT * FROM staging.raw_sales WHERE load_date = CURRENT_DATE;
```

典型输出会显示：
- `Workers Planned: 4`
- `Workers Launched: 4`
- 每个 worker 的 heap/index block reads
- WAL 字节数与 FPW (full-page write) 次数

WAL 压力是 PG 并行 INSERT 的瓶颈——4 个 worker 并行生成 tuple，最终仍要串行写 WAL。

### 并行 INSERT 的限制清单

- 目标表不能有 AFTER ROW 触发器
- 目标表不能有 volatile default（如 `DEFAULT nextval(...)` 在 14 中是 restrict，15+ 放宽）
- 目标表不能有 parallel-unsafe CHECK 约束或 FK 检查
- 目标表不能是分区表的**分区**（INSERT 到分区父表 ok，但分区路由本身串行）
- ON CONFLICT DO UPDATE 在 14 中不支持并行（17 仍然未解决）

## 幂等性与提交保证

并行 DML 引入的一个深层问题：如果某个 worker 失败，语句的原子性如何保证？不同引擎有不同策略。

### 1. 全语句回滚（Oracle、PG、SQL Server）

最严格的语义：任一 worker 失败，所有 worker 都回滚。

Oracle 实现：QC 作为分布式事务协调者，使用 two-phase commit：
1. 所有 slave 执行 DML
2. QC 发送 prepare 给所有 slave
3. 所有 slave ack 后，QC 发送 commit
4. 任一 slave 失败，QC 发送 rollback

这保证了 statement-level ACID，但代价是 worker 之间要同步。

PG 更简单：所有 worker 共享一个 transaction，任一 worker abort 导致整个 transaction 回滚。

### 2. Partition-level 原子性（Spanner Partitioned DML）

Spanner 的 Partitioned DML 牺牲了语句原子性：

```sql
PARTITIONED UPDATE orders SET status = 'closed' WHERE order_date < '2024-04-23';
```

如果这个语句影响 100 个 partition，每个 partition 是独立事务。如果某个 partition 失败：
- 其他 99 个 partition 的 UPDATE 已经提交
- 失败的 partition 会**自动重试**
- 用户看到的语句"最终成功"，但中间某个时间点数据是不一致的

这就是为什么 Spanner 要求 Partitioned DML **幂等**：
```sql
-- OK：幂等，多次执行结果相同
PARTITIONED UPDATE orders SET status = 'closed' WHERE order_date < '2024-04-23';

-- 危险：非幂等，重试会导致多次增加
PARTITIONED UPDATE orders SET view_count = view_count + 1 WHERE ...;
-- 这类 SQL 在 Spanner 中会拒绝或警告
```

### 3. Best-effort 并行（ClickHouse mutation）

ClickHouse 的 `ALTER TABLE ... UPDATE` 是异步的：

- 语句返回成功 = mutation 已经入队
- 实际执行由后台 merge worker 完成
- 执行过程中某个 part 失败 → mutation 状态变为 `is_failed`，其他 part 继续
- 没有"语句级原子性"的概念

这对应 OLAP 场景：最终一致性 + 手工处理失败。

### 4. Write-once 的 Delta Lake / Iceberg

Delta/Iceberg 的 UPDATE/DELETE 实际上是：

1. 读出被影响的文件
2. 生成新文件（修改过的行 + 未修改的行）
3. 原子地替换 commit log

并行发生在第 1 和第 2 步，第 3 步（commit）是原子的 log append。如果第 2 步某个 worker 失败，整个 commit 不会生效。这是 snapshot isolation 的自然延伸。

### 5. 幂等性要求总结

| 引擎 | 语句原子性 | 需要幂等 | 失败处理 |
|------|-----------|---------|---------|
| Oracle PARALLEL DML | 是 | 否 | 整体回滚 |
| SQL Server 并行 DML | 是 | 否 | 整体回滚 |
| PostgreSQL 并行 INSERT | 是 | 否 | 整体回滚 |
| Snowflake | 是 | 否 | 整体回滚（micro-partition 层） |
| BigQuery | 是 | 否 | 整体重试 / 失败 |
| Spanner Partitioned DML | 否 | **是** | 自动重试失败 partition |
| ClickHouse mutation | 否 | 建议 | 手工查 system.mutations 处理 |
| Delta Lake | 是 | 否 | commit log 原子 |
| TiDB bulk 模式 | 否（可能部分成功） | 建议 | 应用层补偿 |
| Cockroach DistSQL | 是 | 否 | 整体回滚 |

## 关键发现

1. **并行 DML 与并行 SELECT 不是同一个问题**。并行 SELECT 只要切分扫描；并行 DML 要协调锁、undo、redo、约束、触发器，难度高一个数量级。绝大多数引擎实现顺序是：并行 SELECT → 并行 CTAS → 并行 INSERT SELECT → 并行 UPDATE/DELETE，到最后一步时很多引擎就停下了。

2. **Oracle 是唯一工业级完整实现，从 7.3 (1996) 起逐步演进 (INSERT SELECT 7.3, UPDATE/DELETE 8i, 分区级 9i)**，PARALLEL DML 覆盖 INSERT/UPDATE/DELETE/MERGE，带有完整的 session 开关、提示语法、DOP 自动调优、undo/redo 私有化、分布式事务提交。其他引擎多多少少都是子集。

3. **PostgreSQL 的并行化是渐进式的教科书案例**：9.6 并行 SELECT → 11 并行 CTAS → 14 并行 INSERT SELECT → 至今仍没有并行 UPDATE/DELETE。社区明确表示 UPDATE/DELETE 的并行化投入产出比不划算（因为锁和 HOT chain 协调）。

4. **MySQL 在并行 DML 上几乎完全缺席**。InnoDB 的 B+ 树聚簇索引、auto-increment 锁、gap lock 使并行 DML 实现异常困难。应用层不得不自行切分 ID 范围做 "client-side parallelism"。这是 MySQL 在分析型工作负载下的长期短板。

5. **云数仓（Snowflake/BigQuery/Redshift）的并行 DML 是"免费"的**——用户完全无感知，按 warehouse/slot 大小自动并行。这得益于它们的 copy-on-write 存储（UPDATE 实际是重写 micro-partition/file），把并行 DML 变成了本质上的并行写入新文件，绕过了传统引擎的锁/undo/redo 协调问题。

6. **Lakehouse 格式（Delta/Iceberg/Hudi）让 Spark/Trino 能做并行 UPDATE/DELETE**。经典 Hive 格式不支持这两个语句，Lakehouse 用 manifest + delete vector/equality delete 解决，把 UPDATE/DELETE 降级为"原子的 manifest append"，自然并行。

7. **ClickHouse 的 mutation 是另一种极端**：把 UPDATE/DELETE 异步化，用户只是在发射指令，实际重写由后台合并完成。这让"并行 UPDATE"变成伪命题——真正的开销在后台 merge 里，用户态几乎无感知。但副作用是语义上失去了即时一致性。

8. **Google Spanner 的 Partitioned DML 是"分布式世界的现实选择"**：承认语句级 ACID 在 Planet-scale 上代价过高，强制用户写幂等 SQL，换取大表 DML 的可扩展性。这种设计思路影响了 TiDB 7.5 的 `bulk` DML 模式。

9. **并行 DML 提示/开关缺乏标准**。Oracle 的 `/*+ PARALLEL */`、SQL Server 的 `MAXDOP`、PG 的 `max_parallel_workers_per_gather`、ClickHouse 的 `max_insert_threads`——每个引擎都有自己的一套，跨引擎迁移时这部分几乎是完全重写。

10. **WAL/redo 是最后的瓶颈**。即便工作节点并行，事务日志的顺序 fsync 仍是单串行化点。PG 14 并行 INSERT 在 WAL flush 密集场景下提升有限就是这个原因。Oracle 用 Private Strand 缓解，PG 用 WAL group commit，但本质没变——这是下一代引擎（PG 18、Postgres on object storage、Cloud-native log stores）的重点优化方向。

11. **DML 触发器是并行化的"规则之外的例外"**。几乎所有引擎在检测到 AFTER ROW 触发器时都会降级为串行。原因是行级触发器可能有副作用（写日志表、发通知、级联 DML），并发执行时副作用难以推理。这是应用层需要注意的陷阱。

12. **"并行 CTAS" 是比"并行 INSERT"更普遍的能力**。因为 CTAS 的目标表是新建的，没有锁/undo/trigger 问题。许多引擎（如 PG 11、SQL Server 早期版本）优先支持并行 CTAS 作为"并行 DML 的敲门砖"。应用层 ETL 可以考虑用 CTAS + swap table 代替 INSERT SELECT 来绕过并行限制。

## 参考资料

- Oracle: [VLDB Guide - Parallel DML](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/parallel-exec-intro.html)
- Oracle: [PARALLEL hint and ENABLE PARALLEL DML](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Comments.html)
- PostgreSQL: [Parallel Query](https://www.postgresql.org/docs/current/parallel-query.html)
- PostgreSQL 14 release notes: [Parallel INSERT ... SELECT](https://www.postgresql.org/docs/14/release-14.html)
- SQL Server: [Parallel Query Processing](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#parallel-query-processing)
- SQL Server: [Batch Mode on Columnstore / Rowstore](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#execution-modes)
- Snowflake: [DML Performance](https://docs.snowflake.com/en/user-guide/data-load-considerations-load)
- BigQuery: [DML Quotas and Limits](https://cloud.google.com/bigquery/quotas#dml)
- ClickHouse: [ALTER TABLE ... UPDATE/DELETE (Mutations)](https://clickhouse.com/docs/en/sql-reference/statements/alter/update)
- ClickHouse: [Lightweight DELETE](https://clickhouse.com/docs/en/sql-reference/statements/delete)
- Spark + Delta Lake: [Delta DML operations](https://docs.delta.io/latest/delta-update.html)
- TiDB: [Bulk DML Execution Mode (tidb_dml_type)](https://docs.pingcap.com/tidb/stable/system-variables#tidb_dml_type-new-in-v800)
- OceanBase: [Parallel DML in OceanBase](https://en.oceanbase.com/docs/common-oceanbase-database-10000000000961113)
- Cloud Spanner: [Partitioned DML](https://cloud.google.com/spanner/docs/dml-partitioned)
- CockroachDB: [Parallel DML Execution](https://www.cockroachlabs.com/docs/stable/architecture/sql-layer#distsql)
- Greenplum: [Parallel DML](https://docs.vmware.com/en/VMware-Greenplum/index.html)
- Vertica: [Parallel DML Design](https://docs.vertica.com/latest/en/)
- Graefe, G. "Volcano — An Extensible and Parallel Query Evaluation System" (1994), IEEE TKDE
- Leis et al. "Morsel-Driven Parallelism: A NUMA-Aware Query Evaluation Framework for the Many-Core Age" (2014), SIGMOD
