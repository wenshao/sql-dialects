-- Apache Impala: 日期时间类型
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- TIMESTAMP: 日期时间，精度到纳秒，无时区信息
-- DATE: 日期（Impala 3.x+）

CREATE TABLE events (
    id         BIGINT,
    event_date DATE,
    created_at TIMESTAMP
)
STORED AS PARQUET;

-- 注意：没有 TIME 类型
-- 注意：没有 TIMESTAMP WITH TIME ZONE
-- 注意：TIMESTAMP 以 UTC 存储，不含时区

-- 获取当前时间
SELECT NOW();                             -- TIMESTAMP
SELECT CURRENT_TIMESTAMP();              -- 同 NOW()
SELECT CURRENT_DATE();                    -- DATE（字符串）
SELECT UTC_TIMESTAMP();                  -- UTC 时间

-- 构造日期时间
SELECT CAST('2024-01-15' AS TIMESTAMP);
SELECT CAST('2024-01-15' AS DATE);
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');

-- 日期加减
SELECT DATE_ADD(CAST('2024-01-15' AS TIMESTAMP), 7);       -- 加 7 天
SELECT DATE_ADD(CAST('2024-01-15' AS TIMESTAMP), INTERVAL 1 MONTH);
SELECT DATE_SUB(CAST('2024-01-15' AS TIMESTAMP), 7);       -- 减 7 天
SELECT ADDDATE('2024-01-15', 7);
SELECT MONTHS_ADD('2024-01-15', 3);

-- 日期差
SELECT DATEDIFF(CAST('2024-12-31' AS TIMESTAMP), CAST('2024-01-01' AS TIMESTAMP));
-- 返回天数

-- 提取
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT HOUR(NOW());
SELECT MINUTE(NOW());
SELECT SECOND(NOW());
SELECT DAYOFWEEK('2024-01-15');           -- 1=周日
SELECT DAYOFYEAR('2024-01-15');
SELECT WEEKOFYEAR('2024-01-15');
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM CAST('2024-01-15' AS TIMESTAMP));

-- 格式化
SELECT FROM_TIMESTAMP(NOW(), 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(NOW(), 'yyyy-MM-dd');   -- 同 FROM_TIMESTAMP（Hive 兼容）

-- 截断
SELECT TRUNC(CAST('2024-01-15 10:30:45' AS TIMESTAMP), 'MONTH');   -- 月初
SELECT TRUNC(CAST('2024-01-15 10:30:45' AS TIMESTAMP), 'YEAR');    -- 年初
SELECT TRUNC(CAST('2024-01-15 10:30:45' AS TIMESTAMP), 'DD');      -- 当天零点

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();                  -- 当前 Unix 时间戳
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd');

-- 时区转换
SELECT FROM_UTC_TIMESTAMP(NOW(), 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP(NOW(), 'Asia/Shanghai');

-- 注意：TIMESTAMP 精度到纳秒
-- 注意：DATE 类型在 Impala 3.x+ 可用
-- 注意：没有 INTERVAL 类型（使用 DATE_ADD/DATE_SUB 替代）
-- 注意：时区通过 FROM_UTC_TIMESTAMP / TO_UTC_TIMESTAMP 转换
