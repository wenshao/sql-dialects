# YugabyteDB: 临时表

> 参考资料:
> - [YugabyteDB Documentation - Temporary Tables](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/ddl_create_table/#temporary-table)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## CREATE TEMPORARY TABLE（YSQL）


```sql
CREATE TEMPORARY TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

ON COMMIT 行为
```sql
CREATE TEMP TABLE temp_tx (id INT, val INT) ON COMMIT DELETE ROWS;
CREATE TEMP TABLE temp_session (id INT, val INT) ON COMMIT PRESERVE ROWS;

```

## 使用临时表


```sql
INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;
DROP TABLE IF EXISTS temp_users;

```

## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

```

可写 CTE
```sql
WITH deleted AS (
    DELETE FROM orders WHERE status = 'cancelled' RETURNING *
)
INSERT INTO cancelled_orders SELECT * FROM deleted;

```

递归 CTE
```sql
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 1 AS level
    FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.level + 1
    FROM departments d JOIN tree t ON d.parent_id = t.id
)
SELECT * FROM tree;

```

**注意:** YugabyteDB YSQL 基于 PostgreSQL，临时表语法相同
**注意:** 临时表数据存储在本地 Tablet Server
**注意:** 支持 ON COMMIT DELETE ROWS / PRESERVE ROWS
**注意:** CTE 和可写 CTE 完全兼容 PostgreSQL
