-- Oracle: 子查询 (Subqueries)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Using Subqueries
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Using-Subqueries.html
--   [2] Oracle SQL Language Reference - SELECT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- ============================================================
-- 1. 标量子查询
-- ============================================================

SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- Oracle 标量子查询缓存（Oracle 独有优化）:
-- Oracle 自动缓存标量子查询的结果（按输入值哈希）。
-- 如果子查询被反复以相同参数调用，后续调用直接从缓存返回。
-- 这使得标量子查询在 Oracle 中的性能远优于其他数据库。
--
-- 对引擎开发者的启示:
--   标量子查询缓存是一个低成本高回报的优化。
--   实现方式: 在执行器中为每个标量子查询维护一个哈希表，
--   键是子查询的关联参数，值是上次计算的结果。

-- ============================================================
-- 2. WHERE 子查询
-- ============================================================

-- IN 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- EXISTS（通常比 IN 更高效，尤其当子查询结果集大时）
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- NOT EXISTS vs NOT IN 的关键区别:
-- NOT IN 在子查询返回 NULL 时，整个结果为空!
-- NOT EXISTS 不受 NULL 影响
-- 由于 Oracle 的 '' = NULL，子查询中的空字符串也会触发这个问题

-- 比较运算符
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- ============================================================
-- 3. FROM 子查询（内联视图，Oracle 术语）
-- ============================================================

SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- Oracle 将 FROM 子句中的子查询称为"内联视图"（Inline View），
-- 这个术语反映了它的本质: 一个临时的、匿名的视图。

-- ============================================================
-- 4. 行子查询与多列比较
-- ============================================================

-- 行子查询（每组最小年龄）
SELECT * FROM users
WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 多列比较
SELECT * FROM users
WHERE (city, age) = (SELECT 'Beijing', MAX(age) FROM users WHERE city = 'Beijing');

-- ============================================================
-- 5. LATERAL 子查询（12c+）
-- ============================================================

-- LATERAL 允许子查询引用外部表的列（打破传统子查询的隔离性）
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 对比传统关联子查询（只能在 SELECT/WHERE 中，不能在 FROM 中引用外部表）:
-- LATERAL 的价值在于可以在 FROM 子句中创建关联引用，
-- 这使得"每组取 Top-N"等问题可以更自然地表达。

-- ============================================================
-- 6. Oracle 独有的子查询特性
-- ============================================================

-- 6.1 WITH CHECK OPTION（视图/DML 子查询中确保数据满足条件）
CREATE VIEW adult_users AS
SELECT * FROM users WHERE age > 18 WITH CHECK OPTION;
-- 通过此视图 INSERT/UPDATE 时，如果 age <= 18 会报错

-- 6.2 子查询中使用 CONNECT BY 生成序列
SELECT LEVEL AS n FROM DUAL CONNECT BY LEVEL <= 10;
-- 生成 1 到 10 的序列，常用于子查询中

-- 6.3 多层嵌套子查询优化: Hint MATERIALIZE
-- Oracle 优化器可以选择物化子查询结果（存入临时段）或内联展开
-- 可以通过 CTE + Hint 控制:
WITH /*+ MATERIALIZE */ expensive AS (
    SELECT user_id, SUM(amount) FROM orders GROUP BY user_id
)
SELECT * FROM expensive WHERE SUM > 1000;

-- ============================================================
-- 7. '' = NULL 对子查询的影响
-- ============================================================

-- NOT IN 子查询的 NULL 陷阱（在 Oracle 中因 '' = NULL 更加危险）:
SELECT * FROM users WHERE city NOT IN (SELECT city FROM blacklist);
-- 如果 blacklist 中任何 city 是 NULL（或空字符串 ''），
-- 整个查询返回 0 行!（因为 x NOT IN (..., NULL) 对所有 x 为 UNKNOWN）

-- 安全写法:
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM blacklist b WHERE b.city = u.city);
-- NOT EXISTS 不受 NULL 影响

-- 对引擎开发者的启示:
--   NOT IN 的 NULL 语义是 SQL 标准定义的（不是 Oracle 特有），
--   但 Oracle 的 '' = NULL 放大了这个问题的影响范围。
--   优化器可以考虑在 NOT IN 子查询结果包含 NULL 时给出警告。

-- ============================================================
-- 8. 子查询展开与优化
-- ============================================================

-- Oracle 优化器的子查询转换策略:
-- 1. 子查询展开（Subquery Unnesting）: 将子查询转为 JOIN
--    IN (subquery) → semi-join
--    NOT IN (subquery) → anti-join
--    EXISTS (subquery) → semi-join
-- 2. 视图合并（View Merging）: 将内联视图合并到外层查询
-- 3. 推入谓词（Predicate Pushing）: 将外层 WHERE 推入子查询
--
-- Hint 控制:
SELECT /*+ UNNEST(@subq) */ * FROM users
WHERE id IN (SELECT /*+ QB_NAME(subq) */ user_id FROM orders);

SELECT /*+ NO_UNNEST(@subq) */ * FROM users
WHERE id IN (SELECT /*+ QB_NAME(subq) */ user_id FROM orders);

-- 对引擎开发者的启示:
--   子查询展开（将 IN/EXISTS 转为 semi-join）是优化器最基本的重写规则之一。
--   没有子查询展开的优化器会导致嵌套循环子查询计划，性能可能差 100 倍以上。
--   PostgreSQL、MySQL 8.0+、SQL Server 都有类似的优化。

-- ============================================================
-- 9. 对引擎开发者的总结
-- ============================================================
-- 1. 标量子查询缓存是 Oracle 独有的高价值优化，实现简单效果显著。
-- 2. NOT IN + NULL 是 SQL 的经典陷阱，'' = NULL 放大了问题。
-- 3. LATERAL 打破了 FROM 子句的隔离性，是现代 SQL 的重要特性。
-- 4. 子查询展开（unnesting）是优化器的基本功，必须实现。
-- 5. Oracle 的"内联视图"术语比"派生表"更直观地表达了 FROM 子查询的本质。
