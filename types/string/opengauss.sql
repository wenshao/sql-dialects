-- openGauss/GaussDB: 字符串类型
-- PostgreSQL compatible with Oracle-compatible extensions.
--
-- 参考资料:
--   [1] openGauss SQL Reference - Data Types
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html
--   [3] openGauss Source Code - data type definitions
--       https://gitee.com/opengauss/openGauss-server

-- ============================================================
-- 1. 字符串类型一览
-- ============================================================
CREATE TABLE string_examples (
    -- 定长: 右侧补空格到 n 个字符，读取时按 PAD SPACE 语义处理
    country_code  CHAR(2)           NOT NULL,    -- 'US', 'CN', 'JP'
    -- 变长: 最大约 1GB（受 toast 表溢出机制支持）
    username      VARCHAR(64)       NOT NULL,
    email         VARCHAR(255)      NOT NULL,
    -- TEXT: 无长度限制的变长文本，与 PostgreSQL 行为一致
    bio           TEXT,
    -- NVARCHAR2: Oracle 兼容的国际字符变长类型
    cname         NVARCHAR2(128),
    -- CLOB: 大文本对象，Oracle 兼容（openGauss 扩展）
    content       CLOB
);

-- ============================================================
-- 2. 核心类型详解
-- ============================================================

-- 2.1 CHAR(n) / CHARACTER(n)
-- 定长字符串，n 为字符数（非字节数），最大 10485760 字符
-- 存储时右侧填充空格至 n 个字符
-- 比较时按 PAD SPACE 语义: 'abc   ' = 'abc'
-- UTF-8 下实际存储大小 = n × 最大字节/字符（如 UTF-8 每字符最多 4 字节）

-- 2.2 VARCHAR(n) / CHARACTER VARYING(n)
-- 变长字符串，n 为字符数，最大约 10485760 字符
-- 不自动填充空格，存储实际内容
-- openGauss 继承 PostgreSQL 的 TOAST 机制:
--   行内存储: 数据量小时直接存储在主表行内
--   TOAST 溢出: 数据超过阈值时自动压缩/移动到 TOAST 表
--   压缩策略: 默认使用 LZ4/PGLZ 压缩，超长数据透明处理

-- 2.3 TEXT
-- 无显式长度限制的变长文本（实际受 TOAST 机制限制，最大约 1GB）
-- 与 VARCHAR 无本质区别（PostgreSQL 的设计哲学）
-- 推荐用于不限长度的文本字段
-- 内部存储机制与 VARCHAR 完全相同，仅元数据中不记录长度约束

-- 2.4 NVARCHAR2(n) — openGauss 扩展（Oracle 兼容）
-- 国际字符变长类型，n 为字符数
-- 与 Oracle 的 NVARCHAR2 行为对齐
-- 使用数据库的国家字符集编码（通常为 UTF-8/AL16UTF16）
-- 适合存储多语言文本，如中文、日文、韩文混合数据

-- 2.5 CLOB — openGauss 扩展（Oracle 兼容）
-- 大文本对象，最大约 1GB
-- 与 TEXT 的区别: CLOB 更强调 Oracle 兼容语义
-- 支持 Oracle 风格的 DBMS_LOB 包操作
-- 内部实现复用 PostgreSQL 的 TOAST 机制

-- ============================================================
-- 3. 二进制字符串类型
-- ============================================================

-- BYTEA: 变长二进制数据，PostgreSQL 原生类型
--   支持两种输出格式: hex（默认）和 escape
--   最大约 1GB（受 TOAST 限制）
--   插入时使用 '\x' 前缀: INSERT INTO t VALUES ('\x48656C6C6F')

-- BLOB: 二进制大对象，openGauss 扩展（Oracle 兼容）
--   最大约 1GB
--   与 BYTEA 功能类似但提供 Oracle 兼容的 API

-- RAW(n): Oracle 兼容的定长二进制类型（部分兼容模式）
--   n 为字节数，最大 32767

CREATE TABLE binary_examples (
    hash_val   BYTEA,                          -- SHA-256 等哈希值
    file_data  BLOB                            -- 大文件存储
);

-- ============================================================
-- 4. 字符集与编码
-- ============================================================

