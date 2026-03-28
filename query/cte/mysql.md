# MySQL: CTE 公共表表达式

> 参考资料:
> - [MySQL 8.0 Reference Manual - WITH (CTE)](https://dev.mysql.com/doc/refman/8.0/en/with.html)
> - [MySQL 8.0 Reference Manual - Recursive CTE](https://dev.mysql.com/doc/refman/8.0/en/with.html#common-table-expressions-recursive)
> - [MySQL 8.0 Reference Manual - Derived Table Optimization](https://dev.mysql.com/doc/refman/8.0/en/derived-table-optimization.html)

## 基本语法

基本 CTE
```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```

多个 CTE
```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;
```

CTE 引用前面的 CTE（链式依赖）
```sql
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id
)
SELECT * FROM enriched WHERE order_count > 5;
```

CTE 用于 INSERT / UPDATE / DELETE（8.0+）
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

## 递归 CTE

数字序列生成
```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n                          -- 锚点（anchor member）
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10    -- 递归成员（recursive member）
)
SELECT n FROM nums;
```

层级结构遍历（组织架构树）
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS CHAR(1000)) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           CONCAT(t.path, ' > ', u.username)
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY path;
```

日期序列生成（常用于报表补齐缺失日期）
```sql
WITH RECURSIVE date_range AS (
    SELECT DATE('2024-01-01') AS dt
    UNION ALL
    SELECT DATE_ADD(dt, INTERVAL 1 DAY) FROM date_range WHERE dt < '2024-01-31'
)
SELECT dr.dt, COALESCE(COUNT(o.id), 0) AS order_count
FROM date_range dr
LEFT JOIN orders o ON DATE(o.created_at) = dr.dt
GROUP BY dr.dt;
```

## CTE 的优化行为: 物化 vs 内联（对引擎开发者关键）

### MySQL 8.0 的 CTE 物化策略

MySQL 8.0 对 CTE 的优化经历了多个版本的演进:

8.0.0 ~ 8.0.13（早期）:
  CTE 总是物化（materialized）为内部临时表
  即使 CTE 只被引用一次，也会创建临时表存储结果
  这导致 CTE 可能比等价的子查询/派生表更慢

8.0.14+:
  优化器可以将 CTE 合并（merge）到外部查询中（与派生表相同的优化）
  条件: CTE 只被引用一次，且满足 merge 条件（无 DISTINCT/GROUP BY/LIMIT/聚合等）
  此时 CTE 等价于一个内联的子查询，不创建临时表

被多次引用的 CTE:
  如果 CTE 被引用多次，MySQL 仍然物化（避免重复计算）
  这是合理的: 物化一次 + 多次读取 < 多次重复计算

### MySQL CTE vs 派生表的执行计划对比

CTE 写法:
```sql
WITH cte AS (SELECT * FROM users WHERE status = 1)
SELECT * FROM cte WHERE age > 25;
```

EXPLAIN: 8.0.14+ 优化器会将 cte merge 到外部查询
等价于: SELECT * FROM users WHERE status = 1 AND age > 25;（单次扫描）

但如果 CTE 包含阻止 merge 的操作:
```sql
WITH cte AS (SELECT city, AVG(age) avg_age FROM users GROUP BY city)
SELECT * FROM cte WHERE avg_age > 30;
```

必须物化: 先执行 GROUP BY 生成临时表，再对临时表过滤
这与等价的派生表行为相同

### 横向对比: 各引擎的 CTE 物化策略

MySQL 8.0:
  单次引用: 8.0.14+ 可以 merge（等价于子查询内联）
  多次引用: 总是物化
  不支持 MATERIALIZED / NOT MATERIALIZED hint

PostgreSQL 12+:
  默认: 单次引用的 CTE 内联（not materialized）
  多次引用: 物化
  可以显式控制:
    WITH cte AS MATERIALIZED (...)      -- 强制物化
    WITH cte AS NOT MATERIALIZED (...)  -- 强制内联（即使多次引用）
  PG 11 及之前: CTE 总是物化（优化器栅栏），这曾是 PG 的性能陷阱

SQL Server:
  CTE 总是内联（不物化），等价于子查询展开
  多次引用 CTE: 每次引用都重新计算！
  如果需要物化: 手动创建临时表 SELECT INTO #temp

Oracle:
  /*+ MATERIALIZE */ hint 强制物化
  /*+ INLINE */ hint 强制内联
  优化器自动选择（通常单次引用内联，多次引用物化）

对引擎开发者的启示:
  (1) CTE 的物化/内联选择对性能影响巨大
  (2) 推荐 PG 12+ 的方案: 默认内联 + MATERIALIZED/NOT MATERIALIZED hint
  (3) SQL Server 的方案（总是内联）在 CTE 被多次引用时可能导致重复计算
  (4) 需要在优化器中实现: CTE 引用计数 → 单次引用内联，多次引用物化

## 递归 CTE 的深度限制和性能风险

### 深度限制

MySQL: cte_max_recursion_depth 变量控制（默认 1000）
```sql
SET cte_max_recursion_depth = 10000;  -- 调整上限
-- 超过限制报错: ERROR 3636 (HY000): Recursive query aborted after N iterations
-- 目的: 防止无限递归（无终止条件时 CPU 和内存耗尽）

-- 4.2 递归 CTE 的性能风险
--
-- 风险 1: 指数级膨胀
-- 如果递归关系是多对多（如图遍历），每层递归行数可能指数增长
-- 例: 社交网络中"朋友的朋友": 每层扩展 100 倍，5 层 = 100^5 = 10 亿行
-- 解决: 添加去重（但 MySQL 递归 CTE 不支持 DISTINCT）
--
-- 风险 2: 无索引的递归 JOIN
-- WITH RECURSIVE tree AS (
--     SELECT ... FROM t WHERE id = 1
--     UNION ALL
--     SELECT ... FROM t JOIN tree ON t.parent_id = tree.id
-- )
-- 如果 t.parent_id 无索引: 每层递归都全表扫描
-- 10 层递归 × 100 万行表 = 1000 万次全表扫描
-- 解决: 确保递归 JOIN 条件列有索引
--
-- 风险 3: 内存消耗
-- 递归 CTE 的中间结果存在内存临时表中
-- 深度递归会消耗大量内存（每层结果都需要保留，直到递归结束）
-- MySQL 的临时表超过 tmp_table_size 时转为磁盘临时表（性能骤降）

-- 4.3 递归 CTE 的限制（MySQL 特有）
-- (1) 递归成员不能包含: GROUP BY, 聚合函数, 窗口函数, DISTINCT, LIMIT
-- (2) 只支持 UNION ALL（不支持 UNION，即不能自动去重）
--     PG 支持 UNION（自动去重），这对图遍历很重要（避免环路）
-- (3) 递归成员只能引用 CTE 一次（不能自 JOIN）
-- (4) 不支持相互递归（CTE A 引用 CTE B，CTE B 引用 CTE A）

-- 4.4 横向对比: 递归 CTE 的实现差异
--
-- MySQL 8.0:
--   UNION ALL only, 无 DISTINCT, 默认深度 1000
--   递归成员限制多（不支持聚合、窗口函数等）
--
-- PostgreSQL:
--   支持 UNION（自动去重，避免环路）和 UNION ALL
--   支持 CYCLE 子句（13+，自动检测环路）
--   递归成员限制少（支持聚合等）
--   无硬性深度限制（但可设 statement_timeout 防止无限递归）
--
-- Oracle:
--   传统语法: CONNECT BY ... START WITH ...（Oracle 特有，早于 SQL 标准）
--   CTE 递归: 11gR2+ 支持标准递归 CTE
--   CONNECT BY 功能更强: NOCYCLE（防环）、LEVEL（层级）、SYS_CONNECT_BY_PATH（路径）
--   CONNECT BY vs 递归 CTE: CONNECT BY 语法更简洁但不标准
--
-- SQL Server:
--   默认最大递归深度 100（OPTION (MAXRECURSION N) 调整，0 = 无限）
--   支持 UNION ALL（不支持 UNION 去重）
--   与 MySQL 限制类似
```

## CTE 的实际应用模式

模式 1: 简化复杂查询（可读性）
```sql
WITH
monthly_revenue AS (
    SELECT DATE_FORMAT(created_at, '%Y-%m') AS month, SUM(amount) AS revenue
    FROM orders GROUP BY month
),
monthly_growth AS (
    SELECT month, revenue,
           LAG(revenue) OVER (ORDER BY month) AS prev_revenue,
           ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
                 / LAG(revenue) OVER (ORDER BY month) * 100, 2) AS growth_pct
    FROM monthly_revenue
)
SELECT * FROM monthly_growth;
```

模式 2: 递归层级查询（BOM 物料清单、组织架构）
见第 2 节的 org_tree 示例

模式 3: 数据生成（用于 JOIN 补齐缺失数据）
见第 2 节的 date_range 示例

## 对引擎开发者: CTE 实现的设计决策

决策 1: 物化策略
  推荐: 引用计数 + hint 控制
  引用 1 次: 默认内联（优化器可以下推过滤条件）
  引用 > 1 次: 默认物化（避免重复计算）
  提供 MATERIALIZED / NOT MATERIALIZED hint 让用户覆盖

决策 2: 递归终止机制
  必须: 深度限制（防止无限递归）
  推荐: 环路检测（CYCLE 子句或自动检测）
  推荐: 支持 UNION 去重（自动去重是最简单的防环方案）
  MySQL 8.0 只有深度限制，PG 13+ 有完整的 CYCLE 子句

决策 3: 递归 CTE 的存储
  迭代表（working table）: 存储当前递归层的新增行
  结果表:                 存储所有已生成的行
  内存管理: 迭代表通常较小（一层的行），结果表持续增长
  当结果表超出内存时需要溢出到磁盘

决策 4: CTE 与优化器的交互
  内联 CTE: 优化器可以将 CTE 的查询与外部查询一起优化（谓词下推、JOIN 重排等）
  物化 CTE: 优化器将 CTE 视为黑盒（优化器栅栏），无法下推过滤条件
  PG 11 之前: CTE 总是物化 → 常见的性能陷阱（用户期望内联但被物化）
  教训: 不要默认物化单次引用的 CTE

## 版本演进

MySQL 8.0:    CTE 首次引入（非递归 + 递归）
MySQL 8.0:    CTE 可用于 SELECT/INSERT/UPDATE/DELETE
MySQL 8.0.14: CTE merge 优化（单次引用的 CTE 可以内联到外部查询）
MySQL 8.0:    cte_max_recursion_depth 默认 1000
未支持:       MATERIALIZED / NOT MATERIALIZED hint
未支持:       递归 CTE 的 UNION（只支持 UNION ALL）
未支持:       CYCLE 子句（环路检测）
