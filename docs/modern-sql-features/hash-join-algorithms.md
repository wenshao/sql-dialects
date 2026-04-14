# Hash Join 算法变体 (Hash Join Algorithms)

当两张大表按等值条件连接时，没有任何算法能比 Hash Join 更高效——它把 O(N×M) 的嵌套循环降到 O(N+M)，是过去三十年 SQL 引擎里最重要的物理算子。但 "Hash Join" 这一个名字底下，藏着十余种实现变体：经典内存哈希、Grace 哈希、混合哈希、并行共享哈希表、Radix 分区哈希、布隆过滤器加速、自适应回退……每一种都对应一段引擎演化史。

## 没有 SQL 标准

Hash Join 是物理算子（physical operator），不是 SQL 标准的一部分。SQL 标准只定义逻辑连接（INNER/LEFT/RIGHT/FULL JOIN），具体用 Nested Loop、Sort-Merge 还是 Hash Join 完全由优化器决定。因此本文讨论的所有特性都是**实现细节**——但正是这些实现细节决定了一个引擎能否在 TB 级数据上完成连接、能否充分利用多核、能否在内存不足时优雅降级。

Hash Join 的基本思想很简单：

1. **Build 阶段**：扫描较小的输入（build side），按连接键计算哈希，把行插入内存哈希表
2. **Probe 阶段**：扫描较大的输入（probe side），对每行计算同样的哈希，在哈希表中查找匹配

复杂性几乎全部来自两个工程问题：(a) build side 比内存大怎么办，(b) 多核 CPU 怎么并行。本文系统对比 49 个引擎在这两个维度上的差异。

## 支持矩阵

### 经典（内存）Hash Join

最朴素的实现：build side 必须能整个塞进内存，否则失败。几乎所有现代引擎都支持，但有些极简引擎（嵌入式、流处理早期版本）只有 Nested Loop。

| 引擎 | Classic Hash Join | 引入版本 | 备注 |
|------|-------------------|---------|------|
| PostgreSQL | 是 | 7.1 (2001) | 内存内 + 批次溢出 |
| MySQL | 是 | 8.0.18 (2019) | 等值连接，inner 起步 |
| MariaDB | 是 (BKA + 块嵌套哈希) | 5.3+ | Block Nested Loop Hash |
| SQLite | -- | -- | 仅 Nested Loop |
| Oracle | 是 | 7.3 (1994) | 业界最早商用之一 |
| SQL Server | 是 | 7.0 (1998) | 内存 + 优雅降级 |
| DB2 | 是 | V2 早期 | 与 Sort-Merge 自动选择 |
| Snowflake | 是 | GA | 列式向量化 |
| BigQuery | 是 | GA | Dremel 执行器 |
| Redshift | 是 | GA | PG 派生 |
| DuckDB | 是 | 0.1+ | 默认 Radix 分区版本 |
| ClickHouse | 是 | 早期 | `hash` 算法默认 |
| Trino | 是 | 早期 | 包含动态过滤 |
| Presto | 是 | 早期 | -- |
| Spark SQL | 是 | 1.0+ | Shuffled / Broadcast |
| Hive | 是 | 0.7+ | MapJoin |
| Flink SQL | 是 | 1.5+ | 批模式 |
| Databricks | 是 | GA | Photon 加速 |
| Teradata | 是 | V2R3+ | -- |
| Greenplum | 是 | 继承 PG | -- |
| CockroachDB | 是 | 1.1+ | -- |
| TiDB | 是 | 1.0+ | -- |
| OceanBase | 是 | 1.x+ | -- |
| YugabyteDB | 是 | 继承 PG | -- |
| SingleStore | 是 | 早期 | -- |
| Vertica | 是 | 早期 | 列式 |
| Impala | 是 | 1.0+ | -- |
| StarRocks | 是 | 早期 | 向量化 |
| Doris | 是 | 早期 | 向量化 |
| MonetDB | 是 | 早期 | 列式 |
| CrateDB | 是 | 4.2+ | 早期版本仅 Nested Loop |
| TimescaleDB | 是 | 继承 PG | -- |
| QuestDB | 是 | 6.0+ | 时序优化 |
| Exasol | 是 | 早期 | MPP 列式 |
| SAP HANA | 是 | 早期 | -- |
| Informix | 是 | 9.x+ | -- |
| Firebird | 是 | 3.0+ | 之前仅 NL |
| H2 | 是 | 1.4+ | 简单实现 |
| HSQLDB | -- | -- | 仅 Nested Loop |
| Derby | -- | -- | 仅 Nested Loop |
| Amazon Athena | 是 | 继承 Trino | -- |
| Azure Synapse | 是 | GA | -- |
| Google Spanner | 是 | GA | 分布式 |
| Materialize | 是 | GA | 增量维护 |
| RisingWave | 是 | GA | 流式 |
| InfluxDB (SQL) | 是 | 3.0+ (DataFusion) | -- |
| DatabendDB | 是 | GA | -- |
| Yellowbrick | 是 | GA | -- |
| Firebolt | 是 | GA | -- |

