# Materialize: 存储过程

## Materialize 不支持存储过程

通过物化视图和 SQL 函数实现类似功能

## 物化视图（替代存储过程的数据处理）


## 物化视图持续计算，类似"自动执行的存储过程"

```sql
CREATE MATERIALIZED VIEW order_stats AS
SELECT user_id,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount,
       AVG(amount) AS avg_amount
FROM orders
GROUP BY user_id;
```

## 复杂转换

```sql
CREATE MATERIALIZED VIEW enriched_orders AS
SELECT o.id, o.amount,
       u.username,
       CASE WHEN o.amount > 1000 THEN 'premium' ELSE 'standard' END AS tier
FROM orders o
JOIN users u ON o.user_id = u.id;
```

## SQL 函数（有限支持）


Materialize 支持部分 PostgreSQL 内置函数
不支持用户定义函数（CREATE FUNCTION）
使用内置函数实现逻辑

```sql
SELECT COALESCE(phone, email, 'N/A') AS contact FROM users;
SELECT CASE WHEN age > 18 THEN 'adult' ELSE 'minor' END FROM users;
```

## SUBSCRIBE（流式结果推送）


## SUBSCRIBE 持续推送物化视图的变更

```sql
SUBSCRIBE TO order_stats;
```

## SUBSCRIBE WITH SNAPSHOT（包含初始快照）

```sql
SUBSCRIBE TO order_stats WITH (SNAPSHOT = TRUE);
```

注意：Materialize 不支持存储过程
注意：物化视图是主要的数据处理机制
注意：不支持 CREATE FUNCTION
注意：SUBSCRIBE 用于流式推送结果
