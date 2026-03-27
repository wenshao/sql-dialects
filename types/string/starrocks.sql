-- StarRocks: 字符串类型
--
-- 参考资料:
--   [1] StarRocks - Data Types
--       https://docs.starrocks.io/docs/sql-reference/data-types/
--   [2] StarRocks - String Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/string-functions/

-- CHAR(n): 定长，1 ~ 255 字节，尾部补空格
-- VARCHAR(n): 变长，最大 1048576 字节（1MB）
-- STRING: 变长，最大 65535 字节（2.1+，VARCHAR(65535) 的别名）
-- BINARY / VARBINARY: 二进制类型（3.0+）

CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长（推荐）
    content    STRING                     -- VARCHAR(65535) 的别名（2.1+）
)
DISTRIBUTED BY HASH(code);

-- 注意：VARCHAR(n) 中 n 是字节数（UTF-8 下一个中文 3 字节）
-- 注意：STRING 类型不能作为分区列、分桶列或排序键

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS VARCHAR);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号也可以（MySQL 兼容）

-- 注意：与 MySQL 类型兼容，但有存储差异
-- 注意：没有 TEXT / MEDIUMTEXT / LONGTEXT 区分
-- 注意：没有 ENUM / SET 类型
-- 注意：VARCHAR 必须指定长度
-- 注意：不支持 COLLATION 设置，默认 UTF-8 字节比较
