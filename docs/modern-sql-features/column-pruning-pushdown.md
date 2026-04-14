# 列裁剪与投影下推 (Column Pruning and Projection Pushdown)

一张 500 列的事实表，查询只用到 3 列——如果优化器能做到只读这 3 列，I/O 就减少 99.4%，这就是列裁剪（Column Pruning）与投影下推（Projection Pushdown）的威力。在列存引擎上，它决定了查询能否"秒开"；在云数仓上，它直接决定账单金额。

## 为什么投影下推至关重要

现代分析型查询的典型场景：一张宽表（事实表）有数百列，但单次 SELECT 只访问其中几列。如果执行引擎不能把"只需要这几列"的信息告诉存储层，就会出现三层浪费：

1. **磁盘 I/O 浪费**：读取整行再丢弃 99% 的字节
2. **网络 I/O 浪费**：在 shared-nothing MPP / 对象存储（S3/GCS/OSS）场景下，无用字节走了网络
3. **内存 / CPU 浪费**：解码、反序列化、构造中间行

对于按列存储（columnar storage）的引擎，投影下推是"降本"的第一发动机：

- **BigQuery**：按扫描字节数计费，只有被投影的列进入账单
- **Snowflake**：micro-partition 中每列独立压缩、独立存取，未投影列不触达
- **ClickHouse**：MergeTree 表每列是独立文件，优化器决定打开哪些文件
- **Parquet / ORC 外表**：通过 FileSource 读端把列裁剪推入文件 reader，按 row group 跳列读

对于按行存储（row store），投影下推不能真正减少磁盘 I/O，但仍有两个收益：① 在内存算子之间传递更窄的元组，减少 CPU / cache miss；② 在 join / aggregation 之后的下游算子看到的列更少，溢写（spill）代价更低。

## 没有 SQL 标准

SQL:2016 / SQL:2023 没有任何与投影下推相关的语法或语义规范。列裁剪是纯粹的**优化器实现特性**，用户无法通过 DDL / DML 显式请求——只能通过 `EXPLAIN` 观察是否生效。因此本文讨论的全部是各引擎的实现差异，而非标准合规度。

> 注：SQL 标准定义的是"逻辑上 SELECT 投影哪几列"，但从"物理上只读这几列"是优化器自由发挥的范畴。

## 支持矩阵

### 核心列裁剪能力

| 引擎 | 行/列存 | Join 列裁剪 | 子查询列裁剪 | UNION 列裁剪 | 存储层投影下推 | 外表投影下推 | 嵌套列裁剪 | EXPLAIN 显示投影 |
|------|--------|-----------|-------------|-------------|---------------|-------------|-----------|-----------------|
| PostgreSQL | 行 | 是 | 是 | 是 | -- | FDW 部分 | 有限 | 是 |
| MySQL | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| MariaDB | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| SQLite | 行 | 是 | 是 | 是 | -- | -- | -- | 是 |
| Oracle | 行+列(IMC) | 是 | 是 | 是 | In-Memory | 外表 | 有限 | 是 |
| SQL Server | 行+列存 | 是 | 是 | 是 | Columnstore | PolyBase | 有限 | 是 |
| DB2 | 行+列(BLU) | 是 | 是 | 是 | BLU | 有限 | -- | 是 |
| Snowflake | 列（micropartition） | 是 | 是 | 是 | 是 | 是 | 是 (VARIANT) | 是 |
| BigQuery | 列（Capacitor） | 是 | 是 | 是 | 是 | 是 (BigLake) | 是 (STRUCT) | 是（bytes billed） |
| Redshift | 列 | 是 | 是 | 是 | 是 | Spectrum | 有限 | 是 |
| DuckDB | 列 | 是 | 是 | 是 | 是 | 是 (Parquet/CSV) | 是 | 是 |
| ClickHouse | 列（MergeTree） | 是 | 是 | 是 | 是（每列文件） | 是 | 是 (Tuple) | 是 |
| Trino | 取决连接器 | 是 | 是 | 是 | -- | 是（connector） | 是 (row) | 是 |
| Presto | 取决连接器 | 是 | 是 | 是 | -- | 是（connector） | 有限 | 是 |
| Spark SQL | 取决 source | 是 | 是 | 是 | -- | 是 (Parquet/ORC) | 是 (3.0+) | 是 (optimizedPlan) |
| Hive | 取决 SerDe | 是 | 是 | 是 | -- | 是 (ORC/Parquet) | 是 (Hive 2.x+) | 是 |
| Flink SQL | 流+批 | 是 | 是 | 是 | -- | 是（Source） | 是 | 是 |
| Databricks | 列 (Delta) | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Teradata | 行+列(Columnar) | 是 | 是 | 是 | Columnar Table | -- | -- | 是 |
| Greenplum | 行+列(AOCO) | 是 | 是 | 是 | 是 (AOCO) | PXF | 有限 | 是 |
| CockroachDB | 行(KV) | 是 | 是 | 是 | -- | -- | -- | 是 |
| TiDB | 行+列(TiFlash) | 是 | 是 | 是 | TiFlash | -- | 有限 | 是 |
| OceanBase | 行+列 4.x | 是 | 是 | 是 | 是 | 外表 4.2+ | -- | 是 |
| YugabyteDB | 行(DocDB) | 是 | 是 | 是 | -- | -- | -- | 是 |
| SingleStore | 行+列存 | 是 | 是 | 是 | 是 | 是 | 是 (JSON) | 是 |
| Vertica | 列（projection） | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Impala | 取决格式 | 是 | 是 | 是 | -- | 是 (Parquet/ORC) | 是 | 是 |
| StarRocks | 列 | 是 | 是 | 是 | 是 | 是 (Iceberg/Hudi) | 是 (JSON/STRUCT) | 是 |
| Doris | 列 | 是 | 是 | 是 | 是 | 是 | 是 (VARIANT/STRUCT) | 是 |
| MonetDB | 列 | 是 | 是 | 是 | 是 | -- | -- | 是 |
| CrateDB | 列 (Lucene) | 是 | 是 | 是 | 是 | -- | 是 (OBJECT) | 是 |
| TimescaleDB | 行+列（压缩块） | 是 | 是 | 是 | 压缩块 | -- | -- | 是 |
| QuestDB | 列 | 是 | 是 | 是 | 是 | -- | -- | 有限 |
| Exasol | 列 | 是 | 是 | 是 | 是 | 是 | -- | 是 |
| SAP HANA | 列 | 是 | 是 | 是 | 是 | 虚表 | -- | 是 |
| Informix | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| Firebird | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| H2 | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| HSQLDB | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| Derby | 行 | 是 | 是 | 是 | -- | -- | -- | 有限 |
| Amazon Athena | 取决格式 | 是 | 是 | 是 | -- | 是 (Parquet/ORC) | 是 | 是 |
| Azure Synapse | 行+列存 | 是 | 是 | 是 | Columnstore | PolyBase | 有限 | 是 |
| Google Spanner | 行(Ressi 列式) | 是 | 是 | 是 | 有限 | -- | -- | 是 |
| Materialize | 增量视图 | 是 | 是 | 是 | -- | 是 | -- | 是 |
| RisingWave | 流+状态 | 是 | 是 | 是 | -- | 是 | 是 (STRUCT) | 是 |
| InfluxDB (IOx) | 列 (Parquet) | 是 | 是 | 是 | 是 | 是 | -- | 是 |
| Databend | 列 (Parquet) | 是 | 是 | 是 | 是 | 是 | 是 (VARIANT) | 是 |
| Yellowbrick | 列 | 是 | 是 | 是 | 是 | 是 (Parquet) | 有限 | 是 |
| Firebolt | 列 (F3) | 是 | 是 | 是 | 是 | 是 (Parquet) | -- | 是 |

