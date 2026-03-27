-- openGauss/GaussDB: 字符串类型
-- PostgreSQL compatible with extensions.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- CHARACTER(n) / CHAR(n): 定长，尾部补空格
-- CHARACTER VARYING(n) / VARCHAR(n): 变长
-- TEXT: 无长度限制的变长文本
-- NCHAR(n): 国际字符定长
-- NVARCHAR2(n): 国际字符变长（openGauss 扩展）
-- CLOB: 大文本（Oracle 兼容）

CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT,
    big_data   CLOB              -- openGauss 扩展，Oracle 兼容
);

-- 二进制字符串
-- BYTEA: 变长二进制
-- BLOB: 二进制大对象（openGauss 扩展）

-- 字符集
-- openGauss 在数据库级别设置字符集，不支持列级别字符集
-- 创建数据库时指定: CREATE DATABASE mydb ENCODING 'UTF8';

-- 排序规则
CREATE TABLE t (
    name VARCHAR(100) COLLATE "en_US.utf8"
);

-- 注意事项：
-- 支持 CLOB 和 BLOB（Oracle 兼容扩展）
-- 支持 NVARCHAR2（Oracle 兼容）
-- 字符集在数据库级别设置
-- TEXT 类型无长度限制
-- 不支持 ENUM 和 SET 类型（与 MySQL 的差异）