> 统计：49 个引擎中 46 支持经典哈希连接；SQLite、HSQLDB、Derby 这三个"教科书级"嵌入式引擎仍然只用 Nested Loop（依赖索引补偿）。

### Grace Hash Join（基于磁盘的分区）

Grace 算法（1983 年东京大学 GRACE 数据库机项目）解决"build 比内存大"的问题：先把两个输入都按哈希分区写到磁盘，每个分区独立做内存 hash join。

| 引擎 | Grace / 分区溢出 | 备注 |
|------|------------------|------|
| PostgreSQL | 是（多批次 batch） | `Hash Batches` 计划字段 |
| MySQL | 是 | 8.0.18+，溢出到 chunk 文件 |
| MariaDB | 部分 | -- |
| Oracle | 是 | "On-disk hash join" |
| SQL Server | 是 | "Hash bailout" |
| DB2 | 是 | 经典实现 |
| Snowflake | 是 | 自动溢出 SSD |
| BigQuery | 是 | Shuffle 溢出 |
| Redshift | 是 | -- |
| DuckDB | 是 | Out-of-core 自 0.5+ |
| ClickHouse | `grace_hash` 算法 | 22.12+ |
| Trino | 是 | spill_enabled |
| Presto | 是 | -- |
| Spark SQL | 是 | Shuffle Sort-Merge 兜底 |
| Hive | 是 | -- |
| Flink SQL | 是 | 批模式 |
| Databricks | 是 | -- |
| Teradata | 是 | -- |
| Greenplum | 是 | 继承 PG |
| CockroachDB | 是 | -- |
| TiDB | 是 | -- |
| OceanBase | 是 | -- |
| Impala | 是 | -- |
| StarRocks | 是 | 3.0+ 溢出 |
| Doris | 是 | 2.0+ 溢出 |
| Vertica | 是 | -- |
| SingleStore | 是 | -- |
| Exasol | 是 | -- |
| SAP HANA | 是 | -- |
| Materialize | -- | 内存内 arrangement |
| RisingWave | 部分 | 状态后端 |
| 其它（SQLite/H2/HSQLDB/Derby/Firebird/Informix/CrateDB/QuestDB/MonetDB/InfluxDB/Spanner/Yellowbrick/Firebolt/Athena/Synapse/Databend/YugabyteDB/TimescaleDB） | 视情况 | 见详细说明 |

> 大型 OLAP 与 MPP 系统普遍支持磁盘溢出；嵌入式引擎和部分流式系统不支持。

### 混合 Hash Join（Hybrid Hash Join）

DeWitt 1984 年提出的优化：第一个分区始终保留在内存中，避免无谓的写盘读盘。当 build 略大于内存时收益最大。

| 引擎 | Hybrid Hash Join |
|------|-------------------|
| PostgreSQL | 是 |
| Oracle | 是 |
| SQL Server | 是 |
| DB2 | 是 |
| Snowflake | 是 |
| Greenplum | 是 |
| Vertica | 是 |
| Teradata | 是 |
| SAP HANA | 是 |
| Exasol | 是 |
| Spark SQL | 部分（仅 SHJ 路径） |
| Trino | 部分 |
| ClickHouse | -- |
| DuckDB | 是 |
| MySQL | 部分（chunk 文件） |
| Impala | 是 |
| StarRocks | 部分 |
| Doris | 部分 |
| 其它 | -- |

### 并行 Hash Join：共享哈希表

多个 worker 共同 build 一张哈希表，再共同 probe。PostgreSQL 11 是经典实现。

