-- BigQuery: 子查询
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Subqueries
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/subqueries

-- ============================================================
-- 1. 标量子查询
-- ============================================================

SELECT username, age,
       (SELECT AVG(age) FROM myproject.mydataset.users) AS avg_age
FROM myproject.mydataset.users;

-- ============================================================
-- 2. IN / EXISTS
-- ============================================================

SELECT * FROM myproject.mydataset.users
WHERE id IN (SELECT user_id FROM myproject.mydataset.orders WHERE amount > 100);

SELECT * FROM myproject.mydataset.users u
WHERE EXISTS (SELECT 1 FROM myproject.mydataset.orders o WHERE o.user_id = u.id);

-- ============================================================
-- 3. ARRAY 子查询（BigQuery 独有）
-- ============================================================

-- ARRAY() 将子查询结果收集为 ARRAY:
SELECT username,
       ARRAY(SELECT amount FROM myproject.mydataset.orders o WHERE o.user_id = u.id) AS order_amounts
FROM myproject.mydataset.users u;

-- 设计分析:
--   ARRAY 子查询是 BigQuery 嵌套类型设计的核心操作。
--   它将一对多关系"内联"为数组列，避免了 GROUP_CONCAT/STRING_AGG。
--   对比 ClickHouse: groupArray() 函数实现相同功能。
--   对比 PostgreSQL: ARRAY() 子查询（语法相同）。

-- ============================================================
-- 4. FROM 子句子查询 + UNNEST
-- ============================================================

-- 派生表
SELECT u.username, stats.total
FROM myproject.mydataset.users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM myproject.mydataset.orders GROUP BY user_id
) stats ON u.id = stats.user_id;

-- UNNEST 子查询（展开 ARRAY 列为行）
SELECT u.username, tag
FROM myproject.mydataset.users u, UNNEST(u.tags) AS tag;

-- STRUCT 子查询
SELECT * FROM UNNEST([
    STRUCT('alice' AS name, 25 AS age),
    STRUCT('bob' AS name, 30 AS age)
]);

-- ============================================================
-- 5. 相关子查询与成本
-- ============================================================

-- 相关子查询在 BigQuery 中可能很昂贵:
-- 外部查询的每一行都触发子查询执行。
-- BigQuery 优化器会尝试去相关化（decorrelation）。
-- 如果去相关化失败，性能可能很差。
-- 推荐: 使用 JOIN 或 CTE 替代相关子查询。

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 子查询的特点:
--   (1) ARRAY 子查询 → 一对多关系内联为数组
--   (2) UNNEST → 数组展开为行（ARRAY 的反操作）
--   (3) STRUCT 子查询 → 内联构造结构化数据
--   (4) 成本影响 → 相关子查询可能扫描多次
--
-- 对引擎开发者的启示:
--   支持 ARRAY/STRUCT 嵌套类型的引擎应提供:
--   ARRAY() 子查询（行→数组）+ UNNEST（数组→行）
--   这对消除了大量 JOIN + GROUP BY 的需求。