> 统计：48 个引擎中，**几乎全部都实现了逻辑层列裁剪**（通过 Join / 子查询 / UNION），但只有约 **30 个**具备真正的"物理存储层投影下推"——这基本上等于"是否是列存"的镜像。

### 嵌套列裁剪支持（Nested / STRUCT / JSON）

| 引擎 | 嵌套类型 | 嵌套裁剪 | 版本 | 备注 |
|------|---------|---------|------|------|
| BigQuery | STRUCT / ARRAY | 是 | GA | 只扫描被引用的子字段 |
| Snowflake | VARIANT / OBJECT | 是 | GA | 半结构化自动列化 |
| Spark SQL | StructType | 是 | 3.0 (2020) | `spark.sql.optimizer.nestedSchemaPruning.enabled` 默认 true |
| Parquet (规范) | group / repeated | 是 | -- | 文件格式级支持 |
| ORC | STRUCT / LIST / MAP | 是 | -- | 文件格式级支持 |
| Trino | ROW / ARRAY | 是 | Hive 连接器 | `hive.dereference-pushdown` |
| Presto | ROW | 部分 | -- | 版本相关 |
| Hive | STRUCT | 是 | Hive 2.x+ | ORC SerDe |
| Impala | STRUCT / ARRAY | 是 | 4.x+ | Parquet 嵌套裁剪 |
| ClickHouse | Tuple / Nested | 是 | -- | 子列独立存储 |
| DuckDB | STRUCT | 是 | 0.7+ | Parquet 嵌套读 |
| StarRocks | STRUCT / JSON | 是 | 3.x | JSON 子字段列化 |
| Doris | VARIANT | 是 | 2.1+ | 自动列化半结构化 |
| CrateDB | OBJECT | 是 | -- | 子列 Lucene 字段 |
| PostgreSQL | JSONB / ROW | 有限 | -- | JSONB 仍整列读取 |
| MySQL | JSON | -- | -- | 整列读取 |
| Oracle | JSON / OBJECT | 有限 | 21c+ | JSON 双向格式改进 |
| SQL Server | JSON (字符串) | -- | -- | JSON 为 nvarchar |
| Redshift | SUPER | 有限 | -- | |
| SingleStore | JSON | 是 | 7.3+ | JSON 列化持久化 |

嵌套列裁剪是 2020 年以来最重要的优化器进展之一：对于以 JSON / Protobuf / Avro 填充的事实表，它让列存的威力延伸到"子字段"粒度。

### 外表投影下推（Parquet / ORC / Iceberg / Hudi / Delta）

| 引擎 | Parquet | ORC | Iceberg | Hudi | Delta | CSV | 说明 |
|------|--------|-----|---------|------|-------|-----|------|
| Trino | 是 | 是 | 是 | 是 | 是 | 列名头部有 | 连接器下推 |
| Presto | 是 | 是 | 是 | 是 | 是 | -- | -- |
| Spark SQL | 是 | 是 | 是 | 是 | 是 | 是 | FileSourceScanExec |
| DuckDB | 是 | 有限 | 是 (0.10+) | -- | 是 | 是 | `read_parquet` projection |
| ClickHouse | 是 | 是 | 是 | 是 | 是 | 是 | `s3()/url()` 表函数 |
| Hive | 是 | 是 | 是 (3.x+) | 是 | 是 | 无 | SerDe 支持 |
| Impala | 是 | 是 | 是 | 是 | -- | 无 | -- |
| Athena | 是 | 是 | 是 | 是 | 是 | -- | 继承 Trino |
| Redshift Spectrum | 是 | 是 | 是 | 有限 | -- | 有限 | S3 扫描 |
| BigQuery BigLake | 是 | 是 | 是 | -- | 是 | -- | 外表 |
| Snowflake External | 是 | 是 | 是 | -- | 是 | 是 | 外表 / Iceberg table |
| StarRocks | 是 | 是 | 是 | 是 | 是 | 是 | catalog 元数据 |
| Doris | 是 | 是 | 是 | 是 | -- | 是 | 多源 catalog |
| Databend | 是 | -- | 是 | -- | 是 | 是 | 原生 Parquet |
| Firebolt | 是 | -- | 是 | -- | -- | 是 | 外表 |
| InfluxDB IOx | 是 | -- | -- | -- | -- | -- | DataFusion |
| Flink SQL | 是 | 是 | 是 | 是 | 是 | 是 | FileSource |
| PostgreSQL | parquet_fdw | -- | -- | -- | -- | file_fdw | 第三方扩展 |

## 行存 vs 列存：裁剪的本质差异

### 行存如何"假装"裁剪

PostgreSQL / MySQL / Oracle（非 IMC）等行存引擎：数据页（heap page）按行存放，一行所有列挤在一起。即便 SELECT 只要 1 列，存储层也必须把整行读进 buffer pool。"列裁剪"发生在执行器构造 `TupleTableSlot` / `Record` 时——只把需要的列投影到下游算子。

收益：降低内存带宽、减少 CPU cache 污染、让 join hash 表更窄。
代价：I/O 并未减少一个字节。

### 列存如何"真正"裁剪

ClickHouse MergeTree 最直观：每个 part 目录下，`col_a.bin / col_a.mrk` 、`col_b.bin / col_b.mrk` 是独立的文件。`SELECT col_a FROM t` 根本不会 `open()` `col_b.bin`。这种"按列独立文件"是最纯粹的投影下推。

