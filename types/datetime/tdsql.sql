-- TDSQL: 日期时间类型
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] MySQL 8.0 Reference Manual - Date and Time Types
--       https://dev.mysql.com/doc/refman/8.0/en/date-and-time-types.html

-- ============================================================
-- 1. 日期时间类型一览
-- ============================================================

-- DATE:      3 字节，'YYYY-MM-DD'，范围 1000-01-01 ~ 9999-12-31
-- TIME:      3 字节 + 小数秒，'HH:MM:SS[.ffffff]'，范围 -838:59:59 ~ 838:59:59
-- DATETIME:  5-8 字节，'YYYY-MM-DD HH:MM:SS[.ffffff]'，不受时区影响
-- TIMESTAMP: 4-7 字节，UTC 存储，自动转换时区，范围 1970-01-01 ~ 2038-01-19
-- YEAR:      1 字节，1901 ~ 2155

CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_date DATE,                               -- 仅日期
    event_time TIME(3),                             -- 时间（毫秒精度）
    created_at DATETIME(6),                         -- 日期+时间（微秒精度）
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
);

-- ============================================================
-- 2. 分布式环境下的时间类型考量
-- ============================================================

-- 2.1 时区一致性问题
-- 分布式环境中最常见的时间问题: 不同分片的系统时区不一致
-- 症状:
--   同一条记录的 created_at 在不同分片上显示不同的时间
--   跨分片时间范围查询遗漏或重复数据
-- 最佳实践:
--   1. 所有分片的系统时区必须统一设置（推荐 UTC）
--   2. 应用层负责时区转换，数据库统一使用 UTC
--   3. 避免在 SQL 中使用 LOCALTIME / LOCALTIMESTAMP

-- 设置全局时区（所有分片必须执行）
-- SET GLOBAL time_zone = '+00:00';  -- UTC
-- SET GLOBAL time_zone = '+08:00';  -- 中国标准时间

-- 2.2 TIMESTAMP vs DATETIME 的选择
-- TIMESTAMP: UTC 存储，自动时区转换，但存在 2038 年问题
-- DATETIME: 原样存储，不做时区转换，范围更大
-- 分布式建议:
--   - 推荐使用 DATETIME + 应用层 UTC 约定，避免 TIMESTAMP 的 2038 限制
--   - 如果使用 TIMESTAMP，确保所有分片 time_zone 一致
--   - 记录创建/更新时间用 TIMESTAMP（自动更新特性）
--   - 业务日期（如订单日期）用 DATETIME 或 DATE

-- 2.3 时间作为 shardkey 的注意事项
-- 日期/时间类型不建议作为 shardkey:
--   1. 时间值存在热点（当前时间的分片写入集中）
--   2. 范围查询需要扫描多个分片
-- 替代方案: 使用时间相关的 hash 值作为 shardkey
--   例如: HASH(DATE(created_at)) 按天分片，或按 user_id 分片

-- ============================================================
-- 3. 时间精度（小数秒）
-- ============================================================

-- DATETIME(fsp) / TIMESTAMP(fsp): fsp = 0~6（小数秒位数）
-- fsp=0: 秒级精度，4 字节存储
-- fsp=3: 毫秒精度，5 字节存储
-- fsp=6: 微秒精度，8 字节存储
-- 分布式场景建议 fsp=3 或 fsp=6，便于分布式事务排序

CREATE TABLE precision_demo (
    t0 DATETIME(0),       -- '2024-01-15 10:30:00'
    t3 DATETIME(3),       -- '2024-01-15 10:30:00.123'
    t6 DATETIME(6)        -- '2024-01-15 10:30:00.123456'
);

-- ============================================================
-- 4. 获取当前时间
-- ============================================================

SELECT NOW();                     -- 当前日期时间（会话时区）
SELECT CURRENT_TIMESTAMP;         -- 同 NOW()
SELECT CURRENT_TIMESTAMP(6);      -- 微秒精度
SELECT CURDATE();                 -- 当前日期
SELECT CURTIME();                 -- 当前时间
SELECT UTC_TIMESTAMP();           -- UTC 时间（推荐分布式使用）
SELECT SYSDATE();                 -- 实时系统时间（注意: 与 NOW() 的区别）

-- NOW() vs SYSDATE() 在分布式中的差异:
--   NOW(): 语句开始时的时间，同一语句中多次调用返回相同值
--   SYSDATE(): 实时获取系统时间，每次调用可能不同
-- 推荐: 使用 NOW() / CURRENT_TIMESTAMP，保证同一事务内时间一致

-- ============================================================
-- 5. 日期运算
-- ============================================================

-- 加减
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 HOUR);
SELECT NOW() + INTERVAL 7 DAY;

-- 差值
SELECT DATEDIFF('2024-12-31', '2024-01-01');                   -- 365（天数差）
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());               -- 小时差
SELECT TIMESTAMPDIFF(MINUTE, '2024-01-01 10:00', '2024-01-01 12:30'); -- 150

-- 提取部分
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW()), HOUR(NOW());
SELECT EXTRACT(YEAR_MONTH FROM NOW());
SELECT DAYOFWEEK(NOW()), DAYOFYEAR(NOW()), WEEK(NOW());

-- ============================================================
-- 6. 格式化与解析
-- ============================================================

-- 格式化输出
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');     -- '2024-01-15 10:30:00'
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');           -- '2024年01月15日'
SELECT TIME_FORMAT(NOW(), '%H:%i:%s');               -- '10:30:00'

-- 解析字符串为日期
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');

-- ============================================================
-- 7. Unix 时间戳
-- ============================================================

SELECT UNIX_TIMESTAMP();                     -- 当前 Unix 时间戳（秒）
SELECT UNIX_TIMESTAMP(NOW(6));               -- 带微秒的时间戳
SELECT FROM_UNIXTIME(1705276800);            -- 时间戳转日期
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d'); -- 时间戳转格式化字符串

-- 分布式场景: Unix 时间戳适合跨分片比较（整数，不受时区显示影响）
-- 但注意: Unix 时间戳范围受 TIMESTAMP 限制（2038 年问题）

-- ============================================================
-- 8. 分布式时间函数行为
-- ============================================================

-- 8.1 跨分片时间聚合
-- 按日/月/年统计在协调节点完成分组:
--   各分片先做局部聚合，协调节点合并结果
--   DATE(created_at) 作为 GROUP BY 键在各分片独立计算
--   跨分片排序在协调节点归并

-- 按小时统计（分布式场景常用）
SELECT DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00') AS hour_start,
       COUNT(*) AS cnt
FROM events
GROUP BY hour_start
ORDER BY hour_start;

-- 8.2 时间范围查询
-- 范围查询的性能取决于 shardkey 设计:
--   如果 shardkey 包含时间维度（如按月分表），可裁剪分片
--   如果 shardkey 与时间无关，范围查询扫描所有分片

-- ============================================================
-- 9. 注意事项与最佳实践
-- ============================================================

-- 1. 日期时间类型与 MySQL 完全兼容
-- 2. 所有分片的系统时区必须统一设置（推荐 UTC）
-- 3. TIMESTAMP 有 2038 年问题，长期存储推荐 DATETIME
-- 4. 记录创建/更新时间可用 TIMESTAMP 的自动更新特性
-- 5. 时间类型不建议作为 shardkey（写入热点问题）
-- 6. 推荐使用 NOW() 而非 SYSDATE()（同一事务时间一致性）
-- 7. 高精度时间（fsp=3 或 fsp=6）便于分布式事务排序
-- 8. 跨分片时间范围查询需注意性能，考虑按时间维度分表