| 引擎 | 共享哈希表并行 | 引入版本 |
|------|---------------|---------|
| PostgreSQL | 是 | 11 (2018) |
| Oracle | 是 | Parallel Query 早期 |
| SQL Server | 是 | 早期 |
| DB2 | 是 | DPF |
| Greenplum | 是 | -- |
| MySQL | -- | 单线程 |
| MariaDB | -- | -- |
| ClickHouse | 是 | parallel_hash 22.3 (2022) |
| DuckDB | -- | 用 Radix 分区代替 |
| Snowflake | 是 | -- |
| Redshift | 是 | -- |
| BigQuery | 是 | -- |
| Spark SQL | 是 | Broadcast Hash Join |
| Trino | 是 | -- |
| Presto | 是 | -- |
| Vertica | 是 | -- |
| SingleStore | 是 | -- |
| Impala | 是 | -- |
| StarRocks | 是 | -- |
| Doris | 是 | -- |
| Teradata | 是 | -- |
| SAP HANA | 是 | -- |
| Exasol | 是 | -- |
| 其它嵌入式 | -- | -- |

### 并行 Hash Join：分区式

每个 worker 拥有独立的哈希表（按键的哈希分区路由），无需锁竞争。DuckDB 和 ClickHouse 的现代默认。

| 引擎 | 分区并行哈希连接 | 备注 |
|------|------------------|------|
| DuckDB | 是 | Radix 分区，默认 |
| ClickHouse | 是 | parallel_hash |
| Snowflake | 是 | Repartition |
| Spark SQL | 是 | Shuffled Hash Join |
| Trino | 是 | Hash exchange |
| Presto | 是 | -- |
| Greenplum | 是 | Redistribute Motion |
| Impala | 是 | Partitioned Hash Join (默认) |
| StarRocks | 是 | Shuffle Join |
| Doris | 是 | Shuffle Join |
| Vertica | 是 | -- |
| BigQuery | 是 | -- |
| Redshift | 是 | DS_DIST_BOTH |
| TiDB | 是 | -- |
| OceanBase | 是 | -- |
| CockroachDB | 是 | -- |
| YugabyteDB | 是 | -- |
| Spanner | 是 | -- |
| Flink SQL | 是 | 批模式 |
| Databricks | 是 | -- |
| SingleStore | 是 | -- |
| Exasol | 是 | -- |
| Teradata | 是 | -- |
| SAP HANA | 是 | -- |
| Yellowbrick | 是 | -- |
| Firebolt | 是 | -- |
| Athena/Synapse/Databend | 是 | -- |
| Materialize | 是 | dataflow |
| RisingWave | 是 | dataflow |
| 其它 | -- | -- |

### 布隆过滤器 / Runtime Filter

build 侧扫描时副产生一个布隆过滤器，下推到 probe 侧（甚至 storage scan），让大表只读"可能匹配"的行。

| 引擎 | Bloom / Runtime Filter | 引入版本 |
|------|------------------------|---------|
| Oracle | 是 | 10g R2 (2005) |
| SQL Server | 是 | 2008 (Batch Mode 2016) |
| DB2 | 是 | LUW 早期 |
| PostgreSQL | 部分 | 17 已有 build-side bloom for parallel HJ |
| MySQL | -- | -- |
| MariaDB | -- | -- |
| Snowflake | 是 | GA |
| BigQuery | 是 | -- |
| Redshift | 是 | -- |
| DuckDB | 是 | min/max + bloom |
| ClickHouse | 是 | indexHint + projections |
| Trino | 是 | Dynamic Filtering 350+ |
| Presto | 是 | -- |
| Spark SQL | 是 | 3.0+ DPP + Runtime Bloom 3.3+ |
| Hive | 是 | LLAP |
| Flink SQL | 是 | 1.16+ |
| Databricks | 是 | Photon DFP |
| Teradata | 是 | -- |
| Greenplum | 是 | Runtime filter |
| CockroachDB | -- | -- |
| TiDB | 是 | TiFlash runtime filter |
| OceanBase | 是 | bloom filter |
| YugabyteDB | -- | -- |
| SingleStore | 是 | -- |
| Vertica | 是 | SIPS |
| Impala | 是 | Runtime Filter (经典) |
| StarRocks | 是 | global runtime filter |
| Doris | 是 | runtime filter (in/min-max/bloom) |
| Exasol | 是 | -- |
| SAP HANA | 是 | -- |
| 其它 | -- | -- |

### 自适应 Hash Join 回退

执行过程中发现内存不足或基数估计严重错误，动态切换算法（如 SQL Server 的 Adaptive Join 在 NL/Hash 之间切换）。

