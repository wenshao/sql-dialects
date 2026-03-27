-- BigQuery: 字符串类型
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Data Types (String)
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#string_type
--   [2] BigQuery SQL Reference - String Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/string_functions

-- STRING: 变长 UTF-8 字符串，无长度限制（最大约 10MB）
-- BYTES: 变长二进制数据

CREATE TABLE examples (
    name       STRING,                    -- 唯一字符串类型
    content    STRING,                    -- 无需区分 TEXT/VARCHAR
    data       BYTES                      -- 二进制数据
);

-- 注意：BigQuery 没有 CHAR(n) / VARCHAR(n)
-- 所有字符串都用 STRING，无需指定长度
-- STRING 内部采用 UTF-8 编码

-- 类型转换
SELECT CAST('hello' AS STRING);
SELECT CAST(123 AS STRING);
SELECT SAFE_CAST('abc' AS INT64);         -- 转换失败返回 NULL（安全转换）

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号也可以
SELECT '''multi
line string''';                           -- 三引号多行字符串
SELECT r'\n is not a newline';            -- 原始字符串（Raw String）
SELECT b'binary data';                    -- BYTES 字面量

-- 模板字符串（仅在脚本中可用）
-- 不支持直接的字符串模板语法，需用 CONCAT 或 FORMAT

-- FORMAT 函数（类似 printf）
SELECT FORMAT('%s has %d items', 'cart', 5);  -- 'cart has 5 items'
SELECT FORMAT('%010d', 42);                    -- '0000000042'

-- COLLATION（排序规则，2023+）
SELECT COLLATE('hello', 'und:ci') = COLLATE('HELLO', 'und:ci');  -- TRUE

-- 注意：没有 ENUM 类型，通常用 STRING + CHECK 约束或视图层面校验
-- 注意：没有 BLOB/CLOB 类型，BYTES 最大约 10MB
-- 注意：BigQuery 是列存储，STRING 列会自动压缩
