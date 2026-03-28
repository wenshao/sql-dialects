# DuckDB: 视图

> 参考资料:
> - [DuckDB Documentation - CREATE VIEW](https://duckdb.org/docs/sql/statements/create_view)
> - [DuckDB Documentation - SQL Features](https://duckdb.org/docs/sql/introduction)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

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

临时视图（仅当前连接可见）
```sql
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;

```

带列别名的视图
```sql
CREATE VIEW order_summary (user_id, order_count, total_amount) AS
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

```

## 物化视图

DuckDB 不支持物化视图
## 替代方案：使用 CREATE TABLE AS（CTAS）

```sql
CREATE TABLE mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

刷新替代方案：DROP + CREATE
```sql
DROP TABLE IF EXISTS mv_order_summary;
CREATE TABLE mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

或使用 INSERT OR REPLACE
```sql
CREATE OR REPLACE TABLE mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

## 可更新视图

DuckDB 不支持可更新视图
## 替代方案：直接操作基表


## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

```

**限制:**
不支持物化视图（使用 CTAS 替代）
不支持 WITH CHECK OPTION
不支持可更新视图
DuckDB 是嵌入式 OLAP 引擎，视图功能较为简洁
支持跨数据源视图（如引用 Parquet、CSV 文件）