| 引擎 | 自适应回退 |
|------|-----------|
| SQL Server | 是 (2017+ Adaptive Join) |
| Oracle | 是 (12c Adaptive Plans) |
| DB2 | 是 |
| Snowflake | 是 |
| Spark SQL | 是 (3.0+ AQE) |
| Databricks | 是 (AQE) |
| Trino | 部分 |
| BigQuery | 是 |
| Greenplum | 是 |
| Vertica | 是 |
| 其它 | -- |

### 哈希表实现：开放寻址 vs 链式

| 引擎 | 实现 |
|------|------|
| PostgreSQL | 链式（ChainHashJoin） |
| Oracle | 开放寻址（cluster table） |
| SQL Server | 链式 |
| DB2 | 链式 |
| DuckDB | 开放寻址（线性探测，Radix 分区） |
| ClickHouse | 开放寻址（HashMap 模板） |
| Spark SQL | BytesToBytesMap（开放寻址 + off-heap） |
| Trino | 开放寻址（PagesHash） |
| Impala | 开放寻址 |
| StarRocks | 开放寻址（vectorized） |
| Doris | 开放寻址 |
| Vertica | 开放寻址 |
| SAP HANA | 开放寻址 |
| MySQL | 链式 + 溢出 chunk 文件 |
| MariaDB | 链式 |
| Snowflake | 不公开 |
| BigQuery | 不公开 |

> 列式 / 向量化引擎几乎一致地选择开放寻址（线性/二次探测），因为缓存友好；行式 OLTP 引擎更多保留链式实现（实现简单，支持任意大 bucket 链）。

### 内存溢出到磁盘

| 引擎 | 内存溢出 | 控制参数 |
|------|---------|---------|
| PostgreSQL | 是 | `work_mem` × `hash_mem_multiplier` (13+) |
| MySQL | 是 | `join_buffer_size` (8.0.18+) |
| Oracle | 是 | `pga_aggregate_target` |
| SQL Server | 是 | tempdb |
| DB2 | 是 | `sortheap` |
| Snowflake | 是 | 自动 SSD |
| BigQuery | 是 | shuffle service |
| Redshift | 是 | `wlm_query_slot_count` |
| DuckDB | 是 | `memory_limit` + temp dir |
| ClickHouse | 是 (grace_hash) | `max_bytes_in_join` |
| Trino | 是 | `spill-enabled` |
| Spark SQL | 是 | `spark.sql.shuffle.partitions` |
| Impala | 是 | `MEM_LIMIT` |
| StarRocks | 是 (3.0+) | spill 选项 |
| Doris | 是 (2.0+) | spill 选项 |
| Vertica | 是 | -- |
| SingleStore | 是 | -- |
| Greenplum | 是 | `gp_workfile_limit` |
| Teradata | 是 | spool space |
| SAP HANA | 是 | -- |
| 其它嵌入式（SQLite/H2/HSQLDB/Derby/Firebird） | -- | 仅内存 |
| MariaDB | -- | 旧版无 |

### HASHJOIN Hint

| 引擎 | Hint 语法 |
|------|----------|
| Oracle | `/*+ USE_HASH(t1 t2) */` |
| SQL Server | `OPTION (HASH JOIN)` 或 `INNER HASH JOIN` |
| DB2 | `/*+ HASHJOIN */`（注册表） |
| MySQL | `/*+ HASH_JOIN(t1 t2) */` 8.0.18+ |
| MariaDB | -- |
| PostgreSQL | 无（pg_hint_plan 扩展提供 `HashJoin(t1 t2)`） |
| Snowflake | 无 |
| BigQuery | `JOIN HASH` 注释 / `JOIN_METHOD=HASH` |
| Redshift | -- |
| Spark SQL | `/*+ SHUFFLE_HASH(t) */`、`/*+ BROADCAST(t) */` |
| Trino | session property `join_distribution_type` |
| Presto | session property |
| Hive | `/*+ MAPJOIN(t) */` |
| Vertica | `/*+ JTYPE(HASH) */` |
| Greenplum | -- |
| TiDB | `/*+ HASH_JOIN(t1, t2) */` |
| OceanBase | `/*+ USE_HASH(t1 t2) */` |
| StarRocks | `[shuffle]` / `[broadcast]` hint |
| Doris | 同 StarRocks |
| Impala | `/* +SHUFFLE */`、`/* +BROADCAST */` |
| Teradata | -- |
| SAP HANA | `WITH HINT(USE_HASH_JOIN)` |
| 其它 | -- |

## 各引擎详解

### PostgreSQL：从经典哈希到并行共享哈希表

