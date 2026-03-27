-- SQL Server: 子查询
--
-- 参考资料:
--   [1] SQL Server T-SQL - Subqueries
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/subqueries-transact-sql

-- ============================================================
-- 1. 标量子查询
-- ============================================================

SELECT username,
       (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- ============================================================
-- 2. WHERE 子查询
-- ============================================================

SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- EXISTS（通常比 IN 更高效）
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- NOT EXISTS
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
-- SOME 是 ANY 的同义词

-- ============================================================
-- 3. FROM 子查询（派生表，必须有别名）
-- ============================================================

SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- ============================================================
-- 4. CROSS APPLY / OUTER APPLY 替代相关子查询
-- ============================================================

-- 传统相关子查询（每行执行一次子查询）:
SELECT u.username,
       (SELECT SUM(amount) FROM orders WHERE user_id = u.id) AS total
FROM users u;

-- APPLY 改写（语义更清晰，优化器处理更好）:
SELECT u.username, t.total
FROM users u
CROSS APPLY (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- OUTER APPLY（左连接语义——用户没有订单时 total 为 NULL）:
SELECT u.username, t.total
FROM users u
OUTER APPLY (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 设计分析（对引擎开发者）:
--   CROSS APPLY 是 SQL Server 对"侧向子查询"的实现（SQL:2003 LATERAL）。
--   它将相关子查询从 SELECT/WHERE 中提升到 FROM 中，使优化器有更多优化空间。
--
--   优化器对 APPLY 的处理:
--   (1) 去关联化: 将 APPLY 转换为 Hash Join（如果可能）
--   (2) 保持 Apply: 使用 Nested Loop + Apply 操作符
--   SQL Server 的查询优化器在 APPLY 去关联化方面非常成熟。

-- ============================================================
-- 5. SQL Server 不支持行构造器子查询
-- ============================================================

-- 标准 SQL 支持: WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city)
-- SQL Server 不支持这种语法。必须用 EXISTS 改写:
SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM (
        SELECT city, MIN(age) AS min_age FROM users GROUP BY city
    ) t WHERE t.city = u.city AND t.min_age = u.age
);

-- 横向对比:
--   PostgreSQL: 支持 (a, b) IN (SELECT ...) 和 (a, b) = (SELECT ...)
--   MySQL:      8.0+ 支持行构造器比较
--   Oracle:     支持 (a, b) IN (SELECT ...)
--   SQL Server: 不支持（必须用 EXISTS 改写）
--
-- 对引擎开发者的启示:
--   行构造器比较是 SQL 标准特性，大多数引擎支持。
--   SQL Server 不支持这个是 T-SQL 解析器的历史遗留限制。
--   实现行构造器比较需要支持匿名复合类型的比较操作。

-- ============================================================
-- 6. 子查询的优化行为
-- ============================================================

-- SQL Server 优化器会尝试将子查询转换为 JOIN:
-- IN 子查询 → Semi Join
-- NOT IN 子查询 → Anti Semi Join
-- EXISTS → Semi Join

-- 但 NOT IN 有 NULL 陷阱:
-- 如果子查询返回 NULL，NOT IN 的结果是 UNKNOWN（不返回任何行）
-- 推荐: 总是使用 NOT EXISTS 替代 NOT IN

-- 示例:
-- 危险: SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM orders);
-- 如果 orders.user_id 有 NULL 值，整个查询返回 0 行
-- 安全: SELECT * FROM users u WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 对引擎开发者的启示:
--   NOT IN 的 NULL 语义是 SQL 三值逻辑的经典陷阱。
--   优化器在转换 NOT IN → Anti Join 时必须处理 NULL 情况:
--   (1) 如果子查询列有 NOT NULL 约束，可以安全转换
--   (2) 否则需要添加 IS NOT NULL 过滤或使用 NOT EXISTS 语义
--   SQL Server 的优化器会自动处理这个问题，但代价是更复杂的执行计划。

-- ============================================================
-- 7. 子查询 vs CTE vs 临时表: 选择策略
-- ============================================================

-- 子查询: 一次性使用，简单逻辑
-- CTE:     多次引用（但注意 SQL Server 可能重复执行 CTE 体）
-- 临时表:  需要物化结果、添加索引、或在多个语句间共享
-- 表变量:  小数据集，不需要统计信息的场景

-- CTE 重复执行的验证:
;WITH expensive_cte AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT * FROM expensive_cte WHERE total > 1000
UNION ALL
SELECT * FROM expensive_cte WHERE total < 100;
-- SQL Server 可能会执行 expensive_cte 两次（不保证物化）
-- 如果需要避免重复计算，使用临时表:
SELECT user_id, SUM(amount) AS total INTO #temp FROM orders GROUP BY user_id;
