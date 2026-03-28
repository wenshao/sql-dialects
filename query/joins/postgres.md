# PostgreSQL: JOIN 连接

> 参考资料:
> - [PostgreSQL Documentation - Table Expressions](https://www.postgresql.org/docs/current/queries-table-expressions.html)
> - [PostgreSQL Source - joinpath.c / joinrels.c](https://github.com/postgres/postgres/blob/master/src/backend/optimizer/path/joinpath.c)

## 标准 JOIN 类型

INNER JOIN
```sql
SELECT u.username, o.amount
FROM users u INNER JOIN orders o ON u.id = o.user_id;
```

LEFT / RIGHT / FULL OUTER JOIN
```sql
SELECT u.username, o.amount FROM users u LEFT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
SELECT u.username, o.amount FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;
```

CROSS JOIN
```sql
SELECT u.username, r.role_name FROM users u CROSS JOIN roles r;
```

USING（同名列简写）
```sql
SELECT * FROM users JOIN orders USING (user_id);
```

NATURAL JOIN（按所有同名列自动匹配——不推荐，隐式行为危险）
```sql
SELECT * FROM users NATURAL JOIN orders;
```

## LATERAL JOIN (9.3+): PostgreSQL 的相关子查询升级

LATERAL 允许子查询引用外部表的列（每行执行一次子查询）
```sql
SELECT u.username, latest.amount, latest.order_date
FROM users u
JOIN LATERAL (
    SELECT amount, order_date FROM orders
    WHERE user_id = u.id ORDER BY order_date DESC LIMIT 1
) latest ON TRUE;
```

LEFT JOIN LATERAL（即使没有匹配也保留左表行）
```sql
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY amount DESC LIMIT 3
) latest ON TRUE;
```

设计分析: LATERAL 的价值
  传统子查询在 FROM 中不能引用同级表的列。
  LATERAL 解除了这个限制——等价于 SQL Server 的 CROSS APPLY / OUTER APPLY。
  典型场景:
    (a) 每组取 Top-N（LATERAL + LIMIT，比窗口函数更高效当有索引时）
    (b) 展开 JSON/数组（LATERAL + jsonb_array_elements）
    (c) 调用 set-returning functions（LATERAL + generate_series）

对比:
  PostgreSQL: LATERAL JOIN (9.3+)
  SQL Server: CROSS APPLY / OUTER APPLY (2005+)
  MySQL:      LATERAL (8.0.14+)
  Oracle:     LATERAL (12c+)

## JOIN 优化器: 三种物理 JOIN 算法

PostgreSQL 优化器会根据数据分布和成本估算选择 JOIN 算法:

(1) Nested Loop Join
  适用: 小表驱动大表，内表有索引
  原理: 外表每行到内表做索引查找
  成本: O(N * log M) (有索引) 或 O(N * M) (无索引)
```sql
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.id = 1;
```

(2) Hash Join
  适用: 等值 JOIN，两个大表
  原理: 小表构建哈希表，大表逐行探测
  成本: O(N + M)，需要内存（work_mem）
```sql
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id;
```

(3) Merge Join
  适用: 等值 JOIN，两表已排序（或有排序索引）
  原理: 两个有序流合并
  成本: O(N log N + M log M)（含排序）或 O(N + M)（已排序）
```sql
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id ORDER BY u.id;
```

控制 JOIN 算法（调试用）
```sql
SET enable_nestloop = off;
SET enable_hashjoin = off;
SET enable_mergejoin = off;
```

## JOIN 顺序优化: GEQO 与搜索空间

对于 N 个表的 JOIN，可能的 JOIN 顺序是 N! 种。
PostgreSQL 的优化策略:
  N <= 8 (geqo_threshold):  穷举搜索所有 JOIN 顺序（动态规划）
  N > 8:                     使用 GEQO（遗传算法）近似搜索

join_collapse_limit（默认8）: 控制优化器展开 JOIN 的深度
from_collapse_limit（默认8）: 控制子查询提升为 JOIN 的深度

强制 JOIN 顺序: SET join_collapse_limit = 1;
此时优化器按 SQL 中写的顺序 JOIN（不重排）

## 并行 JOIN (9.6+)

PostgreSQL 支持并行 Hash Join 和并行 Nested Loop:
  Parallel Hash Join: 多个 worker 并行构建哈希表（11+）
  Parallel Nested Loop: 多个 worker 并行扫描外表
```sql
SET max_parallel_workers_per_gather = 4;
EXPLAIN SELECT * FROM large_table a JOIN large_table b ON a.id = b.ref_id;
```

观察 Parallel Hash Join 节点

## 横向对比: JOIN 实现差异

### LATERAL

  PostgreSQL: LATERAL JOIN (9.3+)
  SQL Server: CROSS/OUTER APPLY (2005+, 功能等价)
  MySQL:      LATERAL (8.0.14+)
  Oracle:     LATERAL (12c+)

### JOIN 算法

  PostgreSQL: Nested Loop + Hash + Merge（3种）+ Parallel Hash (11+)
  MySQL:      Nested Loop 为主，8.0.18+ Hash Join，无 Merge Join
  Oracle:     Nested Loop + Hash + Sort Merge（3种，最成熟）
  SQL Server: Nested Loop + Hash + Merge（3种）

### FULL OUTER JOIN

  所有主流数据库都支持，但 MySQL 到 8.0 才完善

### NATURAL JOIN

  所有数据库都支持，但普遍不推荐（隐式匹配列名，添加列会改变语义）

## 对引擎开发者的启示

(1) 三种 JOIN 算法是 OLTP 引擎的最低要求:
    Nested Loop（有索引）, Hash Join（无索引大表）, Merge Join（已排序）。
    缺少任何一种都会在某些场景下性能崩溃。

(2) LATERAL 是 SQL 表达力的重要扩展:
    "每行执行一次子查询"的语义不能被传统 JOIN 完全替代。
    实现: LATERAL 子查询在执行器中作为参数化子计划（parameterized path）。

(3) JOIN 顺序优化是优化器最复杂的部分:
    穷举搜索 O(N!) 在表多时不可行，必须有启发式或近似算法。
    PostgreSQL 的 GEQO（遗传算法）是一种工程上的折中。

## 版本演进

PostgreSQL 8.4:  Hash Join 性能改进
PostgreSQL 9.3:  LATERAL JOIN
PostgreSQL 9.6:  Parallel Nested Loop
PostgreSQL 11:   Parallel Hash Join
PostgreSQL 13:   Incremental Sort（改进 Merge Join 效率）
PostgreSQL 14:   Memoize 节点（缓存 Nested Loop 内表结果）