Parquet / ORC 则采用"同一文件内按列分 chunk"：一个 row group 内有 N 个 column chunk，column chunk 有独立的 metadata（offset, length, statistics）。Reader 只 seek 到被投影列的 chunk 并读取；未投影列的 page 永远不会进入 decompressor。

Snowflake / BigQuery 的 micro-partition / Capacitor 是其变种：对用户不可见的"按列存储块 + 文件级或 service 级列索引"。

| 维度 | 行存 | 列存（每列独立文件） | 列存（单文件多 column chunk） |
|------|------|--------------------|----------------------------|
| 代表 | PG, MySQL | ClickHouse, Vertica | Parquet, ORC |
| I/O 减少 | 否 | 是 | 是 |
| 压缩比 | 一般 | 好 | 好 |
| 随机点查 | 强 | 弱 | 中 |
| 追加插入成本 | 低 | 中 | 高（需重写文件） |

## 各引擎详解

### PostgreSQL（只有逻辑层裁剪）

PostgreSQL 优化器在 planner 阶段做"targetList 推导"：`create_plan()` 从查询顶端往下逐层决定每个节点需要输出的列集合，未被需要的列不会出现在 plan tree 的 target list 里。典型发生在：

- **子查询平坦化（pull_up_subqueries）**：子查询中未被外层引用的列被丢弃
- **Join 剪枝（join removal）**：当一个 LEFT JOIN 的右表不贡献任何列且 join key 在右表唯一时，直接消除该 join
- **CTE inlining**（PG12+）：非物化 CTE 的投影可进一步下推

但因为 heap 是行存，`SeqScan` / `IndexScan` 从磁盘读的仍是整行——只是读完之后只保留投影列的 Datum。

```sql
EXPLAIN (VERBOSE, COSTS OFF)
SELECT a FROM (SELECT a, b, c FROM wide) t;
-- Seq Scan on wide
--   Output: wide.a        <-- targetList 只有 a，b/c 被丢弃
```

对 FDW（外部表），PG 通过 `GetForeignPlan` 回调把所需列列表传给 connector，由 postgres_fdw / parquet_fdw 等实现真正的远端裁剪。

### ClickHouse（列存一体化，裁剪天然）

MergeTree 表的 `{part}/columns.txt` 列出所有列，每列对应一对 `.bin`（压缩数据）+ `.mrk`（mark 索引）文件。执行器收到查询后，`MergeTreeDataSelectExecutor` 只为被投影的列构造 `MergeTreeReaderStream`，其它列的文件连 file descriptor 都不打开。

```sql
SELECT col_a FROM big_table WHERE ts > now() - INTERVAL 1 DAY;
-- 只有 col_a.bin、ts.bin 会被读取
-- 文件系统层 iostat 可清晰观察到其它列不产生 read
```

ClickHouse 的 `Nested` 与 `Tuple` 类型更进一步：`user.name` 作为子列物化为独立文件 `user.name.bin`，嵌套字段裁剪就是普通列裁剪。

### DuckDB（进程内列存 + Parquet 投影下推）

DuckDB 的 Optimizer 有专门的 `ColumnLifetimeAnalyzer` 和 `RemoveUnusedColumns` pass。对原生 DuckDB 表，storage 层是列存的，投影下推是自然的。对 `read_parquet('s3://...')`，DuckDB 会把投影列表下推到 ParquetReader，只 fetch 被投影的 column chunk：

```sql
EXPLAIN SELECT c_name FROM read_parquet('s3://bucket/customer.parquet');
--  Projection: c_name
--      parquet_scan  customer.parquet [c_name]   -- 只这一列
```

DuckDB 还会把过滤下推（filter pushdown）与投影下推组合，对 Parquet 实现 row group 跳过 + 列跳过的双重裁剪。

### Snowflake（micro-partition 级列裁剪 + 按字节计量）

Snowflake 的表被自动切分为 16MB 左右的 micro-partition，每个 micro-partition 内部按列存储并保存每列的 min/max/null count。执行计划的 TableScan 算子携带"需要哪些列"的信息，Service 层只将这些列对应的字节范围从 S3/Blob 拉取进 warehouse 的 local cache。

查询 profile 中的 "Bytes scanned" 等于**被投影列在命中的 micro-partition 里的字节数**，这正是 Snowflake 计费、优化的中心指标。

```sql
SELECT SYSTEM$CLUSTERING_INFORMATION('lineitem');
-- 可看 micro-partition 列统计
EXPLAIN SELECT l_orderkey FROM lineitem WHERE l_shipdate > '1998-01-01';
-- TableScan lineitem partitions=... columns=[l_orderkey, l_shipdate]
```

### BigQuery（按扫描字节计费，投影直接变成账单）

BigQuery 是最能体现"投影下推 = 钱"的引擎。底层存储是 Capacitor 列式格式，按列独立编码存储在 Colossus 上。Dremel 执行器只发送"需要的列"到 leaf servers。每次查询都会在 UI 展示 Bytes processed（=billed），实测：

```sql
SELECT SUM(total_amount) FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2017`;
-- Bytes processed: ~550MB  (只有 total_amount 列)

SELECT * FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2017` LIMIT 1;
-- Bytes processed: ~27GB   (所有列)
```

差距 50 倍——这直接映射到成本差距 50 倍。BigQuery 对 STRUCT / ARRAY 也支持嵌套裁剪：`SELECT event.user.id FROM t` 只触达 `event.user.id` 子列。

### Redshift（列存 + zone map）

Redshift 把表按列存储在 1MB block 中，每个 block 有 zone map（min/max）。leader node 的 planner 把投影列表和谓词一起发给 compute node 的 scan slice，slice 只读取需要列的 block。

Spectrum 外表进一步把投影下推到 S3 Parquet/ORC reader：

```sql
EXPLAIN SELECT count(*), sum(price) FROM spectrum.sales;
-- XN S3 Seq Scan ... Columns: price  (count(*) 不需列)
```

### Vertica（projection 即物理存储单元）

Vertica 里 projection 本身是物理存储概念：一张逻辑表可有多个 projection，每个 projection 是"投影列 + 排序键 + 分段键"的物化。查询时 optimizer 选择最合适（最小、最能裁剪的）projection 执行。因此 Vertica 的"投影下推"是设计原则而非后加优化。

