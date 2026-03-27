# INSERT OVERWRITE 语义

分区级幂等写入——大数据引擎的核心特性，传统数据库完全不支持的操作。

## 支持矩阵

| 引擎 | 支持 | 语法 | 版本 | 备注 |
|------|------|------|------|------|
| Hive | 完整支持 | `INSERT OVERWRITE TABLE ... PARTITION(...)` | 0.1+ | **核心写入模式** |
| Spark SQL | 完整支持 | `INSERT OVERWRITE TABLE ...` | 1.0+ | 支持 STATIC/DYNAMIC 模式 |
| MaxCompute | 完整支持 | `INSERT OVERWRITE TABLE ...` | 早期 | 阿里云标准写入方式 |
| Databricks | 完整支持 | `INSERT OVERWRITE ...` | Delta Lake 0.3+ | 基于 Delta Lake 的事务保证 |
| Flink SQL | 完整支持 | `INSERT OVERWRITE ...` | 1.12+ | 批模式支持 |
| Trino | 完整支持 | `INSERT OVERWRITE ...` | Hive connector | 通过 connector 支持 |
| Impala | 完整支持 | `INSERT OVERWRITE ...` | 早期 | Hive 兼容 |
| Doris | 完整支持 | `INSERT OVERWRITE ...` | 1.2+ | - |
| StarRocks | 完整支持 | `INSERT OVERWRITE ...` | 2.4+ | - |
| BigQuery | 不支持 | - | - | 用 MERGE 或 WRITE_TRUNCATE 模式 |
| Snowflake | 不支持 | - | - | 用 COPY + TRUNCATE 或 MERGE |
| PostgreSQL | 不支持 | - | - | 无分区覆盖概念 |
| MySQL | 不支持 | - | - | 有 REPLACE INTO 但语义不同 |
| Oracle | 不支持 | - | - | 需 DELETE + INSERT 或 MERGE |
| SQL Server | 不支持 | - | - | 需 TRUNCATE + INSERT 或 MERGE |

## 设计动机

### 问题: 数据管道的幂等性

在数据仓库的 ETL 管道中，最常见的写入模式是"按天/小时分区覆盖"：

```
每天凌晨 2:00 重新计算昨天的数据，写入 dt='2024-01-15' 分区
```

如果使用普通 INSERT：

```sql
-- 第一次运行: 插入 100 条记录 → dt='2024-01-15' 分区有 100 条
INSERT INTO fact_table PARTITION (dt='2024-01-15')
SELECT ... FROM source WHERE date = '2024-01-15';

-- 任务失败后重跑: 再插入 100 条 → dt='2024-01-15' 分区有 200 条!
-- 数据重复了!
```

如果使用 DELETE + INSERT：

```sql
-- 先删除再插入（两步操作，非原子性）
DELETE FROM fact_table WHERE dt = '2024-01-15';
INSERT INTO fact_table PARTITION (dt='2024-01-15')
SELECT ... FROM source WHERE date = '2024-01-15';
-- 如果在 DELETE 之后、INSERT 之前失败，数据丢失!
```

### INSERT OVERWRITE 的解决方案

```sql
-- 原子性的分区覆盖: 重跑多少次结果都一样
INSERT OVERWRITE TABLE fact_table PARTITION (dt='2024-01-15')
SELECT ... FROM source WHERE date = '2024-01-15';
-- dt='2024-01-15' 分区被完全替换，无论之前有什么数据
```

INSERT OVERWRITE 的核心价值: **幂等性**——同一操作执行一次和执行多次的结果完全相同。

## 语法对比

### Hive（原始设计）

```sql
-- 覆盖静态分区
INSERT OVERWRITE TABLE sales PARTITION (year=2024, month=1)
SELECT product_id, amount, quantity
FROM staging_sales
WHERE year = 2024 AND month = 1;

-- 覆盖动态分区（分区值由数据决定）
SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

INSERT OVERWRITE TABLE sales PARTITION (year, month)
SELECT product_id, amount, quantity, year, month
FROM staging_sales;
-- 分区列必须在 SELECT 的最后位置

-- 覆盖整个表（无分区指定 = 全表覆盖）
INSERT OVERWRITE TABLE summary
SELECT category, SUM(amount) AS total
FROM sales
GROUP BY category;

-- 覆盖到文件系统（导出数据）
INSERT OVERWRITE DIRECTORY '/output/path'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT * FROM sales WHERE year = 2024;
```

