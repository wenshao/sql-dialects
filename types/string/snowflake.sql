-- Snowflake: 字符串类型
--
-- 参考资料:
--   [1] Snowflake SQL Reference - String Data Types
--       https://docs.snowflake.com/en/sql-reference/data-types-text
--   [2] Snowflake SQL Reference - String Functions
--       https://docs.snowflake.com/en/sql-reference/functions-string

-- VARCHAR(n): 变长，最大 16MB（n 可选，默认最大）
-- CHAR(n) / CHARACTER(n): 同 VARCHAR（Snowflake 中无真正定长）
-- STRING / TEXT: VARCHAR 的别名
-- BINARY(n): 二进制数据，最大 8MB
-- VARBINARY(n): 同 BINARY

CREATE TABLE examples (
    code       CHAR(10),                  -- 实际等同于 VARCHAR(10)
    name       VARCHAR(255),              -- 变长
    content    STRING,                    -- VARCHAR 的别名，推荐
    data       BINARY                     -- 二进制
);

-- 注意：CHAR/CHARACTER 不做尾部空格填充
-- 所有字符串类型在底层行为一致（均为变长）
-- 不指定长度时默认为 16,777,216（16MB）

-- 排序规则
SELECT COLLATE('hello', 'en-ci');         -- 大小写不敏感比较
CREATE TABLE t (
    name VARCHAR(100) COLLATE 'en-ci'     -- 列级排序规则
);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT $$hello world$$;                   -- 美元引号（避免转义）
SELECT 'it''s escaped';                   -- 单引号转义

-- VARIANT 中的字符串
SELECT PARSE_JSON('{"name": "alice"}'):name::STRING;

-- 注意：没有 ENUM 类型
-- 注意：没有 TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT 区分
-- 注意：UTF-8 编码，一个字符最多 4 字节
-- 注意：字符串比较默认大小写敏感
