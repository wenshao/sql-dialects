-- TDSQL: 日期时间类型
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- DATE: 'YYYY-MM-DD'
-- TIME: 'HH:MM:SS'
-- DATETIME: 'YYYY-MM-DD HH:MM:SS'
-- TIMESTAMP: UTC 存储，自动转时区
-- YEAR: 1901 ~ 2155

CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),
    created_at DATETIME(6),
    updated_at TIMESTAMP(6)
);

-- 获取当前时间
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();

-- 日期运算
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 HOUR);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 提取部分
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW());
SELECT EXTRACT(YEAR FROM NOW());

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();
SELECT FROM_UNIXTIME(1705276800);

-- 注意事项：
-- 日期时间类型与 MySQL 完全兼容
-- 分布式环境下各分片时区应保持一致
-- TIMESTAMP 类型有 2038 年问题
