-- MySQL: 日期时间类型
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Date and Time Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/date-and-time-types.html
--   [2] MySQL 8.0 Reference Manual - MySQL Server Time Zone Support
--       https://dev.mysql.com/doc/refman/8.0/en/time-zone-support.html
--   [3] MySQL Internals - Data Type Storage Requirements
--       https://dev.mysql.com/doc/refman/8.0/en/storage-requirements.html

-- ============================================================
-- 1. 日期时间类型一览
-- ============================================================
CREATE TABLE datetime_examples (
    event_date  DATE,                -- 3B, 'YYYY-MM-DD', 1000-01-01 ~ 9999-12-31
    event_time  TIME(3),             -- 3B+2B(fsp), 'HH:MM:SS.fff', -838:59:59 ~ 838:59:59
    created_dt  DATETIME(6),         -- 5B+3B(fsp), 微秒精度, 1000-01-01 ~ 9999-12-31
    created_ts  TIMESTAMP(6),        -- 4B+3B(fsp), 微秒精度, 1970-01-01 ~ 2038-01-19
    birth_year  YEAR,                -- 1B, 1901 ~ 2155
    id          BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY
) ENGINE=InnoDB;

-- ============================================================
-- 2. DATETIME vs TIMESTAMP: 内部存储和时区转换机制
-- ============================================================

-- 2.1 DATETIME: 字面值存储（无时区转换）
-- 内部存储格式 (5.6.4+): 5 字节打包表示
--   YYYY*13*32 + MM*32 + DD 组成日期部分 (17 bits)
--   HH*3600 + MM*60 + SS 组成时间部分 (17 bits)
--   + 符号位等标志位，合计 40 bits = 5 字节
-- 写入 '2024-06-15 14:30:00' → 存储的就是这个字面值
-- 无论 session time_zone 如何变化，读出的都是 '2024-06-15 14:30:00'
-- 适用: 业务时间（订单时间、生日、合同日期）-- 这些时间不应随时区变化

-- 2.2 TIMESTAMP: UTC 存储 + 时区自动转换
-- 内部存储: 4 字节 Unix epoch 秒数（自 1970-01-01 00:00:00 UTC 起）
-- 写入过程: 客户端时间 → 按 session time_zone 转为 UTC → 存储 epoch
-- 读取过程: 存储 epoch → 按 session time_zone 转为本地时间 → 返回客户端
-- 例:
--   SET time_zone = '+08:00';
--   INSERT INTO t VALUES ('2024-06-15 22:00:00');  -- 存储为 UTC 14:00:00
--   SET time_zone = '+00:00';
--   SELECT ts FROM t;  -- 返回 '2024-06-15 14:00:00' (UTC)
-- 适用: 系统时间戳（日志、审计、分布式事件排序）

-- 2.3 关键差异总结:
-- | 维度       | DATETIME               | TIMESTAMP              |
-- |------------|------------------------|------------------------|
-- | 存储       | 5B（字面值）           | 4B（UTC epoch）        |
-- | 范围       | 1000-01-01 ~ 9999-12-31| 1970-01-01 ~ 2038-01-19|
-- | 时区       | 不转换                 | 自动转换               |
-- | NULL       | 允许                   | 允许（旧版默认NOT NULL）|
-- | ON UPDATE  | 支持                   | 支持                   |
-- | 索引性能   | 5B 比较                | 4B 比较（略快）        |

-- ============================================================
-- 3. 2038 年问题: 影响范围和应对策略
-- ============================================================

-- 3.1 问题本质
-- TIMESTAMP 使用 32 位有符号整数存储 Unix epoch:
-- 最大值: 2^31 - 1 = 2,147,483,647 → 2038-01-19 03:14:07 UTC
-- 超过此时间后: 32 位整数溢出，回绕到负数（1901-12-13）
--
-- 3.2 受影响的范围
-- 直接影响:
--   1. 所有使用 TIMESTAMP 列的表（存储上限 2038-01-19）
--   2. UNIX_TIMESTAMP() 函数返回的 32 位整数
--   3. FROM_UNIXTIME() 无法处理超过 2^31-1 的输入
-- 间接影响:
--   4. 应用层的 Unix timestamp 计算（如 Java int、C time_t）
--   5. 文件系统的 mtime/atime（ext4 已在 2038 扩展中修复）
--
-- 3.3 MySQL 的应对状态
-- 截至 8.4 LTS: TIMESTAMP 仍为 4 字节，2038 问题未解决
-- 社区讨论: 扩展到 8 字节（至 2486 亿年）但需要文件格式变更
-- 官方建议: 新项目使用 DATETIME 代替 TIMESTAMP
--
-- 3.4 各引擎的 2038 应对:
--   PostgreSQL: 无此问题，TIMESTAMPTZ 使用 8 字节微秒精度
--               范围: 4713 BC ~ 294276 AD
--   Oracle:     无此问题，DATE 存 7 字节（世纪+年月日时分秒）
--   SQL Server: 无此问题，DATETIME2 使用 6-8 字节
--   ClickHouse: DateTime 有 2106 问题（32位无符号），DateTime64 无此问题
--   SQLite:     无原生时间类型，时间存为 TEXT/REAL/INTEGER，取决于应用
--
-- 对引擎开发者的启示:
--   时间类型必须使用 64 位存储。4 字节看似节省空间，
--   但 2038 问题的迁移成本远超过每行多 4 字节的存储成本。

-- ============================================================
-- 4. 微秒精度的存储开销（Fractional Seconds Precision, FSP）
-- ============================================================

