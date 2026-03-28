# Vertica: Views

> 参考资料:
> - [Vertica Documentation - CREATE VIEW](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/CREATEVIEW.htm)
> - [Vertica Documentation - Projections (Materialized Views)](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Projections/Projections.htm)
> - [Vertica Documentation - Live Aggregate Projections](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/Projections/LiveAggregateProjections.htm)


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


## 可更新视图

Vertica 视图不可更新

## 物化视图 / Projections

Vertica 使用 Projection 代替物化视图

Projection（投影）- Vertica 的核心存储优化机制
每张表至少有一个 Super Projection
```sql
CREATE PROJECTION users_by_age AS
SELECT id, username, email, age, created_at
FROM users
ORDER BY age, id
SEGMENTED BY HASH(id) ALL NODES;
```


Live Aggregate Projection（实时聚合投影）
数据加载时自动维护，查询时透明使用
```sql
CREATE PROJECTION order_summary_proj AS
SELECT
    user_id,
    SUM(amount) AS total_amount,
    COUNT(*) AS order_count
FROM orders
GROUP BY user_id
SEGMENTED BY HASH(user_id) ALL NODES;
```


Top-K Projection
```sql
CREATE PROJECTION top_users_proj AS
SELECT user_id, SUM(amount) AS total
FROM orders
GROUP BY user_id
ORDER BY total DESC
LIMIT 100
SEGMENTED BY HASH(user_id) ALL NODES;
```


Projection 特性：
1. 自动维护（数据加载时更新）
2. 查询优化器自动选择最优 Projection
3. 相当于预物化的列式存储副本
4. 每张表可以有多个 Projection

刷新 Projection
```sql
SELECT REFRESH('users');
SELECT START_REFRESH();
```


## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;
DROP PROJECTION users_by_age;
```


限制：
不支持 WITH CHECK OPTION
视图不可更新
使用 Projection 代替物化视图
Projection 自动维护，不需要手动刷新
Live Aggregate Projection 有查询限制