```sql
CREATE PROJECTION sales_by_date (date_sk, amount)
AS SELECT date_sk, amount FROM sales ORDER BY date_sk;
-- SELECT sum(amount) FROM sales WHERE date_sk = ... 会走这个 2 列 projection
```

### Spark SQL（Catalyst + FileSourceScanExec）

Catalyst 中的列裁剪由两条规则完成：

- `ColumnPruning`（逻辑规则）：从 LogicalPlan 顶端往下裁剪每个算子的 output
- `PushDownPredicate` + `FileSourceStrategy`（物理规则）：把投影列表传给 DataSourceV2 Scan / FileSourceScanExec

对 Parquet / ORC，Spark 会构造 `requiredSchema`，传给 VectorizedParquetReader，只解码被投影列的 page。`spark.sql.parquet.enableVectorizedReader=true` 默认开启，配合投影下推后 row-group 级跳列 + page 级跳列双管齐下。

```scala
df.select("col_a").explain(true)
// == Optimized Logical Plan ==
// Project [col_a#12]
// +- Relation[col_a#12] parquet  <-- 只保留 col_a
// == Physical Plan ==
// *(1) FileScan parquet [col_a#12] ...
//     ReadSchema: struct<col_a:string>   <-- 下推到 reader
```

### Spark 嵌套列裁剪（since 3.0）

Spark 3.0（2020）引入 `spark.sql.optimizer.nestedSchemaPruning.enabled`（Parquet）与 `spark.sql.optimizer.nestedPredicatePushdown.enabled`。核心规则是 `NestedColumnAliasing` 与 `GeneratePruningExpression`。

```sql
-- 事件表 schema: event STRUCT<user STRUCT<id STRING, name STRING>, ts BIGINT>
SELECT event.user.id FROM events WHERE event.ts > ...;
```

3.0 之前：Spark 读取整个 `event` struct 的所有字段再提取 `user.id`，通常把整列打开反序列化。
3.0 之后：`requiredSchema` 变为 `struct<event:struct<user:struct<id:string>, ts:bigint>>`，ParquetReader 只访问 Parquet 内的 `event.user.id` 和 `event.ts` 两个 leaf column。对于 500 字段的嵌套 schema，I/O 可降到 1%。

配合 `spark.sql.optimizer.expression.nestedPruning.enabled`（3.2+），即便引用的是 `transform(events, e -> e.id)` 这种复杂表达式，嵌套裁剪也能透过 higher-order function 生效。

### Trino（连接器级 ProjectionPushdown）

Trino 的列裁剪分两层：

1. **Optimizer 规则 `PruneTableScanColumns`**：把 TableScan 的 outputSymbols 裁到最小
2. **`ApplyProjection` connector API**：把可下推的 projection 交给连接器（例如 Hive / Iceberg / Delta / JDBC），由连接器决定最终"文件/远端读什么列"

对 Hive Parquet：`hive.dereference-pushdown` 开启后支持嵌套字段（`row.sub.field`）下推。JDBC 连接器则把列列表拼进发往下游数据库的 SELECT。

```sql
EXPLAIN (TYPE IO) SELECT name FROM hive.tpch.customer;
-- columnConstraints: [name]
```

### Oracle In-Memory Column Store（12.1.0.2, 2014）

Oracle 的 IMC 把热表复制一份到 SGA 的 In-Memory Area，格式是列式 IMCU（In-Memory Compression Unit），每列独立压缩。执行器遇到 `SELECT col_a FROM t` 时，优化器选择 `TABLE ACCESS INMEMORY FULL`，只从 IMCU 中拉 col_a 的压缩块，其它列不 touch。

```sql
ALTER TABLE sales INMEMORY;
SELECT /*+ INMEMORY */ SUM(amount) FROM sales WHERE region='US';
-- Plan: TABLE ACCESS INMEMORY FULL SALES
-- Predicate pushed to IMCU scan; columns=[amount, region]
```

注意 Oracle 仍维持行存的 undo / redo 一致性——IMC 只是另一份列存副本，行存这条读路径不变。

### SQL Server Columnstore（batch mode）

SQL Server 2012 引入 non-clustered columnstore 索引，2014 引入 clustered columnstore，SQL Server 2019 引入 batch mode on rowstore (仍需 Enterprise 或 Standard 兼容级别 150+)。columnstore 以 row group（~1M 行）为单位列式存储，每 row group 每列一个 segment（压缩列块）。执行引擎 `ColumnStoreScan` 算子只读取投影列的 segment：

```sql
SET STATISTICS IO ON;
SELECT SUM(amount) FROM fact_sales;  -- 只扫 amount segment
-- LOB logical reads: 1234 (只是 amount 列)
```

batch mode 让每次处理一个 ~900 行的向量（batch），配合列裁剪达到近乎列存引擎的吞吐。

### MySQL / MariaDB（只有逻辑裁剪）

InnoDB 以页为单位（默认 16KB）读取，每一页存若干行，每一行内若有 TEXT / BLOB 且超过阈值则走 off-page 存储。对"SELECT 少量列"：

- **主键点查 / 二级索引覆盖查询**：如果所有投影列 + 谓词列都在一个二级索引中，能实现"索引覆盖"（Covering Index），不回表。这是 InnoDB 最接近"列裁剪"的路径。
- **非覆盖索引 / 全表扫描**：必须读整行，大的 BLOB/TEXT 因为 off-page 存储能意外节省 I/O，但普通列无法跳过。

```sql
-- Covering index: InnoDB 只扫 idx_customer_name 二级索引
CREATE INDEX idx_customer_name ON customer(name, city);
EXPLAIN SELECT name, city FROM customer WHERE name LIKE 'A%';
-- Extra: Using index
```

MariaDB 的 ColumnStore 存储引擎是个例外：它是完全列存的 MPP 引擎（源自 InfiniDB），对 SELECT 特定列可做真正的投影下推。

### SQLite（行存 + 只有逻辑裁剪）

SQLite 的 row 按 record format 存储，每条 record 包含所有列的 serial type header + payload。VDBE 的 `Column` 指令按列号解码（按需解码，未用到的列的 varint header 仍需跳过，但 BLOB payload 本身不解码）。因此 SQLite 的"列裁剪"效果：**不读大 BLOB 列能节省 CPU，但 I/O 页读取粒度不变**。

### Teradata（行存 + 可选 Columnar Table）

Teradata 14.0 引入 Columnar Table，允许按列（或"按列组"）存储。建表时：

```sql
CREATE TABLE sales (
  sales_id   INT,
  cust_id    INT,
  amount     DECIMAL(10,2),
  region     VARCHAR(20)
) NO PRIMARY INDEX
  PARTITION BY COLUMN;
```

