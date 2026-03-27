# 数据湖表格式的 SQL 差异

Apache Iceberg、Delta Lake、Apache Hudi 三大数据湖表格式为数据湖带来了事务、Schema 演进、Time Travel 等能力。它们的 SQL 语法和语义存在显著差异。

## 三大格式概览

| 特性 | Apache Iceberg | Delta Lake | Apache Hudi |
|------|---------------|------------|-------------|
| 发起方 | Netflix (2018) | Databricks (2019) | Uber (2016) |
| 核心思想 | 表级别的抽象 | 事务日志 | 增量处理 |
| 元数据 | Manifest List + Manifest Files | Delta Log (JSON + Parquet) | Timeline + Metadata |
| 引擎支持 | Spark, Trino, Flink, Hive, etc. | 主要 Spark/Databricks, 渐扩展 | Spark, Flink, Hive |
| 开放程度 | Apache 基金会, 引擎无关 | Linux 基金会, Databricks 主导 | Apache 基金会, 社区驱动 |

## Apache Iceberg

### 隐式分区转换

```sql
-- 传统 Hive 分区: 需要显式维护分区列
CREATE TABLE events_hive (
    event_id BIGINT,
    event_time TIMESTAMP,
    event_type STRING,
    dt STRING           -- 分区列, 由用户维护!
)
PARTITIONED BY (dt);
INSERT INTO events_hive VALUES (1, '2024-01-15 10:30:00', 'click', '2024-01-15');
-- 用户必须手动计算 dt = DATE(event_time), 容易出错

-- Iceberg 隐式分区: 从已有列自动派生分区
CREATE TABLE events_iceberg (
    event_id BIGINT,
    event_time TIMESTAMP,
    event_type STRING
) USING iceberg
PARTITIONED BY (month(event_time));
-- 分区由引擎从 event_time 自动计算, 无需额外列!

INSERT INTO events_iceberg VALUES (1, TIMESTAMP '2024-01-15 10:30:00', 'click');
-- 自动分区到 2024-01/

-- 支持的分区转换:
-- year(ts)    -> 按年分区
-- month(ts)   -> 按年月分区
-- day(ts)     -> 按天分区
-- hour(ts)    -> 按小时分区
-- bucket(N, col) -> hash 分桶
-- truncate(L, col) -> 截断 (字符串取前 L 字符, 数字取整到 L)

-- 查询时自动分区裁剪 (Partition Pruning)
SELECT * FROM events_iceberg
WHERE event_time >= TIMESTAMP '2024-03-01'
  AND event_time < TIMESTAMP '2024-04-01';
-- 引擎自动识别只需扫描 2024-03 分区, 无需用户感知分区结构!
```

### Schema Evolution

```sql
-- Iceberg 支持安全的 Schema 演进, 不需要重写数据

-- 添加列 (不重写数据, 旧数据该列返回 NULL)
ALTER TABLE events_iceberg ADD COLUMN source STRING;

-- 重命名列 (不重写数据, 只更新元数据)
ALTER TABLE events_iceberg RENAME COLUMN source TO event_source;

-- 修改列类型 (安全的类型提升, 不重写数据)
ALTER TABLE events_iceberg ALTER COLUMN event_id TYPE BIGINT;
-- 支持: int -> bigint, float -> double, decimal 精度提升

-- 重排列顺序
ALTER TABLE events_iceberg ALTER COLUMN event_source AFTER event_type;

-- 删除列
ALTER TABLE events_iceberg DROP COLUMN event_source;

-- 关键: Iceberg 使用列 ID (而非列名) 跟踪列
-- 即使列被重命名, 旧数据文件仍然可以正确映射
```

### Time Travel

```sql
-- Iceberg: 通过快照 ID 或时间戳回溯

-- 通过时间戳查询历史数据
SELECT * FROM events_iceberg TIMESTAMP AS OF '2024-01-15 10:00:00';

-- 通过快照 ID (Spark 语法)
SELECT * FROM events_iceberg VERSION AS OF 123456789;

-- 查看快照历史
SELECT * FROM events_iceberg.snapshots;

-- 查看元数据文件
SELECT * FROM events_iceberg.files;

-- 回滚到指定快照 (Spark)
CALL system.rollback_to_snapshot('db.events_iceberg', 123456789);

-- 回滚到指定时间
CALL system.rollback_to_timestamp('db.events_iceberg', TIMESTAMP '2024-01-15 10:00:00');

-- Trino 语法:
SELECT * FROM events_iceberg FOR TIMESTAMP AS OF TIMESTAMP '2024-01-15 10:00:00';
SELECT * FROM events_iceberg FOR VERSION AS OF 123456789;
```

