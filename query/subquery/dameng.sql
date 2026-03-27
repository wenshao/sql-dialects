-- DamengDB (达梦): 子查询 (Subqueries)
-- DamengDB is Oracle-compatible, with DM-specific extensions.
--
-- 参考资料:
--   [1] DamengDB SQL Language Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Administration Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html
--   [3] DamengDB Performance Tuning Guide
--       https://eco.dameng.com/document/dm/zh-cn/perf/index.html

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
-- DamengDB 优化器可能将标量子查询转换为外连接（subquery unnesting）

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
--   Oracle 兼容: DamengDB 行为与 Oracle 完全一致

-- ============================================================
-- 3. EXISTS / NOT EXISTS
-- ============================================================

SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- EXISTS 的优化:
--   DamengDB 优化器将 EXISTS 子查询展开为 Semi Join。
--   NOT EXISTS 转换为 Anti Join。
--   与 Oracle 的 unnesting 优化策略一致。

-- ============================================================
-- 4. 比较运算符 + ALL / ANY / SOME
-- ============================================================

SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- DamengDB: ANY 和 SOME 是同义词（SQL 标准行为，与 Oracle 一致）

-- ============================================================
-- 5. FROM 子查询（内联视图 / Inline View）
-- ============================================================

SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- DamengDB Oracle 兼容特性:
--   内联视图在某些情况下可以省略别名（与 Oracle 兼容）
--   但建议始终使用别名以保证可移植性

-- ============================================================
-- 6. WITH 子查询分解 (CTE)
-- ============================================================

-- 简单 CTE
WITH city_stats AS (
    SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
    FROM users GROUP BY city
)
SELECT * FROM city_stats WHERE cnt > 10;

-- 多 CTE 引用
WITH active_users AS (
    SELECT DISTINCT user_id FROM orders WHERE amount > 100
),
user_details AS (
    SELECT u.* FROM users u
    WHERE EXISTS (SELECT 1 FROM active_users a WHERE a.user_id = u.id)
)
SELECT * FROM user_details;

-- 递归 CTE（DamengDB 支持）
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.level + 1
    FROM employees e, org_tree t WHERE e.manager_id = t.id
)
SELECT * FROM org_tree ORDER BY level;

-- ============================================================
-- 7. Oracle 兼容的子查询特性
-- ============================================================

-- CONNECT BY 层级查询（Oracle 兼容语法，DamengDB 支持）
SELECT id, name, manager_id, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR id = manager_id;

-- 标量子查询作为列的默认值（Oracle 风格）
SELECT u.username,
       (SELECT o.order_id FROM orders o
        WHERE o.user_id = u.id AND ROWNUM = 1
        ORDER BY o.amount DESC) AS latest_order_id
FROM users u;

-- ROWNUM 限制（Oracle 兼容，不用 LIMIT）
SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100)
AND ROWNUM <= 10;

-- ============================================================
-- 8. 子查询优化: 展开 (Subquery Unnesting)
-- ============================================================

-- DamengDB 继承 Oracle 风格的子查询展开优化:
--   IN (subquery)      →  Semi Join (Hash / Nested Loop)
--   NOT IN (subquery)  →  Anti Join (注意 NULL 语义)
--   EXISTS (subquery)  →  Semi Join
--   标量子查询          →  Outer Join (某些情况)

-- 查看子查询执行计划:
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
-- 关注: 是否出现 SEMI JOIN / ANTI JOIN 算子

-- DamengDB 优化器提示（控制子查询展开）:
-- ENABLE_UNNEST_SUBQUERY: 允许子查询展开（默认开启）
-- DISABLE_UNNEST_SUBQUERY: 禁止子查询展开（调试用）

-- ============================================================
-- 9. 横向对比: DamengDB vs Oracle vs PostgreSQL
-- ============================================================

-- 1. 语法兼容性:
--   DamengDB:   Oracle 兼容（CONNECT BY, ROWNUM, 内联视图）
--   Oracle:     原生支持所有特性
--   PostgreSQL: 标准SQL + 扩展（LATERAL, ARRAY(SELECT...)）
--
-- 2. 子查询优化:
--   DamengDB:   unnesting 展开（Oracle 风格），Semi/Anti Join
--   Oracle:     成熟的 unnesting + predicate pushdown
--   PostgreSQL: pull_up_subqueries + push_down_qual
--
-- 3. CTE 处理:
--   DamengDB:   支持 CTE，优化器可内联或物化
--   Oracle:     12c+ 支持 CTE，递归 CTE 支持完善
--   PostgreSQL: CTE 默认物化（12+ 可控制内联）
--
-- 4. 不支持 LATERAL:
--   DamengDB 当前版本不直接支持 LATERAL 语法。
--   替代方案: 使用标量子查询、CTE 或内联视图实现类似功能。

-- ============================================================
-- 10. 对引擎开发者的启示
-- ============================================================

-- (1) Oracle 兼容性是 DamengDB 的核心定位:
--     从 Oracle 迁移的子查询通常可以直接运行。
--     CONNECT BY + 子查询、ROWNUM + 子查询是常见迁移场景。
--
-- (2) 子查询展开 (unnesting) 是性能关键:
--     DamengDB 的 unnesting 策略与 Oracle 类似。
--     未展开的子查询以嵌套循环方式执行，性能极差。
--     检查 EXPLAIN 计划确认子查询是否被展开。
--
-- (3) 国产化替代中的测试要点:
--     NOT IN 与 NOT EXISTS 的 NULL 语义一致性。
--     递归 CTE 和 CONNECT BY 的结果一致性。
--     标量子查询在嵌套多层时的优化效果。

-- ============================================================
-- 11. 版本演进
-- ============================================================
-- DamengDB V7:  基本子查询, IN, EXISTS, ALL, ANY（Oracle 兼容）
-- DamengDB V8:  递归 CTE, 改进的子查询展开优化
-- DamengDB V8.1: 增强的 Semi/Anti Join 策略, CTE 物化优化
