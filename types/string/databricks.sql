-- Databricks SQL: 字符串类型
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- STRING: 变长字符串（无长度限制，UTF-8 编码）
-- VARCHAR(n): STRING 的别名（n 仅供文档参考，不强制限制）
-- CHAR(n): STRING 的别名（不做尾部空格填充）
-- BINARY: 二进制数据

CREATE TABLE examples (
    code       CHAR(10),                     -- 实际等同于 STRING
    name       VARCHAR(255),                 -- 实际等同于 STRING
    content    STRING,                       -- 推荐使用 STRING
    data       BINARY                        -- 二进制数据
);

-- 注意：CHAR(n) 和 VARCHAR(n) 不强制长度限制
-- 所有字符串类型在底层都是 STRING

-- 字符串字面量
SELECT 'hello world';                        -- 单引号
SELECT "hello world";                        -- 双引号也可以（Spark SQL）
SELECT 'it''s escaped';                      -- 单引号转义
SELECT 'line1\nline2';                       -- 转义字符

-- 多行字符串
SELECT 'line1
line2';

-- 排序规则（Databricks 2024+）
SELECT * FROM users WHERE name = 'alice' COLLATE 'en_CI';  -- 不区分大小写

-- 字符串插值（在 SQL 参数中使用）
-- 在 Databricks SQL 中使用参数化查询：
-- SELECT * FROM users WHERE name = :name

-- STRUCT 中的字符串
SELECT STRUCT('alice' AS name, 25 AS age);

-- MAP 中的字符串
SELECT MAP('key1', 'value1', 'key2', 'value2');

-- ARRAY 中的字符串
SELECT ARRAY('tag1', 'tag2', 'tag3');

-- 类型转换
SELECT CAST(123 AS STRING);
SELECT STRING(123);                          -- 快捷转换
SELECT CAST('123' AS INT);

-- 注意：STRING 是 Databricks 中唯一的字符串类型
-- 注意：CHAR(n) / VARCHAR(n) 仅是别名，不强制长度
-- 注意：UTF-8 编码，原生支持多字节字符
-- 注意：没有 NCHAR / NVARCHAR（STRING 原生支持 Unicode）
-- 注意：没有 TEXT / TINYTEXT / MEDIUMTEXT / LONGTEXT
-- 注意：没有 ENUM 类型
-- 注意：Delta Lake 使用 Parquet 存储，字符串高效压缩
