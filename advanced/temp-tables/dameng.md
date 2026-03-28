# 达梦 (DM): 临时表与临时存储

> 参考资料:
> - [达梦数据库 SQL 语言使用手册](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)
> - ============================================================
> - 全局临时表
> - ============================================================

```sql
CREATE GLOBAL TEMPORARY TABLE gtt_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
) ON COMMIT PRESERVE ROWS;

CREATE GLOBAL TEMPORARY TABLE gtt_tx_data (
    id BIGINT, value DECIMAL(10,2)
) ON COMMIT DELETE ROWS;
```

## 使用

```sql
INSERT INTO gtt_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM gtt_users;
```

## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;
```

注意：达梦兼容 Oracle 的全局临时表语法
注意：表结构永久，数据对各会话隔离
注意：ON COMMIT DELETE ROWS 事务级，PRESERVE ROWS 会话级
