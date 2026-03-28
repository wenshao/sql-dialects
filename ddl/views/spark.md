# Spark SQL: Views (视图)

> 参考资料:
> - [1] Spark SQL Reference - CREATE VIEW
>   https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-view.html
> - [2] Spark SQL Reference - CACHE TABLE
>   https://spark.apache.org/docs/latest/sql-ref-syntax-aux-cache-cache-table.html


## 1. 持久化视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

带列注释

```sql
CREATE VIEW order_summary (
    user_id COMMENT '用户标识',
    order_count COMMENT '总订单数',
    total_amount COMMENT '总金额'
) AS
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

```

带表属性

```sql
CREATE VIEW tagged_view
TBLPROPERTIES ('creator' = 'admin', 'purpose' = 'reporting')
AS SELECT * FROM users;

```

## 2. 临时视图: Spark SQL 的核心概念


### 2.1 TEMPORARY VIEW（当前 SparkSession 生命周期）

```sql
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email FROM users WHERE age >= 18;

CREATE OR REPLACE TEMP VIEW temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

### 2.2 GLOBAL TEMPORARY VIEW（同一 SparkApplication 内所有 SparkSession 可见）

```sql
CREATE GLOBAL TEMPORARY VIEW global_active_users AS
SELECT id, username, email FROM users WHERE age >= 18;

```

全局临时视图必须通过 global_temp 数据库访问

```sql
SELECT * FROM global_temp.global_active_users;

```

 设计分析: 临时视图 vs 临时表
   Spark 选择"临时视图"而非"临时表"，根本原因:
### 1. Spark 是计算引擎，不是存储引擎——视图只保存查询定义（逻辑计划），不物化数据

### 2. 临时视图的创建是瞬间的（仅注册一个逻辑计划），不涉及任何 I/O

### 3. 如果需要物化数据，使用 CACHE TABLE 或 df.cache()


   GLOBAL TEMPORARY VIEW 的 global_temp 数据库设计是独特的:
   Spark 在启动时创建一个特殊的 global_temp 数据库，跨 Session 共享视图定义。
   这解决了"多线程共享查询结果"的场景，但实践中使用率不高（SparkSession 通常单例）。

 对比:
   MySQL/PostgreSQL: CREATE TEMP TABLE 创建真正的临时存储（会话结束自动删除）
   Hive:             支持临时表（CREATE TEMPORARY TABLE），Spark 继承但推荐用视图
   Flink SQL:        CREATE TEMPORARY VIEW 语义与 Spark 一致
   Trino:            无临时视图，通过 WITH (CTE) 替代
   BigQuery:          WITH 子句或临时表函数替代

## 3. CACHE TABLE: Spark SQL 的"物化视图"替代


缓存查询结果到内存（Tungsten 二进制格式）

```sql
CACHE TABLE cached_users AS
SELECT id, username, email FROM users WHERE age >= 18;

```

缓存已有的表/视图

```sql
CACHE TABLE users;

```

惰性缓存（首次访问时才缓存，不阻塞创建语句）

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
### 1. 数据被物化并以 Tungsten 列式二进制格式存储在 Executor 内存中

### 2. 后续查询直接从 InMemoryTableScan 读取，跳过文件扫描

### 3. 内存不足时溢出到磁盘（取决于 StorageLevel 配置）

### 4. 不自动刷新——源表变更后缓存不会更新


 对比物化视图:
   PostgreSQL: CREATE MATERIALIZED VIEW + REFRESH MATERIALIZED VIEW（手动/定时刷新）
   Oracle:     CREATE MATERIALIZED VIEW + 自动/按需刷新 + 查询重写
   BigQuery:   支持 CREATE MATERIALIZED VIEW（自动增量刷新）
   Spark:      无 CREATE MATERIALIZED VIEW，CACHE TABLE 是最接近的替代
               但 CACHE TABLE 不支持自动刷新，不支持查询重写

 对引擎开发者的启示:
   Spark 的 CACHE TABLE 证明了"手动管理缓存"的模型在批处理场景中是可行的。
   但它的最大缺陷是不支持增量刷新——每次都需要全量重新计算。
   如果你在设计引擎的物化视图功能，增量刷新和自动查询重写是核心竞争力。

## 4. 视图的限制


### 4.1 不可更新

 Spark SQL 视图不支持通过视图进行 INSERT/UPDATE/DELETE
 PostgreSQL/MySQL 支持简单视图的可更新性（WITH CHECK OPTION）

### 4.2 无 WITH CHECK OPTION

 不能限制通过视图插入的数据必须满足视图的 WHERE 条件

### 4.3 无物化视图（使用 CACHE TABLE 或 CTAS 替代）

```sql
CREATE TABLE mv_order_summary USING DELTA AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

## 5. 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP GLOBAL TEMPORARY VIEW global_active_users;

```

## 6. 版本演进

Spark 1.0: 临时视图（通过 DataFrame API）
Spark 2.0: CREATE TEMPORARY VIEW / GLOBAL TEMPORARY VIEW SQL 语法
Spark 2.0: CACHE TABLE / UNCACHE TABLE
Spark 3.0: 视图列注释、TBLPROPERTIES
Spark 3.4: 视图 Schema 绑定改进

限制:
不支持物化视图（MATERIALIZED VIEW）
不支持可更新视图（Updatable Views）
不支持 WITH CHECK OPTION
全局临时视图必须通过 global_temp 前缀访问
CACHE TABLE 不自动刷新，不支持查询重写

