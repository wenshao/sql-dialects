-- ClickHouse: 子查询
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - SELECT
--       https://clickhouse.com/docs/en/sql-reference/statements/select
--   [2] ClickHouse - IN Operators
--       https://clickhouse.com/docs/en/sql-reference/operators/in

-- ============================================================
-- 1. 标量子查询
-- ============================================================

SELECT username, age,
       (SELECT avg(age) FROM users) AS avg_age
FROM users;

SELECT * FROM users WHERE age > (SELECT avg(age) FROM users);

-- ============================================================
-- 2. IN / NOT IN（ClickHouse 的特殊行为）
-- ============================================================

SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

-- GLOBAL IN: 分布式查询的特殊处理
SELECT * FROM users WHERE id GLOBAL IN (SELECT user_id FROM orders WHERE amount > 100);
-- GLOBAL IN: 子查询在发起节点执行，结果广播到所有 shard
-- 普通 IN: 子查询在每个 shard 本地执行（分布式表时行为不同!）

-- 设计分析:
--   IN vs GLOBAL IN 是 ClickHouse 分布式查询的核心概念。
--   如果子查询引用分布式表:
--     IN → 每个 shard 独立执行子查询（可能得到不同结果）
--     GLOBAL IN → 在协调节点执行子查询，结果广播（结果一致）
--   其他数据库没有这个区分（因为不暴露分布式细节给用户）。

-- ============================================================
-- 3. EXISTS / NOT EXISTS
-- ============================================================

SELECT * FROM users u WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.amount > 100
);

-- ============================================================
-- 4. FROM 子句子查询
-- ============================================================

SELECT u.username, stats.total
FROM users u
JOIN (
    SELECT user_id, sum(amount) AS total FROM orders GROUP BY user_id
) stats ON u.id = stats.user_id;

-- ============================================================
-- 5. 数组子查询（ClickHouse 独有）
-- ============================================================

-- groupArray: 将子查询结果收集为数组
SELECT username,
       (SELECT groupArray(amount) FROM orders WHERE user_id = users.id) AS amounts
FROM users;

-- arrayJoin: 将数组展开为行（反向操作）
SELECT arrayJoin([1, 2, 3]) AS x;

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 子查询的特点:
--   (1) GLOBAL IN vs IN → 分布式一致性控制
--   (2) groupArray → 子查询结果收集为数组
--   (3) arrayJoin → 数组展开为行
--   (4) 无 LATERAL JOIN → 用相关子查询替代
--
-- 对引擎开发者的启示:
--   分布式引擎需要 GLOBAL IN 类的机制:
--   用户需要控制子查询在哪里执行（本地 vs 全局）。
--   groupArray + arrayJoin 是 ClickHouse 独有的强大工具:
--   将关系模型和数组操作无缝连接。
