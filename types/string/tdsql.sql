-- TDSQL: 字符串类型
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- CHAR(n): 定长，最大 255 字符
-- VARCHAR(n): 变长，最大 65535 字节
-- TINYTEXT: 最大 255 字节
-- TEXT: 最大 65535 字节
-- MEDIUMTEXT: 最大 16MB
-- LONGTEXT: 最大 4GB

CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT,
    big_data   LONGTEXT
);

-- 二进制字符串
-- BINARY(n) / VARBINARY(n)
-- TINYBLOB / BLOB / MEDIUMBLOB / LONGBLOB

-- 字符集和排序规则
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);

-- ENUM
CREATE TABLE t (status ENUM('active', 'inactive', 'deleted'));

-- SET
CREATE TABLE t (tags SET('tag1', 'tag2', 'tag3'));

-- 注意事项：
-- 字符串类型与 MySQL 完全兼容
-- shardkey 列建议使用 VARCHAR 或 INT 类型
-- TEXT/BLOB 类型不能作为 shardkey
-- 默认字符集 utf8mb4
