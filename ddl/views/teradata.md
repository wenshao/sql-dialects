# Teradata: Views

> 参考资料:
> - [Teradata Documentation - CREATE VIEW](https://docs.teradata.com/r/Enterprise_IntelliFlex_VMware/SQL-Data-Definition-Language-Syntax-and-Examples/View-Statements/CREATE-VIEW)
> - [Teradata Documentation - Materialized Views (Join Indexes)](https://docs.teradata.com/r/Enterprise_IntelliFlex_VMware/SQL-Data-Definition-Language-Syntax-and-Examples/Index-Statements/CREATE-JOIN-INDEX)


## 基本视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```


REPLACE VIEW（Teradata 特有语法）
```sql
REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```


锁定行访问的视图
```sql
CREATE VIEW secure_users AS
LOCKING ROW FOR ACCESS
SELECT id, username, email
FROM users;
```


## 可更新视图 + WITH CHECK OPTION

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;
```


## 物化视图 (Join Index / Aggregate Join Index)

Teradata 使用 Join Index 代替物化视图

单表聚合索引（类似物化视图）
```sql
CREATE JOIN INDEX mv_order_summary AS
SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY user_id
PRIMARY INDEX (user_id);
```


多表 Join Index
```sql
CREATE JOIN INDEX mv_order_detail AS
SELECT
    o.user_id,
    u.username,
    o.amount,
    o.order_date
FROM orders o
INNER JOIN users u ON o.user_id = u.id
PRIMARY INDEX (user_id);
```


Join Index 特性：
1. 自动维护（DML 时自动更新）
2. 查询优化器自动使用（透明改写）
3. 支持单表聚合和多表 JOIN
4. 有存储开销

稀疏 Join Index
```sql
CREATE JOIN INDEX sparse_idx AS
SELECT user_id, SUM(amount) AS total
FROM orders
WHERE order_date > DATE '2024-01-01'
GROUP BY user_id
PRIMARY INDEX (user_id);
```


## 删除视图

```sql
DROP VIEW active_users;
DROP JOIN INDEX mv_order_summary;
```


限制：
不支持 CREATE OR REPLACE（使用 REPLACE VIEW）
不支持 IF NOT EXISTS
使用 Join Index 代替物化视图
Join Index 自动维护，不需要手动刷新
支持 WITH CHECK OPTION
