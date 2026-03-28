-- Snowflake: 日期与时间函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Date & Time Functions
--       https://docs.snowflake.com/en/sql-reference/functions-date-time

-- ============================================================
-- 1. 当前日期时间
-- ============================================================

SELECT CURRENT_DATE();           -- DATE
SELECT CURRENT_TIME();           -- TIME
SELECT CURRENT_TIMESTAMP();      -- TIMESTAMP_LTZ（默认）
SELECT SYSDATE();                -- 真实当前时间（非事务时间）
SELECT LOCALTIMESTAMP();         -- TIMESTAMP_NTZ
SELECT GETDATE();                -- TIMESTAMP_LTZ（SQL Server 兼容别名）

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 三种 TIMESTAMP 类型的影响
-- 每个日期时间函数的返回类型取决于 TIMESTAMP_TYPE_MAPPING 参数:
--   CURRENT_TIMESTAMP() → TIMESTAMP_LTZ（始终带本地时区）
--   LOCALTIMESTAMP()    → TIMESTAMP_NTZ（始终不带时区）
--   SYSDATE()           → 与 CURRENT_TIMESTAMP 不同: 返回语句执行时的真实时间
--
-- CURRENT_TIMESTAMP vs SYSDATE 的区别:
--   事务内: CURRENT_TIMESTAMP 返回事务开始时间（不变）
--   事务内: SYSDATE 返回每次调用的真实时间（可能不同）
-- 对比 Oracle: SYSDATE vs SYSTIMESTAMP 有类似区别

-- 2.2 DATEADD / DATEDIFF: Snowflake 的标准日期运算
SELECT DATEADD(DAY, 7, '2024-01-15'::DATE);
SELECT DATEADD(MONTH, 3, CURRENT_DATE());
SELECT DATEADD(HOUR, 2, CURRENT_TIMESTAMP());

SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');  -- 11
SELECT DATEDIFF(YEAR, '2024-01-01', '2025-06-01');   -- 1

-- 对比:
--   PostgreSQL: date + interval '7 days'（运算符方式，最优雅）
--               不需要 DATEADD 函数
--   MySQL:      DATE_ADD(date, INTERVAL 7 DAY) 或 date + INTERVAL 7 DAY
--   Oracle:     date + 7（天为单位的数字运算） + ADD_MONTHS
--   SQL Server: DATEADD(day, 7, date)（与 Snowflake 语法一致）
--   BigQuery:   DATE_ADD(date, INTERVAL 7 DAY)
--
-- 对引擎开发者的启示:
--   DATEADD(unit, amount, date) vs date + INTERVAL 是两种流派。
--   函数式（DATEADD）对优化器更友好（参数类型确定）。
--   运算符式（+ INTERVAL）对用户更自然（PostgreSQL 的选择）。

-- ============================================================
-- 3. 构造函数
-- ============================================================

SELECT DATE_FROM_PARTS(2024, 1, 15);
SELECT TIME_FROM_PARTS(10, 30, 0);
SELECT TIMESTAMP_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_NTZ_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_LTZ_FROM_PARTS(2024, 1, 15, 10, 30, 0);
SELECT TIMESTAMP_TZ_FROM_PARTS(2024, 1, 15, 10, 30, 0, 0, 'Asia/Shanghai');

SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TRY_TO_DATE('invalid');            -- 安全解析，返回 NULL

-- ============================================================
-- 4. 提取函数
-- ============================================================

SELECT EXTRACT(YEAR FROM CURRENT_DATE());
-- Snowflake 提供大量便捷提取函数:
SELECT YEAR(CURRENT_DATE());
SELECT MONTH(CURRENT_DATE());
SELECT DAY(CURRENT_DATE());
SELECT HOUR(CURRENT_TIMESTAMP());
SELECT MINUTE(CURRENT_TIMESTAMP());
SELECT SECOND(CURRENT_TIMESTAMP());
SELECT DAYOFWEEK(CURRENT_DATE());     -- 0=周日（受 WEEK_START 参数影响）
SELECT DAYOFWEEKISO(CURRENT_DATE());  -- 1=周一（ISO 标准）
SELECT DAYOFYEAR(CURRENT_DATE());
SELECT WEEKOFYEAR(CURRENT_DATE());
SELECT WEEKISO(CURRENT_DATE());       -- ISO 周数
SELECT QUARTER(CURRENT_DATE());

