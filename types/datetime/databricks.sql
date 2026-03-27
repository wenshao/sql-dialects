-- Databricks SQL: 日期时间类型
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- DATE: 日期，0001-01-01 ~ 9999-12-31
-- TIMESTAMP: 日期时间（带本地时区信息），微秒精度
-- TIMESTAMP_NTZ: 日期时间（无时区），微秒精度（Databricks 2022+）
-- INTERVAL: 时间间隔

CREATE TABLE events (
    id           BIGINT GENERATED ALWAYS AS IDENTITY,
    event_date   DATE,
    event_ts     TIMESTAMP,                  -- 带会话时区
    event_ts_ntz TIMESTAMP_NTZ              -- 无时区
);

-- TIMESTAMP vs TIMESTAMP_NTZ
-- TIMESTAMP: 存储时转为 UTC，读取时转为会话时区
-- TIMESTAMP_NTZ: 存什么取什么（"wall clock time"）

-- 设置会话时区
SET TIME ZONE 'Asia/Shanghai';
SET TIME ZONE 'UTC';

-- 获取当前时间
SELECT current_date();                       -- DATE
SELECT current_timestamp();                  -- TIMESTAMP
SELECT now();                                -- TIMESTAMP（同 current_timestamp）

-- 构造日期时间
SELECT DATE '2024-01-15';                    -- DATE 字面量
SELECT TIMESTAMP '2024-01-15 10:30:00';      -- TIMESTAMP 字面量
SELECT MAKE_DATE(2024, 1, 15);               -- 构造 DATE
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);  -- 构造 TIMESTAMP
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- 日期加减
SELECT DATE_ADD('2024-01-15', 7);            -- 加 7 天
SELECT DATE_SUB('2024-01-15', 7);            -- 减 7 天
SELECT DATEADD(MONTH, 3, '2024-01-15');      -- 加 3 月
SELECT DATEADD(HOUR, 2, current_timestamp());
SELECT TIMESTAMPADD(MINUTE, 30, current_timestamp());

-- INTERVAL 语法
SELECT current_timestamp() + INTERVAL 7 DAYS;
SELECT current_timestamp() - INTERVAL '3' MONTHS;
SELECT current_date() + INTERVAL 1 YEAR;

-- 日期差
SELECT DATEDIFF(DAY, '2024-01-01', '2024-12-31');      -- 365
SELECT DATEDIFF(MONTH, '2024-01-01', '2024-12-31');    -- 11
SELECT TIMESTAMPDIFF(HOUR, ts1, ts2) FROM events;

-- 提取
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT HOUR(current_timestamp());
SELECT MINUTE(current_timestamp());
SELECT SECOND(current_timestamp());
SELECT DAYOFWEEK('2024-01-15');              -- 1=周日
SELECT DAYOFYEAR('2024-01-15');
SELECT WEEKOFYEAR('2024-01-15');
SELECT QUARTER('2024-01-15');
SELECT EXTRACT(YEAR FROM current_date());
SELECT EXTRACT(EPOCH FROM current_timestamp());

-- 格式化
SELECT DATE_FORMAT(current_timestamp(), 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(current_timestamp(), 'EEEE, MMMM dd, yyyy');  -- 星期, 月 日, 年

-- 截断
SELECT DATE_TRUNC('MONTH', current_timestamp());
SELECT DATE_TRUNC('YEAR', current_date());
SELECT DATE_TRUNC('HOUR', current_timestamp());
SELECT TRUNC(current_date(), 'MM');          -- 月初

-- 时区转换
SELECT FROM_UTC_TIMESTAMP(current_timestamp(), 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP('2024-01-15 10:30:00', 'Asia/Shanghai');

-- 月末
SELECT LAST_DAY('2024-01-15');               -- 2024-01-31

-- 下一个星期几
SELECT NEXT_DAY('2024-01-15', 'Monday');

-- UNIX 时间戳
SELECT UNIX_TIMESTAMP();                     -- 当前 Unix 时间戳
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');
SELECT FROM_UNIXTIME(1705276800);            -- Unix 时间戳转 TIMESTAMP

-- 注意：TIMESTAMP 默认带会话时区，TIMESTAMP_NTZ 无时区
-- 注意：DATE_FORMAT 使用 Java SimpleDateFormat 模式
-- 注意：EXTRACT(EPOCH ...) 返回 Unix 秒数
-- 注意：INTERVAL 支持 YEAR / MONTH / DAY / HOUR / MINUTE / SECOND
-- 注意：时区名称使用 IANA 数据库（如 'Asia/Shanghai'）
-- 注意：Delta Lake 存储精度为微秒（6 位小数秒）
