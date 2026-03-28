# Spark SQL: Indexes (索引与数据布局优化)

> 参考资料:
> - [1] Spark SQL - Performance Tuning
>   https://spark.apache.org/docs/latest/sql-performance-tuning.html
> - [2] Delta Lake - Data Skipping & Z-Ordering
>   https://docs.delta.io/latest/optimizations-oss.html
> - [3] Apache Iceberg - Hidden Partitioning
>   https://iceberg.apache.org/docs/latest/partitioning/


## 1. 核心设计: Spark SQL 没有传统索引


 Spark SQL 不支持 CREATE INDEX。这是有意为之的设计决策:
   传统索引 (B+Tree/Hash):  针对单行随机查找优化，适合 OLTP
   Spark 的优化策略:         针对批量扫描优化，适合 OLAP/ETL

 在列式存储（Parquet/ORC）+ 分布式计算的架构下，传统索引的价值很低:
### 1. 数据分布在多个节点和文件上，全局 B+Tree 无法高效维护

### 2. 列式存储本身带有列统计信息（min/max/null count），可以做 Data Skipping

### 3. 批量扫描时顺序读 >> 随机读，索引的随机 I/O 模式反而更慢


 对比:
   Hive:       曾支持 CREATE INDEX（Hive 0.7-2.x），3.0 移除——证明索引在大数据无用
   Flink SQL:  无索引概念（流处理引擎，数据持续流动）
   Trino:      无索引（依赖底层数据源的 Data Skipping）
   MaxCompute: 无传统索引，通过 Clustering 和 Range Index 优化
   ClickHouse: MergeTree 引擎有 Primary Key 索引（稀疏索引，本质是排序键）
   BigQuery:   无索引，通过 Clustering 和分区实现优化

 对引擎开发者的启示:
   如果你在设计 OLAP/数据湖引擎，不要照搬 OLTP 的 B+Tree 索引。
   列式存储的 min/max 统计 + 分区裁剪 + 排序键才是正确的优化方向。
   ClickHouse 的稀疏索引（每 8192 行一个索引条目）是 OLAP 索引的好参考。

## 2. 分区: 最主要的优化机制


分区 = 文件系统目录，查询时通过分区裁剪跳过不需要的目录

```sql
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) USING PARQUET
PARTITIONED BY (order_date DATE);

```

 查询时 Spark 只扫描匹配的分区目录
 SELECT * FROM orders WHERE order_date = '2024-06-15';
 物理计划中会显示 PartitionFilters: [order_date = 2024-06-15]

## 3. 分桶: Hash 分布优化 JOIN


```sql
CREATE TABLE bucketed_users (
    user_id    BIGINT,
    username   STRING,
    created_at TIMESTAMP
) USING PARQUET
CLUSTERED BY (user_id) INTO 32 BUCKETS;

CREATE TABLE bucketed_orders (
    order_id   BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2)
) USING PARQUET
CLUSTERED BY (user_id) SORTED BY (amount) INTO 32 BUCKETS;

```

 两表都按 user_id 分桶时，JOIN 可以避免 Shuffle（Bucket Join）
 这是 Spark SQL 中分桶的核心价值——用建表时的预分布换取查询时的 Shuffle 开销

 设计分析:
   分桶在实践中使用率不高，原因:
### 1. 写入时必须按桶排列数据，增加写入成本

### 2. 桶数量在建表时固定，后续难以调整

### 3. AQE（自适应查询执行）在很多场景下能自动优化 JOIN

### 4. Delta Lake 的 Z-ORDER 提供了更灵活的替代方案


## 4. Delta Lake: Z-ORDER（多维聚簇）


Z-ORDER 通过空间填充曲线将多个列的值交织排列，使相关数据物理上更紧凑

