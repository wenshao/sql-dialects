-- TDSQL: 日期函数
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 当前日期时间
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT SYSDATE();
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();

-- 构造日期
SELECT MAKEDATE(2024, 100);
SELECT MAKETIME(10, 30, 0);
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 日期加减
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);

-- 日期差
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');

-- 提取
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT EXTRACT(YEAR FROM '2024-01-15');

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');

-- 截断
SELECT DATE(NOW());
SELECT LAST_DAY('2024-02-15');

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();
SELECT FROM_UNIXTIME(1705276800);

-- 注意事项：
-- 日期函数与 MySQL 完全兼容
-- 分布式环境下各分片时区应保持一致
