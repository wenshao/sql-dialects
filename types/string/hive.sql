-- Hive: 字符串类型
--
-- 参考资料:
--   [1] Apache Hive - Data Types (String)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
--   [2] Apache Hive - String Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-StringFunctions

-- ============================================================
-- 1. 三种字符串类型
-- ============================================================
-- STRING:     变长，无长度限制（受 Java 堆内存约束）
-- VARCHAR(n): 变长，1 ~ 65535 字符 (0.12+)
-- CHAR(n):    定长，1 ~ 255 字符，尾部补空格 (0.13+)

CREATE TABLE examples (
    code    CHAR(10),                -- 定长（尾部补空格）
    name    VARCHAR(255),            -- 变长有限制
    content STRING                   -- 变长无限制（最常用）
) STORED AS ORC;

-- 设计分析: STRING 为什么是 Hive 的首选?
-- 1. Schema-on-Read: 数据文件中的字符串没有长度约束，STRING 与之自然匹配
-- 2. 简单: 不需要考虑 VARCHAR(n) 的长度限制（超长会被截断）
-- 3. 性能: ORC/Parquet 列式存储对 STRING 有字典编码优化，
--    VARCHAR(n) 的长度约束在列存中没有额外的性能优势
-- 4. 历史: 早期 Hive 只有 STRING，VARCHAR/CHAR 在 0.12/0.13 才加入
--
-- 对比:
--   MySQL:      VARCHAR(n) 是主力，TEXT 用于大文本
--   PostgreSQL: TEXT 推荐代替 VARCHAR，无性能差异
--   Hive:       STRING 推荐代替 VARCHAR/CHAR

-- ============================================================
-- 2. BINARY 类型 (0.8+)
-- ============================================================
CREATE TABLE files (id BIGINT, data BINARY) STORED AS ORC;

SELECT LENGTH(data) FROM files;           -- 字节长度
SELECT BASE64(data) FROM files;           -- Base64 编码
SELECT UNBASE64('aGVsbG8=');             -- Base64 解码

-- ============================================================
-- 3. 字符串字面量
-- ============================================================
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号也可以（Hive 特有）
SELECT 'it''s';                           -- 单引号转义
SELECT "it's";                            -- 双引号内不需要转义

-- 对比: PostgreSQL 只支持单引号; MySQL 支持单引号和双引号（ANSI_QUOTES 模式除外）

-- ============================================================
-- 4. 编码与排序
-- ============================================================
-- Hive 内部使用 UTF-8 编码
-- 没有排序规则（COLLATION）设置
-- 字符串比较默认大小写敏感

SELECT LENGTH('hello');          -- 5 (字符数)
SELECT OCTET_LENGTH('你好');    -- 6 (字节数, UTF-8 编码)

-- 大小写不敏感比较: 需要手动 LOWER/UPPER
SELECT * FROM users WHERE LOWER(name) = LOWER('Alice');

-- 对比:
--   MySQL:      有 COLLATE 设置（utf8mb4_general_ci 大小写不敏感）
--   PostgreSQL: 有 COLLATE 设置（citext 扩展提供大小写不敏感类型）
--   Hive:       无 COLLATE（只能手动 LOWER/UPPER）

-- ============================================================
-- 5. 跨引擎对比: 字符串类型
-- ============================================================
-- 引擎          主力类型      最大长度      COLLATION   编码
-- MySQL         VARCHAR(n)    65535 字节    丰富        utf8mb4
-- PostgreSQL    TEXT          无限(1GB)     丰富        UTF-8
-- Oracle        VARCHAR2(n)   32767 字节    NLS设置     AL32UTF8
-- Hive          STRING        无限(JVM限制) 无          UTF-8
-- Spark SQL     STRING        无限          无          UTF-8
-- BigQuery      STRING        无限          无          UTF-8
-- ClickHouse    String        无限          有(实验性)  UTF-8
--
-- 趋势: 分析引擎倾向于单一的 STRING 类型，不区分 VARCHAR/TEXT/CHAR。
-- RDBMS 的 VARCHAR(n) 在 OLTP 场景中有存储优化意义（行存中预分配空间），
-- 在列存中 VARCHAR(n) 的长度限制没有性能优势。

-- ============================================================
-- 6. 已知限制
-- ============================================================
-- 1. 无排序规则(COLLATION): 不能设置大小写不敏感比较
-- 2. 无 ENUM 类型: 用 STRING + CHECK 约束(不强制执行)模拟
-- 3. 无 BLOB/CLOB/TEXT 分级: 只有 STRING 和 BINARY
-- 4. CHAR(n) 尾部补空格: 与 STRING 比较时需要注意 TRIM
-- 5. VARCHAR 超长截断: VARCHAR(10) 存储 'abcdefghijk' 会截断为 'abcdefghij'

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================
-- 1. 单一的 STRING 类型是分析引擎的最佳实践:
--    Hive/Spark/BigQuery 都选择了统一的 STRING 类型
-- 2. VARCHAR(n) 在列存中没有性能优势:
--    列存引擎不需要预分配行内空间，长度限制没有意义
-- 3. COLLATION 支持是企业级需求:
--    缺少 COLLATION 导致大小写不敏感查询需要手动 LOWER()
-- 4. 双引号字符串是 Hive 的便利特性:
--    但与 SQL 标准冲突（标准中双引号用于标识符引用）
