# 达梦 (DM): Views

> 参考资料:
> - [达梦数据库 SQL 语言参考 - CREATE VIEW](https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-view.html)
> - [达梦数据库 SQL 语言参考 - 物化视图](https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-mview.html)


## 基本视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## CREATE OR REPLACE VIEW

```sql
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 可更新视图 + WITH CHECK OPTION

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;
```

## WITH LOCAL CHECK OPTION / WITH CASCADED CHECK OPTION

```sql
CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH CASCADED CHECK OPTION;
```

## 物化视图 (Materialized View)

达梦支持物化视图，兼容 Oracle 语法

```sql
CREATE MATERIALIZED VIEW mv_order_summary
BUILD IMMEDIATE                               -- 创建时立即填充数据
REFRESH COMPLETE                              -- 完全刷新
ON DEMAND                                     -- 按需刷新
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
```

## 快速刷新（增量刷新，需要物化视图日志）

```sql
CREATE MATERIALIZED VIEW LOG ON orders
WITH PRIMARY KEY, ROWID;

CREATE MATERIALIZED VIEW mv_orders_fast
BUILD IMMEDIATE
REFRESH FAST                                  -- 快速（增量）刷新
ON DEMAND
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
```

## 自动刷新

```sql
CREATE MATERIALIZED VIEW mv_auto_refresh
BUILD IMMEDIATE
REFRESH COMPLETE
START WITH SYSDATE
NEXT SYSDATE + 1/24                          -- 每小时刷新
AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;
```

## 手动刷新物化视图

```sql
CALL DBMS_MVIEW.REFRESH('mv_order_summary', 'C');  -- C=Complete, F=Fast
```

## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_summary;
```

限制：
物化视图快速刷新需要物化视图日志
兼容 Oracle 的物化视图语法
支持 WITH CHECK OPTION
