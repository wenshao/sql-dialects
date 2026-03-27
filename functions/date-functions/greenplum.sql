-- Greenplum: 日期函数
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- 当前日期时间
SELECT NOW();                                -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                    -- TIMESTAMPTZ
SELECT CURRENT_DATE;                         -- DATE
SELECT CURRENT_TIME;                         -- TIMETZ
SELECT LOCALTIME;                            -- TIME
SELECT LOCALTIMESTAMP;                       -- TIMESTAMP
SELECT clock_timestamp();                    -- 实际执行时间

-- 构造日期
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai');
SELECT TO_TIMESTAMP('2024-01-15', 'YYYY-MM-DD');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');

-- 日期加减
SELECT DATE '2024-01-15' + INTERVAL '7 days';
SELECT DATE '2024-01-15' + 7;                -- 加 7 天
SELECT DATE '2024-01-15' - INTERVAL '1 month';
SELECT NOW() + INTERVAL '2 hours';
SELECT NOW() - INTERVAL '30 minutes';

-- 日期差
SELECT DATE '2024-12-31' - DATE '2024-01-01';       -- 365（整数）
SELECT AGE(DATE '2024-12-31', DATE '2024-01-01');    -- INTERVAL 格式
SELECT AGE(TIMESTAMP '2024-12-31');                  -- 从今天算

-- 提取
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DAY FROM NOW());
SELECT EXTRACT(HOUR FROM NOW());
SELECT EXTRACT(DOW FROM NOW());              -- 0=周日
SELECT EXTRACT(DOY FROM NOW());              -- 年内第几天
SELECT EXTRACT(WEEK FROM NOW());
SELECT EXTRACT(QUARTER FROM NOW());
SELECT EXTRACT(EPOCH FROM NOW());            -- Unix 时间戳
SELECT DATE_PART('year', NOW());             -- 等同于 EXTRACT

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');
SELECT TO_CHAR(NOW(), 'IYYY-IW');            -- ISO 年-周

-- 截断
SELECT DATE_TRUNC('year', NOW());
SELECT DATE_TRUNC('quarter', NOW());
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('week', NOW());
SELECT DATE_TRUNC('day', NOW());
SELECT DATE_TRUNC('hour', NOW());

-- 时区
SELECT NOW() AT TIME ZONE 'UTC';
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT TIMEZONE('UTC', NOW());

-- 区间运算
SELECT INTERVAL '1 year 3 months' + INTERVAL '2 days';
SELECT JUSTIFY_DAYS(INTERVAL '35 days');      -- 1 mon 5 days
SELECT JUSTIFY_HOURS(INTERVAL '27 hours');    -- 1 day 03:00:00
SELECT JUSTIFY_INTERVAL(INTERVAL '1 month -1 hour');

-- 生成日期序列
SELECT generate_series(
    DATE '2024-01-01',
    DATE '2024-01-31',
    INTERVAL '1 day'
);

-- 判断是否闰年（通过计算）
SELECT EXTRACT(DAY FROM (DATE_TRUNC('year', DATE '2024-01-01')
    + INTERVAL '2 months' - INTERVAL '1 day')) = 29 AS is_leap;

-- 注意：Greenplum 兼容 PostgreSQL 日期函数
-- 注意：EXTRACT 和 DATE_PART 功能相同
-- 注意：generate_series 可以生成日期/时间序列
-- 注意：AGE 函数返回 INTERVAL 类型