### Spark SQL

```sql
-- 静态分区覆盖
INSERT OVERWRITE TABLE sales PARTITION (dt='2024-01-15')
SELECT product_id, amount FROM staging;

-- 动态分区覆盖: Spark 的关键设计选择
-- STATIC 模式 (默认): 覆盖表中 ALL 分区
-- DYNAMIC 模式: 只覆盖出现在数据中的分区

-- STATIC 模式
SET spark.sql.sources.partitionOverwriteMode=STATIC;
INSERT OVERWRITE TABLE sales
SELECT product_id, amount, dt FROM staging;
-- 危险! 会删除 staging 中不存在的分区!

-- DYNAMIC 模式 (推荐)
SET spark.sql.sources.partitionOverwriteMode=DYNAMIC;
INSERT OVERWRITE TABLE sales
SELECT product_id, amount, dt FROM staging;
-- 安全! 只覆盖 staging 中出现的 dt 值对应的分区
-- 其他分区保持不变

-- DataFrameWriter API (非 SQL)
-- df.write.mode("overwrite").insertInto("sales")
-- df.write.mode("overwrite").partitionBy("dt").saveAsTable("sales")
```

### Databricks (Delta Lake)

```sql
-- Delta Lake 的 INSERT OVERWRITE 具有 ACID 事务保证
INSERT OVERWRITE sales
SELECT product_id, amount, dt FROM staging;

-- 可以通过 replaceWhere 精确控制覆盖范围
INSERT OVERWRITE sales
REPLACE WHERE dt >= '2024-01-01' AND dt <= '2024-01-31'
SELECT * FROM staging;

-- Delta Lake 的优势: 如果 INSERT OVERWRITE 失败，数据自动回滚
-- 不会出现"写了一半"的中间状态
```

### MaxCompute / Flink SQL

```sql
-- MaxCompute: 与 Hive 语法一致
INSERT OVERWRITE TABLE sales PARTITION (dt='2024-01-15')
SELECT product_id, amount FROM staging;

-- 多级分区混合（静态 + 动态）
INSERT OVERWRITE TABLE sales PARTITION (year='2024', month='01', day)
SELECT product_id, amount, day FROM staging;

-- Flink SQL: 批模式下支持，语法类似
INSERT OVERWRITE sales PARTITION (dt='2024-01-15')
SELECT product_id, amount FROM staging;
```

## STATIC vs DYNAMIC 分区覆盖

这是 Spark SQL 中最重要的配置选择，也是最常见的数据丢失原因之一。

### STATIC 模式（Spark 默认）

```
目标表分区: [dt=01, dt=02, dt=03, dt=04, dt=05]
写入数据包含: [dt=03, dt=04]

STATIC 覆盖后: [dt=03, dt=04]
→ dt=01, dt=02, dt=05 的数据被删除!
```

STATIC 模式将整个表视为覆盖目标，即使写入的数据只涉及部分分区。

### DYNAMIC 模式（推荐）

```
目标表分区: [dt=01, dt=02, dt=03, dt=04, dt=05]
写入数据包含: [dt=03, dt=04]

DYNAMIC 覆盖后: [dt=01, dt=02, dt=03, dt=04, dt=05]
→ 只有 dt=03 和 dt=04 被替换，其他分区不受影响
```

### 各引擎的默认行为

| 引擎 | 默认模式 | 配置项 |
|------|---------|--------|
| Hive | DYNAMIC (非严格模式下) | `hive.exec.dynamic.partition.mode` |
| Spark | STATIC (危险!) | `spark.sql.sources.partitionOverwriteMode` |
| MaxCompute | DYNAMIC | 默认行为 |
| Flink | DYNAMIC | 默认行为 |
| Databricks | DYNAMIC (Delta Lake) | 默认行为 |

## 不支持 INSERT OVERWRITE 的引擎如何替代