```sql
OPTIMIZE orders ZORDER BY (user_id, order_date);

```

 原理: 传统排序只能优化第一个排序键的查询，Z-ORDER 同时优化多个列的查询
 适用场景: 查询经常按 user_id 或 order_date 过滤时
 不适用: 只有一个过滤列时（普通排序更高效）

 对比:
   ClickHouse: ORDER BY (col1, col2) 只优化 col1 前缀查询
   BigQuery:   CLUSTER BY 类似 Z-ORDER（但实现细节不公开）
   Snowflake:  CLUSTER BY 支持自动 reclustering
   DuckDB:     无 Z-ORDER，但有 ART 索引

## 5. Delta Lake: Bloom Filter 索引


Bloom Filter 用于精确匹配查询（点查询）的加速

```sql
CREATE BLOOMFILTER INDEX ON TABLE orders
FOR COLUMNS (user_id OPTIONS (fpp=0.1, numItems=1000000));

DROP BLOOMFILTER INDEX ON TABLE orders FOR COLUMNS (user_id);

```

 fpp = False Positive Probability（误判率），越低越精确但占用空间越大
 numItems = 预期的不同值数量

 Bloom Filter vs B+Tree:
   B+Tree: 精确范围查询，维护成本高，OLTP 场景
   Bloom Filter: 只支持等值查询（=, IN），空间效率极高，只能排除不匹配的文件
   Spark 的 Bloom Filter 是文件级别的——快速判断某个文件是否可能包含目标值

## 6. Iceberg: Hidden Partitioning with Transforms


```sql
CREATE TABLE catalog.db.events (
    id         BIGINT,
    event_time TIMESTAMP,
    user_id    BIGINT
) USING ICEBERG
PARTITIONED BY (days(event_time), bucket(16, user_id));

```

 Iceberg 的 Hidden Partitioning 是比 Hive 分区更优雅的设计:
   Hive/Spark 分区: 用户必须知道分区列并在查询中使用精确的分区值
   Iceberg 分区:    用户查询 WHERE event_time > '2024-01-01' 时自动裁剪
                    不需要知道分区是按天还是按月
 Transform 函数: year(), month(), day(), hour(), bucket(n, col), truncate(n, col)

## 7. Data Skipping: 列式存储的内置优化


 Parquet/ORC 文件的 Row Group / Stripe 自动记录每列的统计信息:
   min/max:     列的最小/最大值
   null_count:  NULL 值数量
   distinct:    不同值数量（可选）
 查询时 Spark 读取文件 footer 的统计信息，跳过不可能包含目标数据的 Row Group
 无需任何 CREATE INDEX 语句——这是列式存储格式的内置能力

## 8. 统计信息收集（CBO 优化器依赖）

```sql
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, age;
ANALYZE TABLE orders COMPUTE STATISTICS FOR ALL COLUMNS;

```

查看表统计信息和文件布局

```sql
DESCRIBE EXTENDED users;
DESCRIBE FORMATTED users;
SHOW PARTITIONS orders;

```

 统计信息用于 Catalyst 优化器的 CBO（Cost-Based Optimization）:
   行数估算 → 选择 JOIN 策略（Broadcast vs Sort-Merge vs Shuffle-Hash）
   列基数 → 选择过滤顺序和聚合策略
   数据大小 → 决定 Shuffle 分区数

 对比:
   MySQL:      ANALYZE TABLE 更新 InnoDB 统计信息，影响 JOIN 顺序和索引选择
   PostgreSQL: ANALYZE 更新 pg_statistics，autovacuum 自动执行
   Hive:       ANALYZE TABLE 类似但执行更慢（MapReduce 作业）
   Flink SQL:  不需要 ANALYZE（流处理无统计信息概念）

## 9. 版本演进与未来方向

Spark 2.0: 分区裁剪、CBO 基础
Spark 2.4: Bucketing 优化
Spark 3.0: AQE 运行时重优化（减少对静态统计的依赖）、动态分区裁剪
Spark 3.3: Bloom Filter Index（Delta Lake）
未来方向: 列式存储的 Secondary Index（Databricks Liquid Clustering）
Liquid Clustering 是 Z-ORDER 的进化——增量聚簇，无需 OPTIMIZE 全表

