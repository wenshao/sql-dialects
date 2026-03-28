# Materialize: Views

> 参考资料:
> - [Materialize Documentation - CREATE VIEW](https://materialize.com/docs/sql/create-view/)
> - [Materialize Documentation - CREATE MATERIALIZED VIEW](https://materialize.com/docs/sql/create-materialized-view/)
> - [Materialize Documentation - CREATE INDEX](https://materialize.com/docs/sql/create-index/)


## 普通视图（Non-materialized View）

不持久化数据，每次查询时重新计算

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

## 物化视图 (Materialized View)

Materialize 的核心功能：增量计算的物化视图

```sql
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
```

## 复杂的物化视图（JOIN、子查询等都支持）

```sql
CREATE MATERIALIZED VIEW mv_order_detail AS
SELECT
    o.user_id,
    u.username,
    COUNT(*) AS order_count,
    SUM(o.amount) AS total_amount
FROM orders o
JOIN users u ON o.user_id = u.id
GROUP BY o.user_id, u.username;
```

Materialize 物化视图的关键特性：
1. 增量计算：只处理变更数据，不需要全量重算
2. 自动维护：基表数据变更时，物化视图自动更新
3. 毫秒级延迟：物化视图几乎实时反映最新数据
4. 支持复杂查询：JOIN、子查询、窗口函数等
在物化视图上创建索引（加速查询）

```sql
CREATE INDEX idx_mv_user ON mv_order_summary (user_id);
CREATE DEFAULT INDEX ON mv_order_summary;    -- 在所有列上创建默认索引
```

## 订阅变更 (SUBSCRIBE)

## SUBSCRIBE 允许实时获取物化视图的变更

SUBSCRIBE TO mv_order_summary;

## 可更新视图

Materialize 视图不可更新


## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;
DROP MATERIALIZED VIEW mv_order_summary CASCADE;
```

限制：
不支持 WITH CHECK OPTION
不支持可更新视图
物化视图占用内存（状态存储在内存中）
不支持手动刷新（总是自动增量更新）
Materialize 专为流式物化视图设计，这是其核心价值