-- 对比: PostgreSQL 只有 EXTRACT / DATE_PART
-- Snowflake 的 YEAR()/MONTH()/DAY() 等是便捷语法糖（与 SQL Server 类似）

-- ============================================================
-- 5. 截断与取整
-- ============================================================

SELECT DATE_TRUNC('MONTH', CURRENT_TIMESTAMP());
SELECT DATE_TRUNC('YEAR', CURRENT_DATE());
SELECT DATE_TRUNC('HOUR', CURRENT_TIMESTAMP());
SELECT DATE_TRUNC('WEEK', CURRENT_DATE());

-- LAST_DAY
SELECT LAST_DAY(CURRENT_DATE());             -- 月最后一天
SELECT LAST_DAY(CURRENT_DATE(), 'YEAR');     -- 年最后一天
SELECT LAST_DAY(CURRENT_DATE(), 'QUARTER'); -- 季最后一天

-- ============================================================
-- 6. 格式化
-- ============================================================

SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(CURRENT_DATE(), 'YYYY/MM/DD');
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'DY, MON DD, YYYY');

-- 格式符使用 Oracle 风格（不是 PostgreSQL/C 的 strftime 风格）:
--   YYYY=年, MM=月, DD=日, HH24=24小时制, MI=分, SS=秒
--   DY=缩写星期, MON=缩写月份, DAY=完整星期名

-- ============================================================
-- 7. 时区转换
-- ============================================================

SELECT CONVERT_TIMEZONE('UTC', 'Asia/Shanghai', CURRENT_TIMESTAMP());
SELECT CONVERT_TIMEZONE('Asia/Shanghai', CURRENT_TIMESTAMP());

-- 对比:
--   PostgreSQL: AT TIME ZONE 'Asia/Shanghai'（SQL 标准语法）
--   MySQL:      CONVERT_TZ(ts, from_tz, to_tz)
--   Oracle:     FROM_TZ + AT TIME ZONE

-- ============================================================
-- 8. Unix 时间戳
-- ============================================================

SELECT DATE_PART(EPOCH_SECOND, CURRENT_TIMESTAMP());
SELECT TO_TIMESTAMP(1705312800);           -- Unix 秒 → TIMESTAMP

-- ============================================================
-- 9. 日期序列生成
-- ============================================================

-- 使用 GENERATOR 表函数生成日期序列:
SELECT DATEADD(DAY, seq4(), '2024-01-01'::DATE) AS dt
FROM TABLE(GENERATOR(ROWCOUNT => 31));

-- 对比:
--   PostgreSQL: generate_series('2024-01-01', '2024-01-31', '1 day')
--   BigQuery:   GENERATE_DATE_ARRAY('2024-01-01', '2024-01-31')
--   MySQL:      无原生日期序列生成（需要递归 CTE 或数字表）
-- Snowflake 的 GENERATOR 需要 DATEADD 包装，不如 PostgreSQL 直观

-- ============================================================
-- 横向对比: 日期函数亮点
-- ============================================================
-- 特性           | Snowflake     | BigQuery      | PostgreSQL    | MySQL
-- 日期加减       | DATEADD       | DATE_ADD      | + INTERVAL    | DATE_ADD
-- 日期差         | DATEDIFF      | DATE_DIFF     | date - date   | DATEDIFF
-- 截断           | DATE_TRUNC    | DATE_TRUNC    | DATE_TRUNC    | 无(需变通)
-- 便捷提取       | YEAR()/MONTH()| EXTRACT only  | EXTRACT only  | YEAR()/MONTH()
-- 时区转换       | CONVERT_TZ    | 不支持(UTC)   | AT TIME ZONE  | CONVERT_TZ
-- 格式化风格     | Oracle 风格   | format_string | to_char       | date_format
-- 日期序列       | GENERATOR     | GENERATE_DATE | generate_series| 递归CTE
-- 安全解析       | TRY_TO_DATE   | SAFE.PARSE_DATE| 无原生       | STR_TO_DATE