## Delta Lake

### OPTIMIZE 与 Z-ORDER

```sql
-- Delta Lake: OPTIMIZE 合并小文件
OPTIMIZE events_delta;

-- 指定条件, 只优化特定分区
OPTIMIZE events_delta WHERE event_date >= '2024-01-01';

-- Z-ORDER: 多维聚类排序
-- 将数据按多列联合排序, 使得按这些列的查询都能跳过不相关的文件
OPTIMIZE events_delta
ZORDER BY (event_type, event_time);

-- Z-ORDER 的原理:
-- 将多维数据映射到一维空间 (Z曲线/希尔伯特曲线)
-- 使得多维上相近的数据在物理上也相近
-- 效果: 按 event_type 或 event_time 的查询都能有效裁剪文件
```

### VACUUM

```sql
-- VACUUM: 清理不再需要的旧数据文件
VACUUM events_delta;                    -- 默认保留 7 天
VACUUM events_delta RETAIN 168 HOURS;   -- 保留 7 天

-- 注意: VACUUM 后无法 Time Travel 到被清理的版本!

-- 安全措施:
SET spark.databricks.delta.retentionDurationCheck.enabled = false;
VACUUM events_delta RETAIN 0 HOURS;  -- 危险! 只保留最新版本

-- 查看 VACUUM 将删除哪些文件 (dry run)
VACUUM events_delta RETAIN 168 HOURS DRY RUN;
```

### Liquid Clustering (Delta Lake 3.0+)

```sql
-- Liquid Clustering: 替代传统分区和 Z-ORDER
-- 自动、增量地优化数据布局

-- 创建使用 Liquid Clustering 的表
CREATE TABLE events_delta (
    event_id BIGINT,
    event_time TIMESTAMP,
    event_type STRING,
    user_id BIGINT
) USING delta
CLUSTER BY (event_type, user_id);

-- 触发增量聚类
OPTIMIZE events_delta;

-- 修改聚类列 (不需要重写所有数据!)
ALTER TABLE events_delta CLUSTER BY (event_time, event_type);

-- 与传统方式对比:
-- 传统分区: 固定不变, 修改需要重写所有数据
-- Z-ORDER: 每次 OPTIMIZE 全量重写
-- Liquid Clustering: 增量优化, 聚类列可变
```

### Delta Lake Time Travel

```sql
-- 通过版本号
SELECT * FROM events_delta VERSION AS OF 5;

-- 通过时间戳
SELECT * FROM events_delta TIMESTAMP AS OF '2024-01-15 10:00:00';

-- 查看历史
DESCRIBE HISTORY events_delta;
-- 返回: version, timestamp, operation, operationParameters, ...

-- 恢复到指定版本
RESTORE TABLE events_delta TO VERSION AS OF 5;
RESTORE TABLE events_delta TO TIMESTAMP AS OF '2024-01-15 10:00:00';
```

## Apache Hudi

### COW vs MOR 表类型

```sql
-- COW (Copy-On-Write): 写时合并
-- 每次更新都重写整个文件
-- 读取快 (无合并开销), 写入慢 (需要重写)
CREATE TABLE events_cow
USING hudi
TBLPROPERTIES (
    'type' = 'cow',
    'primaryKey' = 'event_id',
    'preCombineField' = 'event_time'
);

-- MOR (Merge-On-Read): 读时合并
-- 更新写入 delta 日志, 读取时合并
-- 写入快 (追加日志), 读取稍慢 (需要合并)
CREATE TABLE events_mor
USING hudi
TBLPROPERTIES (
    'type' = 'mor',
    'primaryKey' = 'event_id',
    'preCombineField' = 'event_time'
);

-- COW vs MOR 的选择:
-- COW: 读多写少, 对查询延迟敏感 (BI 报表场景)
-- MOR: 写多读少, 对写入延迟敏感 (实时入湖场景)

-- MOR 的两种查询视图:
-- 读优化查询 (Read Optimized): 只读基础文件, 不合并 delta
SELECT * FROM events_mor_ro;  -- _ro 后缀

-- 快照查询 (Snapshot): 合并基础文件和 delta (最新数据)
SELECT * FROM events_mor;     -- 默认快照视图
```