-- openGauss 在数据库级别设置字符集，不支持列级别字符集
-- 创建数据库时指定:
--   CREATE DATABASE mydb ENCODING 'UTF8' LC_COLLATE='zh_CN.UTF-8' LC_CTYPE='zh_CN.UTF-8';
-- 支持的编码: UTF-8, GBK, GB18030, SQL_ASCII, LATIN1 等
--
-- 编码对存储的影响:
--   UTF-8:    1-4 字节/字符（推荐，全 Unicode 支持）
--   GBK:      1-2 字节/字符（中文常用，不支持 CJK 扩展 B 及以上）
--   GB18030:  1-4 字节/字符（中国国家标准，强制支持）
--
-- 对比 PostgreSQL:
--   openGauss 额外支持 GBK、GB18030 等中文编码
--   默认编码建议 UTF-8，除非有明确的遗留系统兼容需求

-- ============================================================
-- 5. 排序规则（COLLATION）
-- ============================================================

-- openGauss 继承 PostgreSQL 的 COLLATION 体系
-- 支持 ICU collation 和操作系统 locale

-- 列级 COLLATION
CREATE TABLE collation_demo (
    val_ci  VARCHAR(64) COLLATE "en_US.utf8",    -- 按英语排序
    val_zh  VARCHAR(64) COLLATE "zh_CN.utf8"     -- 按中文拼音排序
);

-- 表达式级 COLLATION
SELECT * FROM collation_demo ORDER BY val_zh COLLATE "zh_CN.utf8";

-- 排序规则对索引的影响:
--   B-tree 索引使用列的 COLLATION 决定键的排列顺序
--   不同 COLLATION 的列做 JOIN 时可能隐式转换，导致索引失效
--   建议: 需要精确匹配时使用 COLLATE "C"（二进制比较，最快）

-- ============================================================
-- 6. 字符串函数（openGauss 常用）
-- ============================================================

-- 长度函数
SELECT LENGTH('你好世界');              -- 4（字符数）
SELECT LENGTHB('你好世界');             -- 12（UTF-8 字节数: 4×3=12）
SELECT OCTET_LENGTH('你好世界');        -- 12（字节数）

-- 拼接
SELECT CONCAT('Hello', ' ', 'World');  -- 'Hello World'
SELECT 'Hello' || ' ' || 'World';      -- 'Hello World'（PostgreSQL 风格）

-- 截取与查找
SELECT SUBSTRING('Hello World', 1, 5); -- 'Hello'
SELECT POSITION('World' IN 'Hello World'); -- 7
SELECT LEFT('Hello', 3);               -- 'Hel'
SELECT RIGHT('Hello', 3);              -- 'llo'

-- 模式匹配
SELECT * FROM t WHERE name LIKE '%测试%';
SELECT * FROM t WHERE name ~ '^[A-Z]+';        -- 正则匹配（PostgreSQL 风格）
SELECT * FROM t WHERE name SIMILAR TO '[A-Z]+'; -- SQL 标准正则

-- ============================================================
-- 7. 与 PostgreSQL / Oracle 的横向对比
-- ============================================================

-- 类型对比:
--   类型          PostgreSQL    openGauss      Oracle
--   CHAR(n)       支持          支持           支持
--   VARCHAR(n)    支持          支持           支持（VARCHAR2）
--   TEXT          支持          支持           无（用 CLOB）
--   CLOB          无（用 TEXT）  支持（扩展）    支持
--   NVARCHAR2     无            支持（扩展）    支持
--   BLOB          无（用 BYTEA） 支持（扩展）    支持
--   RAW           无            部分（扩展）    支持
--
-- openGauss 的定位:
--   以 PostgreSQL 内核为基础，通过扩展类型和函数实现 Oracle 兼容
--   TEXT 是日常首选（与 PostgreSQL 一致）
--   CLOB/NVARCHAR2 用于 Oracle 迁移场景
--   BLOB/RAW 用于 Oracle 二进制兼容场景

-- ============================================================
-- 8. 注意事项与最佳实践
-- ============================================================

-- 1. 不支持 MySQL 的 ENUM 和 SET 类型（可使用 CHECK 约束替代）
-- 2. TEXT 类型无长度限制但内部使用 TOAST 溢出机制，超大文本性能可能下降
-- 3. NVARCHAR2 是 openGauss 扩展，迁移到原生 PostgreSQL 需改为 VARCHAR/TEXT
-- 4. CLOB 与 TEXT 内部机制相同，Oracle 迁移场景用 CLOB，新项目用 TEXT
-- 5. 字符集在 CREATE DATABASE 时确定，之后不可更改
-- 6. 建议使用 UTF-8 编码以获得完整的 Unicode 支持
-- 7. 排序规则可按列/表达式设置，注意 JOIN 时的 COLLATION 一致性
