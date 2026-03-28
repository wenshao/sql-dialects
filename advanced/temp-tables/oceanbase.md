# OceanBase: 临时表

> 参考资料:
> - [OceanBase Documentation](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL 模式：CREATE TEMPORARY TABLE


```sql
CREATE TEMPORARY TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;
DROP TEMPORARY TABLE IF EXISTS temp_users;

```

## Oracle 模式：全局临时表


CREATE GLOBAL TEMPORARY TABLE gtt_data (
    id NUMBER, value NUMBER
) ON COMMIT PRESERVE ROWS;

## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

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

**注意:** OceanBase MySQL 模式兼容 MySQL 临时表语法
**注意:** OceanBase Oracle 模式兼容 Oracle 全局临时表语法
**注意:** 临时表数据对各会话隔离
**注意:** CTE 是组织复杂查询的推荐方式
