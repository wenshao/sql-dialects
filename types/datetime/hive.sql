-- Hive: 日期时间类型
--
-- 参考资料:
--   [1] Apache Hive - Data Types (Date/Time)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
--   [2] Apache Hive - Date Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-DateFunctions

-- TIMESTAMP: 日期时间，精度到纳秒，不含时区（0.8+）
-- DATE: 日期，YYYY-MM-DD 格式（0.12+）
-- INTERVAL: 时间间隔（1.2+，仅限查询表达式）

CREATE TABLE events (
    id           BIGINT,
    event_date   DATE,                    -- 0.12+
    created_at   TIMESTAMP                -- 0.8+
);

-- 注意：早期 Hive 只能用 STRING 存储日期
-- TIMESTAMP 不含时区信息，解释为本地时区
-- 没有 TIME 类型（只有日期或日期时间）

-- 获取当前时间
SELECT CURRENT_DATE;                      -- DATE（Hive 2.0+）
SELECT CURRENT_TIMESTAMP;                -- TIMESTAMP（Hive 2.0+）
SELECT UNIX_TIMESTAMP();                 -- 当前 Unix 时间戳（秒）
SELECT FROM_UNIXTIME(UNIX_TIMESTAMP()); -- 当前时间字符串

-- 构造日期时间
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT TO_DATE('2024-01-15 10:30:00');    -- 提取日期部分

-- 日期加减
SELECT DATE_ADD('2024-01-15', 7);         -- 加 7 天
SELECT DATE_SUB('2024-01-15', 7);         -- 减 7 天
SELECT ADD_MONTHS('2024-01-15', 3);       -- 加 3 月

-- INTERVAL 表达式（1.2+）
SELECT CURRENT_TIMESTAMP + INTERVAL '1' DAY;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;

-- 日期差
SELECT DATEDIFF('2024-12-31', '2024-01-01');         -- 365（天数）
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');   -- 月数

-- 提取
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT HOUR('2024-01-15 10:30:00');
SELECT MINUTE('2024-01-15 10:30:00');
SELECT SECOND('2024-01-15 10:30:00');
SELECT WEEKOFYEAR('2024-01-15');          -- 第几周
SELECT DAYOFWEEK('2024-01-15');           -- 周几（2.2+）

-- 格式化
SELECT DATE_FORMAT('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(UNIX_TIMESTAMP(), 'yyyy-MM-dd');

-- Unix 时间戳
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705312800);
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd');

-- 截断
SELECT TRUNC('2024-01-15', 'MM');         -- 月初
SELECT TRUNC('2024-01-15', 'YY');         -- 年初

-- 最后一天
SELECT LAST_DAY('2024-01-15');            -- 2024-01-31
SELECT NEXT_DAY('2024-01-15', 'MO');      -- 下一个周一

-- 注意：没有 TIME 类型
-- 注意：没有时区支持（TIMESTAMP 解释为本地时区）
-- 注意：日期函数接受 STRING 参数（隐式转换）
