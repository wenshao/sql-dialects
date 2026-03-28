# 人大金仓 (KingbaseES): 临时表与临时存储

> 参考资料:
> - [KingbaseES 基于 PostgreSQL，临时表语法兼容](https://help.kingbase.com.cn/)
> - ============================================================
> - CREATE TEMPORARY TABLE（兼容 PostgreSQL）
> - ============================================================

```sql
CREATE TEMP TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;
```

## ON COMMIT 行为

```sql
CREATE TEMP TABLE temp_tx (id INT, val INT) ON COMMIT DELETE ROWS;
CREATE TEMP TABLE temp_session (id INT, val INT) ON COMMIT PRESERVE ROWS;
CREATE TEMP TABLE temp_drop (id INT, val INT) ON COMMIT DROP;
```

## UNLOGGED 表


```sql
CREATE UNLOGGED TABLE staging_data (id BIGINT, data TEXT);
```

## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;
```

注意：KingbaseES 基于 PostgreSQL，临时表语法完全兼容
注意：支持 ON COMMIT DELETE ROWS / PRESERVE ROWS / DROP
注意：UNLOGGED 表适合中间数据处理
