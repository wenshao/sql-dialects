-- DuckDB: PIVOT / UNPIVOT（原生支持）
--
-- 参考资料:
--   [1] DuckDB Documentation - PIVOT
--       https://duckdb.org/docs/sql/statements/pivot
--   [2] DuckDB Documentation - UNPIVOT
--       https://duckdb.org/docs/sql/statements/unpivot

-- ============================================================
-- PIVOT: 原生语法
-- ============================================================
-- 基本 PIVOT
PIVOT sales ON quarter USING SUM(amount) GROUP BY product;

-- 等价的 FROM 子句 PIVOT
SELECT * FROM sales
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
)
GROUP BY product;

-- 多聚合
PIVOT sales ON quarter USING SUM(amount) AS total, COUNT(amount) AS cnt GROUP BY product;

-- 动态 PIVOT（自动检测所有唯一值）
PIVOT sales ON quarter USING SUM(amount);

-- 多列 PIVOT
PIVOT sales ON (quarter, region) USING SUM(amount) GROUP BY product;

-- ============================================================
-- PIVOT: CASE WHEN 替代方法
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- FILTER 子句
SELECT
    product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: 原生语法
-- ============================================================
-- 基本 UNPIVOT
UNPIVOT quarterly_sales ON Q1, Q2, Q3, Q4 INTO NAME quarter VALUE amount;

-- 等价的 FROM 子句 UNPIVOT
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- INCLUDE NULLS
UNPIVOT quarterly_sales ON Q1, Q2, Q3, Q4
INTO NAME quarter VALUE amount
INCLUDE NULLS;

-- 动态 UNPIVOT（使用 COLUMNS 表达式）
UNPIVOT quarterly_sales
ON COLUMNS(* EXCLUDE product)
INTO NAME quarter VALUE amount;

-- ============================================================
-- UNPIVOT: UNION ALL 替代方法
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- LATERAL + VALUES
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES
        ('Q1', s.Q1),
        ('Q2', s.Q2),
        ('Q3', s.Q3),
        ('Q4', s.Q4)
) AS v(quarter, amount);

-- ============================================================
-- 从文件直接 PIVOT / UNPIVOT
-- ============================================================
PIVOT read_csv('sales.csv') ON quarter USING SUM(amount) GROUP BY product;

UNPIVOT read_parquet('quarterly_sales.parquet')
ON Q1, Q2, Q3, Q4 INTO NAME quarter VALUE amount;

-- ============================================================
-- 注意事项
-- ============================================================
-- DuckDB 原生支持 PIVOT 和 UNPIVOT，语法独特且强大
-- PIVOT 支持自动检测唯一值（无需列举所有值）
-- UNPIVOT 支持 COLUMNS 表达式做动态列选择
-- 可直接对文件执行 PIVOT/UNPIVOT
-- FILTER 子句比 CASE WHEN 更简洁
-- DuckDB 的 PIVOT/UNPIVOT 是最灵活的实现之一
