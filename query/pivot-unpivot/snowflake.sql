-- Snowflake: PIVOT / UNPIVOT（原生支持）
--
-- 参考资料:
--   [1] Snowflake Documentation - PIVOT
--       https://docs.snowflake.com/en/sql-reference/constructs/pivot
--   [2] Snowflake Documentation - UNPIVOT
--       https://docs.snowflake.com/en/sql-reference/constructs/unpivot
--   [3] Snowflake Documentation - Dynamic PIVOT
--       https://docs.snowflake.com/en/sql-reference/constructs/pivot#dynamic-pivot

-- ============================================================
-- PIVOT: 原生语法
-- ============================================================
-- 基本 PIVOT
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
) AS pvt;

-- 指定列别名
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
) AS pvt (product, Q1, Q2, Q3, Q4);

-- 不同聚合函数
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    AVG(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
) AS pvt;

-- ============================================================
-- PIVOT: 动态 PIVOT（Snowflake 独有特性）
-- ============================================================
-- 使用 ANY 关键字自动检测所有不同值（无需列举）
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN (ANY ORDER BY quarter)
) AS pvt;

-- 使用子查询指定 IN 值
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN (SELECT DISTINCT quarter FROM sales ORDER BY quarter)
) AS pvt;

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

-- IFF 函数（Snowflake 版 IF）
SELECT
    product,
    SUM(IFF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IFF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IFF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IFF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: 原生语法
-- ============================================================
-- 基本 UNPIVOT
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- 自定义列值名称
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1 AS 'First Quarter', Q2 AS 'Second Quarter',
                           Q3 AS 'Third Quarter', Q4 AS 'Fourth Quarter')
);

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

-- FLATTEN 方法（Snowflake 特有，适用于半结构化数据）
SELECT
    s.product,
    f.value:quarter::VARCHAR AS quarter,
    f.value:amount::NUMBER AS amount
FROM quarterly_sales s,
    LATERAL FLATTEN(input => ARRAY_CONSTRUCT(
        OBJECT_CONSTRUCT('quarter', 'Q1', 'amount', s.Q1),
        OBJECT_CONSTRUCT('quarter', 'Q2', 'amount', s.Q2),
        OBJECT_CONSTRUCT('quarter', 'Q3', 'amount', s.Q3),
        OBJECT_CONSTRUCT('quarter', 'Q4', 'amount', s.Q4)
    )) f;

-- ============================================================
-- 注意事项
-- ============================================================
-- Snowflake 原生支持 PIVOT 和 UNPIVOT
-- 动态 PIVOT（ANY / 子查询）是 Snowflake 独有特性，非常强大
-- UNPIVOT 默认排除 NULL 值行
-- FLATTEN 可用于半结构化数据的 UNPIVOT
-- PIVOT 只支持单个聚合函数（不同于 Oracle）
