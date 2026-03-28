# PostgreSQL: CTE 公共表表达式

> 参考资料:
> - [PostgreSQL Documentation - WITH Queries](https://www.postgresql.org/docs/current/queries-with.html)
> - [PostgreSQL Source - parse_cte.c / rewriteHandler.c](https://github.com/postgres/postgres/blob/master/src/backend/parser/parse_cte.c)

## 基本 CTE

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

多个 CTE
```sql
WITH
active AS (SELECT * FROM users WHERE status = 1),
orders_sum AS (SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id)
SELECT u.username, o.total
FROM active u JOIN orders_sum o ON u.id = o.user_id;
```

## 递归 CTE (WITH RECURSIVE)

数值序列
```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n                          -- 锚定成员
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10    -- 递归成员
)
SELECT n FROM nums;
```

层级遍历（组织架构）
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           username::TEXT AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY path;
```

循环检测（防止无限递归）
```sql
WITH RECURSIVE search AS (
    SELECT id, username, manager_id, ARRAY[id] AS path, FALSE AS cycle
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, s.path || u.id, u.id = ANY(s.path)
    FROM users u JOIN search s ON u.manager_id = s.id
    WHERE NOT s.cycle
)
SELECT * FROM search WHERE NOT cycle;
```

14+: SEARCH 和 CYCLE 子句（SQL 标准语法）
```sql
WITH RECURSIVE org AS (
    SELECT id, username, manager_id FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id FROM users u JOIN org t ON u.manager_id = t.id
)
SEARCH DEPTH FIRST BY id SET ordercol
CYCLE id SET is_cycle USING path
SELECT * FROM org WHERE NOT is_cycle ORDER BY ordercol;
```

## 可写 CTE (9.1+): PostgreSQL 最独特的 CTE 特性

DELETE + INSERT（归档操作，单语句原子完成）
```sql
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;
```

UPDATE + SELECT（返回更新前后的值）
```sql
WITH updated AS (
    UPDATE users SET status = 0
    WHERE last_login < NOW() - INTERVAL '1 year'
    RETURNING id, username
)
SELECT * FROM updated;
```

复杂链式操作: INSERT → UPDATE → SELECT
```sql
WITH new_order AS (
    INSERT INTO orders (user_id, amount) VALUES (1, 100) RETURNING id, user_id
),
updated_user AS (
    UPDATE users SET order_count = order_count + 1
    FROM new_order WHERE users.id = new_order.user_id
    RETURNING users.id
)
SELECT * FROM new_order;
```

设计分析: 可写 CTE 的唯一性
  PostgreSQL 是唯一在 CTE 中支持 DML (INSERT/UPDATE/DELETE) 的主流数据库。
  实现: 可写 CTE 在执行计划中创建 ModifyTable 节点，RETURNING 数据
  通过 tuplestore 传递给后续 CTE 或主查询。
  所有 CTE 中的 DML 在同一个事务中执行，共享同一个快照。

对比:
  MySQL:      CTE 只支持 SELECT（不支持 DML）
  Oracle:     CTE 只支持 SELECT
  SQL Server: CTE 支持 DML，但不支持 RETURNING（需要 OUTPUT）

## CTE 物化控制 (12+): 优化围栏的变革

12 之前: CTE 总是物化（optimization fence / 优化围栏）
  优化器不会将 CTE 的谓词下推到 CTE 内部
  WHERE cte.col = 1 不会被推入 CTE 的定义中
  这是已知的性能陷阱——将简单查询包装在 CTE 中可能导致全表扫描

12+: 非递归 CTE 默认尝试内联（NOT MATERIALIZED）
可以手动控制:

强制物化（创建临时结果集）
```sql
WITH active AS MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active WHERE age > 25;
```

强制内联（展开到主查询中优化）
```sql
WITH active AS NOT MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active WHERE age > 25;
```

NOT MATERIALIZED 等价于子查询——优化器可以推入外部谓词

12+ 的默认行为:
  非递归 CTE: 如果只被引用一次且无副作用 → 自动内联
  递归 CTE: 总是物化（无法内联）
  可写 CTE: 总是物化（有副作用）
  被引用多次的 CTE: 总是物化（避免重复计算）

## 递归 CTE 的内部实现

PostgreSQL 递归 CTE 的执行流程:
  (1) 执行锚定成员，结果放入 "working table"
  (2) 对 working table 执行递归成员，结果放入 "intermediate table"
  (3) intermediate table 变成新的 working table
  (4) 重复 (2)-(3) 直到 working table 为空

限制与保护:
  max_recursion_depth: 无内置限制（不像 MySQL 有 cte_max_recursion_depth）
  递归终止靠 WHERE 条件或 CYCLE 检测
  UNION 去重 vs UNION ALL: UNION 自动去重防止无限循环

性能考虑:
  每次迭代的中间结果存在 tuplestore 中（内存→磁盘溢出）
  work_mem 参数影响 tuplestore 的内存上限

## 横向对比: CTE 能力

### 基本 CTE

  所有主流数据库都支持（MySQL 8.0+, Oracle 9i+, SQL Server 2005+）

### 递归 CTE

  PostgreSQL: 8.4+（SEARCH/CYCLE 14+）
  MySQL:      8.0+（有 cte_max_recursion_depth 限制，默认1000）
  Oracle:     11gR2+（也支持传统 CONNECT BY）
  SQL Server: 2005+（MAXRECURSION 选项）

### 可写 CTE

  PostgreSQL: 9.1+（唯一完整支持 DML RETURNING 的数据库）
  SQL Server: CTE 可用于 DELETE/UPDATE 的目标，但无 RETURNING
  MySQL/Oracle: 不支持

### 物化控制

  PostgreSQL: MATERIALIZED / NOT MATERIALIZED (12+)
  MySQL:      无控制（总是物化或总是内联，取决于版本和优化器）
  Oracle:     /*+ MATERIALIZE */ hint
  SQL Server: 总是内联（CTE 只是语法糖）

## 对引擎开发者的启示

(1) CTE 物化 vs 内联是关键的优化决策:
    12 之前 PostgreSQL 的"总是物化"策略导致了很多性能陷阱。
    12+ 的自动内联修复了这个问题，但增加了优化器复杂度。
    新引擎应从一开始就支持 CTE 内联。

(2) 可写 CTE 是 PostgreSQL 的杀手特性:
    单语句完成 DELETE+INSERT（归档）极大简化了应用层逻辑。
    实现关键: RETURNING 数据通过 tuplestore 在执行计划内传递。

(3) 递归 CTE 需要 tuplestore 管理:
    每轮迭代的中间结果需要存储在 working table 中。
    内存不足时溢出到磁盘——work_mem 是调优关键。

## 版本演进

PostgreSQL 8.4:  WITH (CTE), WITH RECURSIVE
PostgreSQL 9.1:  可写 CTE（DML in WITH）
PostgreSQL 12:   MATERIALIZED / NOT MATERIALIZED（CTE 内联优化）
PostgreSQL 14:   SEARCH DEPTH/BREADTH FIRST, CYCLE 子句
PostgreSQL 15:   MERGE 可以作为可写 CTE 的目标