可混合"部分列按列、部分列按行"的 PARTITION BY COLUMN (ROW(cust_id, sales_id), region, amount)。投影下推只对列分区生效。传统行存表仍然是行读。

### Greenplum（AOCO vs heap）

Greenplum 的表有三种存储：heap（行存）、AO row（Append-Only 行存）、AO column（AOCO，Append-Only 列存）。

```sql
CREATE TABLE sales (...) WITH (appendonly=true, orientation=column, compresstype=zstd);
```

AOCO 每列一个物理 segfile，列裁剪行为与 ClickHouse 类似：只打开被投影列的 segfile。对 heap 表和 AO row 表仍然是行读+内存裁剪。

### StarRocks / Doris（列存 + 外表 catalog）

StarRocks 的 OLAP 表采用列存 + 前缀索引 + bloom filter + bitmap index，优化器规则 `PruneTableScanColumns` 生成的投影列表直接传递给 BE 的 `OlapScanNode`，BE 只从 `rowset/segment/column_reader` 中读出需要的列。嵌套列（STRUCT / JSON / MAP）在 3.x 后支持子路径裁剪。

对 `external catalog`（Hive / Iceberg / Hudi / Delta / Paimon），StarRocks FE 会把列列表下推到 `HdfsScanNode` / `FileScanNode`，BE 底层用自己的 Parquet / ORC reader 实现 chunk 级投影。Doris 2.x 的架构与之高度相似，尤其是 VARIANT 类型（2.1+）的自动列化，实现对高频 JSON 子字段的物理列存。

### Databricks / Delta（Photon 向量化 + Parquet 下推）

Databricks Runtime 在 Spark Catalyst 之上加了 Photon 向量化引擎。Delta 表的物理存储是 Parquet + JSON transaction log，投影下推经过：

1. Catalyst 的 `ColumnPruning` 与 `NestedColumnAliasing`
2. Delta scan 构造 `requiredSchema` + file list
3. Photon 的 Parquet reader（native C++）按列 chunk 向量化读取

Delta Lake 的 deletion vectors / column mapping 特性对投影下推无影响，因为它们是行级元数据。

### TiDB（行存 TiKV + 列存 TiFlash）

TiDB 的存储分两路：TiKV（行存 KV）和 TiFlash（列存副本，基于 ClickHouse 魔改）。优化器的 HTAP cost model 会为每个物理算子选择 TiKV 或 TiFlash，投影列表通过 coprocessor protocol 下推：

- **TiKV coprocessor**：收到 `DAGRequest.executors` 中的 `Selection + TableScan.columns`，按列名过滤 row
- **TiFlash**：收到同样的列列表，但因为是列存，真的只读对应列的数据

```sql
EXPLAIN SELECT a FROM wide;
-- TableReader_5  root  data:TableFullScan_4
-- TableFullScan_4  cop[tiflash] table:wide keep order:false
```

### OceanBase（4.x 行列混存）

OceanBase 4.x 重构存储层为"行列混存"：宏块内部可以按列组织（Column Store）。对 OLAP 风格查询，优化器生成的 plan 会带列裁剪，物理层直接按列读 microblock。4.2+ 支持外表，投影下推通过 `EXTERNAL_TABLE` 参数传递给 Parquet 读取器。

### DuckDB（细节补充）

DuckDB 还有一个很独特的设计：`FILTER_PUSHDOWN` 与 `PROJECTION_PUSHDOWN` 都是 Optimizer Pipeline 中的独立 pass，它们与 `STATISTICS_PROPAGATION` 交互——若统计信息显示某列无用，pass 会主动把该列从 upstream 的 projection list 中移除。对 `read_parquet` 的 late materialization：DuckDB 会先对用于 filter 的列做 column chunk 读取 + 条件计算得到匹配行号，再对被投影的其它列只读匹配行号对应的 page 范围。

### Flink SQL（源 connector 级下推）

Flink 的 DynamicTableSource 接口有 `SupportsProjectionPushDown`，各 connector 选择是否实现。Kafka JSON / Debezium 源 connector 实现 projection pushdown 后，可以避免反序列化未投影字段，尤其对深层嵌套 JSON 收益明显。

对 Paimon / Iceberg / Hive FileSystem source，投影下推最终落到 Parquet/ORC reader。对 JDBC source，它落到远端 SELECT 的列列表。

### Materialize / RisingWave（流式视图）

两者都是增量物化视图引擎，列裁剪意义是"减少每条流事件维持的状态列"。未被 downstream 需要的列不会进入 dataflow operator 的 key/value 字节，显著减少状态存储空间。对外部源（Kafka / Parquet / Postgres CDC）还可以进一步下推到源解析器。

### ClickHouse 细节补充：投影与物化视图

ClickHouse 的 `projection`（注意：与 Vertica 同名但概念不同）是表内的"另一份预计算列子集"，支持自动路由：

```sql
ALTER TABLE events
ADD PROJECTION p_user
    (SELECT user_id, count() GROUP BY user_id);
```

查询命中 projection 时，只读 projection 对应的列文件，相当于"在 ClickHouse 里做了 Vertica 式的 projection"。这是列裁剪 + 聚合预计算的组合拳。

## Parquet 投影下推深度解析

Parquet 文件的物理布局决定了它为什么能高效列裁剪：

```
Parquet File
├── Row Group 0
│   ├── Column Chunk col_a  (metadata: offset=0, length=120KB, stats=...)
│   │     └── Page 0, Page 1, ... (压缩)
│   ├── Column Chunk col_b  (metadata: offset=120K, length=80KB, stats=...)
│   └── Column Chunk col_c  (metadata: offset=200K, length=60KB, stats=...)
├── Row Group 1
│   └── ...
└── Footer
    ├── File schema
    ├── Row group metadata (每个 row group 每列的 offset/length/stats)
    └── Key-value metadata
```

一次典型的投影裁剪读流程：

1. **读 Footer**（尾部 4 字节给出 footer length，然后 seek 到 footer 区域读取 Thrift 结构）
2. **按 schema 解析被投影列的 leaf column 索引**
3. **对每个 row group，按投影列的 metadata 定位 column chunk 的 offset/length**
4. **只发起这些 offset/length 的 range read**（对 S3/GCS/OSS 就是 HTTP Range GET）
5. **对拉回的 column chunk 做 page 级解压**

未被投影的列，从 HTTP / 磁盘 I/O 到解压 / 解码全部跳过。对宽表这是数量级的节省。

### Parquet 嵌套字段的 definition/repetition levels

