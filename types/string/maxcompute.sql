-- MaxCompute (ODPS): 字符串类型
--
-- 参考资料:
--   [1] MaxCompute SQL - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
--   [2] MaxCompute - String Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/string-functions

-- STRING: 变长字符串，最大 8MB（旧版本 2MB）
-- VARCHAR(n): 变长，1 ~ 65535 字符（2.0+）
-- CHAR(n): 定长，1 ~ 255 字符（2.0+）
-- BINARY: 二进制数据，最大 8MB（2.0+）

CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长有限制
    content    STRING                     -- 变长无限制（推荐）
);

-- 注意：1.0 版只有 STRING 类型
-- 2.0 新数据类型需要开启：set odps.sql.type.system.odps2 = true;

-- 类型转换
SELECT CAST('123' AS BIGINT);
SELECT CAST(123 AS STRING);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号也可以

-- 注意：STRING 内部采用 UTF-8 编码
-- 注意：没有 ENUM / SET 类型
-- 注意：没有 BLOB/CLOB/TEXT 的分级
-- 注意：不支持字符集和排序规则设置
-- 注意：STRING 作为分区键时有长度限制（256 字节）
