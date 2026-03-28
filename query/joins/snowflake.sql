-- Snowflake: JOIN
--
-- 参考资料:
--   [1] Snowflake SQL Reference - JOIN
--       https://docs.snowflake.com/en/sql-reference/constructs/join

-- ============================================================
-- 1. 标准 JOIN
-- ============================================================

SELECT u.username, o.amount
FROM users u INNER JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u RIGHT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u FULL OUTER JOIN orders o ON u.id = o.user_id;

SELECT u.username, r.role_name
FROM users u CROSS JOIN roles r;

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e LEFT JOIN users m ON e.manager_id = m.id;

-- USING / NATURAL JOIN
SELECT * FROM users JOIN orders USING (user_id);
SELECT * FROM users NATURAL JOIN orders;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 LATERAL JOIN + FLATTEN: Snowflake 的核心 JOIN 创新
-- LATERAL 允许子查询引用外部表的列:
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC LIMIT 1
) latest;

-- FLATTEN: 展开 VARIANT 数组/对象为行（Snowflake 独有语法）
SELECT u.username, f.value::STRING AS tag
FROM users u, LATERAL FLATTEN(input => u.tags) f;

-- FLATTEN 的内部实现:
--   FLATTEN 是一个表函数，将 VARIANT 的每个元素生成一行
--   输出列: SEQ, KEY, PATH, INDEX, VALUE, THIS
--   LATERAL 关键字使每行调用一次 FLATTEN（关联执行）
--
-- 对比:
--   PostgreSQL: unnest(array) 或 jsonb_array_elements
--   MySQL:      JSON_TABLE (8.0.4+)
--   BigQuery:   UNNEST(array_col)（必须用 CROSS JOIN UNNEST）
--   Oracle:     JSON_TABLE 或 TABLE(cast_collection)
--
-- 对引擎开发者的启示:
--   LATERAL + 表函数是展开嵌套数据的通用方案。
--   Snowflake 的 FLATTEN 语法（INPUT, PATH, RECURSIVE, MODE 参数）
--   比 PostgreSQL 的 unnest 更结构化（但也更冗长）。
--   如果引擎支持嵌套类型，LATERAL + 展开函数是必要能力。

-- 2.2 ASOF JOIN: 时间序列匹配（Snowflake 独有）
SELECT s.symbol, s.price, t.trade_price
FROM stock_prices s
ASOF JOIN trades t
    MATCH_CONDITION(s.timestamp >= t.timestamp)
    ON s.symbol = t.symbol;

-- ASOF JOIN 找到满足 MATCH_CONDITION 的最近一行
-- 典型场景: 将交易匹配到最近的价格快照
-- 对比:
--   PostgreSQL: LATERAL + ORDER BY + LIMIT 1（手动实现）
--   BigQuery:   无原生 ASOF JOIN
--   Databricks: 无原生 ASOF JOIN
--   kdb+/TimescaleDB: 原生 ASOF JOIN（时序数据库的标配）
--
-- 对引擎开发者的启示:
--   ASOF JOIN 是时间序列分析的刚需。传统方案（LATERAL + LIMIT 1）
--   性能很差（每行触发一次子查询）。专用的 ASOF JOIN 算子可以
--   利用排序归并实现 O(N+M) 的时间复杂度。

-- ============================================================
-- 3. FLATTEN 详细用法
-- ============================================================

-- 展开嵌套数组
SELECT u.username, f.VALUE:name::STRING AS item_name
FROM users u, LATERAL FLATTEN(input => u.order_details) f;

-- 展开对象的 KEY-VALUE
SELECT u.id, f.KEY, f.VALUE
FROM users u, LATERAL FLATTEN(input => u.metadata) f;

-- 递归展开嵌套结构
SELECT f.PATH, f.KEY, f.VALUE
FROM events, LATERAL FLATTEN(input => data, RECURSIVE => TRUE) f
WHERE TYPEOF(f.VALUE) NOT IN ('OBJECT', 'ARRAY');

-- ============================================================
-- 4. 多表 JOIN
-- ============================================================

SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- TABLESAMPLE（采样 JOIN）
SELECT u.username, o.amount
FROM users u TABLESAMPLE (10)       -- 采样 10% 的行
JOIN orders o ON u.id = o.user_id;

-- ============================================================
-- 横向对比: JOIN 能力矩阵
-- ============================================================
-- 能力           | Snowflake    | BigQuery      | PostgreSQL  | MySQL
-- LATERAL JOIN   | 支持         | 不支持        | 支持        | 8.0.14+
-- FLATTEN        | 原生         | UNNEST        | unnest      | JSON_TABLE
-- ASOF JOIN      | 原生         | 不支持        | 不支持      | 不支持
-- NATURAL JOIN   | 支持         | 不支持        | 支持        | 支持
-- TABLESAMPLE    | 支持         | 不支持        | 支持        | 不支持
-- SEMI JOIN      | EXISTS/IN    | EXISTS/IN     | EXISTS/IN   | EXISTS/IN