### Incremental Query (增量查询)

```sql
-- Hudi 的独特能力: 增量读取变更数据

-- Spark SQL:
SELECT * FROM hudi_table
WHERE _hoodie_commit_time > '20240115100000'
  AND _hoodie_commit_time <= '20240116100000';

-- Spark DataFrame API (更推荐):
spark.read.format("hudi")
  .option("hoodie.datasource.query.type", "incremental")
  .option("hoodie.datasource.read.begin.instanttime", "20240115100000")
  .option("hoodie.datasource.read.end.instanttime", "20240116100000")
  .load("path/to/hudi_table");

-- 增量查询返回指定时间范围内变更的行
-- 包括: 新增、更新、删除 (如果开启了删除标记)
-- 用途: CDC 管道、增量 ETL、数据同步
```

### Hudi 的 SQL 操作

```sql
-- UPSERT (默认写入模式)
INSERT INTO events_hudi VALUES (1, TIMESTAMP '2024-01-15 10:30:00', 'click');
-- 如果 event_id=1 已存在, 按 preCombineField (event_time) 决定保留哪个版本

-- DELETE
DELETE FROM events_hudi WHERE event_id = 1;

-- UPDATE
UPDATE events_hudi SET event_type = 'view' WHERE event_id = 1;

-- MERGE INTO
MERGE INTO events_hudi target
USING updates source
ON target.event_id = source.event_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Compaction (MOR 表的基础文件与 delta 合并)
-- 手动触发:
CALL run_compaction(table => 'db.events_mor', op => 'run');
-- 查看 compaction 计划:
CALL show_compaction(table => 'db.events_mor');
```

## MERGE INTO 在三种格式中的差异

### 语法对比

```sql
-- Iceberg (Spark):
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED AND s.op = 'DELETE' THEN DELETE
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.value = s.value
WHEN NOT MATCHED THEN INSERT (id, name, value) VALUES (s.id, s.name, s.value);

-- Delta Lake (Spark/Databricks):
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED AND s.op = 'DELETE' THEN DELETE
WHEN MATCHED THEN UPDATE SET *           -- Delta 支持 SET *
WHEN NOT MATCHED THEN INSERT *;          -- Delta 支持 INSERT *

-- 注意: Delta 的 SET * 和 INSERT * 是语法糖
-- SET * = SET t.col1 = s.col1, t.col2 = s.col2, ...
-- INSERT * = INSERT (col1, col2, ...) VALUES (s.col1, s.col2, ...)

-- Hudi (Spark):
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
-- Hudi 的 MERGE INTO 自动处理 preCombineField
```

### 行为差异

```
1. 多行匹配:
   - Iceberg: 一个 target 行匹配多个 source 行 -> 报错
   - Delta Lake: 同上, 报错 (DeltaUnsupportedOperationException)
   - Hudi: 按 preCombineField 选择最新的 source 行

2. NOT MATCHED BY SOURCE:
   - Delta Lake: 支持 WHEN NOT MATCHED BY SOURCE THEN DELETE/UPDATE
     (Databricks 扩展, 非标准 SQL)
   - Iceberg: 不支持 (需要改写为 DELETE + MERGE)
   - Hudi: 不支持

3. Schema Evolution:
   - Delta Lake: MERGE 时可以自动添加新列 (mergeSchema=true)
   - Iceberg: 需要先 ALTER TABLE ADD COLUMN
   - Hudi: 需要先 ALTER TABLE ADD COLUMN

4. 性能:
   - COW 格式: MERGE 需要重写匹配到的文件
   - MOR 格式: MERGE 追加 delta 日志, 后台异步合并
   - Iceberg: Copy-on-Write 为主, 2.0 开始支持 MOR
   - Delta: 类似 COW (重写文件)
   - Hudi: COW 或 MOR, 用户选择
```

## 各格式在不同引擎中的 SQL 差异

### Spark SQL

