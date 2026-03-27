-- Redshift: 日期函数
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- 当前日期时间
SELECT GETDATE();                                    -- TIMESTAMP（事务时间）
SELECT SYSDATE;                                      -- TIMESTAMP（执行时间）
SELECT CURRENT_DATE;                                 -- DATE
SELECT CURRENT_TIMESTAMP;                            -- TIMESTAMPTZ
SELECT TIMEOFDAY();                                  -- 字符串时间

-- 构造日期
SELECT DATE '2024-01-15';
SELECT '2024-01-15'::DATE;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 日期加减
SELECT DATEADD(DAY, 7, '2024-01-15'::DATE);
SELECT DATEADD(MONTH, 3, GETDATE());
SELECT DATEADD(YEAR, 1, GETDATE());
SELECT DATEADD(HOUR, 2, GETDATE());
SELECT ADD_MONTHS('2024-01-15'::DATE, 3);
SELECT GETDATE() + INTERVAL '7 days';

-- 日期差
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');    -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');  -- 11
SELECT DATEDIFF(YEAR, '2024-01-01', '2025-12-31');   -- 1
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');   -- 11.97

-- 提取
SELECT EXTRACT(YEAR FROM GETDATE());
SELECT EXTRACT(MONTH FROM GETDATE());
SELECT EXTRACT(DAY FROM GETDATE());
SELECT EXTRACT(HOUR FROM GETDATE());
SELECT EXTRACT(DOW FROM GETDATE());                  -- 0=周日
SELECT EXTRACT(DOY FROM GETDATE());
SELECT EXTRACT(WEEK FROM GETDATE());
SELECT EXTRACT(EPOCH FROM GETDATE());
SELECT DATE_PART('year', GETDATE());                 -- 同 EXTRACT
SELECT DATE_PART_YEAR(GETDATE());                    -- 快捷方式

-- 格式化
SELECT TO_CHAR(GETDATE(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(GETDATE(), 'Day, Month DD, YYYY');
SELECT TO_CHAR(GETDATE(), 'HH12:MI AM');

-- 截断
SELECT DATE_TRUNC('month', GETDATE());               -- 月初
SELECT DATE_TRUNC('year', GETDATE());                -- 年初
SELECT DATE_TRUNC('hour', GETDATE());                -- 整点
SELECT DATE_TRUNC('week', GETDATE());                -- 周一
SELECT TRUNC(GETDATE());                             -- 去掉时间部分

-- 时区转换
SELECT CONVERT_TIMEZONE('UTC', 'Asia/Shanghai', GETDATE());
SELECT CONVERT_TIMEZONE('US/Eastern', GETDATE());

-- 月末
SELECT LAST_DAY('2024-01-15'::DATE);                 -- 2024-01-31

-- 下一个星期几
SELECT NEXT_DAY('2024-01-15'::DATE, 'Monday');

-- 日期比较
SELECT GETDATE() > '2024-01-01'::TIMESTAMP;          -- true/false

-- 日期序列生成（使用递归 CTE）
WITH RECURSIVE dates AS (
    SELECT '2024-01-01'::DATE AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < '2024-01-31'
)
SELECT d FROM dates;

-- 注意：GETDATE() 返回事务开始时间，SYSDATE 返回实际执行时间
-- 注意：DATEDIFF 只计算跨越边界的次数，不是完整间隔
-- 注意：CONVERT_TIMEZONE 需要 TIMESTAMPTZ 输入才能正确转换
-- 注意：没有 generate_series（用递归 CTE 替代）
-- 注意：时区名称使用 IANA 数据库
