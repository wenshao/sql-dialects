-- DamengDB (达梦): 字符串类型
-- Oracle compatible types.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- CHAR(n): 定长，最大 32767 字节
-- VARCHAR(n) / VARCHAR2(n): 变长，最大 32767 字节
-- TEXT: 变长文本，最大 2GB
-- CLOB: 大文本，最大 2GB
-- NCHAR(n): 国际字符定长
-- NVARCHAR(n): 国际字符变长

CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    name2      VARCHAR2(255),     -- Oracle 兼容
    content    TEXT,
    big_data   CLOB
);

-- 二进制类型
-- BINARY(n): 定长二进制
-- VARBINARY(n): 变长二进制
-- BLOB: 二进制大对象，最大 2GB
-- RAW(n): Oracle 兼容的原始二进制

CREATE TABLE binary_examples (
    hash_val   BINARY(32),
    raw_data   VARBINARY(1024),
    file_data  BLOB
);

-- 字符集
-- 达梦在数据库级别设置字符集（创建数据库时指定）
-- 支持 UTF-8、GBK、GB18030 等

-- 注意事项：
-- VARCHAR 和 VARCHAR2 功能相同（Oracle 兼容）
-- CLOB 用于大文本存储
-- 支持 NCHAR/NVARCHAR 国际字符类型
-- 大小写敏感性可在初始化时配置
-- MySQL 兼容模式下支持 ENUM 和 SET 类型
