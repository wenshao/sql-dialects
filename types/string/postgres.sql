-- PostgreSQL: 字符串类型
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Character Types
--       https://www.postgresql.org/docs/current/datatype-character.html
--   [2] PostgreSQL Documentation - String Functions
--       https://www.postgresql.org/docs/current/functions-string.html

-- CHAR(n) / CHARACTER(n): 定长，尾部补空格
-- VARCHAR(n) / CHARACTER VARYING(n): 变长，有长度限制
-- VARCHAR / TEXT: 变长，无长度限制（两者性能完全一样）

CREATE TABLE examples (
    code    CHAR(10),                 -- 定长
    name    VARCHAR(255),             -- 变长，有限制
    content TEXT                      -- 变长，无限制（推荐）
);

-- PostgreSQL 中 VARCHAR 不指定长度 = TEXT = VARCHAR(无限)
-- 官方建议：大多数情况直接用 TEXT，性能没有区别
-- VARCHAR(n) 只在需要数据库层面限制长度时使用

-- 二进制数据
-- BYTEA: 变长二进制（类似 BLOB）
CREATE TABLE files (data BYTEA);

-- 排序规则
CREATE TABLE t (
    name TEXT COLLATE "en_US.utf8"
);

-- 12+: 非确定性排序（大小写/重音不敏感比较）
CREATE COLLATION ci (provider = icu, locale = 'und-u-ks-level2', deterministic = false);
CREATE TABLE t (name TEXT COLLATE ci);

-- ENUM 类型：需要先用 CREATE TYPE 定义
CREATE TYPE status_type AS ENUM ('active', 'inactive', 'deleted');
CREATE TABLE t (status status_type);

-- 注意：TEXT 没有大小限制（最大 1GB）
-- 注意：不区分 TINYTEXT/MEDIUMTEXT/LONGTEXT，只有 TEXT