```sql
-- 三种格式在 Spark 中的语法最为一致

-- Iceberg:
CREATE TABLE t (...) USING iceberg;
-- Delta Lake:
CREATE TABLE t (...) USING delta;
-- Hudi:
CREATE TABLE t (...) USING hudi;

-- 基本 DML 语法在三种格式中几乎相同
-- INSERT INTO, UPDATE, DELETE, MERGE INTO 都支持
```

### Trino

```sql
-- Trino 主要支持 Iceberg, 对 Delta Lake 支持有限, 不支持 Hudi

-- Iceberg (完整支持):
CREATE TABLE iceberg_catalog.db.t (id BIGINT, name VARCHAR)
WITH (format = 'PARQUET', partitioning = ARRAY['month(ts)']);

-- 时间旅行:
SELECT * FROM t FOR TIMESTAMP AS OF TIMESTAMP '2024-01-15 10:00:00';

-- Delta Lake (Trino 393+, 只读为主):
SELECT * FROM delta_catalog.db.t;

-- Hudi: Trino 不支持 Hudi 格式
```

### Flink SQL

```sql
-- Flink 对三种格式的支持各有侧重

-- Iceberg (Flink connector):
CREATE CATALOG iceberg_catalog WITH (
    'type' = 'iceberg',
    'catalog-type' = 'hive',
    'uri' = 'thrift://localhost:9083'
);

CREATE TABLE events (
    event_id BIGINT,
    event_time TIMESTAMP(3),
    event_type STRING
) WITH (
    'write.upsert.enabled' = 'true'
);

-- Hudi (Flink connector, 流式入湖):
CREATE TABLE events (
    event_id BIGINT PRIMARY KEY NOT ENFORCED,
    event_time TIMESTAMP(3),
    event_type STRING
) WITH (
    'connector' = 'hudi',
    'table.type' = 'MERGE_ON_READ',
    'hoodie.datasource.write.recordkey.field' = 'event_id'
);

-- Delta Lake: Flink 支持有限, 主要通过 delta-flink connector
```

## 对引擎开发者: 表格式 = 元数据管理 + 文件组织

### 需要实现的核心能力

```
1. 元数据管理:
   - 快照 (Snapshot): 表在某个时间点的完整状态
   - 元数据文件: 记录哪些数据文件属于哪个快照
   - Schema 版本: 跟踪列的添加、删除、类型变更
   - 分区规格: 分区策略的定义和演进

2. 文件组织:
   - 数据文件: Parquet / ORC / Avro
   - 小文件合并: 多个小文件合并为大文件 (compaction)
   - 文件级统计信息: min/max/count/null_count (用于文件裁剪)

3. 事务支持:
   - 原子提交: 一次写入要么全部可见，要么全部不可见
   - 并发控制: 多个写入者不冲突 (乐观并发)
   - 冲突检测: 两个写入修改同一文件时如何处理

4. 查询优化:
   - 分区裁剪: 根据查询条件跳过不相关的分区
   - 文件裁剪: 根据列统计信息跳过不相关的文件
   - 列裁剪: 只读取查询需要的列 (Parquet/ORC 天然支持)
```

### 选择建议

```
1. 如果做通用分析引擎: 优先支持 Iceberg
   - 引擎无关, 社区最广泛
   - 元数据设计最成熟 (列 ID 追踪, 隐式分区)

2. 如果做 Spark/Databricks 生态: 考虑 Delta Lake
   - 与 Spark 集成最深
   - Photon 引擎优化

3. 如果做实时入湖: 考虑 Hudi
   - 增量查询是独特优势
   - MOR 表写入延迟最低
   - 与 Flink 集成最好

4. 趋势: 三大格式在功能上趋同
   - 都支持 ACID、Schema Evolution、Time Travel
   - 差异主要在生态和实现细节
   - Apache XTable 项目: 格式间互转
```

## 参考资料

- Apache Iceberg: [Spec](https://iceberg.apache.org/spec/)
- Delta Lake: [Protocol](https://github.com/delta-io/delta/blob/master/PROTOCOL.md)
- Apache Hudi: [Design](https://hudi.apache.org/docs/concepts/)
- Databricks: [Lakehouse Architecture](https://www.databricks.com/research/lakehouse-a-new-generation-of-open-platforms)
- Apache XTable: [Interoperability](https://xtable.apache.org/)
