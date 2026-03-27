-- Doris: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Apache Doris Documentation
--       https://doris.apache.org/docs/

-- 一、与 MySQL 兼容性: 兼容MySQL协议和大部分语法
--   数据类型: INT, BIGINT, FLOAT, DOUBLE, DECIMAL, VARCHAR, STRING,
--     BOOLEAN, DATE, DATETIME, JSON(1.2+), BITMAP, HLL, ARRAY(2.0+)
-- 二、数据模型: Duplicate/Aggregate/Unique/Primary Key
--   选择合适的模型很关键(影响写入和查询性能)
-- 三、陷阱: MPP架构, DISTRIBUTED BY HASH 必须指定, BUCKETS数量影响性能,
--   不支持事务, AUTO_INCREMENT不支持(2.1+实验性支持),
--   MySQL工具可直接连接(mysqlclient), 无外键/约束
-- 四、自增: 无（使用UUID或应用层生成）
-- 五、日期: NOW(); CURDATE(); DATE_ADD(d, INTERVAL 1 DAY);
--   DATEDIFF(a,b); DATE_FORMAT(ts,'%Y-%m-%d %H:%i:%s')
--   UNIX_TIMESTAMP(); FROM_UNIXTIME(); STR_TO_DATE()
-- 六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, LOCATE, CONCAT, GROUP_CONCAT

-- ============================================================
-- 七、数据类型映射（从 MySQL/PostgreSQL 到 Doris）
-- ============================================================
-- MySQL → Doris:
--   INT → INT, BIGINT → BIGINT, FLOAT → FLOAT,
--   DOUBLE → DOUBLE, DECIMAL(p,s) → DECIMAL(p,s),
--   VARCHAR(n) → VARCHAR(n)/STRING, TEXT → STRING,
--   DATETIME → DATETIME, DATE → DATE,
--   BOOLEAN → BOOLEAN, JSON → JSON (1.2+),
--   AUTO_INCREMENT → 不支持 (2.1+ 实验性),
--   BLOB → 不支持, ENUM → VARCHAR
-- PostgreSQL → Doris:
--   INTEGER → INT, TEXT → STRING, SERIAL → 不支持,
--   BOOLEAN → BOOLEAN, JSONB → JSON,
--   ARRAY → ARRAY (2.0+), BYTEA → 不支持

-- 八、函数等价映射
-- MySQL → Doris: 基本兼容
--   IFNULL → IFNULL/COALESCE, NOW() → NOW(),
--   DATE_FORMAT → DATE_FORMAT, CONCAT → CONCAT,
--   GROUP_CONCAT → GROUP_CONCAT, LIMIT → LIMIT

-- 九、常见陷阱补充
--   MPP 架构，DISTRIBUTED BY HASH 必须指定
--   BUCKETS 数量影响性能（建议根据数据量调整）
--   数据模型选择: Duplicate(明细)/Aggregate(聚合)/Unique(唯一)/Primary Key(主键)
--   不支持事务（原子性仅限单次导入）
--   无外键/约束
--   MySQL 客户端可直接连接（兼容 MySQL 协议）
--   Routine Load 可持续从 Kafka 导入数据
--   BITMAP/HLL 类型用于近似去重

-- 十、NULL 处理
-- IFNULL(a, b); COALESCE(a, b, c);
-- NULLIF(a, b); IF(a IS NULL, b, a);

-- 十一、分页语法
-- SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- 十二、数据导入方式
-- Stream Load (HTTP)、Broker Load (HDFS/S3)、
-- Routine Load (Kafka)、INSERT INTO SELECT