PostgreSQL 7.1（2001）就引入了 Hash Join，使用经典的 GRACE 风格分批策略：当 build 超过 `work_mem`，按哈希位将其切成 N 个 batch，每个 batch 独立做内存哈希。计划里能看到 `Hash Batches: 16  Memory Usage: ...kB`。

```sql
EXPLAIN ANALYZE
SELECT * FROM orders o JOIN customers c ON o.cust_id = c.id;
--  Hash Join  (cost=27.50..70.62 rows=1000 width=...)
--    Hash Cond: (o.cust_id = c.id)
--    ->  Seq Scan on orders o
--    ->  Hash
--          Buckets: 1024  Batches: 1  Memory Usage: 11kB
--          ->  Seq Scan on customers c
```

PostgreSQL 11（2018）引入**并行 Hash Join**，关键创新是**共享哈希表**：build 阶段所有 worker 一起向同一张 DSM（动态共享内存）哈希表插入，barrier 同步后并行 probe。这避免了让每个 worker 各 build 一份的内存浪费。Thomas Munro 的实现细节是为多 worker 的并发插入做了无锁桶分配。

```sql
SET max_parallel_workers_per_gather = 4;
EXPLAIN ANALYZE
SELECT count(*) FROM lineitem l JOIN orders o ON l.l_orderkey = o.o_orderkey;
--  Gather  (cost=...)
--    Workers Planned: 4
--    ->  Parallel Hash Join
--          Hash Cond: (l.l_orderkey = o.o_orderkey)
--          ->  Parallel Seq Scan on lineitem l
--          ->  Parallel Hash
--                ->  Parallel Seq Scan on orders o
```

PostgreSQL 13 引入了 `hash_mem_multiplier`，允许哈希算子使用 `work_mem × hash_mem_multiplier` 字节内存，单独区分排序与哈希的预算（哈希溢出比排序代价更高）。PostgreSQL 17 增加了 build-side bloom filter 的能力以加速 parallel hash join 的 probe 阶段。

### Oracle：业界最早的成熟实现（1994）

Oracle 7.3（1994）首次商用 Hash Join，与 Sort-Merge 并列。Oracle 的实现包含完整的 Grace 分区、Hybrid 优化、并行哈希、布隆过滤（10gR2 引入）。布隆过滤在 RAC 环境尤其关键：广播一个紧凑的 bitmap 比广播整张哈希表节省数十倍网络。

```sql
SELECT /*+ USE_HASH(o c) PARALLEL(4) */ *
  FROM orders o, customers c
 WHERE o.cust_id = c.id;
```

执行计划里出现 `HASH JOIN`、`HASH JOIN BUFFERED`、`HASH JOIN OUTER`、`HASH JOIN SEMI`、`HASH JOIN ANTI` 多种变体；并行下还有 `PX SEND BROADCAST` / `PX SEND HASH`。12c 引入的 Adaptive Plans 能在执行时根据真实行数从 NL 切换到 Hash。

### SQL Server：In-Memory + Grace + Batch Mode

SQL Server 7.0（1998）引入 Hash Match。它分三阶段：
1. **In-Memory Hash Join**：一切 OK 时
2. **Grace Hash Join**：内存不够，分桶溢出到 tempdb
3. **Recursive Hash Join**：单个分区还是太大，再次分桶

外加"Hash Bailout"机制——发现严重数据倾斜时切到 Sort-Merge。2016 引入的 **Batch Mode hash join** 在列存上以 1024 行为一批向量化处理，性能数量级提升；2019 起 Batch Mode 也能在行存上启用。SQL Server 2017 的 Adaptive Join 在运行时按行数阈值在 Hash 与 NL 间二选一。

```sql
SELECT * FROM Orders o
  INNER HASH JOIN Customers c ON o.CustId = c.Id
OPTION (HASH JOIN);
```

### MySQL：迟到的 8.0.18

MySQL 在 InnoDB 时代长期只有 BNL（Block Nested Loop），2019 年 10 月发布的 **8.0.18** 才引入真正的 Hash Join，仅支持等值 inner join。**8.0.20**（2020-04）扩展到 outer / semi / anti join，并默认替代 BNL。MySQL 的实现使用 chunk 文件做磁盘溢出（每个 build chunk 独立 probe）。

```sql
EXPLAIN FORMAT=TREE
SELECT /*+ HASH_JOIN(o c) */ *
  FROM orders o JOIN customers c ON o.cust_id = c.id;
-- -> Inner hash join (o.cust_id = c.id)
--    -> Table scan on o
--    -> Hash
--       -> Table scan on c
```

