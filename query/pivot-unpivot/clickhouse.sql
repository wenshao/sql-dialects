-- ClickHouse: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] ClickHouse Documentation - Aggregate Functions
--       https://clickhouse.com/docs/en/sql-reference/aggregate-functions
--   [2] ClickHouse Documentation - CASE
--       https://clickhouse.com/docs/en/sql-reference/functions/conditional-functions
--   [3] ClickHouse Documentation - Array Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/array-functions

-- ============================================================
-- 注意：ClickHouse 没有原生 PIVOT / UNPIVOT 语法
-- 使用 CASE WHEN / IF + GROUP BY 实现 PIVOT
-- 使用 ARRAY JOIN 或 UNION ALL 实现 UNPIVOT
-- ============================================================

-- ============================================================
-- PIVOT: CASE WHEN + GROUP BY
-- ============================================================
SELECT
    product,
    sumIf(amount, quarter = 'Q1') AS Q1,
    sumIf(amount, quarter = 'Q2') AS Q2,
    sumIf(amount, quarter = 'Q3') AS Q3,
    sumIf(amount, quarter = 'Q4') AS Q4
FROM sales
GROUP BY product;

-- 使用 -If 组合聚合函数（ClickHouse 特有）
SELECT
    product,
    countIf(quarter = 'Q1') AS Q1_count,
    countIf(quarter = 'Q2') AS Q2_count,
    avgIf(amount, quarter = 'Q1') AS Q1_avg,
    avgIf(amount, quarter = 'Q2') AS Q2_avg
FROM sales
GROUP BY product;

-- 使用 if() 函数
SELECT
    product,
    sum(if(quarter = 'Q1', amount, 0)) AS Q1,
    sum(if(quarter = 'Q2', amount, 0)) AS Q2,
    sum(if(quarter = 'Q3', amount, 0)) AS Q3,
    sum(if(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- PIVOT: Map 聚合（ClickHouse 特有）
-- ============================================================
-- 使用 Map 类型实现动态 PIVOT
SELECT
    product,
    sumMap(map(quarter, amount)) AS quarter_amounts
FROM sales
GROUP BY product;
-- 结果：{'Q1': 100, 'Q2': 200, ...}

-- ============================================================
-- UNPIVOT: ARRAY JOIN（ClickHouse 特有）
-- ============================================================
SELECT
    product,
    quarter,
    amount
FROM quarterly_sales
ARRAY JOIN
    ['Q1', 'Q2', 'Q3', 'Q4'] AS quarter,
    [Q1, Q2, Q3, Q4] AS amount;

-- 过滤 NULL / 0
SELECT
    product,
    quarter,
    amount
FROM quarterly_sales
ARRAY JOIN
    ['Q1', 'Q2', 'Q3', 'Q4'] AS quarter,
    [Q1, Q2, Q3, Q4] AS amount
WHERE amount > 0;

-- ============================================================
-- UNPIVOT: UNION ALL
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- ============================================================
-- 注意事项
-- ============================================================
-- ClickHouse 没有原生 PIVOT/UNPIVOT
-- -If 组合聚合函数（sumIf, countIf 等）是最佳的行转列方式
-- ARRAY JOIN 是最强大的列转行方式（ClickHouse 独有）
-- Map 类型适合动态 PIVOT 场景
-- 大数据量下 ARRAY JOIN 性能优于 UNION ALL
