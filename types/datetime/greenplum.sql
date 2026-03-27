-- Greenplum: 日期时间类型
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- DATE: 日期，4713 BC ~ 5874897 AD
-- TIME: 时间（不含日期），精度到微秒
-- TIME WITH TIME ZONE / TIMETZ: 带时区的时间
-- TIMESTAMP: 日期时间，精度到微秒
-- TIMESTAMP WITH TIME ZONE / TIMESTAMPTZ: 带时区的日期时间
-- INTERVAL: 时间间隔

CREATE TABLE events (
    id         BIGSERIAL,
    event_date DATE,
    event_time TIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_tz TIMESTAMPTZ DEFAULT NOW(),
    duration   INTERVAL
)
DISTRIBUTED BY (id);

-- 获取当前时间
SELECT CURRENT_DATE;                      -- DATE
SELECT CURRENT_TIME;                      -- TIMETZ
SELECT CURRENT_TIMESTAMP;                 -- TIMESTAMPTZ
SELECT NOW();                             -- TIMESTAMPTZ
SELECT LOCALTIME;                         -- TIME
SELECT LOCALTIMESTAMP;                    -- TIMESTAMP
SELECT clock_timestamp();                 -- 实际执行时间

-- 构造日期时间
SELECT DATE '2024-01-15';
SELECT TIMESTAMP '2024-01-15 10:30:00';
SELECT TIMESTAMPTZ '2024-01-15 10:30:00+08:00';
SELECT INTERVAL '3 days 4 hours';
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT TO_TIMESTAMP('2024-01-15', 'YYYY-MM-DD');

-- 日期加减
SELECT '2024-01-15'::DATE + INTERVAL '7 days';
SELECT '2024-01-15'::DATE + 7;            -- 加 7 天
SELECT '2024-01-15'::DATE - INTERVAL '1 month';
SELECT NOW() + INTERVAL '2 hours';

-- 日期差
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;   -- 365 天（整数）
SELECT AGE('2024-12-31', '2024-01-01');            -- INTERVAL 格式

-- 提取
SELECT EXTRACT(YEAR FROM TIMESTAMP '2024-01-15 10:30:00');
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DOW FROM DATE '2024-01-15');         -- 0=周日
SELECT EXTRACT(EPOCH FROM NOW());                   -- Unix 时间戳
SELECT DATE_PART('hour', NOW());                    -- 等同于 EXTRACT

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');

-- 截断
SELECT DATE_TRUNC('month', NOW());        -- 月初
SELECT DATE_TRUNC('year', NOW());         -- 年初
SELECT DATE_TRUNC('hour', NOW());         -- 整点

-- 时区
SET timezone = 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';
SELECT NOW() AT TIME ZONE 'America/New_York';

-- 注意：Greenplum 兼容 PostgreSQL 日期时间类型
-- 注意：TIMESTAMPTZ 推荐用于存储时间（自动处理时区）
-- 注意：INTERVAL 支持丰富的时间运算
-- 注意：EXTRACT 和 DATE_PART 功能相同
