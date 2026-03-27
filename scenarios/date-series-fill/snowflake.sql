-- Snowflake: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Snowflake Documentation - GENERATOR
--       https://docs.snowflake.com/en/sql-reference/functions/generator
--   [2] Snowflake Documentation - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic

-- ============================================================
-- 准备数据
-- ============================================================

CREATE OR REPLACE TEMPORARY TABLE daily_sales (sale_date DATE, amount NUMBER(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

-- ============================================================
-- 1. 使用 GENERATOR 生成日期序列
-- ============================================================

SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
FROM TABLE(GENERATOR(ROWCOUNT => 10))
ORDER BY d;

-- 动态范围
WITH params AS (
    SELECT MIN(sale_date) AS min_d, MAX(sale_date) AS max_d,
           DATEDIFF('DAY', MIN(sale_date), MAX(sale_date)) + 1 AS days
    FROM daily_sales
)
SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, p.min_d) AS d
FROM TABLE(GENERATOR(ROWCOUNT => 10000)) g, params p
QUALIFY ROW_NUMBER() OVER (ORDER BY 1) <= p.days;

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10))
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 3. COALESCE 填零 + 累计和
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10))
)
SELECT ds2.d, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY ds2.d) AS running_total
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;

-- ============================================================
-- 4. 用最近已知值填充（Snowflake 支持 IGNORE NULLS）
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10))
)
SELECT ds2.d AS date,
       LAST_VALUE(ds.amount IGNORE NULLS)
           OVER (ORDER BY ds2.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS filled_amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;

-- ============================================================
-- 5-6. 多维度
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 4))
),
cats AS (SELECT DISTINCT category FROM category_sales)
SELECT ds.d, c.category, COALESCE(cs.amount, 0) AS amount
FROM date_series ds CROSS JOIN cats c
LEFT JOIN category_sales cs ON cs.sale_date = ds.d AND cs.category = c.category
ORDER BY c.category, ds.d;

-- 注意：Snowflake 使用 GENERATOR + ROW_NUMBER 生成序列
-- 注意：Snowflake 支持 IGNORE NULLS
-- 注意：QUALIFY 子句可以过滤生成的序列
-- 注意：DATEDIFF 和 DATEADD 用于日期计算