Parquet 通过 Dremel 论文的 definition level + repetition level 把嵌套结构压平成多个 leaf column。`STRUCT<user:STRUCT<id:INT64, name:STRING>, tags:ARRAY<STRING>>` 对应 3 个 leaf：

- `user.id` (optional, int64)
- `user.name` (optional, string)
- `tags.element` (repeated, string)

每个 leaf 独立存成 column chunk——所以 "只查 `user.id`" 的裁剪和 "只查一个顶级列" 完全等价。这就是为什么 Spark 3.0 能够对 Parquet 做嵌套列裁剪，而对 JSON/Avro 相对更难（两者 leaf 级物理独立性较弱）。

## Spark optimizedPlan 演示

Spark 的 `.explain(mode = "extended")` 显示 Parsed / Analyzed / Optimized / Physical 四阶段计划。列裁剪发生在 Optimized 阶段：

```scala
spark.read.parquet("/data/events").select($"event.user.id").where($"event.ts" > 1_700_000_000L).explain(true)
```

```
== Parsed Logical Plan ==
Project [event.user.id]
+- Filter (event.ts > 1700000000)
   +- Relation[event#0] parquet

== Optimized Logical Plan ==
Project [event.user.id AS id#2]
+- Filter (event.ts#3L > 1700000000)
   +- Project [event#0.user.id AS event.user.id, event#0.ts AS event.ts]   <-- 嵌套裁剪
      +- Relation[event#0] parquet

== Physical Plan ==
*(1) Project [event.user.id]
+- *(1) Filter (event.ts > 1700000000)
   +- *(1) FileScan parquet [event#0]
        DataFilters: [event.ts > 1700000000]
        ReadSchema: struct<event:struct<user:struct<id:string>,ts:bigint>>  <-- 只读 2 个 leaf
```

`ReadSchema` 行是投影下推的"证据"——它是 Spark 传给底层 ParquetReader 的 `requiredSchema`。可以通过这行快速判断嵌套裁剪有没有生效。

## 列裁剪的典型 SQL 模式与优化器行为

### 模式 1：JOIN 列裁剪

```sql
SELECT o.order_id, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2024-01-01';
```

优化器的推导：

- 顶层 `SELECT` 需要 `o.order_id`, `c.name`
- `JOIN` 条件需要 `o.customer_id`, `c.customer_id`
- `WHERE` 需要 `o.order_date`
- 因此 `orders` 表只需要 `order_id, customer_id, order_date`；`customers` 表只需要 `customer_id, name`

无论 orders 有多少其它列（shipping_address / notes / items 数组 / ...），列存引擎都只读这 3 个 + 2 个列。在 500 列宽表上，这是 99% I/O 节省。

### 模式 2：SELECT * 的危险

```sql
SELECT * FROM wide_fact WHERE id = 123;
```

`SELECT *` 会导致所有列都被投影。对列存，这意味着"打开每一列的 chunk / segment"，在 BigQuery 上意味着"按全表 bytes 计费"。这也是 `SELECT *` 在 OLAP 场景下被强烈劝阻的根本原因。

### 模式 3：子查询 / CTE 的列裁剪穿透

```sql
WITH t AS (SELECT a, b, c, d FROM wide)
SELECT a FROM t;
```

优化器必须能"看穿" CTE / 子查询，把 outer 的列需求传导进去。PostgreSQL 12 之前的 CTE 是 optimization fence（CTE 内部无法被外层裁剪穿透），12 之后默认 inline，才能穿透。ClickHouse、DuckDB、Spark、Trino 都默认 CTE 可穿透。

### 模式 4：UNION / UNION ALL 的裁剪

```sql
SELECT a FROM (
  SELECT a, b, c FROM t1
  UNION ALL
  SELECT a, b, c FROM t2
) u;
```

优化器把 outer 只需 `a` 的需求推给 UNION 的每个分支，使每个子查询只读 `a`。多数主流引擎都支持这一穿透。

### 模式 5：视图展开

```sql
CREATE VIEW v AS SELECT a, b, c, d FROM wide;
SELECT a FROM v;
```

对"可内联视图"（simple view），引擎在 plan 时直接把视图定义展开，然后列裁剪像普通子查询一样工作。对"物化视图"则取决于引擎是否支持基于物化视图的投影子集路由。

## 向量化执行与列裁剪的协同

现代列存引擎（ClickHouse、DuckDB、StarRocks、Doris、Photon、Velox）普遍使用**向量化执行**：一次处理一个"列向量"（Arrow-like layout）而非一行。向量化天生与列裁剪协同：

- 未被投影的列根本不构造向量
- 被投影列的向量在整个 pipeline 中保持列布局，直到最后才物化为行发送给客户端
- CPU 的 SIMD 指令对连续列数据的处理效率远高于行数据

这是 Spark Photon / ClickHouse / DuckDB 相对于 Hive MR / 早期 Spark 的核心性能来源之一。

## 与其它下推优化的协同

投影下推（Projection Pushdown）通常不是孤立的——它与以下下推优化协同：

| 下推类型 | 作用 | 与投影下推的关系 |
|---------|------|-----------------|
| Predicate Pushdown | 把 WHERE 条件推到存储层 | 组合后可实现"只读命中 row group 的被投影列" |
| Aggregation Pushdown | 把 SUM/COUNT/MIN/MAX 推给存储 | 列存 zone map / Parquet column stats 可完全免扫 |
| Limit Pushdown | 把 LIMIT N 推给扫描层 | 列存早停减少后续列读 |
| Partition Pruning | 按分区字段值跳过整个分区 | 与列裁剪正交，I/O 节省相乘 |
| Topk Pushdown | ORDER BY ... LIMIT N 推给 scan | 与投影一起决定读哪些列到内存 |
| Runtime Filter | Join build 侧生成 filter 推给 probe | 减少 probe 列的扫描量 |

一个"教科书级"的下推组合：对 5TB Parquet 事实表的查询 `SELECT a, sum(b) FROM fact WHERE dt='2024-06-01' AND region='US' GROUP BY a`，顺序的优化过程是：

1. **分区裁剪**：按 `dt='2024-06-01'` 裁到当天的 5GB
2. **文件级统计裁剪**：按 Parquet footer 的 min/max 跳过 region 不匹配的 row group，剩 1.5GB
3. **投影下推**：只读 a, b, region 三列，剩 100MB
4. **谓词下推**：在列 chunk 扫描时 SIMD 评估 `region='US'`，得到有效行数
5. **聚合**：向量化 hash agg

