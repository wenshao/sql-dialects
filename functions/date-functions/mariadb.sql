-- MariaDB: 日期和时间函数
-- 与 MySQL 基本一致
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Date & Time Functions
--       https://mariadb.com/kb/en/date-time-functions/

-- ============================================================
-- 1. 当前时间
-- ============================================================
SELECT NOW(), CURRENT_TIMESTAMP, SYSDATE();
SELECT CURDATE(), CURRENT_DATE;
SELECT CURTIME(), CURRENT_TIME;
SELECT UNIX_TIMESTAMP(), UNIX_TIMESTAMP('2024-01-01 00:00:00');

-- ============================================================
-- 2. 日期运算
-- ============================================================
SELECT DATE_ADD('2024-01-01', INTERVAL 30 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 MONTH);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01 00:00:00', '2024-01-02 12:00:00');

-- ============================================================
-- 3. 日期格式化和解析
-- ============================================================
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- ============================================================
-- 4. 日期部分提取
-- ============================================================
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW());
SELECT HOUR(NOW()), MINUTE(NOW()), SECOND(NOW());
SELECT DAYOFWEEK(NOW()), DAYOFYEAR(NOW()), WEEKOFYEAR(NOW());
SELECT EXTRACT(YEAR_MONTH FROM NOW());

-- ============================================================
-- 5. 微秒精度 (同 MySQL 5.6+)
-- ============================================================
SELECT NOW(6), CURRENT_TIMESTAMP(6);
-- MariaDB 和 MySQL 都支持最多 6 位小数精度 (微秒)

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- MariaDB 与 MySQL 的日期函数几乎完全一致
-- 唯一的注意点是系统版本表的时间处理:
--   row_start/row_end 使用 TIMESTAMP(6) 存储
--   FOR SYSTEM_TIME 查询需要精确的时间比较
-- 时区处理: 与 MySQL 相同 (TIMESTAMP 存 UTC, DATETIME 存字面值)
