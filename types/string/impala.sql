-- Apache Impala: 字符串类型
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- STRING: 变长，无长度限制（实际受内存限制）
-- CHAR(n): 定长，1 ~ 255，尾部补空格
-- VARCHAR(n): 变长，1 ~ 65535

CREATE TABLE examples (
    code       CHAR(10),                  -- 定长（较少使用）
    name       VARCHAR(255),              -- 变长
    content    STRING                     -- 推荐使用（最灵活）
)
STORED AS PARQUET;

-- 注意：STRING 是 Impala 中最常用的字符串类型
-- 注意：Parquet 存储中 STRING 不会浪费空间

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS STRING);
SELECT CAST('2024-01-15' AS TIMESTAMP);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号（Impala 支持）

-- 字符串比较
SELECT 'abc' = 'abc';                     -- TRUE
SELECT 'abc' < 'abd';                     -- TRUE
-- 注意：字符串比较区分大小写

-- BINARY 类型（不支持）
-- Impala 没有 BINARY / BYTEA 类型
-- 可以用 STRING 存储 Base64 编码的二进制数据

-- Kudu 表的字符串类型
CREATE TABLE kudu_strings (
    id     BIGINT,
    name   STRING,                        -- Kudu 中 STRING 是 UTF-8 编码
    code   STRING,
    PRIMARY KEY (id)
)
STORED AS KUDU;

-- 注意：STRING 是推荐的字符串类型（等价于 VARCHAR 无限长）
-- 注意：CHAR/VARCHAR 主要用于兼容其他系统
-- 注意：没有 TEXT / CLOB 类型
-- 注意：没有 ENUM 类型
-- 注意：字符串默认 UTF-8 编码
-- 注意：不支持 COLLATION 设置
