-- DamengDB (达梦): 字符串类型
-- Oracle-compatible database with native Chinese support.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html
--   [3] DamengDB Migration Guide (Oracle to DamengDB)
--       https://eco.dameng.com/document/dm/zh-cn/start/oracle-migration.html

-- ============================================================
-- 1. 字符串类型一览
-- ============================================================
CREATE TABLE string_examples (
    -- 定长: 右侧补空格到 n 个字节（注意: n 是字节数，不是字符数）
    country_code  CHAR(2)           NOT NULL,    -- 'US', 'CN', 'JP'
    -- 变长: 最大 32767 字节（或 8188 字符，取决于 PAGE 大小）
    username      VARCHAR(64)       NOT NULL,
    email         VARCHAR(255)      NOT NULL,
    -- VARCHAR2: Oracle 兼容，功能与 VARCHAR 相同
    name2         VARCHAR2(255),
    -- TEXT: 变长文本，最大 2GB-1
    content       TEXT,
    -- CLOB: 大文本对象，最大 2GB-1（Oracle 兼容）
    big_data      CLOB,
    -- 国际字符类型
    cname         NCHAR(64),                     -- 国家字符定长
    ename         NVARCHAR(128),                 -- 国家字符变长
    ename2        NVARCHAR2(128)                 -- Oracle 兼容国家字符变长
);

-- ============================================================
-- 2. 核心类型详解
-- ============================================================

-- 2.1 CHAR(n)
-- 定长字符串，n 为字节长度（非字符数！这是与 PostgreSQL 的关键差异）
-- 最大 32767 字节
-- 存储时右侧填充空格至 n 字节
-- 比较时按 PAD SPACE 语义: 'abc   ' = 'abc'
-- 注意: UTF-8 下一个中文字符占 3 字节，CHAR(10) 只能存 3 个中文字 + 1 字节

-- 2.2 VARCHAR(n) / VARCHAR2(n)
-- 变长字符串，n 为字节长度（同样注意是字节数）
-- VARCHAR 和 VARCHAR2 功能完全相同（VARCHAR2 是 Oracle 兼容别名）
-- 最大 32767 字节（受数据库 PAGE 大小影响，默认 PAGE=8K 时上限更低）
-- VARCHAR2 的语义更贴近 Oracle:
--   Oracle 中 VARCHAR2 保证未来版本不改变行为
--   达梦中 VARCHAR2 = VARCHAR，无实质区别

-- 2.3 TEXT
-- 变长大文本，最大 2GB-1 字节
-- 不需要指定长度
-- 适合存储文章、日志等大段文本
-- 与 VARCHAR 的区别: TEXT 不计入行长度限制，单独存储

-- 2.4 CLOB
-- 大文本对象，最大 2GB-1 字节（Oracle 兼容）
-- 功能与 TEXT 类似，但提供 Oracle 兼容的 LOB 操作接口
-- 支持 DBMS_LOB 包函数: READ, WRITE, APPEND, SUBSTR 等
-- Oracle 迁移场景推荐使用 CLOB 替代 Oracle CLOB

-- 2.5 NCHAR(n) / NVARCHAR(n) / NVARCHAR2(n)
-- 国家字符集类型，使用 Unicode 编码
-- NCHAR: 定长，最大 32767 字节
-- NVARCHAR / NVARCHAR2: 变长，最大 32767 字节
-- n 为字符数（非字节数）— 这与 CHAR/VARCHAR 的 n（字节数）不同！
-- NVARCHAR2 是 Oracle 兼容写法，功能与 NVARCHAR 相同
-- 推荐用于存储多语言混合数据

-- ============================================================
-- 3. 二进制字符串类型
-- ============================================================

-- BINARY(n):    定长二进制，右侧补 0x00，最大 32767 字节
-- VARBINARY(n): 变长二进制，最大 32767 字节
-- BLOB:         二进制大对象，最大 2GB-1
-- RAW(n):       Oracle 兼容的定长二进制，最大 32767 字节
-- IMAGE:        图像大对象（兼容旧版本，不推荐新项目使用）

CREATE TABLE binary_examples (
    hash_val   BINARY(32),                   -- SHA-256 等哈希值
    raw_data   VARBINARY(1024),              -- 变长二进制
    oracle_raw RAW(16),                      -- Oracle 兼容（如 UUID 二进制）
    file_data  BLOB                          -- 大文件存储
);

-- ============================================================
-- 4. 字符集与编码
-- ============================================================

