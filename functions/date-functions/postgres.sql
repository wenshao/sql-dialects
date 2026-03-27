-- PostgreSQL: 日期函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Date/Time Functions
--       https://www.postgresql.org/docs/current/functions-datetime.html
--   [2] PostgreSQL Documentation - generate_series
--       https://www.postgresql.org/docs/current/functions-srf.html

-- ============================================================
-- 1. 当前日期时间
-- ============================================================

SELECT NOW();                           -- TIMESTAMPTZ（事务开始时间）
SELECT CURRENT_TIMESTAMP;               -- 同 NOW()（SQL 标准）
SELECT CLOCK_TIMESTAMP();               -- 真实执行时间（每次调用不同）
SELECT CURRENT_DATE;                    -- DATE
SELECT LOCALTIME;                       -- TIME（无时区）
SELECT LOCALTIMESTAMP;                  -- TIMESTAMP（无时区）

-- 设计分析: NOW() vs CLOCK_TIMESTAMP()
--   NOW() 返回事务开始时间——同一事务中多次调用结果相同。
--   CLOCK_TIMESTAMP() 返回真实的当前时间——每次调用结果不同。
--   STATEMENT_TIMESTAMP() 返回当前语句开始时间。
--   设计原因: 事务内时间一致性保证（如审计日志的时间戳应一致）。
--   MySQL 的 NOW() 在同一语句中返回同一值，但不同语句中不同（语句级）。

-- ============================================================
-- 2. 日期构造
-- ============================================================

SELECT MAKE_DATE(2024, 1, 15);                              -- DATE
SELECT MAKE_TIME(10, 30, 0);                                -- TIME
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);              -- TIMESTAMP
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai'); -- TIMESTAMPTZ
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- ============================================================
-- 3. INTERVAL 类型: PostgreSQL 的日期运算核心
-- ============================================================

-- PostgreSQL 的日期运算基于 INTERVAL 类型（16字节存储）
SELECT '2024-01-15'::DATE + INTERVAL '1 day';
SELECT '2024-01-15'::DATE + INTERVAL '3 months';
SELECT '2024-01-15'::DATE + 7;                -- 直接加天数（DATE + INT）
SELECT NOW() - INTERVAL '2 hours 30 minutes';
SELECT INTERVAL '1 year 2 months 3 days 4 hours';

-- 日期差
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;  -- 365（返回 INTEGER 天数）
SELECT AGE('2024-12-31', '2024-01-01');            -- INTERVAL '11 mons 30 days'
SELECT AGE(CURRENT_DATE);                          -- 距今的 INTERVAL

-- INTERVAL 的设计特点:
--   (a) INTERVAL 内部分三部分存储: months, days, microseconds
--       不自动换算（1 month ≠ 30 days，因为月份天数不同）
--   (b) DATE - DATE 返回整数天数（不是 INTERVAL）
--   (c) TIMESTAMP - TIMESTAMP 返回 INTERVAL
--
-- 对比:
--   MySQL:      DATE_ADD(d, INTERVAL 1 DAY), DATEDIFF(a, b) 返回天数
--   Oracle:     d + 1（加天数），INTERVAL '1' DAY（ANSI 语法）
--   SQL Server: DATEADD(day, 1, d), DATEDIFF(day, a, b)

-- ============================================================
-- 4. 日期提取
-- ============================================================

SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DOW FROM NOW());            -- 0=周日（ISO: ISODOW 1=周一）
SELECT EXTRACT(DOY FROM NOW());            -- 一年中的第几天
SELECT EXTRACT(EPOCH FROM NOW());          -- Unix 时间戳（秒，含小数）
SELECT EXTRACT(WEEK FROM NOW());           -- ISO 周数
SELECT DATE_PART('year', NOW());           -- 同 EXTRACT（旧语法）

-- 14+: EXTRACT 返回 NUMERIC（之前返回 FLOAT8，可能有精度问题）

-- ============================================================
-- 5. 日期截断与格式化
-- ============================================================

