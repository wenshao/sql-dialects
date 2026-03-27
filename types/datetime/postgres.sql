-- PostgreSQL: 日期时间类型
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Date/Time Types
--       https://www.postgresql.org/docs/current/datatype-datetime.html
--   [2] PostgreSQL Documentation - Date/Time Functions
--       https://www.postgresql.org/docs/current/functions-datetime.html

-- DATE: 日期，4 字节，4713 BC ~ 5874897 AD
-- TIME: 时间（无时区），8 字节
-- TIME WITH TIME ZONE: 时间（带时区），12 字节
-- TIMESTAMP: 日期时间（无时区），8 字节，4713 BC ~ 294276 AD
-- TIMESTAMP WITH TIME ZONE (TIMESTAMPTZ): 日期时间（带时区），8 字节
-- INTERVAL: 时间间隔，16 字节

CREATE TABLE events (
    id         BIGSERIAL PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),              -- 毫秒精度
    created_at TIMESTAMP(6),         -- 微秒精度（默认就是 6）
    updated_at TIMESTAMPTZ           -- 推荐：自动处理时区
);

-- TIMESTAMP vs TIMESTAMPTZ:
-- TIMESTAMP: 存什么就是什么，不做时区转换
-- TIMESTAMPTZ: 存入时转换为 UTC，读取时转为会话时区
-- 官方推荐总是使用 TIMESTAMPTZ

-- 获取当前时间
SELECT NOW();                          -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;              -- TIMESTAMPTZ
SELECT CURRENT_DATE;                   -- DATE
SELECT CURRENT_TIME;                   -- TIME WITH TIME ZONE
SELECT CLOCK_TIMESTAMP();              -- 真实当前时间（NOW() 在事务内不变）

-- 日期运算（直接用 INTERVAL，非常灵活）
SELECT NOW() + INTERVAL '1 day';
SELECT NOW() - INTERVAL '2 hours 30 minutes';
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;   -- 返回整数天数
SELECT AGE('2024-12-31', '2024-01-01');            -- 返回 INTERVAL

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');

-- 提取部分
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(EPOCH FROM NOW());      -- Unix 时间戳
SELECT DATE_PART('hour', NOW());       -- 同 EXTRACT
SELECT DATE_TRUNC('month', NOW());     -- 截断到月初

-- 时区转换
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT '2024-01-15 10:00:00'::TIMESTAMP AT TIME ZONE 'UTC';
