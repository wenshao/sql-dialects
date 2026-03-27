-- Hologres: 日期函数
-- Hologres 兼容 PostgreSQL 日期函数
--
-- 参考资料:
--   [1] Hologres - Date/Time Functions
--       https://help.aliyun.com/zh/hologres/user-guide/date-time-functions
--   [2] Hologres Built-in Functions
--       https://help.aliyun.com/zh/hologres/user-guide/built-in-functions

-- 当前日期时间
SELECT NOW();                                            -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                               -- TIMESTAMPTZ
SELECT CURRENT_DATE;                                    -- DATE
SELECT CURRENT_TIME;                                    -- TIME WITH TIME ZONE

-- 构造
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT CAST('2024-01-15' AS DATE);
SELECT '2024-01-15'::DATE;                               -- :: 转换语法

-- 日期加减
SELECT DATE '2024-01-15' + INTERVAL '7 days';
SELECT DATE '2024-01-15' + INTERVAL '3 months';
SELECT DATE '2024-01-15' + 7;                            -- 加天数
SELECT NOW() - INTERVAL '2 hours';
SELECT NOW() + INTERVAL '30 minutes';

-- 日期差
SELECT DATE '2024-12-31' - DATE '2024-01-01';            -- 365（整数天数）
SELECT NOW() - TIMESTAMP '2024-01-01 00:00:00';          -- INTERVAL

-- 提取
SELECT EXTRACT(YEAR FROM NOW());                         -- 2024
SELECT EXTRACT(MONTH FROM NOW());                        -- 1
SELECT EXTRACT(DAY FROM NOW());                          -- 15
SELECT EXTRACT(HOUR FROM NOW());                         -- 10
SELECT EXTRACT(DOW FROM NOW());                          -- 0=周日
SELECT EXTRACT(DOY FROM NOW());                          -- 一年中第几天
SELECT EXTRACT(EPOCH FROM NOW());                        -- Unix 时间戳
SELECT EXTRACT(WEEK FROM NOW());                         -- ISO 周数
SELECT DATE_PART('year', NOW());                         -- 同 EXTRACT

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');

-- 截断
SELECT DATE_TRUNC('month', NOW());                       -- 月初
SELECT DATE_TRUNC('year', NOW());                        -- 年初
SELECT DATE_TRUNC('hour', NOW());                        -- 整点
SELECT DATE_TRUNC('day', NOW());                         -- 当天零点

-- 时区转换
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';

-- 注意：与 PostgreSQL 日期函数基本一致
-- 注意：不支持 AGE 函数
-- 注意：不支持 MAKE_DATE / MAKE_TIMESTAMP 等构造函数
-- 注意：不支持 generate_series 生成日期序列
-- 注意：不支持 CLOCK_TIMESTAMP
-- 注意：EXTRACT(DOW ...) 返回 0=周日（PostgreSQL 兼容）
