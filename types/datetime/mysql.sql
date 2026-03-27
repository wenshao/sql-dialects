-- MySQL: 日期时间类型
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Date and Time Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/date-and-time-types.html
--   [2] MySQL 8.0 Reference Manual - Date and Time Functions
--       https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html

-- DATE: 日期，格式 'YYYY-MM-DD'，范围 1000-01-01 ~ 9999-12-31
-- TIME: 时间，格式 'HH:MM:SS'，范围 -838:59:59 ~ 838:59:59
-- DATETIME: 日期时间，'YYYY-MM-DD HH:MM:SS'，范围 1000-01-01 ~ 9999-12-31
-- TIMESTAMP: 时间戳，存储为 UTC，自动转换时区，范围 1970-01-01 ~ 2038-01-19
-- YEAR: 年份，1901 ~ 2155

-- 5.6.4+: DATETIME/TIMESTAMP 支持微秒精度
CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),              -- 毫秒精度
    created_at DATETIME(6),          -- 微秒精度
    updated_at TIMESTAMP(6)          -- 微秒精度
);

-- DATETIME vs TIMESTAMP 的关键区别:
-- DATETIME: 5 字节（5.6.4+，之前为 8 字节）+ 小数秒存储，不受时区影响，范围更大
-- TIMESTAMP: 4 字节 + 小数秒存储，自动转时区，2038 年问题
-- 8.0.28+: TIMESTAMP 范围扩展的讨论仍在进行

-- 获取当前时间
SELECT NOW();                        -- 当前日期时间
SELECT CURRENT_TIMESTAMP;            -- 同 NOW()
SELECT CURDATE();                    -- 当前日期
SELECT CURTIME();                    -- 当前时间
SELECT UTC_TIMESTAMP();              -- 当前 UTC 时间

-- 日期运算
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 HOUR);
SELECT DATEDIFF('2024-12-31', '2024-01-01');    -- 返回天数差
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW()); -- 指定单位的差值

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 提取部分
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW());
SELECT HOUR(NOW()), MINUTE(NOW()), SECOND(NOW());
SELECT EXTRACT(YEAR FROM NOW());