由于 MySQL 不并行执行单个查询，hash join 始终单线程，但对内存友好的中等规模连接已有数倍提升。MariaDB 走的是另一条路：`Block Nested Loop Hash`（BNLH，5.3+），不是真正的 hash join 算子，而是在 BNL 基础上对 join buffer 建哈希索引。

### DB2：自动选择 Sort-Merge vs Hash

DB2 LUW 把 Hash Join、Merge Scan Join、Nested Loop 同时放到代价模型里，由优化器选。Hash Join 始终是 Hybrid 实现：build 侧能放进 `sortheap` 的部分留在内存，超出的按哈希分区写盘。LUW 早期就引入了 build-to-probe bloom filter（DB2 自己的术语）。注册表变量 `DB2_HASH_JOIN=YES` 在很老的版本曾用于显式开启。

### ClickHouse：从 hash 到 parallel_hash 到 grace_hash

ClickHouse 早期只有内存内 `hash` 算法。2022 年 22.3 引入 `parallel_hash`：build 阶段多线程并发插入分片哈希表，probe 时按 key 路由。2022 年底 22.12 引入 `grace_hash`：内存不够时按桶溢出磁盘，类似经典 Grace。设置：

```sql
SET join_algorithm = 'parallel_hash';   -- 或 'grace_hash', 'partial_merge', 'auto'
SELECT count() FROM events e ANY INNER JOIN users u ON e.user_id = u.id;
```

`auto` 模式会先尝试 parallel hash，超过阈值切到 grace hash 或 partial merge。

### DuckDB：Radix 分区并行哈希

DuckDB 没有共享哈希表，而是 Mark Raasveldt 与 Hannes Mühleisen 实现的 **Radix-Partitioned Hash Join**（论文：Balkesen et al., 2013 的工程化）。build 阶段所有线程把行写入 N 个 radix 分区（N 通常 = 256 或 1024），完成后每个线程领取若干分区独立 build + probe。这种设计完全无锁、缓存友好，且天然支持磁盘溢出（分区直接落盘）。DuckDB 0.5 起支持 out-of-core hash join。

```sql
PRAGMA memory_limit='2GB';
PRAGMA temp_directory='/tmp/duckdb';
SELECT count(*) FROM tpch_lineitem l JOIN tpch_orders o USING (o_orderkey);
```

### Snowflake：分区 Hash + 广播

Snowflake 在编译期估代价决定 Distributed Hash Join 的分发方式：小表广播、大表分区交换。每个 worker（XP 进程）内部用经典哈希表，写入虚拟磁盘溢出区（SSD）。布隆过滤器在跨节点 join 中默认开启。

### Spark SQL：三种连接战术

Spark 把 Join 选择封装为三种物理算子：

1. **Broadcast Hash Join (BHJ)**：小表广播，大表本地 probe。`spark.sql.autoBroadcastJoinThreshold` 默认 10MB。
2. **Shuffled Hash Join (SHJ)**：双侧按 key 哈希 shuffle，每个分区内 build 较小一侧的哈希表
3. **Sort-Merge Join (SMJ)**：双侧按 key shuffle + 排序，内存友好的兜底

3.0 引入 **AQE**（Adaptive Query Execution），可在 shuffle 后根据真实统计动态把 SMJ 升级为 BHJ。3.0 引入 Dynamic Partition Pruning，3.3 引入 Runtime Bloom Filter。

```sql
SELECT /*+ BROADCAST(c) */ *
FROM orders o JOIN customers c ON o.cust_id = c.id;

SELECT /*+ SHUFFLE_HASH(o) */ *
FROM orders o JOIN line_item l ON o.id = l.order_id;
```

### Trino：动态过滤的优等生

Trino（前 PrestoSQL）的 Hash Join 整合了 **Dynamic Filtering**：build 侧扫描时同步建立一个值集合或布隆过滤器，下推到 probe 侧的 TableScan，让 connector（Hive/Iceberg/Delta）跳过整个 Parquet/ORC stripe 甚至 partition。动态过滤在 350+ 版本里成为默认开启。Join 顺序由 cost-based optimizer 决定，可通过 `join_distribution_type=AUTOMATIC|PARTITIONED|BROADCAST` 调整。

```sql
SET SESSION join_distribution_type = 'PARTITIONED';
SET SESSION enable_dynamic_filtering = true;
```

## Grace Hash Join 深入

Grace Hash Join 由日本东京大学的 GRACE 数据库机项目（Kitsuregawa et al., 1983）首先提出，针对 build 远超内存的场景：

