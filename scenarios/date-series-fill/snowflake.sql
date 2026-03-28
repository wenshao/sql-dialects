-- Snowflake: 日期序列生成与间隙填充
--
-- 参考资料:
--   [1] Snowflake Documentation - GENERATOR
--       https://docs.snowflake.com/en/sql-reference/functions/generator

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY TABLE daily_sales (sale_date DATE, amount NUMBER(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

-- ============================================================
-- 1. GENERATOR 生成日期序列
-- ============================================================

-- 固定范围
SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
FROM TABLE(GENERATOR(ROWCOUNT => 10));

-- 动态范围（QUALIFY 裁剪多余行）
WITH params AS (
    SELECT MIN(sale_date) AS min_d, MAX(sale_date) AS max_d,
           DATEDIFF('DAY', MIN(sale_date), MAX(sale_date)) + 1 AS days
    FROM daily_sales
)
SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, p.min_d) AS d
FROM TABLE(GENERATOR(ROWCOUNT => 10000)) g, params p
QUALIFY ROW_NUMBER() OVER (ORDER BY 1) <= p.days;

-- 对比:
--   PostgreSQL: generate_series('2024-01-01', '2024-01-10', '1 day')（最优雅）
--   BigQuery:   GENERATE_DATE_ARRAY('2024-01-01', '2024-01-10')
--   MySQL:      递归 CTE 或数字表（最繁琐）
--   Snowflake:  GENERATOR + DATEADD + QUALIFY（独特但不够直观）

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10))
)
SELECT ds.d AS date, COALESCE(s.amount, 0) AS amount
FROM date_series ds
LEFT JOIN daily_sales s ON s.sale_date = ds.d
ORDER BY ds.d;

-- ============================================================
-- 3. 填零 + 累计和
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10))
)
SELECT ds.d, COALESCE(s.amount, 0) AS amount,
       SUM(COALESCE(s.amount, 0)) OVER (ORDER BY ds.d) AS running_total
FROM date_series ds
LEFT JOIN daily_sales s ON s.sale_date = ds.d ORDER BY ds.d;

-- ============================================================
-- 4. 用最近已知值填充 (LAST_VALUE IGNORE NULLS)
-- ============================================================

WITH date_series AS (
    SELECT DATEADD('DAY', ROW_NUMBER() OVER (ORDER BY 1) - 1, '2024-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 10))
)
SELECT ds.d AS date,
       LAST_VALUE(s.amount IGNORE NULLS)
           OVER (ORDER BY ds.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS filled_amount
FROM date_series ds
LEFT JOIN daily_sales s ON s.sale_date = ds.d ORDER BY ds.d;

-- IGNORE NULLS: Snowflake 支持，对比:
--   PostgreSQL: 不支持 IGNORE NULLS（需要自连接或子查询变通）
--   BigQuery:   支持 IGNORE NULLS
--   Oracle:     支持 IGNORE NULLS

-- ============================================================
-- 5. 多维度填充
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

-- ============================================================
-- 横向对比: 日期序列生成
-- ============================================================
-- 引擎       | 序列生成方式              | IGNORE NULLS
-- Snowflake  | GENERATOR+DATEADD+QUALIFY | 支持
-- PostgreSQL | generate_series           | 不支持
-- BigQuery   | GENERATE_DATE_ARRAY       | 支持
-- MySQL      | 递归CTE                   | 不支持
