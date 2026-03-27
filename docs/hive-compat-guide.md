# Hive 兼容引擎开发指南

如果你在开发一个 Hive 兼容引擎（如 MaxCompute、Spark SQL、Impala、Databricks、Flink SQL），本文档帮助你了解 HiveQL 的核心设计决策和兼容性要点。

## Hive 生态的独特性

Hive 不是传统数据库——它是"SQL on Hadoop"的先驱，很多设计源于 MapReduce 的限制。理解这些历史背景对引擎开发者至关重要。

### 核心设计哲学

1. **Schema-on-Read**: 数据先写入再定义 schema，不在写入时校验类型
2. **不可变数据**: 早期不支持 UPDATE/DELETE（文件是 append-only 的）
3. **分区 = 目录**: PARTITIONED BY 创建的是 HDFS 目录结构
4. **外部表 vs 内部表**: 外部表 DROP 时不删数据（数据不属于 Hive 管理）
5. **SerDe 架构**: 数据的序列化/反序列化由独立的 SerDe 类处理

## 兼容性分级

### P0: 必须兼容

| 特性 | 关键文件 | 重要性 |
|------|---------|--------|
| SELECT + WHERE + JOIN | [query/joins/hive.sql](../query/joins/hive.sql) | 所有查询的基础 |
| INSERT INTO / INSERT OVERWRITE | [dml/insert/hive.sql](../dml/insert/hive.sql) | Hive 的主要写入方式，INSERT OVERWRITE 是杀手特性 |
| PARTITIONED BY | [advanced/partitioning/hive.sql](../advanced/partitioning/hive.sql) | Hive 核心概念，分区 = 目录 |
| STORED AS (ORC/Parquet) | [ddl/create-table/hive.sql](../ddl/create-table/hive.sql) | 文件格式决定性能 |
| EXTERNAL TABLE | [ddl/create-table/hive.sql](../ddl/create-table/hive.sql) | 数据湖场景必须 |
| GROUP BY + 基本聚合 | [functions/aggregate/hive.sql](../functions/aggregate/hive.sql) | MapReduce 的 reduce 阶段 |
| LATERAL VIEW explode | [types/array-map-struct/hive.sql](../types/array-map-struct/hive.sql) | 展开数组/Map 的标准方式 |

### P1: 应该兼容

| 特性 | 关键文件 | 说明 |
|------|---------|------|
| 窗口函数 (0.11+) | [query/window-functions/hive.sql](../query/window-functions/hive.sql) | 分析场景核心 |
| CTE (0.13+) | [query/cte/hive.sql](../query/cte/hive.sql) | 复杂查询必需 |
| UNION ALL | [query/set-operations/hive.sql](../query/set-operations/hive.sql) | 注意: Hive 的 UNION 默认是 UNION ALL 行为(2.0前) |
| UDF/UDAF/UDTF | [advanced/stored-procedures/hive.sql](../advanced/stored-procedures/hive.sql) | 可扩展性的核心 |
| 动态分区 | [advanced/partitioning/hive.sql](../advanced/partitioning/hive.sql) | INSERT 时自动创建分区 |
| SORT BY / DISTRIBUTE BY / CLUSTER BY | [dml/insert/hive.sql](../dml/insert/hive.sql) | Hive 独有的分发排序语义 |

### P2: 可选兼容

| 特性 | 说明 |
|------|------|
| UPDATE/DELETE (0.14+ ACID) | 需要 ORC + 事务表，大多数 Hive 用户不用 |
| MERGE (2.2+) | 同上，需要 ACID 支持 |
| MSCK REPAIR TABLE | 修复分区元数据，可用替代命令 |
| TRANSFORM/MAP/REDUCE | 调用外部脚本，已被 UDF 替代 |
| Bucketing (CLUSTERED BY INTO N BUCKETS) | 分桶优化，使用率较低 |

## Hive 最大的 10 个坑

### 1. INSERT OVERWRITE 不是 DELETE + INSERT

详见 [dml/insert/hive.sql](../dml/insert/hive.sql)

