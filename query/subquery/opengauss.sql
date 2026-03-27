-- openGauss / GaussDB: 子查询 (Subqueries)
-- openGauss is PostgreSQL-compatible; GaussDB adds distributed capabilities.
--
-- 参考资料:
--   [1] openGauss SQL Reference - Subqueries
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation - SQL Syntax
--       https://support.huaweicloud.com/gaussdb/index.html
--   [3] openGauss Source - Optimizer
--       https://gitee.com/opengauss/openGauss-server/tree/master/src/gausskernel/runtime/executor

-- ============================================================
-- 1. 标量子查询
-- ============================================================

-- 示例数据:
--   users(id, username, age, city)
--   orders(id, user_id, amount, status)

SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- 标量子查询必须返回 0 或 1 行，否则运行时报错
-- openGauss 优化器可能将标量子查询转换为 JOIN（subquery flattening）

SELECT username,
    (SELECT SUM(amount) FROM orders WHERE user_id = users.id) AS total_amount
FROM users
WHERE city = 'Beijing';

-- ============================================================
-- 2. WHERE 子查询 (IN / NOT IN)
-- ============================================================

SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- NOT IN 的 NULL 陷阱:
--   如果子查询返回任何 NULL，NOT IN 的结果为 UNKNOWN（空集）。
--   因为: x NOT IN (1, NULL) = x<>1 AND x<>NULL = ? AND UNKNOWN = UNKNOWN
--   解决: 使用 NOT EXISTS 替代 NOT IN

-- ============================================================
-- 3. EXISTS / NOT EXISTS
-- ============================================================

SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- EXISTS 的优化:
--   openGauss 优化器将 EXISTS 子查询转换为 Semi Join。
--   Semi Join 只需要找到第一个匹配行即可停止（不需要遍历所有匹配）。
--   NOT EXISTS 转换为 Anti Join。

-- ============================================================
-- 4. 比较运算符 + ALL / ANY
-- ============================================================

SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- ============================================================
-- 5. FROM 子查询（派生表 / Derived Table）
-- ============================================================

SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- openGauss 要求派生表必须有别名（与 PostgreSQL 一致）

-- ============================================================
-- 6. LATERAL 子查询: 相关子查询的进化
-- ============================================================

-- LATERAL 允许 FROM 中的子查询引用同级表的列
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 返回多行多列
SELECT u.username, t.order_id, t.amount
FROM users u,
LATERAL (SELECT order_id, amount FROM orders
         WHERE user_id = u.id ORDER BY amount DESC LIMIT 3) t;

-- ============================================================
-- 7. CTE (WITH 子句): 子查询的替代方案
-- ============================================================

-- 简单 CTE
WITH city_stats AS (
    SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
    FROM users GROUP BY city
)
SELECT * FROM city_stats WHERE cnt > 10;

-- 递归 CTE
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.level + 1
    FROM employees e, org_tree t WHERE e.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY level;

-- ============================================================
-- 8. 子查询优化: 提升 (Subquery Flattening)
-- ============================================================

-- openGauss 继承并增强 PostgreSQL 优化器:
--   IN (subquery)      →  Semi Join (Hash / Nested Loop / Merge)
--   NOT IN (subquery)  →  Anti Join (注意 NULL 语义)
--   EXISTS (subquery)  →  Semi Join
--   标量子查询          →  Left Join (某些情况)

-- openGauss 自研增强:
--   (a) 增强的代价模型，更准确地评估子查询执行代价
--   (b) 自适应执行计划（根据运行时统计动态调整 Semi Join 策略）
--   (c) 分布式执行计划优化（GaussDB 分布式版本）

-- 查看子查询执行计划:
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
-- 关注: 是否出现 Hash Semi Join（说明子查询被提升为 JOIN）

EXPLAIN PERFORMANCE SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- EXPLAIN PERFORMANCE 显示实际执行时间和行数

-- ============================================================
-- 9. GaussDB 分布式子查询
-- ============================================================

-- GaussDB 分布式版本中，子查询生成分布式执行计划:
--   协调节点 (Coordinator) 解析 SQL 并生成分布式计划
--   数据节点 (DN) 执行分片内操作
--   协调节点汇总结果

-- 分布式优化策略:
--   (a) 子查询下推: 尽量将子查询推到数据节点执行
--   (b) 分布式 Semi Join: 使用 redistribute + local semi join
--   (c) Replicate 表: 小表复制到所有节点，避免数据重分布

-- 示例: 利用分布键优化子查询
-- 如果 users.id 和 orders.user_id 都是分布键:
SELECT * FROM users WHERE id IN (
    SELECT user_id FROM orders WHERE amount > 100
);
-- 分布键一致 → 本地 Semi Join（最优）

-- 分布键不一致时:
SELECT * FROM users WHERE id IN (
    SELECT user_id FROM orders WHERE amount > 100
);
-- 需要数据重分布 → redistribute user_id 到对应分片

-- ============================================================
-- 10. 横向对比: openGauss vs PostgreSQL vs 其他国产数据库
-- ============================================================

-- 1. 优化器增强:
--   openGauss:   PG 优化器 + 自研增强（自适应执行、分布式优化）
--   PostgreSQL:  成熟的 pull_up_subqueries + push_down_qual
--   KingbaseES:  PG 优化器（无额外增强）
--   DamengDB:    Oracle 风格 unnesting
--
-- 2. 分布式子查询:
--   GaussDB:     分布式执行计划 + 数据重分布
--   TDSQL:       shardkey 路由优化
--   PolarDB-X:   分片路由 + 下推优化
--   TiDB:        Coprocessor 下推 + Hash Join
--
-- 3. LATERAL 支持:
--   openGauss:  完全支持（继承 PG 9.3+）
--   KingbaseES: 完全支持（继承 PG）
--   DamengDB:   不直接支持
--   TDSQL:      MySQL 8.0.14+ LATERAL

-- ============================================================
-- 11. 对引擎开发者的启示
-- ============================================================

-- (1) openGauss 在 PG 优化器基础上做了显著增强:
--     自适应执行计划是 openGauss 的亮点，可以根据运行时统计调整策略。
--     对子查询而言，这意味着 Semi Join 策略可以在执行中动态切换。
--
-- (2) GaussDB 分布式子查询的关键是数据分布:
--     分布键的选择直接决定子查询是否需要跨节点通信。
--     设计时确保关联列使用相同的分布策略。
--
-- (3) EXPLAIN PERFORMANCE 是调试利器:
--     相比 EXPLAIN ANALYZE，openGauss 的 EXPLAIN PERFORMANCE
--     提供更详细的执行时间分解和算子级别统计。

-- ============================================================
-- 12. 版本演进
-- ============================================================
-- openGauss 1.0:  基于 PostgreSQL 9.2，基本子查询支持
-- openGauss 2.0:  增强的子查询优化，LATERAL 支持
-- openGauss 3.0:  自适应执行计划，改进的 Semi Join 策略
-- openGauss 5.0:  分布式子查询优化增强，CTE 内联控制
-- GaussDB:        企业级分布式 + 分布式子查询计划优化
