-- StarRocks: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] StarRocks Documentation
--       https://docs.starrocks.io/

-- 一、与 MySQL 兼容性: 兼容MySQL协议和语法
--   数据类型: INT, BIGINT, FLOAT, DOUBLE, DECIMAL, VARCHAR, STRING,
--     BOOLEAN, DATE, DATETIME, JSON(2.5+), BITMAP, HLL, ARRAY, MAP, STRUCT
-- 二、表模型: Duplicate/Aggregate/Unique/Primary Key
--   Primary Key模型支持实时UPDATE/DELETE
-- 三、陷阱: 与Doris类似(StarRocks从Doris分叉), MPP架构,
--   DISTRIBUTED BY HASH必须, 物化视图(异步)可加速查询,
--   CBO优化器(比Doris更先进), 外表联邦查询
-- 四、自增: 无（使用UUID或应用层生成）
-- 五、日期: NOW(); CURDATE(); DATE_ADD; DATEDIFF; DATE_FORMAT
--   UNIX_TIMESTAMP(); FROM_UNIXTIME(); STR_TO_DATE()
--   DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s')
-- 六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, LOCATE, CONCAT, GROUP_CONCAT

-- ============================================================
-- 七、数据类型映射（从 MySQL/PostgreSQL 到 StarRocks）
-- ============================================================
-- MySQL → StarRocks:
--   INT → INT, BIGINT → BIGINT, FLOAT → FLOAT,
--   DOUBLE → DOUBLE, DECIMAL(p,s) → DECIMAL(p,s),
--   VARCHAR(n) → VARCHAR(n)/STRING, TEXT → STRING,
--   DATETIME → DATETIME, DATE → DATE,
--   BOOLEAN → BOOLEAN, JSON → JSON (2.5+),
--   AUTO_INCREMENT → 不支持, BLOB → 不支持
-- PostgreSQL → StarRocks:
--   INTEGER → INT, TEXT → STRING, SERIAL → 不支持,
--   BOOLEAN → BOOLEAN, JSONB → JSON, ARRAY → ARRAY (3.0+),
--   BYTEA → 不支持

-- 八、函数等价映射
-- MySQL → StarRocks: 基本兼容
--   IFNULL → IFNULL/COALESCE, NOW() → NOW(),
--   DATE_FORMAT → DATE_FORMAT, CONCAT → CONCAT,
--   GROUP_CONCAT → GROUP_CONCAT, LIMIT → LIMIT

-- 九、常见陷阱补充
--   从 Apache Doris 分叉，语法和架构类似
--   MPP 架构，DISTRIBUTED BY HASH 必须指定
--   表模型选择: Duplicate(明细)/Aggregate(聚合)/Unique(唯一)/Primary Key(主键)
--   Primary Key 模型支持实时 UPDATE/DELETE
--   物化视图（异步）可加速查询
--   CBO 优化器比 Doris 更先进
--   外表联邦查询支持 Hive/MySQL/Elasticsearch 等
--   BITMAP/HLL 类型用于近似去重

-- 十、NULL 处理
-- IFNULL(a, b); COALESCE(a, b, c);
-- NULLIF(a, b); IF(a IS NULL, b, a);

-- 十一、分页语法
-- SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;
