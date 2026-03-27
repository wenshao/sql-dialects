-- Oracle: 日期函数
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Datetime Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html

-- ============================================================
-- 1. 当前日期时间（注意: 所有 SELECT 需要 FROM DUAL）
-- ============================================================

SELECT SYSDATE FROM DUAL;                      -- DATE（数据库服务器时间）
SELECT SYSTIMESTAMP FROM DUAL;                 -- TIMESTAMP WITH TIME ZONE
SELECT CURRENT_DATE FROM DUAL;                 -- DATE（会话时区）
SELECT CURRENT_TIMESTAMP FROM DUAL;            -- TIMESTAMP WITH TZ（会话时区）

-- 设计分析: SYSDATE vs CURRENT_DATE
--   SYSDATE: 总是返回数据库服务器的操作系统时间（不受会话时区影响）
--   CURRENT_DATE: 返回会话时区的时间
--   多时区应用中应使用 CURRENT_TIMESTAMP 而非 SYSTIMESTAMP
--
-- 横向对比:
--   Oracle:     SYSDATE（无括号!）/ SYSTIMESTAMP
--   PostgreSQL: NOW() / CURRENT_TIMESTAMP（事务开始时间）
--               clock_timestamp()（语句执行时间，类似 SYSDATE）
--   MySQL:      NOW() / CURRENT_TIMESTAMP / SYSDATE()（有括号!）
--   SQL Server: GETDATE() / SYSDATETIME()

-- ============================================================
-- 2. 日期构造
-- ============================================================

SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_DATE('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00.123', 'YYYY-MM-DD HH24:MI:SS.FF3') FROM DUAL;
SELECT DATE '2024-01-15' FROM DUAL;            -- ANSI 日期字面量

-- Oracle 独有: NLS_DATE_FORMAT 影响隐式日期转换
-- ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
-- 隐式转换依赖 NLS 设置，是 Oracle 数据库中 Bug 的常见来源

-- ============================================================
-- 3. 日期加减（Oracle 独特的算术语义）
-- ============================================================

-- Oracle DATE 类型可以直接做加减法（单位是天）
SELECT SYSDATE + 1 FROM DUAL;                  -- + 1 天
SELECT SYSDATE + 1/24 FROM DUAL;               -- + 1 小时
SELECT SYSDATE + 1/1440 FROM DUAL;             -- + 1 分钟
SELECT SYSDATE + 1/86400 FROM DUAL;            -- + 1 秒

-- 这是 Oracle 独有的设计: DATE + NUMBER 得到 DATE
-- 数字 1 = 1 天，小数 = 天的分数

-- INTERVAL 语法（SQL 标准）
SELECT SYSDATE + INTERVAL '3' MONTH FROM DUAL;
SELECT SYSDATE + INTERVAL '2' HOUR FROM DUAL;

-- 专用函数
SELECT ADD_MONTHS(SYSDATE, 6) FROM DUAL;       -- + 6 个月

-- 日期差（Oracle DATE 相减直接得到天数!）
SELECT SYSDATE - TO_DATE('2024-01-01', 'YYYY-MM-DD') FROM DUAL;  -- 天数（小数）
SELECT MONTHS_BETWEEN(SYSDATE, TO_DATE('2024-01-01', 'YYYY-MM-DD')) FROM DUAL;

-- 横向对比:
--   Oracle:     date1 - date2 → NUMBER（天数），直接算术
--   PostgreSQL: date1 - date2 → INTERVAL（需要 EXTRACT 得到天数）
--   MySQL:      DATEDIFF(date1, date2) → INTEGER（天数）
--   SQL Server: DATEDIFF(DAY, date1, date2) → INTEGER

-- ============================================================
-- 4. 日期提取
-- ============================================================

SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(DAY FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(HOUR FROM SYSTIMESTAMP) FROM DUAL;

SELECT TO_CHAR(SYSDATE, 'D') FROM DUAL;        -- 星期几（NLS_TERRITORY 依赖!）
SELECT TO_CHAR(SYSDATE, 'DDD') FROM DUAL;      -- 年中第几天
SELECT TO_CHAR(SYSDATE, 'WW') FROM DUAL;       -- 年中第几周

-- ============================================================
-- 5. 格式化
-- ============================================================

SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'Day, Month DD, YYYY') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY"年"MM"月"DD"日"') FROM DUAL;

-- ============================================================
-- 6. TRUNC / ROUND（Oracle 独特的日期截断函数）
-- ============================================================

SELECT TRUNC(SYSDATE) FROM DUAL;               -- 去掉时间部分
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;         -- 月初
SELECT TRUNC(SYSDATE, 'YYYY') FROM DUAL;       -- 年初
SELECT TRUNC(SYSDATE, 'Q') FROM DUAL;          -- 季初
SELECT TRUNC(SYSDATE, 'DAY') FROM DUAL;        -- 本周起始日

SELECT ROUND(SYSDATE) FROM DUAL;               -- 四舍五入到天
SELECT ROUND(SYSDATE, 'MM') FROM DUAL;         -- 四舍五入到月

-- 设计分析:
--   Oracle 的 TRUNC/ROUND 对日期的操作与对数值的操作使用相同的函数名。
--   TRUNC(3.14, 0) → 3  vs  TRUNC(SYSDATE, 'MM') → 月初
--   通过第二个参数的类型（数值 vs 字符串）来区分行为。
--
-- 横向对比:
--   Oracle:     TRUNC(date, 'MM') -- 通用函数，格式字符串
--   PostgreSQL: DATE_TRUNC('month', date) -- 专用函数
--   MySQL:      无 DATE_TRUNC，需要组合: DATE_FORMAT + STR_TO_DATE
--   SQL Server: DATETRUNC(month, date) (2022+)

-- ============================================================
-- 7. 月末 / 下一个星期几
-- ============================================================

SELECT LAST_DAY(SYSDATE) FROM DUAL;            -- 本月最后一天
SELECT NEXT_DAY(SYSDATE, 'MONDAY') FROM DUAL;  -- 下一个周一

-- ============================================================
-- 8. 时区转换
-- ============================================================

SELECT FROM_TZ(CAST(SYSDATE AS TIMESTAMP), 'UTC')
    AT TIME ZONE 'Asia/Shanghai' FROM DUAL;

-- ============================================================
-- 9. 对引擎开发者的总结
-- ============================================================
-- 1. Oracle DATE + NUMBER 的算术语义是独特的（数字 1 = 1 天），简单但易混淆。
-- 2. SYSDATE 无括号是 Oracle 独有的语法（其他数据库的函数都有括号）。
-- 3. NLS_DATE_FORMAT 影响隐式转换，是 Bug 来源，新引擎应避免隐式日期转换。
-- 4. TRUNC 对日期和数值使用同一个函数名是 Oracle 的多态设计，有争议。
-- 5. DUAL 表在日期函数中频繁出现，新引擎应允许无 FROM 的 SELECT。
