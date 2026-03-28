# Spanner: 临时表

> 参考资料:
> - [Spanner Documentation - Data Manipulation Language](https://cloud.google.com/spanner/docs/dml-tasks)
> - [Spanner Documentation - Subqueries](https://cloud.google.com/spanner/docs/subqueries)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## CTE（推荐替代方式）


```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username,
           COUNT(o.id) AS order_count,
           SUM(o.amount) AS total_amount
    FROM active_users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders WHERE order_count > 5;

```

## 子查询


```sql
SELECT u.username, t.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) t ON u.id = t.user_id
WHERE t.total > 1000;

```

## STRUCT 和 ARRAY（内联临时数据）


使用 UNNEST 创建内联临时数据
```sql
SELECT * FROM UNNEST(ARRAY<STRUCT<id INT64, name STRING>>[
    STRUCT(1, 'alice'),
    STRUCT(2, 'bob'),
    STRUCT(3, 'charlie')
]) AS temp_data;

```

## 批处理 DML（应用层临时存储）


在应用层使用批处理替代临时表
## 查询数据到应用内存

## 在应用层处理

## 批量写回


## Staging 表（替代方案）


创建永久的 Staging 表用于中间处理
```sql
CREATE TABLE staging_data (
    batch_id STRING(36),
    id INT64,
    data STRING(MAX),
    created_at TIMESTAMP
) PRIMARY KEY (batch_id, id);

```

使用后清理
```sql
DELETE FROM staging_data WHERE batch_id = 'batch-123';

```

**注意:** Spanner 不支持临时表
**注意:** CTE 是最常用的临时数据组织方式
**注意:** UNNEST + ARRAY<STRUCT> 可以创建内联临时数据
**注意:** 复杂场景建议在应用层处理中间数据
**注意:** 可以使用永久的 Staging 表替代临时表
