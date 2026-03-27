-- PostgreSQL: 字符串类型
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Character Types
--       https://www.postgresql.org/docs/current/datatype-character.html
--   [2] PostgreSQL Documentation - Collation Support
--       https://www.postgresql.org/docs/current/collation.html

-- ============================================================
-- 1. 字符类型: VARCHAR, TEXT, CHAR
-- ============================================================

-- CHAR(n):    定长，尾部补空格，比较时忽略尾部空格
-- VARCHAR(n): 变长，有长度限制
-- VARCHAR:    变长，无长度限制 = TEXT
-- TEXT:       变长，无长度限制（推荐!）

CREATE TABLE examples (
    code    CHAR(10),                 -- 定长（很少使用）
    name    VARCHAR(255),             -- 变长，有限制
    content TEXT                      -- 变长，无限制（推荐）
);

-- 设计分析: 为什么 PostgreSQL 推荐 TEXT
--   在 PostgreSQL 中 VARCHAR(n) 和 TEXT 的性能完全相同。
--   两者都使用 varlena 存储格式: 4字节头部 + 实际数据。
--   VARCHAR(n) 唯一的额外操作: INSERT/UPDATE 时检查长度 ≤ n。
--   因此: 除非需要数据库层面强制长度限制，否则直接用 TEXT。
--
-- 对比:
--   MySQL: VARCHAR(n) 是推荐方式，TEXT 有诸多限制:
--     - TEXT 不能有默认值（8.0.13之前）
--     - TEXT 不能完整索引（只能前缀索引）
--     - TEXT 列强制使用磁盘临时表
--   PostgreSQL 没有这些限制——TEXT 与 VARCHAR 完全等价。
--
--   MySQL 将 TEXT 分为 TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT（不同大小）
--   PostgreSQL 只有一个 TEXT（最大 1GB），内部用 TOAST 自动处理大值。

-- ============================================================
-- 2. TOAST: 大值的透明压缩和外部存储
-- ============================================================

-- TOAST (The Oversized-Attribute Storage Technique):
--   当 tuple 超过约 2KB 时，PostgreSQL 自动:
--   (1) 压缩大字段（LZ4 或 pglz）
--   (2) 如果仍然太大，将大字段移到 TOAST 表（外部存储）
--   (3) 原 tuple 中只存指针
--
-- TOAST 策略（可按列设置）:
--   PLAIN:    不压缩不外部存储（固定长度类型默认）
--   EXTENDED: 压缩+外部存储（变长类型默认，如 TEXT/JSONB）
--   EXTERNAL: 不压缩但外部存储（适合已压缩的数据如图片）
--   MAIN:     尽量压缩不外部存储

ALTER TABLE examples ALTER COLUMN content SET STORAGE EXTERNAL;

-- ============================================================
-- 3. 排序规则 (Collation)
-- ============================================================

-- 数据库级排序（创建数据库时设定）
-- CREATE DATABASE mydb WITH LC_COLLATE = 'en_US.UTF-8';

-- 列级排序
CREATE TABLE names (name TEXT COLLATE "en_US.utf8");

-- 表达式级排序
SELECT * FROM names ORDER BY name COLLATE "C";

-- 12+: ICU 排序（跨平台一致性）
CREATE COLLATION ci_collation (
    provider = icu, locale = 'und-u-ks-level2', deterministic = false
);
CREATE TABLE ci_table (name TEXT COLLATE ci_collation);
-- deterministic = false: 大小写不敏感比较

-- 排序规则对索引的影响:
--   索引使用列的默认排序规则。
--   如果查询用不同排序: WHERE name COLLATE "C" = 'test'，索引不生效!
--   解决: 创建使用目标排序规则的索引。

-- ============================================================
-- 4. ENUM 类型: 需要 CREATE TYPE
-- ============================================================

CREATE TYPE status_type AS ENUM ('active', 'inactive', 'deleted');
CREATE TABLE users (status status_type DEFAULT 'active');

-- ENUM 的内部实现:
--   ENUM 值存储为 4 字节 OID（不是字符串），比较用整数比较。
--   顺序由 CREATE TYPE 中的定义顺序决定。
--   添加值: ALTER TYPE status_type ADD VALUE 'suspended' AFTER 'active';
--   限制: 不能删除值，不能重排序（这是已知限制）。
--
-- 对比:
--   MySQL: ENUM('a','b','c')（内联定义，存储为整数1,2,3）
--   PostgreSQL: 需要先 CREATE TYPE 再使用（独立的类型对象）
--   替代方案: VARCHAR + CHECK 约束（更灵活，可添加/删除值）

