# Databricks: Views

> 参考资料:
> - [Databricks SQL Reference - CREATE VIEW](https://docs.databricks.com/sql/language-manual/sql-ref-syntax-ddl-create-view.html)
> - [Databricks Documentation - Materialized Views](https://docs.databricks.com/sql/language-manual/sql-ref-syntax-ddl-create-materialized-view.html)
> - [Databricks Documentation - Streaming Tables](https://docs.databricks.com/sql/language-manual/sql-ref-syntax-ddl-create-streaming-table.html)


## 基本视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```


CREATE OR REPLACE VIEW
```sql
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```


IF NOT EXISTS
```sql
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```


临时视图（仅当前 SparkSession 可见）
```sql
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;
```


全局临时视图（所有 SparkSession 可见）
```sql
CREATE GLOBAL TEMPORARY VIEW global_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;
-- 访问: SELECT * FROM global_temp.global_active_users;
```


带列注释的视图
```sql
CREATE VIEW order_summary (
    user_id COMMENT 'User identifier',
    order_count COMMENT 'Total number of orders',
    total_amount COMMENT 'Sum of order amounts'
) AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
```


## 物化视图 (Materialized View, Unity Catalog, Databricks SQL)

需要 Unity Catalog 和 Databricks SQL Warehouse
```sql
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
```


带调度的物化视图（通过 Delta Live Tables 管道刷新）
物化视图在 DLT 管道执行时自动刷新
手动刷新：
```sql
REFRESH MATERIALIZED VIEW mv_order_summary;
```


## Streaming Table（增量数据视图）

CREATE STREAMING TABLE streaming_orders AS
SELECT * FROM STREAM(orders);

## 可更新视图

Databricks 视图不可更新（不支持 INSERT/UPDATE/DELETE）
## 替代方案：使用 MERGE INTO 操作基表（Delta Lake）


## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;
```


限制：
物化视图需要 Unity Catalog
不支持 WITH CHECK OPTION
不支持可更新视图
物化视图通过 Delta Live Tables 管道刷新
