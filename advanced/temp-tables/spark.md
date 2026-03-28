# Spark SQL: 临时表与临时存储 (Temporary Tables & Caching)

> 参考资料:
> - [1] Spark SQL - CREATE VIEW
>   https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-view.html
> - [2] Spark SQL - CACHE TABLE
>   https://spark.apache.org/docs/latest/sql-ref-syntax-aux-cache-cache-table.html


## 1. 核心设计: Spark 用临时视图替代临时表


 Spark SQL 没有 CREATE TEMP TABLE。所有"临时"概念都通过视图和缓存实现。

 设计理由:
   Spark 是计算引擎，不是存储引擎。临时视图只保存查询定义（逻辑计划），不物化数据。
   这使得创建临时视图是瞬间的（零 I/O），而传统数据库的临时表需要分配存储。
   如果需要物化中间结果，使用 CACHE TABLE（内存）或 CTAS（磁盘）。

 对比:
   MySQL:      CREATE TEMPORARY TABLE（会话级，真实存储在 tmpdir）
   PostgreSQL: CREATE TEMP TABLE（会话级，存在系统表空间中，支持索引/约束）
   SQL Server: #temp_table（tempdb 中）/ @table_variable（内存中）
   Oracle:     CREATE GLOBAL TEMPORARY TABLE（结构持久，数据临时）
   Hive:       CREATE TEMPORARY TABLE（会话级，存在 scratch 目录）
   Flink SQL:  CREATE TEMPORARY VIEW（与 Spark 一致）
   BigQuery:   临时表函数或 WITH 子句
   Trino:      无临时表，通过 CTE 替代

 对引擎开发者的启示:
   临时表和临时视图服务于不同目的:
   - 临时视图: 命名一个查询，便于在同一 SQL 会话中复用（零成本）
   - 临时表:   物化中间结果，避免重复计算（有存储成本）
   Spark 选择只提供视图，物化通过 CACHE TABLE 按需实现——这是合理的分层设计。

## 2. TEMPORARY VIEW（会话级）


```sql
CREATE TEMPORARY VIEW temp_users AS
SELECT * FROM users WHERE status = 1;

CREATE OR REPLACE TEMP VIEW temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

使用临时视图（与普通表/视图的查询语法完全相同）

```sql
SELECT * FROM temp_users WHERE age > 25;

```

 临时视图的生命周期: SparkSession 结束时自动销毁
 不持久化到 Hive Metastore（不会出现在 SHOW TABLES 中）

## 3. GLOBAL TEMPORARY VIEW（应用级）


```sql
CREATE GLOBAL TEMPORARY VIEW global_stats AS
SELECT COUNT(*) AS total_users FROM users;

```

必须通过 global_temp 数据库前缀访问

```sql
SELECT * FROM global_temp.global_stats;

```

 生命周期: SparkApplication 结束时销毁
 跨同一应用的多个 SparkSession 共享
 实践中使用率不高: 大多数场景只有一个 SparkSession

## 4. CACHE TABLE: 物化中间结果到内存


缓存查询结果（立即执行查询并物化到内存）

```sql
CACHE TABLE cached_users AS
SELECT * FROM users WHERE status = 1;

```

缓存已有的表/视图

```sql
CACHE TABLE users;

```

惰性缓存（首次访问时才物化——不阻塞创建语句）

```sql
CACHE LAZY TABLE cached_orders AS SELECT * FROM orders;

```

取消缓存

```sql
UNCACHE TABLE cached_users;
UNCACHE TABLE IF EXISTS users;

```

清除所有缓存

```sql
CLEAR CACHE;

```

 CACHE TABLE 的实现机制:
### 1. 数据以 Tungsten 列式二进制格式存储在 Executor 内存中

### 2. 后续查询通过 InMemoryTableScan 操作符读取（跳过文件扫描）

### 3. 内存不足时溢出到磁盘（取决于 Storage Level）

### 4. 不自动刷新——源表变更后缓存变为"陈旧"（Stale）


 CACHE TABLE vs df.cache():
   CACHE TABLE:   SQL 语法，缓存结果集，创建一个命名的缓存表
   df.cache():    API 方法，缓存 DataFrame 的计算结果
   两者底层机制相同，都使用 InMemoryRelation

## 5. CTAS: 持久化中间结果


当中间结果太大无法放入内存时，使用 CTAS 写入磁盘

```sql
CREATE TABLE staging.temp_results
USING DELTA
AS SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

使用后清理

```sql
DROP TABLE staging.temp_results;

```

 CTAS vs CACHE TABLE:
   CACHE TABLE:  内存中，读取快但容量有限，不持久（重启丢失）
   CTAS:         磁盘上，容量无限但 I/O 成本，持久化（重启保留）

## 6. CTE: 最轻量的"临时"机制


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u
JOIN stats s ON u.id = s.user_id;

```

 CTE 的优势: 作用域最小（单条 SQL 语句），无需创建/删除操作
 但 CTE 不能跨语句复用——如果需要多条语句共享，用 TEMP VIEW

## 7. DataFrame API（Spark 原生方式）


 Python:
 df = spark.sql("SELECT * FROM users WHERE status = 1")
 df.createOrReplaceTempView("temp_users")     -- 注册为临时视图
 df.cache()                                    -- 缓存到内存
 df.unpersist()                                -- 释放缓存

## 8. 最佳实践与选择指南


 需求: 在同一会话中多次引用同一查询
 方案: CREATE TEMP VIEW + CACHE TABLE（如果需要物化）

 需求: 中间结果数据量 < 可用内存
 方案: CACHE TABLE（最快读取）

 需求: 中间结果数据量 > 可用内存
 方案: CTAS 写入 Delta/Parquet（持久化到磁盘）

 需求: 单条 SQL 内的中间步骤
 方案: CTE（WITH 子句）

 需求: 跨作业共享数据
 方案: CTAS 写入持久化表（TEMP VIEW 只在当前 Session 有效）

## 9. 版本演进

Spark 1.0: DataFrame.registerTempTable (API)
Spark 2.0: CREATE TEMP VIEW / GLOBAL TEMP VIEW (SQL)
Spark 2.0: CACHE TABLE / UNCACHE TABLE
Spark 3.0: CACHE TABLE 性能优化
Spark 3.4: CLEAR CACHE 改进

限制:
无 CREATE TEMP TABLE（使用 TEMP VIEW 替代）
CACHE TABLE 不自动刷新（源表变更后需手动 UNCACHE + CACHE）
全局临时视图必须通过 global_temp 前缀访问
CACHE TABLE 受 Executor 内存限制（大数据集可能 OOM）

