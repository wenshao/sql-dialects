-- PostgreSQL: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - generate_series
--       https://www.postgresql.org/docs/current/functions-srf.html
--   [2] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/functions-window.html
--   [3] PostgreSQL Documentation - Date/Time Functions
--       https://www.postgresql.org/docs/current/functions-datetime.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    NUMERIC(10,2)
);
INSERT INTO daily_sales (sale_date, amount) VALUES
    ('2024-01-01', 100), ('2024-01-02', 150),
    ('2024-01-04', 200), ('2024-01-05', 120),
    ('2024-01-08', 300), ('2024-01-09', 250),
    ('2024-01-10', 180);

-- ============================================================
-- 1. 使用 generate_series 生成连续日期序列
-- ============================================================

-- 生成日期范围
SELECT d::DATE AS date
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-01-10'::DATE,
    INTERVAL '1 day'
) AS t(d);

-- 按月生成
SELECT d::DATE AS month_start
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-12-01'::DATE,
    INTERVAL '1 month'
) AS t(d);

-- 按小时生成
SELECT d AS hour_ts
FROM generate_series(
    '2024-01-01 00:00:00'::TIMESTAMP,
    '2024-01-01 23:00:00'::TIMESTAMP,
    INTERVAL '1 hour'
) AS t(d);

-- ============================================================
-- 2. LEFT JOIN 填充间隙（缺失日期补零）
-- ============================================================

SELECT
    d::DATE                  AS date,
    COALESCE(ds.amount, 0)   AS amount
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-01-10'::DATE,
    INTERVAL '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- ============================================================
-- 3. COALESCE 填零 + 累计和
-- ============================================================

SELECT
    d::DATE                                AS date,
    COALESCE(ds.amount, 0)                 AS amount,
    SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-01-10'::DATE,
    INTERVAL '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- ============================================================
-- 4. 用最近已知值填充（LAST_VALUE / LAG + IGNORE NULLS 模拟）
-- ============================================================

-- PostgreSQL 不直接支持 IGNORE NULLS，需要模拟
-- 方法：使用 COUNT 窗口函数标记分组，再取每组最后值
WITH filled AS (
    SELECT
        d::DATE AS date,
        ds.amount,
        COUNT(ds.amount) OVER (ORDER BY d) AS grp
    FROM generate_series(
        '2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day'
    ) AS t(d)
    LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
)
SELECT
    date,
    FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled_amount
FROM filled
ORDER BY date;

-- 替代方法：使用子查询
SELECT
    d::DATE AS date,
    COALESCE(
        ds.amount,
        (SELECT ds2.amount FROM daily_sales ds2
         WHERE ds2.sale_date <= t.d::DATE
         ORDER BY ds2.sale_date DESC LIMIT 1)
    ) AS filled_amount
FROM generate_series(
    '2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- ============================================================
-- 5. 动态日期范围（从数据中获取）
-- ============================================================

SELECT
    d::DATE                  AS date,
    COALESCE(ds.amount, 0)   AS amount
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- ============================================================
-- 6. 多维度日期填充（按类别 × 日期交叉）
-- ============================================================

CREATE TABLE category_sales (
    sale_date DATE,
    category  VARCHAR(50),
    amount    NUMERIC(10,2)
);
INSERT INTO category_sales VALUES
    ('2024-01-01','A',100),('2024-01-02','A',150),
    ('2024-01-01','B',200),('2024-01-04','B',120);

SELECT
    d::DATE                  AS date,
    c.category,
    COALESCE(cs.amount, 0)   AS amount
FROM generate_series('2024-01-01'::DATE, '2024-01-04'::DATE, INTERVAL '1 day') AS t(d)
CROSS JOIN (SELECT DISTINCT category FROM category_sales) c
LEFT JOIN category_sales cs ON cs.sale_date = t.d::DATE AND cs.category = c.category
ORDER BY c.category, d;

-- 注意：generate_series 是 PostgreSQL 特有函数
-- 注意：PostgreSQL 不支持 IGNORE NULLS（需要模拟）
-- 注意：generate_series 支持 DATE、TIMESTAMP、INTEGER 等类型
-- 注意：对于大范围日期序列，generate_series 内存消耗可控