```sql
-- INSERT OVERWRITE 替换整个分区（或整个表）的数据
INSERT OVERWRITE TABLE orders PARTITION(dt='2024-01-15')
SELECT * FROM staging_orders WHERE dt = '2024-01-15';
```

- 这是 Hive 的"更新"方式——重写整个分区的文件
- 原子性保证: 要么全部成功要么全部回滚（通过文件重命名）
- 没有行级粒度，只有分区级粒度
- **对引擎开发者**: 如果你的引擎基于文件存储，INSERT OVERWRITE 比实现行级 UPDATE 简单得多

### 2. 分区列不是普通数据列

详见 [advanced/partitioning/hive.sql](../advanced/partitioning/hive.sql)

```sql
CREATE TABLE orders (
    id BIGINT,
    amount DECIMAL(10,2)
) PARTITIONED BY (dt STRING, region STRING);
```

- `dt` 和 `region` 不在数据文件中，而是编码在目录路径中: `/orders/dt=2024-01-15/region=us/`
- SELECT * 会自动包含分区列
- 分区列的类型通常是 STRING（即使逻辑上是 DATE）
- **对引擎开发者**: 分区列的存储和普通列完全不同，查询时需要从文件路径解析

### 3. STRING 是万能类型

详见 [types/string/hive.sql](../types/string/hive.sql)

- Hive 中 STRING 类型没有长度限制
- 很多用户把所有列都定义为 STRING（schema-on-read 哲学）
- VARCHAR(n) 和 CHAR(n) 在 0.12+ 才加入，使用率低
- **对引擎开发者**: 如果兼容 Hive 表，要做好处理全 STRING schema 的准备

### 4. NULL 处理差异

```sql
-- Hive 的 NULL 处理有几个独特行为:
-- 1. 空字符串 '' ≠ NULL（和 Oracle 不同）
-- 2. 但空字符串在某些函数中被视为 NULL（如 CONCAT 的旧行为）
-- 3. NULL 在 GROUP BY 中算一个分组
-- 4. NULL 在 ORDER BY 中排在最前面（默认 NULLS FIRST，和 PG 相同，和 MySQL 相反）
```

### 5. JOIN 的历史限制

详见 [query/joins/hive.sql](../query/joins/hive.sql)

- 早期 Hive（<0.13）只支持等值 JOIN（WHERE a.id = b.id）
- 0.13+: 支持非等值 JOIN（但可能退化为 Cross Join + Filter）
- LEFT SEMI JOIN 代替 IN/EXISTS（Hive 独有语法）
- MAPJOIN / BROADCAST hint 对小表广播（/*+ MAPJOIN(small_table) */）
- 不支持 LATERAL JOIN（用 LATERAL VIEW 代替）
- **对引擎开发者**: Hive 的 JOIN 限制源于 MapReduce 的 shuffle 阶段设计

### 6. SORT BY vs ORDER BY vs DISTRIBUTE BY vs CLUSTER BY

详见 [dml/insert/hive.sql](../dml/insert/hive.sql)

```sql
-- ORDER BY: 全局排序，只有一个 reducer（大数据集极慢）
-- SORT BY: 每个 reducer 内部排序（分布式友好）
-- DISTRIBUTE BY: 按指定列分发到 reducer（类似 HASH 分区）
-- CLUSTER BY: = DISTRIBUTE BY + SORT BY 同一列
```

- 这四个关键字是 MapReduce 架构的直接映射
- 现代引擎（Spark、Flink）通常只保留 ORDER BY，其余用内部优化替代
- **对引擎开发者**: 如果你的引擎不是 MapReduce，SORT BY/DISTRIBUTE BY 可以映射到内部的 partition + sort

### 7. STORED AS 和 SerDe

详见 [ddl/create-table/hive.sql](../ddl/create-table/hive.sql)

```sql
CREATE TABLE logs (
    message STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ("input.regex" = "([^ ]*) ([^ ]*) (.*)")
STORED AS TEXTFILE;
```

