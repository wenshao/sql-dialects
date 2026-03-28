# SQL Server: CTE 公共表表达式

> 参考资料:
> - [SQL Server T-SQL - WITH (CTE)](https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql)

## 基本 CTE

> **注意**: CTE 前面如果有语句，前一条必须以分号结尾。
最佳实践: 在 WITH 前面加分号（;WITH），避免前一条语句缺少分号导致错误。
这是 T-SQL 独有的坑——其他数据库不需要这样做。
```sql
;WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

多个 CTE（逗号分隔，不需要重复 WITH）
```sql
;WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u JOIN user_orders o ON u.id = o.user_id;
```

## 递归 CTE（不需要 RECURSIVE 关键字）

SQL Server 的递归 CTE 不需要 RECURSIVE 关键字（PostgreSQL 需要）。
```sql
;WITH nums AS (
    SELECT 1 AS n                          -- 锚成员
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10    -- 递归成员
)
SELECT n FROM nums;
```

默认最大递归 100 次（防止无限循环）
使用 OPTION (MAXRECURSION N) 覆盖:
```sql
;WITH deep_recursion AS (
    SELECT 1 AS n UNION ALL SELECT n + 1 FROM deep_recursion WHERE n < 500
)
SELECT n FROM deep_recursion OPTION (MAXRECURSION 500);
```

OPTION (MAXRECURSION 0) = 无限制（危险，可能导致死循环）

设计分析（对引擎开发者）:
  SQL Server 的 MAXRECURSION 是查询级别的安全阀——这是好的设计。
  PostgreSQL 没有内置的递归深度限制（依赖 statement_timeout 超时机制）。
  MySQL 8.0 使用 cte_max_recursion_depth 系统变量（默认 1000）。

  递归 CTE 的实现方式:
  SQL Server/PostgreSQL: 迭代求值（每次递归执行一次递归成员）
  ClickHouse: 不支持递归 CTE
  BigQuery:   支持但有严格的资源限制

对引擎开发者的启示:
  递归 CTE 的终止条件检测是引擎必须解决的问题。
  方案 A: 固定深度限制（SQL Server/MySQL）
  方案 B: 检测工作集为空（SQL 标准行为）
  方案 C: 检测数据是否在循环（SQL:2011 CYCLE 子句，PG 14+ 支持）
  SQL Server 不支持 CYCLE 子句——需要用户手动在路径中检测循环。

## 层级结构遍历（经典应用）

```sql
;WITH org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS NVARCHAR(MAX)) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path + N' > ' + u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY path;
```

横向对比:
  Oracle:      CONNECT BY PRIOR parent_id = id（Oracle 独有的层次查询语法）
  PostgreSQL:  WITH RECURSIVE（标准语法，14+ 支持 SEARCH 和 CYCLE）
  SQL Server:  WITH（不需要 RECURSIVE 关键字）

对引擎开发者的启示:
  SQL:2011 引入了 SEARCH DEPTH/BREADTH FIRST 和 CYCLE 子句，
  PostgreSQL 14+ 支持，SQL Server 至今不支持——用户需要手动构造排序路径。

## CTE + DML（SQL Server 特色能力）

SQL Server 允许直接在 CTE 上执行 INSERT/UPDATE/DELETE:
```sql
;WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM inactive;  -- 直接从 CTE 删除

;WITH ranked AS (
    SELECT id, status, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
)
UPDATE ranked SET status = 1 WHERE rn = 1;  -- 直接在 CTE 上更新

-- 设计分析:
--   "可更新 CTE" 是 SQL Server 的独特能力——CTE 表现得像可更新视图。
--   PostgreSQL 不支持直接在 CTE 上执行 DML（需要用 WHERE id IN (SELECT id FROM cte)）。
--   这大大简化了基于窗口函数的更新/删除操作。
```

## CTE 不支持的特性

SQL Server 的 CTE 不支持:
  (1) MATERIALIZED / NOT MATERIALIZED 提示（PostgreSQL 12+ 支持）
  (2) SEARCH DEPTH/BREADTH FIRST（PostgreSQL 14+ 支持）
  (3) CYCLE 子句（PostgreSQL 14+ 支持）
  (4) 在 CTE 内部引用 OPTION 提示（OPTION 只能在最终 SELECT 后面）

CTE 的物化行为:
  SQL Server 的 CTE 不保证物化——优化器可能将 CTE 内联到主查询中。
  如果 CTE 被多次引用且需要避免重复计算，应使用临时表（#temp）替代。
  PostgreSQL 12+ 可以用 MATERIALIZED 强制物化。

对引擎开发者的启示:
  CTE 物化是一个优化器决策问题。物化有利于多次引用的复杂子查询，
  但不利于简单子查询（因为物化阻止了谓词下推等优化）。
  让用户通过提示控制物化行为是好的设计（PostgreSQL 的做法）。

## GO 批分隔符与 CTE 的交互

GO 不是 SQL 语句，是 SSMS/sqlcmd 客户端工具的批分隔符。
GO 会将脚本分割为多个批次，每个批次独立发送到服务器。
CTE 必须在同一个批次内完成（不能跨 GO）。
这是 T-SQL 独有的概念——其他数据库没有 GO。

正确:
```sql
;WITH cte AS (SELECT 1 AS n)
SELECT * FROM cte;
```

错误（GO 打断了 CTE 和 SELECT 的关系）:
;WITH cte AS (SELECT 1 AS n)
GO  -- 此处会报错
```sql
SELECT * FROM cte;
```