-- 5.6.4+ 支持 DATETIME(fsp) / TIMESTAMP(fsp) / TIME(fsp)
-- fsp 范围 0-6，表示小数秒的位数
CREATE TABLE fsp_demo (
    ts0 TIMESTAMP,            -- 4B + 0B = 4B (秒精度)
    ts3 TIMESTAMP(3),         -- 4B + 2B = 6B (毫秒精度)
    ts6 TIMESTAMP(6),         -- 4B + 3B = 7B (微秒精度)
    dt0 DATETIME,             -- 5B + 0B = 5B
    dt3 DATETIME(3),          -- 5B + 2B = 7B
    dt6 DATETIME(6)           -- 5B + 3B = 8B
);

-- 小数秒存储规则:
--   fsp 1-2 → 1 字节 (百分之一秒)
--   fsp 3-4 → 2 字节 (万分之一秒)
--   fsp 5-6 → 3 字节 (微秒)
--
-- 设计决策分析:
--   为什么不直接固定 6 位微秒？
--   → 节省存储: 亿行表中 TIMESTAMP vs TIMESTAMP(6) 差 3GB
--   → 但增加了用户认知负担和 ALTER TABLE 的复杂度
--   → PostgreSQL 的选择: TIMESTAMP 固定微秒精度，不可配置 → 更简单
--   → ClickHouse: DateTime 秒精度 / DateTime64(precision) 支持到纳秒
--
-- 横向对比: 时间精度
--   MySQL:      微秒 (10^-6)，需要显式指定 DATETIME(6)
--   PostgreSQL: 微秒 (10^-6)，默认就是微秒精度
--   Oracle:     TIMESTAMP(9) 支持纳秒 (10^-9)
--   SQL Server: DATETIME2(7) 支持 100 纳秒精度
--   ClickHouse: DateTime64(9) 支持纳秒
--   BigQuery:   TIMESTAMP 微秒精度

-- ============================================================
-- 5. 时区处理的深层问题
-- ============================================================

-- 5.1 MySQL 的时区机制
SET GLOBAL time_zone = 'UTC';              -- 全局
SET SESSION time_zone = '+08:00';          -- 会话级
-- 时区数据来源: mysql.time_zone* 表（需要手动加载 mysql_tzinfo_to_sql）
-- 未加载时区表时，只能用 '+08:00' 格式，不能用 'Asia/Shanghai'

-- 5.2 DATETIME 的时区陷阱
-- DATETIME 不存储时区信息，也不做转换。
-- 如果应用层在 +08:00 写入 '2024-06-15 22:00:00'，
-- 另一个 +00:00 的应用读取到的仍然是 '2024-06-15 22:00:00'
-- 但语义已经错误! 它应该显示为 '2024-06-15 14:00:00'
--
-- 这就是为什么分布式系统中 DATETIME 是危险的:
--   多时区写入 DATETIME 列 → 时间语义混乱 → 数据实质腐败
-- 解决: 统一应用层时区为 UTC，或使用 TIMESTAMP

-- 5.3 横向对比: 时区类型设计
--   MySQL:      DATETIME(无时区) vs TIMESTAMP(隐式UTC)
--               缺少 "带时区的DATETIME" 类型
--   PostgreSQL: TIMESTAMP vs TIMESTAMPTZ
--               官方强烈推荐总是用 TIMESTAMPTZ
--               内部存 UTC，显示时按 session timezone 转换
--   Oracle:     TIMESTAMP / TIMESTAMP WITH TIME ZONE / TIMESTAMP WITH LOCAL TIME ZONE
--               三种类型覆盖所有场景（最完整）
--   SQL Server: DATETIME2(无时区) vs DATETIMEOFFSET(存储偏移量)
--               DATETIMEOFFSET 存储偏移量而非时区名，不随 DST 变化
--   BigQuery:   DATETIME(无时区) vs TIMESTAMP(UTC)，语义与 MySQL 类似

-- ============================================================
-- 6. 常用日期时间函数
-- ============================================================
SELECT NOW();                                          -- 当前 DATETIME
SELECT CURRENT_TIMESTAMP;                              -- 同 NOW()
SELECT UTC_TIMESTAMP();                                -- 当前 UTC 时间
SELECT UNIX_TIMESTAMP();                               -- 当前 Unix epoch (秒)

-- 日期运算
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);                -- 加 1 天
SELECT DATE_SUB(NOW(), INTERVAL 2 HOUR);               -- 减 2 小时
SELECT DATEDIFF('2024-12-31', '2024-01-01');           -- 天数差: 365
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());       -- 指定单位差值

-- 格式化与解析
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');        -- 自定义格式
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');          -- 字符串→日期

-- 提取部分
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW());
SELECT EXTRACT(YEAR FROM NOW());

-- ============================================================
-- 7. 版本演进与最佳实践
-- ============================================================
-- MySQL 5.6.4: DATETIME/TIMESTAMP 支持微秒精度 (FSP)
-- MySQL 5.6.5: DATETIME 可用 DEFAULT CURRENT_TIMESTAMP 和 ON UPDATE
-- MySQL 8.0:   时区表自动加载改进，表达式默认值支持
-- MySQL 8.0.28: TIMESTAMP 范围扩展仍未实现
--
-- 实践建议:
--   1. 新项目优先 DATETIME(6) -- 避免 2038 问题且保留微秒精度
--   2. 分布式系统: 应用层统一 UTC + DATETIME，或使用 TIMESTAMP
--   3. 不要在 WHERE 中对时间列使用函数: WHERE YEAR(dt) = 2024 → 索引失效
--      改为: WHERE dt >= '2024-01-01' AND dt < '2025-01-01'
--   4. 考虑到微秒精度的存储开销: 日志系统用 DATETIME(3) (毫秒) 通常足够
--   5. 存储 Unix timestamp 时直接用 BIGINT 而非 TIMESTAMP 可规避 2038 问题