SELECT DATE_TRUNC('month', NOW());        -- 截断到月初
SELECT DATE_TRUNC('year', NOW());         -- 截断到年初
SELECT DATE_TRUNC('hour', NOW());         -- 截断到整点
SELECT DATE_TRUNC('week', NOW());         -- 截断到周一（ISO）

SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');
SELECT TO_CHAR(NOW(), 'HH12:MI AM');

-- ============================================================
-- 6. 时区转换: AT TIME ZONE
-- ============================================================

SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';

-- AT TIME ZONE 的语义取决于输入类型:
--   TIMESTAMPTZ AT TIME ZONE 'X' → TIMESTAMP（从 UTC 转为 X 时区的本地时间）
--   TIMESTAMP AT TIME ZONE 'X'   → TIMESTAMPTZ（假设输入是 X 时区，转为 UTC）
-- 这个语义经常让人困惑，但逻辑上是自洽的。

-- ============================================================
-- 7. generate_series: PostgreSQL 的日期序列生成器
-- ============================================================

-- 生成日期范围（generate_series 是 PostgreSQL 最强大的内置函数之一）
SELECT d::DATE FROM generate_series(
    '2024-01-01'::DATE, '2024-12-31'::DATE, INTERVAL '1 month'
) AS t(d);

-- 生成小时序列
SELECT d FROM generate_series(
    '2024-01-01 00:00'::TIMESTAMP, '2024-01-01 23:00'::TIMESTAMP, INTERVAL '1 hour'
) AS t(d);

-- 典型场景: 填充缺失日期（LEFT JOIN 完整日期序列）
SELECT d::DATE, COALESCE(s.amount, 0)
FROM generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day') AS t(d)
LEFT JOIN daily_sales s ON s.sale_date = t.d::DATE;

-- 对比:
--   MySQL:      无等价函数（需要递归 CTE 或辅助数字表）
--   Oracle:     CONNECT BY LEVEL（递归层级查询生成序列）
--   SQL Server: 递归 CTE 或 master.dbo.spt_values
--   BigQuery:   GENERATE_DATE_ARRAY(), UNNEST()

-- ============================================================
-- 8. 横向对比: 日期函数差异
-- ============================================================

-- 1. 日期加减:
--   PostgreSQL: d + INTERVAL '1 day'（最直观）
--   MySQL:      DATE_ADD(d, INTERVAL 1 DAY)
--   Oracle:     d + 1（加天数），d + INTERVAL '1' DAY
--   SQL Server: DATEADD(day, 1, d)
--
-- 2. 日期差:
--   PostgreSQL: DATE1 - DATE2 → INTEGER 天数
--   MySQL:      DATEDIFF(d1, d2) → INTEGER 天数
--   Oracle:     DATE1 - DATE2 → NUMBER 天数（含小数）
--   SQL Server: DATEDIFF(day, d1, d2)
--
-- 3. 格式化:
--   PostgreSQL: TO_CHAR(d, 'YYYY-MM-DD')（Oracle 兼容）
--   MySQL:      DATE_FORMAT(d, '%Y-%m-%d')（C 风格格式符）
--   SQL Server: FORMAT(d, 'yyyy-MM-dd')（.NET 风格）

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- (1) INTERVAL 三部分存储（months, days, microseconds）是正确设计:
--     "1 month" 不等于 "30 days"（2月只有28/29天）。
--     将 months 独立存储避免了精度损失。
--
-- (2) generate_series 是 set-returning function (SRF) 的典范:
--     在 FROM 子句中调用的函数可以返回多行。
--     这种设计让日期填充、数值序列等场景无需递归 CTE。
--
-- (3) 事务时间 vs 实际时间的区分:
--     NOW() = 事务时间，CLOCK_TIMESTAMP() = 实际时间。
--     这种区分对审计日志至关重要。

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- PostgreSQL 8.4:  MAKE_DATE, MAKE_TIME, MAKE_TIMESTAMP
-- PostgreSQL 9.4:  MAKE_TIMESTAMPTZ
-- PostgreSQL 12:   DATE_TRUNC 支持 AT TIME ZONE
-- PostgreSQL 14:   EXTRACT 返回 NUMERIC（不再是 FLOAT8）
-- PostgreSQL 16:   generate_series 对 DATE 类型的改进
