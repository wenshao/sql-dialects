-- Oracle: 字符串类型
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Character Data Types
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html
--   [2] Oracle SQL Language Reference - Character Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html

-- CHAR(n): 定长，最大 2000 字节
-- VARCHAR2(n): 变长，最大 4000 字节（标准），32767 字节（MAX_STRING_SIZE=EXTENDED）
-- NCHAR(n): 定长 Unicode
-- NVARCHAR2(n): 变长 Unicode
-- CLOB: 大文本，最大 (4GB - 1) * 数据库块大小
-- NCLOB: Unicode 大文本

CREATE TABLE examples (
    code    CHAR(10),                 -- 定长
    name    VARCHAR2(255),            -- 变长（推荐，Oracle 特有）
    content CLOB                      -- 大文本
);

-- VARCHAR2 vs VARCHAR:
-- Oracle 推荐用 VARCHAR2
-- VARCHAR 是保留字，Oracle 不建议使用（可能未来改变语义）

-- 12c+: VARCHAR2 最大长度扩展到 32767 字节
-- ALTER SYSTEM SET MAX_STRING_SIZE = EXTENDED;

-- 字节 vs 字符语义
-- VARCHAR2(100 BYTE): 100 字节
-- VARCHAR2(100 CHAR): 100 字符（推荐）
-- 默认取决于 NLS_LENGTH_SEMANTICS 参数

-- 排序规则
-- 由 NLS_SORT 和 NLS_COMP 控制
ALTER SESSION SET NLS_SORT = 'BINARY_CI';         -- 大小写不敏感
ALTER SESSION SET NLS_COMP = 'LINGUISTIC';

-- 12c R2+: 列级排序规则
CREATE TABLE t (name VARCHAR2(100) COLLATE BINARY_CI);

-- 注意：空字符串 '' 等同于 NULL（Oracle 特有行为！）
-- SELECT * FROM t WHERE name IS NULL; -- 也会匹配 name = '' 的行
