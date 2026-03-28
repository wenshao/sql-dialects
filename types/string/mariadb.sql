-- MariaDB: 字符串类型
-- 与 MySQL 基本一致, JSON 存储差异显著
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - String Data Types
--       https://mariadb.com/kb/en/string-data-types/

-- ============================================================
-- 1. 基本字符串类型
-- ============================================================
-- CHAR(n):    定长, 0-255 字符, 右补空格
-- VARCHAR(n): 变长, 0-65535 字符, 1-2 字节长度前缀
-- TINYTEXT:   变长, 最大 255 字节
-- TEXT:       变长, 最大 65535 字节
-- MEDIUMTEXT: 变长, 最大 16MB
-- LONGTEXT:   变长, 最大 4GB
CREATE TABLE string_demo (
    code    CHAR(10),
    name    VARCHAR(255),
    bio     TEXT,
    content LONGTEXT
);

-- ============================================================
-- 2. 字符集与排序规则
-- ============================================================
CREATE TABLE intl_data (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);
-- MariaDB 的 utf8 和 utf8mb4 行为与 MySQL 相同:
--   utf8 = 3 字节 UTF-8 (不完整!)
--   utf8mb4 = 4 字节 UTF-8 (推荐)
-- MariaDB 10.6+: 默认字符集改为 utf8mb3 (utf8 的显式别名)

-- ============================================================
-- 3. BINARY / VARBINARY / BLOB
-- ============================================================
CREATE TABLE binary_demo (
    hash     BINARY(32),
    data     VARBINARY(1000),
    content  BLOB,
    large    LONGBLOB
);

-- ============================================================
-- 4. ENUM 和 SET
-- ============================================================
CREATE TABLE enum_demo (
    status  ENUM('active', 'inactive', 'suspended'),
    roles   SET('admin', 'editor', 'viewer')
);
-- ENUM: 内部存为整数, 最多 65535 个值
-- SET: 位图存储, 最多 64 个值
-- 陷阱: ALTER TABLE 添加 ENUM 值需要重建表 (除非添加到末尾)

-- ============================================================
-- 5. UUID 函数 (不是类型)
-- ============================================================
SELECT UUID();     -- 生成 UUID v1 (基于时间+MAC)
-- MariaDB 10.7+: UUID 列类型 (底层 BINARY(16))
CREATE TABLE uuid_demo (
    id UUID DEFAULT UUID() PRIMARY KEY,
    name VARCHAR(100)
);

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- MariaDB 10.7+ 的 UUID 类型是重要创新:
--   MySQL 没有原生 UUID 类型, 需要 BINARY(16) + 函数
--   PostgreSQL 有原生 UUID 类型 (推荐配合 gen_random_uuid())
--   UUID 类型让存储更紧凑 (16B vs 36B 字符串) 且比较更快
-- TEXT 分级 (TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT) 是 MySQL/MariaDB 特色
-- 现代引擎趋势: 统一的 STRING/TEXT 类型, 内部自动管理存储