- STORED AS: 文件格式（TEXTFILE, ORC, PARQUET, AVRO, RCFILE）
- ROW FORMAT: 行的序列化方式
- SerDe: 可插拔的序列化/反序列化器
- **对引擎开发者**: 不需要实现 SerDe 架构，但需要支持读取 ORC/Parquet 格式

### 8. ACID 表的限制

详见 [advanced/transactions/hive.sql](../advanced/transactions/hive.sql)

- ACID 支持需要: ORC 格式 + transactional=true + Compaction 后台进程
- UPDATE/DELETE 实际是写入 delta 文件，后台 compact 合并
- 性能远不如原生 RDBMS 的行级更新
- Hive 3.0+ 默认所有内部表为 ACID 表
- **对引擎开发者**: 如果你的引擎需要 UPDATE/DELETE，考虑 Delta Lake/Iceberg 的方案而非 Hive ACID

### 9. 类型转换的宽松性

```sql
-- Hive 允许很多隐式转换:
SELECT 1 + '2';        -- 3（STRING 自动转 INT）
SELECT 1.5 + 2;        -- 3.5（INT 自动升级为 DOUBLE）
SELECT '2024-01-15' > '2024-01-14';  -- TRUE（STRING 比较）
```

- 但某些转换会静默失败返回 NULL: `CAST('abc' AS INT)` → NULL（不报错）
- **对引擎开发者**: 需要决定兼容 Hive 的宽松转换还是采用严格模式

### 10. UDF/UDAF/UDTF 接口

详见 [advanced/stored-procedures/hive.sql](../advanced/stored-procedures/hive.sql)

- UDF: 标量函数（一行进一行出）
- UDAF: 聚合函数（多行进一行出）
- UDTF: 表生成函数（一行进多行出，如 explode）
- GenericUDF: 可以处理复杂类型的 UDF
- **对引擎开发者**: 兼容 Hive UDF JAR 是获取生态的捷径（Spark/Flink 都做了）

## 兼容族引擎对比

| 引擎 | 兼容度 | 核心差异 | 参考 |
|------|--------|---------|------|
| Spark SQL | 最高 | USING 替代 STORED AS、DataFrame API、Delta Lake | [dialects/spark.md](../dialects/spark.md) |
| Databricks | 高 | Unity Catalog、Liquid Clustering、Photon | [dialects/databricks.md](../dialects/databricks.md) |
| MaxCompute | 中 | 自有扩展多、事务表语法不同 | [dialects/maxcompute.md](../dialects/maxcompute.md) |
| Impala | 中 | Kudu 表支持 UPDATE、COMPUTE STATS | [dialects/impala.md](../dialects/impala.md) |
| Flink SQL | 低 | 流处理语义、WATERMARK、Connector | [dialects/flink.md](../dialects/flink.md) |
| Trino | 中 | ANSI SQL 风格、Connector 架构 | [dialects/trino.md](../dialects/trino.md) |

## 从 Hive 迁移到其他引擎的注意事项

| 问题 | Hive 写法 | 标准 SQL / 现代引擎写法 |
|------|----------|----------------------|
| 展开数组 | `LATERAL VIEW explode(arr) t AS val` | `UNNEST(arr)` 或 `CROSS JOIN UNNEST(arr)` |
| 条件聚合 | `SUM(IF(cond, val, 0))` | `SUM(val) FILTER (WHERE cond)` (PG) 或 `COUNTIF` (BigQuery) |
| 排序语义 | `SORT BY`（分区内排序） | `ORDER BY`（全局排序） |
| 类型转换 | 隐式宽松转换 | 显式 CAST (标准 SQL) |
| JSON 处理 | `get_json_object(col, '$.key')` | `col->>'key'` (PG) 或 `JSON_VALUE(col, '$.key')` |
| 字符串拼接 | `CONCAT(a, b, c)` | `a \|\| b \|\| c` (标准 SQL) |
| 分区操作 | `INSERT OVERWRITE PARTITION(dt='...')` | `MERGE INTO` 或 `DELETE + INSERT` |
