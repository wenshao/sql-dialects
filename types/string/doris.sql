-- Apache Doris: 字符串类型
--
-- 参考资料:
--   [1] Doris Documentation - String Types
--       https://doris.apache.org/docs/sql-manual/data-types/

-- ============================================================
-- 1. 类型体系
-- ============================================================
-- CHAR(n):    定长, 1~255 字节, 尾部补空格
-- VARCHAR(n): 变长, 最大 65533 字节
-- STRING:     变长, 最大 2GB (2.0+)
-- TEXT:       STRING 的别名

CREATE TABLE examples (
    code CHAR(10), name VARCHAR(255), content STRING
) DUPLICATE KEY(code) DISTRIBUTED BY HASH(code);

-- ============================================================
-- 2. 关键限制
-- ============================================================
-- VARCHAR(n) 的 n 是字节数(UTF-8 中文 3 字节):
--   VARCHAR(255) 最多存 85 个中文字符
--
-- STRING 不能作为 Key 列、分区列或分桶列
-- CHAR 不能作为分区列
-- 必须指定 VARCHAR 的长度(不像 PG 的 TEXT 无长度限制)
-- 不支持 COLLATION(默认 UTF-8 字节比较)
-- 不支持 ENUM / SET 类型

-- ============================================================
-- 3. 字符串字面量
-- ============================================================
SELECT 'hello world';    -- 单引号
SELECT "hello world";    -- 双引号(MySQL 兼容)

-- ============================================================
-- 4. 对比其他引擎
-- ============================================================
-- VARCHAR(n) 的 n:
--   Doris:     字节数(UTF-8)
--   MySQL:     字符数
--   PostgreSQL: 字符数
--
-- 大文本:
--   Doris:     STRING(统一，2.0+)
--   MySQL:     TEXT/MEDIUMTEXT/LONGTEXT(分级)
--   PostgreSQL: TEXT(无大小限制)
--   ClickHouse: String(无大小限制)
--   BigQuery:  STRING(无大小限制)
--
-- COLLATION:
--   Doris/StarRocks: 不支持(UTF-8 字节比较)
--   MySQL:   utf8mb4_unicode_ci 等(丰富)
--   PostgreSQL: ICU collation(12+)
--
-- 对引擎开发者的启示:
--   统一的 STRING 类型(不分级)是现代引擎的趋势。
--   MySQL 的 TEXT 分级增加了用户认知负担。
--   列存引擎不需要分级——列内压缩自动处理长短字符串。