-- 达梦在数据库初始化时设置字符集，创建后不可更改
-- 初始化参数: UNICODE_FLAG = 1（启用 Unicode 模式，推荐）
--
-- 支持的字符集:
--   UTF-8:      1-4 字节/字符（推荐，全 Unicode 支持）
--   GBK:        1-2 字节/字符（中文常用）
--   GB18030:    1-4 字节/字符（中国国家标准，支持所有中文字符）
--   EUC-KR:     韩文编码
--   ISO-8859-1: 西欧语言
--
-- 达梦字符集的特殊考量:
--   1. CHAR/VARCHAR 的 n 是字节数，不是字符数
--      VARCHAR(100) 在 UTF-8 下最多存 33 个中文字符（100/3=33.3）
--      这与 PostgreSQL/MySQL 的 VARCHAR(n) 中 n 为字符数不同
--   2. NVARCHAR 的 n 是字符数，不受字节限制
--      NVARCHAR(100) 在任何编码下都能存 100 个字符
--   3. 数据库页面大小影响 VARCHAR 最大长度
--      PAGE=4K: VARCHAR 最大约 3900 字节
--      PAGE=8K: VARCHAR 最大约 7900 字节
--      PAGE=16K: VARCHAR 最大约 16000 字节
--      PAGE=32K: VARCHAR 最大约 32700 字节

-- ============================================================
-- 5. 大小写敏感性
-- ============================================================

-- 达梦的大小写敏感性在初始化时配置（CASE_SENSITIVE 参数）
-- CASE_SENSITIVE = 1（默认）: 大小写敏感
--   'ABC' != 'abc'
--   对象名（表名、列名）如果不加引号则自动转为大写
-- CASE_SENSITIVE = 0: 大小写不敏感
--   'ABC' = 'abc'
--   对象名保持原样
--
-- 注意: 此设置在数据库创建后不可更改！
-- Oracle 迁移场景建议设置 CASE_SENSITIVE = 0（与 Oracle 默认行为一致）

-- ============================================================
-- 6. 字符串函数（达梦常用）
-- ============================================================

-- 长度函数
SELECT LENGTH('你好世界');              -- 4（字符数）
SELECT LENGTHB('你好世界');             -- 12（UTF-8 字节数: 4×3=12）
SELECT BIT_LENGTH('你好世界');          -- 96（位长度）

-- 拼接
SELECT CONCAT('Hello', ' ', 'World');  -- 'Hello World'
SELECT 'Hello' || ' ' || 'World';      -- 'Hello World'（Oracle 风格）

-- 截取
SELECT SUBSTR('Hello World', 1, 5);    -- 'Hello'（Oracle 风格）
SELECT SUBSTRING('Hello World', 1, 5); -- 'Hello'（SQL 标准）

-- 查找
SELECT INSTR('Hello World', 'World');  -- 7（Oracle 风格）
SELECT POSITION('World' IN 'Hello World'); -- 7（SQL 标准）

-- 填充与裁剪
SELECT LPAD('abc', 10, '*');           -- '*******abc'
SELECT RPAD('abc', 10, '*');           -- 'abc*******'
SELECT TRIM('  hello  ');              -- 'hello'
SELECT LTRIM('  hello');               -- 'hello'

-- ============================================================
-- 7. 与 Oracle 的兼容性对比
-- ============================================================

-- 类型对比:
--   类型          Oracle        达梦           说明
--   CHAR(n)       支持          支持           达梦 n 是字节，Oracle n 也是字节
--   VARCHAR2(n)   支持          支持           完全兼容
--   NVARCHAR2(n)  支持          支持           达梦 n 是字符数
--   NCHAR(n)      支持          支持           达梦 n 是字符数
--   CLOB          支持          支持           功能兼容
--   BLOB          支持          支持           功能兼容
--   RAW(n)        支持          支持           功能兼容
--   LONG          支持          不支持         用 CLOB 替代
--   VARCHAR(n)    不推荐        支持           等同 VARCHAR2
--
-- Oracle 迁移到达梦的常见调整:
--   1. LONG → CLOB（达梦不支持 LONG）
--   2. VARCHAR2 长度注意字节/字符差异
--   3. 使用 DBMS_LOB 包操作 CLOB（达梦兼容）

-- ============================================================
-- 8. 注意事项与最佳实践
-- ============================================================

-- 1. VARCHAR 和 VARCHAR2 功能相同，Oracle 迁移用 VARCHAR2，新项目均可
-- 2. CHAR/VARCHAR 的 n 是字节数（不是字符数！），设计表时需考虑编码
-- 3. NVARCHAR/NVARCHAR2 的 n 是字符数，多语言场景推荐使用
-- 4. CLOB 用于大文本存储，提供 Oracle 兼容的 DBMS_LOB 操作
-- 5. 字符集在数据库初始化时设置，不可更改，建议 UTF-8
-- 6. 大小写敏感性在初始化时配置，Oracle 迁移建议设为不敏感
-- 7. PAGE 大小影响 VARCHAR 最大长度，大字段场景建议 PAGE=32K
-- 8. 支持 RAW 类型存储二进制数据，Oracle 兼容迁移可直接使用