-- ============================================================
-- 5. BYTEA: 二进制数据
-- ============================================================

CREATE TABLE files (data BYTEA);
INSERT INTO files VALUES (decode('48656c6c6f', 'hex'));
SELECT encode(data, 'base64') FROM files;

-- BYTEA 存储:
--   使用 hex 或 escape 格式输入/输出。
--   受 TOAST 管理（大 BYTEA 自动外部存储）。
--   最大 1GB。
--
-- 对比:
--   MySQL:      BLOB/MEDIUMBLOB/LONGBLOB（分级大小）
--   Oracle:     BLOB（最大 4GB × 块大小）
--   SQL Server: VARBINARY(MAX)（最大 2GB）

-- ============================================================
-- 6. 字符串运算符: || 和 ~
-- ============================================================

-- || 拼接（SQL 标准，NULL 传播）
SELECT 'hello' || ' ' || 'world';      -- 'hello world'
-- 注意: 'text' || NULL = NULL

-- ~ 正则匹配（PostgreSQL 独有运算符）
SELECT 'abc123' ~ '[0-9]+';             -- TRUE
SELECT 'abc123' ~* 'ABC';               -- TRUE（不区分大小写）

-- ============================================================
-- 7. 横向对比: 字符串类型差异
-- ============================================================

-- 1. TEXT 性能:
--   PostgreSQL: TEXT = VARCHAR 性能完全相同
--   MySQL:      TEXT 有诸多限制（不能默认值、不能完整索引、强制磁盘临时表）
--
-- 2. 大小限制:
--   PostgreSQL: TEXT 最大 1GB，TOAST 自动管理
--   MySQL:      TINYTEXT(255) / TEXT(64K) / MEDIUMTEXT(16M) / LONGTEXT(4G)
--   Oracle:     CLOB（最大 4GB × 块大小）
--
-- 3. 字符编码:
--   PostgreSQL: UTF-8 就是真正的 UTF-8（建库时设定，整个库统一）
--   MySQL:      utf8 = 3字节（假UTF-8!），utf8mb4 = 真 UTF-8
--   SQL Server: VARCHAR(UTF-8, 2019+) 或 NVARCHAR(UTF-16)
--
-- 4. 大小写敏感:
--   PostgreSQL: 默认大小写敏感（标识符折叠为小写）
--   MySQL:      默认大小写不敏感（取决于排序规则）
--   SQL Server: 默认大小写不敏感
--   Oracle:     默认大小写敏感

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) VARCHAR(n) 的长度检查应该是可选的:
--     PostgreSQL 的设计证明: 统一的变长字符串类型（TEXT）
--     比分级的 TEXT/MEDIUMTEXT/LONGTEXT 更简洁。
--     TOAST 机制让用户不需要关心存储大小。
--
-- (2) TOAST 是大值存储的优雅方案:
--     透明压缩+外部存储，用户无感知。
--     对比 MySQL 的 TEXT 类型限制（不能索引等），PostgreSQL 的方案更统一。
--
-- (3) 排序规则的 ICU 支持 (12+) 保证了跨平台一致性:
--     libc 排序在不同 OS 上可能行为不同。
--     ICU 提供了确定性的排序行为。
--
-- (4) 字符编码应该统一为 UTF-8:
--     MySQL 的 utf8 vs utf8mb4 历史教训: 不要使用 3 字节 UTF-8 子集。
--     PostgreSQL 从一开始就正确处理了 UTF-8。

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- PostgreSQL 全版本: CHAR, VARCHAR, TEXT, BYTEA
-- PostgreSQL 9.1:   ENUM ADD VALUE
-- PostgreSQL 10:    ICU collation provider
-- PostgreSQL 12:    非确定性排序（deterministic = false，大小写不敏感）
-- PostgreSQL 14:    TOAST 支持 LZ4 压缩（default_toast_compression）
-- PostgreSQL 16:    ENUM 值重命名 (ALTER TYPE RENAME VALUE)
