-- PostgreSQL: 日期函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Date/Time Functions
--       https://www.postgresql.org/docs/current/functions-datetime.html
--   [2] PostgreSQL Documentation - Date/Time Types
--       https://www.postgresql.org/docs/current/datatype-datetime.html

-- 当前日期时间
SELECT NOW();                                    -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                        -- TIMESTAMPTZ（事务开始时间）
SELECT CLOCK_TIMESTAMP();                        -- 实际执行时间
SELECT CURRENT_DATE;                             -- DATE
SELECT CURRENT_TIME;                             -- TIME WITH TIME ZONE
SELECT LOCALTIME;                                -- TIME（无时区）
SELECT LOCALTIMESTAMP;                           -- TIMESTAMP（无时区）

-- 构造日期
SELECT MAKE_DATE(2024, 1, 15);                   -- 2024-01-15
SELECT MAKE_TIME(10, 30, 0);                     -- 10:30:00
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);   -- 2024-01-15 10:30:00
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 日期加减（直接用 INTERVAL，非常灵活）
SELECT '2024-01-15'::DATE + INTERVAL '1 day';
SELECT '2024-01-15'::DATE + INTERVAL '3 months';
SELECT '2024-01-15'::DATE + 7;                   -- 直接加天数
SELECT NOW() - INTERVAL '2 hours 30 minutes';

-- 日期差
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;  -- 365（天数整数）
SELECT AGE('2024-12-31', '2024-01-01');           -- 11 mons 30 days
SELECT AGE(CURRENT_DATE);                         -- 距今的 INTERVAL

-- 提取
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DAY FROM NOW());
SELECT EXTRACT(HOUR FROM NOW());
SELECT EXTRACT(DOW FROM NOW());                   -- 0=周日
SELECT EXTRACT(DOY FROM NOW());                   -- 一年中的第几天
SELECT EXTRACT(EPOCH FROM NOW());                 -- Unix 时间戳
SELECT EXTRACT(WEEK FROM NOW());                  -- ISO 周数
SELECT DATE_PART('year', NOW());                  -- 同 EXTRACT

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');
SELECT TO_CHAR(NOW(), 'HH12:MI AM');

-- 截断
SELECT DATE_TRUNC('month', NOW());                -- 月初
SELECT DATE_TRUNC('year', NOW());                 -- 年初
SELECT DATE_TRUNC('hour', NOW());                 -- 整点

-- 时区转换
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';

-- 生成日期序列
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);
SELECT generate_series('2024-01-01'::DATE, '2024-12-31'::DATE, '1 month'::INTERVAL);

-- 14+: EXTRACT 从 INTERVAL 提取的行为更精确