原始 5TB → 最终 I/O 100MB，50000x 减少——这就是现代 lakehouse 架构的工程奇迹。

## 关键发现

1. **"列裁剪"是两种完全不同的能力**：逻辑层列裁剪几乎所有关系型引擎都有（纯 plan tree 裁剪），但物理层投影下推（真正减少磁盘/网络 I/O）基本上等价于"使用列存或外部列存格式"。

2. **列存是投影下推的充分条件**：ClickHouse、Vertica、DuckDB、Snowflake、BigQuery、Redshift、StarRocks、Doris、MonetDB、Firebolt 等原生列存一律天然支持。行存引擎（PG、MySQL、Oracle non-IMC）只能减少内存 / CPU，不能减少磁盘 I/O。

3. **Parquet / ORC 是异构世界的"通用投影下推层"**：Spark、Trino、Presto、Hive、Impala、DuckDB、Athena、Flink、ClickHouse 都可以对 Parquet / ORC 外部表做 row group + column chunk 级的双重裁剪。这是 Lakehouse 架构之所以可行的关键物理基础。

4. **BigQuery 把投影下推变成了用户可见的经济学指标**：按 scanned bytes 计费让每个工程师都被"教育"要写 `SELECT col_a`，这是其它所有引擎没有的直接激励。Redshift Spectrum、Athena 也按字节计费，有类似效果。

5. **嵌套列裁剪是 2020 年之后的优化器前沿**：Spark 3.0 的 `nestedSchemaPruning`、Trino 的 `hive.dereference-pushdown`、BigQuery 一直支持的 STRUCT 路径裁剪，把列存的威力延伸到"子字段粒度"，对 JSON / Protobuf / Avro 填充的事实表是数量级加速。

6. **JSON 型数据的裁剪取决于"是否被列化"**：PostgreSQL 的 JSONB、MySQL 的 JSON 是整列存储的 TOAST / LONGBLOB，子字段查询必须读整列再提取；Snowflake VARIANT、BigQuery JSON、Doris VARIANT、StarRocks 3.x JSON 则在写入时把高频子字段自动列化，实现"子字段级"投影下推。

7. **`EXPLAIN` 的"投影列"行是最简单的验证点**：Spark 的 `ReadSchema`、Trino 的 `columnConstraints`、ClickHouse 的 `ReadFromMergeTree` 的 `Columns`、DuckDB 的 `parquet_scan [columns]`、Snowflake 的 Scan `columns`——一看这行就知道投影下推生效没有。

8. **Vertica 的"projection = 物理存储"代表了另一种哲学**：不依赖优化器推导，用户显式设计 projection 作为物化的"列子集 + 排序 + 分段"，查询命中合适的 projection 即自动享受最激进的列裁剪 + 数据局部性。

9. **Oracle In-Memory（2014）是行存世界"曲线救国"的典范**：OLTP 的 redo / undo 都走行存路径，分析查询走 IMC 列存副本；投影下推只对 IMC 路径生效，这是 HTAP 最早的商业化尝试之一。

10. **列裁剪、谓词下推、聚合下推是优化器"下推三件套"**：单独做任何一个都不够，只有三者组合才能在 Parquet 外表上达到接近原生列存数据库的性能。这也是现代查询引擎（Trino、Spark、StarRocks、Doris、Databend、Firebolt）共同演进的路线。

## 附：各引擎 EXPLAIN 对照

以下汇总"如何从 EXPLAIN 中看到投影下推"的方法，按引擎字母顺序排列。

### PostgreSQL

```sql
EXPLAIN (VERBOSE, COSTS OFF) SELECT a FROM wide;
-- Seq Scan on public.wide
--   Output: a
```

关注 `Output:` 行，它显示 targetList。

### MySQL / MariaDB

```sql
EXPLAIN FORMAT=JSON SELECT a FROM wide;
```

JSON 输出中的 `used_columns` 数组显示被引用的列。行存所以仍读整行，但能看出 planner 知道哪些列需要。

### ClickHouse

```sql
EXPLAIN SELECT a FROM wide;
-- ReadFromMergeTree
--   ReadType: Default
--   Parts: 4
--   Granules: 1200
-- SELECT a FROM wide   <-- 只 a 列
```

更详细：`EXPLAIN actions=1`，`EXPLAIN pipeline`。

### DuckDB

```sql
EXPLAIN SELECT a FROM read_parquet('x.parquet');
-- │  PROJECTION   │
-- │      a        │
-- └───────────────┘
-- │  PARQUET_SCAN │
-- │    columns:   │
-- │      a        │
```

### Snowflake

查看 Query Profile 的 TableScan 节点：`columns` 属性列出扫描的列；"Bytes scanned" 指标反映真实扫描字节。

### BigQuery

查看 Query Details 的 "Bytes processed"——只增加被投影列的字节数。Stages 的 "Read" 步骤可看到 columns。

### Redshift

```sql
SET enable_result_cache_for_session TO off;
EXPLAIN SELECT amount FROM sales;
-- XN Seq Scan on sales  (cost=...)
--   ->  Columns: amount
```

`SVL_QUERY_SUMMARY` 视图的 `rows` 与 `bytes` 能对照确认列裁剪效果。

### Spark SQL

已在前文展示。关注 `FileScan` 的 `ReadSchema`。

### Trino / Presto

```sql
EXPLAIN (TYPE IO) SELECT col_a FROM hive.db.t;
-- inputTableColumnInfos: [col_a]
```

`EXPLAIN ANALYZE VERBOSE` 还会显示每个 scan operator 的 `inputSize`。

### StarRocks / Doris

```sql
EXPLAIN VERBOSE SELECT a FROM wide;
-- OlapScanNode
--   PROJECTIONS: a
--   TABLE: wide
```

FE 的执行计划直接打印 SELECTED_COLUMNS / projections。

### TiDB

```sql
EXPLAIN SELECT a FROM wide;
-- TableReader_5 ... data:TableFullScan_4
-- TableFullScan_4  cop[tikv/tiflash] table:wide  keep order:false
```

`EXPLAIN FORMAT='verbose'` 能看到 push down 的列列表。

### Impala

```sql
EXPLAIN SELECT col_a FROM t;
-- 00:SCAN HDFS [db.t]
--    partitions=1/1  files=1  size=...
--    predicates: ...
--    runtime filters: ...
--    columns: col_a
```

## 投影下推对 HTAP 架构的意义

HTAP（Hybrid Transactional / Analytical Processing）系统——TiDB、OceanBase、SingleStore、Oracle IMC、SQL Server（columnstore 索引）——的核心设计决策之一是"AP 路径上如何做到极致的投影下推"。因为：

