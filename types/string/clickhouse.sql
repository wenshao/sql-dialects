-- ClickHouse: 字符串类型
--
-- 参考资料:
--   [1] ClickHouse - String Data Type
--       https://clickhouse.com/docs/en/sql-reference/data-types/string
--   [2] ClickHouse - FixedString
--       https://clickhouse.com/docs/en/sql-reference/data-types/fixedstring

-- String: 变长字符串，无长度限制（任意字节序列）
-- FixedString(N): 定长 N 字节，尾部补 \0
-- 注意：ClickHouse 类型名大小写敏感

CREATE TABLE examples (
    code       FixedString(10),           -- 定长 10 字节
    name       String,                    -- 变长（最常用）
    content    String                     -- 无 TEXT / VARCHAR 区分
) ENGINE = MergeTree() ORDER BY code;

-- 注意：所有字符串底层都是字节序列，不限编码
-- 没有 VARCHAR(n) / CHAR(n) / TEXT 等区分
-- FixedString(N) 中 N 是字节数而非字符数

-- LowCardinality（字典编码优化，18.12+）
-- 适合值种类少的列（如国家代码、状态值）
CREATE TABLE t (
    status LowCardinality(String)         -- 自动字典编码，减少存储和加速查询
) ENGINE = MergeTree() ORDER BY status;

-- Enum 类型
-- Enum8: 最多 256 个值，底层 Int8
-- Enum16: 最多 65536 个值，底层 Int16
CREATE TABLE t (
    status Enum8('active' = 1, 'inactive' = 2, 'deleted' = 3)
) ENGINE = MergeTree() ORDER BY status;

-- UUID 类型
CREATE TABLE t (
    id UUID DEFAULT generateUUIDv4()
) ENGINE = MergeTree() ORDER BY id;

-- 类型转换
SELECT toString(123);
SELECT toFixedString('abc', 5);           -- 'abc\0\0'
SELECT CAST('123' AS Int64);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT 'it''s escaped';                   -- 转义

-- 注意：没有排序规则（COLLATION），比较总是字节级
-- 注意：String 可以存储任意二进制数据（无需单独的 BINARY 类型）
-- 注意：LowCardinality 是性能优化的关键特性