1. **分区阶段**：扫描两侧输入，对 join key 计算 `h1(key) mod N`，把行按桶号写到 2N 个临时文件（build 侧 N 个、probe 侧 N 个）
2. **连接阶段**：对每个桶 i，加载 build 侧文件 i 到内存哈希表（用不同的 `h2`），扫描 probe 侧文件 i 探测

这样每个桶都能放进内存，整体复杂度 O(N+M) 加上一次额外写盘读盘。

```text
        Build Side (10 GB)            Probe Side (100 GB)
              |                              |
              v  h1(key) mod 16              v  h1(key) mod 16
       +----+----+----+...+         +----+----+----+...+
       | b0 | b1 | b2 |   |         | p0 | p1 | p2 |   |
       +----+----+----+...+         +----+----+----+...+
              \                             /
               +---> 桶 i: 加载 bi 建表 ---+
                     扫描 pi 探测
                     输出匹配
```

**Hybrid Hash Join** 的优化：第一个分区（桶 0）的 build 行**不写盘**，直接保留在内存哈希表里；probe 阶段桶 0 的 probe 行也不写盘，直接探测。当 build 大小约等于内存时，节约一半 I/O。DeWitt 1984 论文证明 Hybrid 对所有 build 大小都不劣于 Grace。

**多次分区（recursive partitioning）**：如果某个桶仍然超过内存（数据倾斜），用第二个哈希函数把该桶再分一次。SQL Server 把此称为 "Recursive Hash Join"，PostgreSQL 在计划里显示为 "Hash Batches: 32 Original: 16"。

## PostgreSQL 11 共享哈希表方案

传统并行 Hash Join 让每个 worker 各 build 一份哈希表（Spark 的 BHJ 即此），优点简单，缺点是 build 侧大时极度浪费内存。PostgreSQL 11 的 Parallel Hash 由 Thomas Munro 实现，关键设计：

1. **DSM 段**：哈希表桶数组放在动态共享内存，所有 worker 都能访问
2. **Barrier 同步**：build 阶段所有 worker 一起插入，结束时通过 barrier 等待对方完成
3. **无锁桶分配**：用原子 CAS 申请 chunk，避免锁竞争
4. **多 batch 协作**：超过 work_mem 时大家一起把多余 batch 写到共享溢出文件，所有 worker 协同处理

```sql
SET max_parallel_workers_per_gather = 8;
SET work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lineitem l JOIN part p ON l.l_partkey = p.p_partkey
WHERE p.p_brand = 'Brand#23';
--  Finalize Aggregate
--    ->  Gather
--          Workers Planned: 8
--          ->  Partial Aggregate
--                ->  Parallel Hash Join
--                      Hash Cond: (l.l_partkey = p.p_partkey)
--                      ->  Parallel Seq Scan on lineitem l
--                      ->  Parallel Hash
--                            Buckets: 131072  Batches: 1  Memory Usage: 9216kB
--                            ->  Parallel Seq Scan on part p
--                                  Filter: (p_brand = 'Brand#23')
```

Memory Usage 是**所有 worker 共享**的总和，而不是每 worker 的份额——这是相对老式 Parallel Hash Join 的核心节约。

## 布隆过滤器作为 Hash Join 加速器

布隆过滤器在 hash join 中的妙用：build 侧扫描时顺手把 join key 插入 bloom filter，filter 比哈希表小百倍以上，可推到 probe 侧的 TableScan 节点甚至 storage 层。被 filter 拒绝的行根本不需要进入哈希探测，更不需要从磁盘读出。

```text
Build:  [ scan dim ]──build hash table──┐
                  └──build bloom filter──┘
                                     │
                                     ▼  (push down)
Probe:  [ scan fact ──filter by bloom── hash probe ── output ]
```

效果举例：星型查询 `SELECT * FROM fact JOIN dim ON ... WHERE dim.x = ...`，dim 过滤后只剩 1 万行，bloom filter ~12KB，下推到 fact 表的 Parquet/ORC 扫描后能跳过 99% 的 row group，I/O 数量级减少。

各厂商的术语：

- **Oracle**：Bloom Filter（10gR2 起，RAC 跨节点尤其重要）
- **SQL Server**：Bitmap Filter（早期叫 Star Join Bitmap），Batch Mode 列存自动启用
- **Trino**：Dynamic Filter
- **Spark**：Dynamic Partition Pruning（DPP，分区粒度）+ Runtime Bloom Filter（行级，3.3+）
- **Impala**：Runtime Filter（IN-list / min-max / bloom 三种）
- **StarRocks/Doris**：Global Runtime Filter（cross-fragment）
- **Vertica**：SIPS（Sideways Information Passing）
- **PostgreSQL**：17 起 parallel hash 内置 build-side bloom

