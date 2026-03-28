# SQL 标准: 临时表与临时存储

> 参考资料:
> - [ISO/IEC 9075-2:2023 - SQL Foundation](https://www.iso.org/standard/76584.html)
> - [SQL:2023 - Temporary Tables](https://www.iso.org/standard/76583.html)

## SQL 标准临时表

创建全局临时表（标准语法）
```sql
CREATE GLOBAL TEMPORARY TABLE temp_active_users (
    id BIGINT,
    username VARCHAR(100),
    last_login TIMESTAMP
) ON COMMIT DELETE ROWS;       -- 事务提交时清空数据
```

```sql
CREATE GLOBAL TEMPORARY TABLE temp_results (
    id BIGINT,
    value NUMERIC
) ON COMMIT PRESERVE ROWS;    -- 事务提交时保留数据（会话结束时清空）
```

创建本地临时表（标准语法）
```sql
CREATE LOCAL TEMPORARY TABLE temp_session_data (
    key VARCHAR(100),
    value VARCHAR(1000)
);
```

## ON COMMIT 行为

ON COMMIT DELETE ROWS    事务提交时删除所有行（默认）
ON COMMIT PRESERVE ROWS  事务提交时保留行（会话结束时清空）
ON COMMIT DROP           事务提交时删除表（部分实现支持）

## CTE（公共表表达式）作为临时存储

SQL:1999 引入的 WITH 子句
```sql
WITH active_users AS (
    SELECT id, username, email FROM users WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username, COUNT(o.id) AS order_count
    FROM active_users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders WHERE order_count > 5;
```

## 递归 CTE

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 1 AS level
    FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.level + 1
    FROM departments d
    JOIN org_tree t ON d.parent_id = t.id
)
SELECT * FROM org_tree;
```

## 各数据库的实现差异

全局临时表：Oracle, SQL Server, PostgreSQL, DB2
本地临时表：SQL Server (#table), PostgreSQL
表变量：SQL Server (@table)
内存表：MySQL (MEMORY 引擎), SAP HANA
无临时表支持：部分云数据仓库使用 CTE 替代

- **注意：SQL 标准定义了 GLOBAL TEMPORARY 和 LOCAL TEMPORARY**
- **注意：ON COMMIT DELETE ROWS 是默认行为**
- **注意：临时表的结构在数据库目录中可见，但数据对各会话隔离**
- **注意：CTE 是临时存储数据的标准替代方案**
- **注意：各数据库对临时表的实现差异很大**
