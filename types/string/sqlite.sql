-- SQLite: 字符串类型
--
-- 参考资料:
--   [1] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html
--   [2] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html

-- SQLite 只有一个文本类型：TEXT
-- 声明 VARCHAR(255)、CHAR(10)、CLOB 等都会映射为 TEXT 亲和性
-- 长度限制不强制执行

CREATE TABLE examples (
    code    TEXT,                     -- 所有字符串都是 TEXT
    name    TEXT,
    content TEXT
);

-- VARCHAR(n) 可以写但不强制限制
CREATE TABLE t (name VARCHAR(255));  -- 合法，但长度不受限

-- 二进制数据：BLOB
CREATE TABLE files (data BLOB);

-- 排序规则
-- 内置: BINARY（默认）、NOCASE（大小写不敏感）、RTRIM（忽略尾部空格）
SELECT * FROM users WHERE username = 'Alice' COLLATE NOCASE;

CREATE TABLE t (name TEXT COLLATE NOCASE);

-- 注意：TEXT 没有大小限制（受 SQLITE_MAX_LENGTH 控制，默认 1GB）
-- 注意：类型名只影响亲和性，不强制类型检查
-- 注意：没有 ENUM 类型，可以用 CHECK 约束模拟
CREATE TABLE t (status TEXT CHECK (status IN ('active', 'inactive', 'deleted')));