- OLTP（行存）路径不需要投影下推，点查从 B+Tree 一次取整行是最优的
- OLAP（列存）路径若做不到投影下推，列存就失去了意义

这推动了几种架构选择：

1. **双副本（TiDB）**：TiKV 存行，TiFlash 存列，优化器按 cost 选路径
2. **双存储区（Oracle）**：行存 + 内存列存，同步维护
3. **双索引（SQL Server）**：行存主索引 + 列存索引，同一张表
4. **双格式 row group（SingleStore）**：单存储引擎内混合行存 rowstore 和列存 columnstore 分区

无论哪种，投影下推都只在列存路径上发挥作用——它决定了 HTAP 在 AP 负载上的性能上限。

## 反模式与常见陷阱

即便引擎支持投影下推，用户的 SQL 写法仍可能让它失效。以下是常见陷阱：

### 陷阱 1：`SELECT *` 包在子查询里

```sql
SELECT id FROM (SELECT * FROM wide) t;
```

多数现代优化器（PG、Spark、Trino、ClickHouse、DuckDB、Snowflake）都能穿透并裁剪成 `SELECT id FROM wide`。但一些旧引擎或特殊场景（例如 view 被声明为 `SECURITY INVOKER` + `OPTIMIZER_FENCE`）会保留 `SELECT *`，导致真的读全列。

### 陷阱 2：UDF / 黑盒函数

```sql
SELECT my_udf(t) FROM wide t;
```

当 UDF 接收整行对象（Spark 的 `Row`、PG 的 `RECORD`、Oracle 的 `%ROWTYPE`）时，优化器无法知道 UDF 内部访问了哪些字段，只能保守地把所有列都投影进来。解决方案是把 UDF 的参数改为具体字段：`my_udf(t.col_a, t.col_b)`。

### 陷阱 3：`ORDER BY` / `DISTINCT` 引用额外列

```sql
SELECT DISTINCT a FROM wide ORDER BY last_modified;
```

`ORDER BY last_modified` 强制把 `last_modified` 加入投影列表，即便最终输出不含它。Spark / Trino / PG 都会带这个列去 scan，想要更激进就只能先 distinct 再排序。

### 陷阱 4：JSONB 子字段访问

```sql
-- PostgreSQL
SELECT data->>'user_id' FROM events;
```

即便只访问 `user_id`，PG 仍会把整个 `data` 列（JSONB TOAST 对象）读进内存解析。真正的子字段裁剪需要"把 JSONB shredded 到多列"——这正是 Snowflake VARIANT、BigQuery JSON、Doris VARIANT 做的事。

### 陷阱 5：SELECT 列表中的相关子查询

```sql
SELECT (SELECT max(b) FROM wide w2 WHERE w2.key = w1.key), a FROM wide w1;
```

相关子查询 decorrelation 失败时，每行都要扫子查询的 b 列，变成"按行嵌套循环 + 每次全扫 b"。现代优化器（PG 15+、Spark、Trino、CockroachDB、OceanBase）有 decorrelation 规则把它改写为 join，但写法上仍应尽量避免相关子查询。

### 陷阱 6：动态 SQL / ORM 的全列拉取

如果应用层用 ORM（Hibernate、ActiveRecord、Entity Framework）默认的 eager fetch，往往会生成 `SELECT col_1, col_2, ..., col_N FROM t` 动态拼接的全列查询。这在行存上只是 CPU 浪费，但在列存上直接毁掉投影下推的全部价值。OLAP 场景务必审计 ORM 生成的 SQL。

## 历史演进时间线

| 年份 | 事件 |
|------|------|
| 1985 | System R 完成，关系优化器的目标列（targetList）概念诞生 |
| 2005 | C-Store 论文（Stonebraker 等），商用列存数据库理论奠基 |
| 2005 | Vertica 公司成立，projection 作为物理存储单元 |
| 2006 | Oracle 在 Exadata 引入 Smart Scan，最早的"下推到存储"之一 |
| 2010 | Dremel 论文（Google），Parquet / ORC 嵌套列编码的理论原型 |
| 2012 | Parquet / ORC 开源项目启动 |
| 2012 | SQL Server 2012 引入 non-clustered Columnstore Index |
| 2014 | Oracle Database In-Memory (12.1.0.2)，行存 + IMC 双模式 |
| 2014 | Snowflake GA，micro-partition + 按列计费模型 |
| 2015 | Apache Spark 1.3+ DataFrame，Catalyst 的 ColumnPruning 规则 |
| 2016 | BigQuery 按 bytes scanned 计费，把投影下推变成经济学指标 |
| 2018 | ClickHouse 开源普及，MergeTree 每列独立文件成为教科书案例 |
| 2019 | Delta Lake / Iceberg / Hudi 普及，投影下推落到 Parquet 层 |
| 2020 | Spark 3.0 `spark.sql.optimizer.nestedSchemaPruning.enabled` |
| 2021 | DuckDB 1.0 接近 GA，进程内列存 + Parquet 下推成为轻量分析代表 |
| 2022 | Trino `hive.dereference-pushdown` 嵌套字段下推稳定 |
| 2023 | StarRocks / Doris 3.x STRUCT / JSON / VARIANT 子字段裁剪 |
| 2024 | Iceberg v2、Puffin 文件、Apache XTable 推动外表下推更标准化 |

这条时间线显示：投影下推的核心理论在 20 世纪 80 年代就已存在，但把它从"逻辑层"推到"物理层、存储层、甚至文件格式层"花了整整 40 年，每一次进步都对应一次查询成本的数量级下降。

## 参考

- 本站相关文章：
  - `query-rewrite-rules.md`：查询重写规则概览，列裁剪属于其中"投影相关重写"一类
  - `optimizer-evolution.md`：优化器演进史，从 System R 的列投影到 Catalyst 的嵌套裁剪
  - `sampling-query.md`：采样查询（另一种"少读数据"的策略，与投影下推正交）
- 外部文献：
  - Dremel paper (Melnik et al., VLDB 2010)：Parquet repetition/definition levels 的源头
  - Spark SPIP "Nested Schema Pruning for Parquet"（SPARK-4502, SPARK-25556）
  - Snowflake SIGMOD 2016 paper "The Snowflake Elastic Data Warehouse"
  - "Column-Stores vs. Row-Stores: How Different Are They Really?" (Abadi et al., SIGMOD 2008)
  - Oracle Database In-Memory white paper (2014)
