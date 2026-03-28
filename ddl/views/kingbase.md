# KingbaseES (人大金仓): Views

> 参考资料:
> - [KingbaseES SQL 参考手册 - CREATE VIEW](https://help.kingbase.com.cn/v8/development/sql/sql/SQL_Statements_10.html)
> - [KingbaseES SQL 参考手册 - CREATE MATERIALIZED VIEW](https://help.kingbase.com.cn/v8/development/sql/sql/SQL_Statements_10.html)
> - ============================================
> - 基本视图（兼容 PostgreSQL 语法）
> - ============================================

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

## IF NOT EXISTS

```sql
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 临时视图

```sql
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
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

## 物化视图

KingbaseES 支持物化视图（兼容 PostgreSQL）

```sql
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
```

## 手动刷新

```sql
REFRESH MATERIALIZED VIEW mv_order_summary;
```

## 并发刷新

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary;
```

## 不填充数据创建

```sql
CREATE MATERIALIZED VIEW mv_empty AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
WITH NO DATA;
```

## 在物化视图上创建索引

```sql
CREATE INDEX idx_mv_user ON mv_order_summary (user_id);
```

## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;
DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;
```

限制：
物化视图不支持自动刷新
KingbaseES 兼容 PostgreSQL，大部分功能一致
支持 Oracle 兼容模式（可使用 Oracle 风格的物化视图语法）