错误率通常配为 5%~10%；filter 越大越精确，但传输和探测成本越高，需要权衡。

## 关键发现

1. **Hash Join 是物理算子，不是 SQL 标准**：49 个引擎里 46 个支持，剩下三个（SQLite、HSQLDB、Derby）是教科书级嵌入式引擎，依赖索引补偿。

2. **Oracle 1994 年即商用 Hash Join**，比 PostgreSQL 早 7 年，比 MySQL 早 25 年。MySQL 直到 2019 年 8.0.18 才有真正的 hash join，2020 年 8.0.20 才支持 outer/semi/anti——对 OLAP 工作负载是迟来的关键升级。

3. **PostgreSQL 11 的共享哈希表方案**（2018, Thomas Munro）是开源数据库里最优雅的并行 hash join 实现：DSM 共享桶 + barrier 同步 + 无锁 chunk 分配，让 N 个 worker 共享一份哈希表内存而非各 build 一份。

4. **DuckDB 选择了完全不同的路径**：Radix-Partitioned Hash Join 完全无锁，每线程独占分区，缓存极度友好，且天然支持磁盘溢出。这条路在向量化/列式引擎里逐渐成为主流（ClickHouse parallel_hash 思路类似）。

5. **Grace Hash Join 仍是磁盘溢出的标准方案**。PostgreSQL `Hash Batches`、SQL Server "Hash Bailout"、Oracle "On-disk Hash Join"、ClickHouse `grace_hash` 都是同一个 1983 年算法的现代实现。Hybrid 优化（DeWitt 1984）把第一个分区留在内存，几乎被所有成熟实现采用。

6. **布隆过滤器 / Runtime Filter 是过去十年最重要的 Hash Join 加速器**。Oracle 10gR2（2005）首开商用先河，Impala 把它做成必备特性，Trino 命名为 Dynamic Filtering 并默认开启，Spark 3.3 才加入运行时 bloom——这是 OLAP 引擎区分高低的关键能力。

7. **哈希表实现的列式/行式分野**：列式向量化引擎几乎一致选择**开放寻址 + 线性探测**（DuckDB、ClickHouse、Trino、Impala、StarRocks、Doris、Vertica、Spark BytesToBytesMap），缓存命中率高；行式 OLTP 引擎更多保留**链式哈希**（PostgreSQL、SQL Server、DB2、MySQL），实现简单且支持任意大 bucket。

8. **自适应 Hash Join 是现代优化器的标配**：SQL Server 2017 Adaptive Join、Oracle 12c Adaptive Plans、Spark 3.0 AQE、Snowflake 自动选择——它们都承认编译期估行数会出错，必须在执行时根据真实数据修正连接策略。

9. **HASHJOIN hint 在生产里依然常用**：Oracle `USE_HASH`、SQL Server `OPTION (HASH JOIN)`、MySQL 8.0.18 的 `HASH_JOIN`、Spark `BROADCAST`/`SHUFFLE_HASH`、TiDB/OceanBase 沿用 Oracle 风格。PostgreSQL 是少数没有原生 hint 语法的主流引擎，需要 `pg_hint_plan` 扩展。

10. **MPP/云数仓 vs 单机引擎在 Hash Join 上的复杂度差距巨大**：单机 hash join 大约 2000 行 C 代码就能写好，分布式 hash join 涉及 build 侧广播 vs 双侧分区交换、跨节点 bloom filter、shuffle 服务的容错、动态 repartition——Snowflake、BigQuery、Spark、Trino 在这层投入了大量工程。

11. **流处理引擎做 hash join 是另一道门**：Materialize 用增量维护的 arrangement，Flink SQL 用 RocksDB 状态后端，RisingWave 用 Hummock；它们的"hash join"语义是双向连续维护，而非批式的一次 build + 一次 probe。

12. **`work_mem` 与 `hash_mem_multiplier`**：PostgreSQL 13 把哈希算子的内存预算与排序解耦，因为哈希溢出的代价远高于排序——溢出意味着多写一次磁盘 + 多读一次磁盘，外加 I/O 模式从顺序变成半随机。13+ 调优 hash join 时应优先考虑提升 `hash_mem_multiplier` 而非全局 `work_mem`。