```sql
-- BigQuery: 用 MERGE 或 bq CLI 的 WRITE_TRUNCATE 模式
-- PostgreSQL / MySQL: 用事务保证原子性
BEGIN;
DELETE FROM target WHERE dt = '2024-01-15';
INSERT INTO target SELECT * FROM source WHERE dt = '2024-01-15';
COMMIT;
```

## 对引擎开发者的实现建议

### 1. 语法解析

```
insert_statement:
    INSERT [INTO | OVERWRITE] TABLE table_name
    [PARTITION '(' partition_spec ')']
    select_statement

partition_spec:
    partition_column '=' value [',' partition_column '=' value]*    -- 静态
  | partition_column [',' partition_column]*                         -- 动态
  | 混合: partition_column '=' value ',' partition_column           -- 半动态
```

### 2. 文件级替换 vs 行级替换

大数据引擎和传统数据库对"覆盖"的实现完全不同：

**文件级替换（Hive / Spark / MaxCompute）**

```
1. 将新数据写入临时目录: /table/dt=2024-01-15/.tmp/
2. 确认写入成功后，原子性替换:
   - 删除 /table/dt=2024-01-15/ 下的旧文件
   - 将 .tmp/ 下的新文件移动到 /table/dt=2024-01-15/
3. 更新元数据（Hive Metastore）
```

优点: 高效（文件系统级操作），适合大批量数据。
缺点: 依赖文件系统的 rename 原子性（HDFS 支持，S3 不完全支持）。

**行级替换（传统 RDBMS）**

```
1. DELETE FROM table WHERE partition_key = value
2. INSERT INTO table SELECT ... FROM source
3. 两步操作在同一事务中
```

优点: 事务保证。缺点: DELETE 大量数据时性能差。

**Delta Lake / Iceberg 的混合方案**

```
1. 写入新数据文件
2. 更新表元数据 (JSON/Avro manifest):
   - 标记旧分区的数据文件为"已删除"
   - 添加新数据文件的引用
3. 原子性提交元数据变更
4. 旧文件可以延迟清理（Time Travel 支持）
```

这是最优方案: 既有文件级效率，又有事务保证。

### 3. REPLACE INTO 不是 INSERT OVERWRITE

MySQL 的 `REPLACE INTO` 和 INSERT OVERWRITE 语义完全不同：

| 特性 | INSERT OVERWRITE | REPLACE INTO |
|------|-----------------|-------------|
| 粒度 | 分区级 | 行级（按主键） |
| 语义 | 替换整个分区 | DELETE + INSERT 单行 |
| 用途 | 批量 ETL | 单行 upsert |
| 事务 | 分区原子替换 | 行级事务 |

## 实际场景

```sql
-- 场景 1: 每日 ETL 管道（最典型）
-- 凌晨重算昨天的指标，覆盖写入
INSERT OVERWRITE TABLE daily_metrics PARTITION (dt='${yesterday}')
SELECT user_id, COUNT(*) AS actions, SUM(revenue) AS total_revenue
FROM events WHERE dt = '${yesterday}'
GROUP BY user_id;

-- 场景 2: 维度表全量刷新
INSERT OVERWRITE TABLE dim_product
SELECT product_id, product_name, category, price
FROM source_products;

-- 场景 3: 数据修复（重跑某个月的数据）
-- Spark DYNAMIC 模式: 只覆盖涉及的日期分区
SET spark.sql.sources.partitionOverwriteMode=DYNAMIC;
INSERT OVERWRITE TABLE fact_orders
SELECT * FROM raw_orders
WHERE dt BETWEEN '2024-01-01' AND '2024-01-31';
```

## 参考资料

- Hive: [INSERT OVERWRITE](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML#LanguageManualDML-InsertingdataintoHiveTablesfromqueries)
- Spark SQL: [INSERT OVERWRITE](https://spark.apache.org/docs/latest/sql-ref-syntax-dml-insert-overwrite-table.html)
- Spark: [Partition Overwrite Mode](https://spark.apache.org/docs/latest/sql-ref-syntax-dml-insert-overwrite-table.html)
- Delta Lake: [INSERT OVERWRITE](https://docs.delta.io/latest/delta-update.html)
- MaxCompute: [INSERT OVERWRITE](https://help.aliyun.com/document_detail/73768.html)
