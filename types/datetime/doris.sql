-- Apache Doris: 日期时间类型
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- DATE: 日期，0000-01-01 ~ 9999-12-31
-- DATETIME: 日期时间，精度到秒（默认），0000-01-01 ~ 9999-12-31
-- DATETIME(p): 日期时间，亚秒精度 p=0~6（2.0+）

CREATE TABLE events (
    id           BIGINT,
    event_date   DATE,
    created_at   DATETIME,                -- 秒精度
    precise_at   DATETIME(6)              -- 微秒精度（2.0+）
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id);

-- 注意：没有 TIME 类型
-- 注意：没有 TIMESTAMP WITH TIME ZONE
-- 注意：DATETIME 不存储时区信息

-- 获取当前时间
SELECT CURRENT_DATE();                    -- DATE
SELECT NOW();                             -- DATETIME
SELECT CURRENT_TIMESTAMP();              -- DATETIME
SELECT CURDATE();                        -- DATE（MySQL 兼容）
SELECT CURTIME();                        -- TIME 字符串
SELECT UTC_TIMESTAMP();                  -- UTC 时间

-- 构造日期时间
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
SELECT MAKEDATE(2024, 100);              -- 2024-04-09

-- 日期加减
SELECT DATE_ADD('2024-01-15', INTERVAL 7 DAY);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 MONTH);
SELECT ADDDATE('2024-01-15', 7);          -- 加 7 天
SELECT TIMESTAMPADD(HOUR, 2, NOW());
SELECT YEARS_ADD('2024-01-15', 1);       -- Doris 特有
SELECT MONTHS_ADD('2024-01-15', 3);      -- Doris 特有

-- 日期差
SELECT DATEDIFF('2024-12-31', '2024-01-01');          -- 365 天
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-12-31'); -- 11 月

-- 提取
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT HOUR(NOW());
SELECT MINUTE(NOW());
SELECT SECOND(NOW());
SELECT DAYOFWEEK('2024-01-15');           -- 1=周日（MySQL 兼容）
SELECT DAYOFYEAR('2024-01-15');
SELECT WEEKOFYEAR('2024-01-15');

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');

-- 截断
SELECT DATE_TRUNC('month', NOW());        -- 月初
SELECT DATE_TRUNC('year', NOW());         -- 年初
SELECT DATE_TRUNC('day', NOW());          -- 当天零点

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();                  -- 当前 Unix 时间戳
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);
SELECT FROM_UNIXTIME(1705312800, '%Y-%m-%d');

-- 注意：与 MySQL 日期函数基本兼容
-- 注意：分区表常用 DATE 类型作为分区键
-- 注意：时区由 FE 配置的 time_zone 参数决定
-- 注意：2.0+ 支持微秒精度
