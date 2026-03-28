# ClickHouse: 临时表与临时存储

> 参考资料:
> - [1] ClickHouse Documentation - CREATE TABLE
>   https://clickhouse.com/docs/en/sql-reference/statements/create/table
> - [2] ClickHouse Documentation - Temporary Tables
>   https://clickhouse.com/docs/en/sql-reference/statements/create/table#temporary-tables


## CREATE TEMPORARY TABLE


创建临时表（会话级别）

```sql
CREATE TEMPORARY TABLE temp_users (
    id UInt64,
    username String,
    age UInt8
);

```

注意：临时表使用 Memory 引擎（不能指定其他引擎）
注意：会话结束时自动删除


```sql
INSERT INTO temp_users VALUES (1, 'alice', 30), (2, 'bob', 25);
SELECT * FROM temp_users;

```

## 使用 Memory 引擎表（替代临时表）


Memory 引擎表：数据存储在内存中，服务器重启后丢失

```sql
CREATE TABLE memory_cache (
    id UInt64,
    key String,
    value String
) ENGINE = Memory;

INSERT INTO memory_cache VALUES (1, 'k1', 'v1');
SELECT * FROM memory_cache;

```

 与临时表的区别：Memory 表对所有会话可见

## Buffer 引擎（内存缓冲 + 批量写入）


Buffer 引擎在内存中缓冲数据，定期刷入目标表

```sql
CREATE TABLE users_buffer AS users
ENGINE = Buffer(currentDatabase(), users,
    16,   -- num_layers
    10,   -- min_time
    100,  -- max_time
    10000, -- min_rows
    1000000, -- max_rows
    10000000, -- min_bytes
    100000000  -- max_bytes
);

```

## CTE（WITH 子句）


```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, count() AS order_count
FROM active_users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY order_count DESC;

```

## 子查询作为临时数据源


```sql
SELECT u.username, t.total
FROM users u
JOIN (
    SELECT user_id, sum(amount) AS total
    FROM orders
    GROUP BY user_id
) t ON u.id = t.user_id
WHERE t.total > 1000;

```

## CREATE TABLE AS SELECT


创建持久表从查询结果

```sql
CREATE TABLE daily_stats
ENGINE = MergeTree()
ORDER BY (date, user_id)
AS SELECT
    toDate(order_date) AS date,
    user_id,
    sum(amount) AS total,
    count() AS cnt
FROM orders
GROUP BY date, user_id;

```

使用后删除

```sql
DROP TABLE IF EXISTS daily_stats;

```

## 物化视图（持久化的"临时"计算）


物化视图自动维护聚合结果

```sql
CREATE MATERIALIZED VIEW mv_user_totals
ENGINE = SummingMergeTree()
ORDER BY user_id
AS SELECT user_id, sum(amount) AS total_amount, count() AS order_count
FROM orders
GROUP BY user_id;

```

注意：ClickHouse 临时表固定使用 Memory 引擎
注意：临时表只在当前会话中可见
注意：Memory 引擎表适合存储中间计算结果
注意：CTE 和子查询是更常用的临时数据组织方式
注意：物化视图可以持久化维护聚合结果
注意：Buffer 引擎在内存中缓冲数据，适合高频写入

