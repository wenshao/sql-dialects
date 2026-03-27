-- MySQL: 字符串类型
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - String Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/string-types.html
--   [2] MySQL 8.0 Reference Manual - Character Sets
--       https://dev.mysql.com/doc/refman/8.0/en/charset.html

-- CHAR(n): 定长，最大 255 字符，尾部补空格
-- VARCHAR(n): 变长，最大 65535 字节（实际受行大小限制）
-- TINYTEXT: 最大 255 字节
-- TEXT: 最大 65535 字节（约 64KB）
-- MEDIUMTEXT: 最大 16MB
-- LONGTEXT: 最大 4GB

CREATE TABLE examples (
    code       CHAR(10),              -- 定长，适合固定长度（如国家代码）
    name       VARCHAR(255),          -- 变长，最常用
    content    TEXT,                   -- 长文本
    big_data   LONGTEXT               -- 超大文本
);

-- 二进制字符串
-- BINARY(n): 定长二进制
-- VARBINARY(n): 变长二进制
-- TINYBLOB / BLOB / MEDIUMBLOB / LONGBLOB

-- 字符集和排序规则
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);

-- 查看字符集
SHOW CHARACTER SET;
SHOW COLLATION WHERE Charset = 'utf8mb4';

-- 8.0+: 默认字符集改为 utf8mb4（5.7 默认是 latin1）
-- 8.0+: 默认排序规则改为 utf8mb4_0900_ai_ci

-- ENUM（枚举）
CREATE TABLE t (status ENUM('active', 'inactive', 'deleted'));

-- SET（集合，可多选）
CREATE TABLE t (tags SET('tag1', 'tag2', 'tag3'));

-- 注意：VARCHAR(n) 中 n 是字符数，不是字节数（utf8mb4 下一个字符最多 4 字节）
