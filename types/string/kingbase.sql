-- KingbaseES (人大金仓): 字符串类型
-- PostgreSQL compatible types.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- CHARACTER(n) / CHAR(n): 定长，尾部补空格
-- CHARACTER VARYING(n) / VARCHAR(n): 变长
-- TEXT: 无长度限制的变长文本
-- VARCHAR2(n): Oracle 兼容模式

CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT
);

-- 二进制字符串
-- BYTEA: 变长二进制

-- 字符集
-- 在数据库级别设置字符集
-- CREATE DATABASE mydb ENCODING 'UTF8';

-- 排序规则
CREATE TABLE t (
    name VARCHAR(100) COLLATE "zh_CN.utf8"
);

-- Oracle 兼容模式下的类型
-- VARCHAR2(n): Oracle 兼容
-- NCHAR(n): 国际字符定长
-- NVARCHAR2(n): 国际字符变长
-- CLOB: 大文本

-- 注意事项：
-- 字符串类型与 PostgreSQL 完全兼容
-- Oracle 兼容模式下支持 VARCHAR2、CLOB 等
-- TEXT 类型无长度限制
-- 字符集在数据库级别设置
-- 支持多种字符集（UTF-8、GBK 等）
