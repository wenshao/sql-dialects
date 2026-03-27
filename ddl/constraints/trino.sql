-- Trino (formerly PrestoSQL): 约束
--
-- 参考资料:
--   [1] Trino - CREATE TABLE
--       https://trino.io/docs/current/sql/create-table.html
--   [2] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html

-- Trino 本身不管理约束，约束能力取决于底层 Connector

-- ============================================================
-- NOT NULL（部分 Connector 支持）
-- ============================================================

-- Iceberg Connector
CREATE TABLE iceberg.mydb.users (
    id       BIGINT NOT NULL,
    username VARCHAR NOT NULL,
    email    VARCHAR
);

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- Hive Connector: NOT NULL 取决于底层 Hive 表定义
-- Memory Connector: 支持 NOT NULL

-- ============================================================
-- 不支持的约束
-- ============================================================

-- PRIMARY KEY: 不支持
-- UNIQUE: 不支持
-- FOREIGN KEY: 不支持
-- CHECK: 不支持
-- DEFAULT: 不支持（部分 Connector 通过底层引擎支持）
-- EXCLUDE: 不支持

-- ============================================================
-- Connector 特有的约束行为
-- ============================================================

-- Hive Connector:
-- 约束在 Hive 元数据中定义（DISABLE NOVALIDATE）
-- Trino 不读取也不执行这些约束
-- Hive ACID 表的 NOT NULL 可能被底层 Hive 执行

-- Iceberg Connector:
-- 支持 NOT NULL 约束
-- 支持列的 required/optional 属性
-- 不支持其他约束

-- Delta Lake Connector:
-- 支持 NOT NULL 约束
-- 支持 CHECK 约束（由 Delta Lake 定义和执行）
-- Trino 读取数据时不执行 Delta 的 CHECK 约束

-- PostgreSQL / MySQL Connector:
-- 底层数据库的约束会在写入时由底层数据库执行
-- Trino 通过 Connector 传递写入请求，约束由底层强制执行

-- ============================================================
-- 数据验证替代方案
-- ============================================================

-- 使用查询验证数据完整性
SELECT id, COUNT(*) FROM users GROUP BY id HAVING COUNT(*) > 1;

-- 使用 CASE WHEN 做数据质量检查
SELECT *
FROM users
WHERE email NOT LIKE '%@%.%'
   OR username IS NULL;

-- 使用 INSERT INTO ... SELECT 时添加验证
INSERT INTO users_clean
SELECT * FROM users_raw
WHERE id IS NOT NULL AND email LIKE '%@%.%';

-- 注意：Trino 是查询引擎，不直接管理数据完整性
-- 注意：约束由底层存储系统（Hive/Iceberg/Delta/RDBMS）管理
-- 注意：写入 RDBMS Connector 时，底层数据库的约束会生效
-- 注意：写入文件格式 Connector 时，基本没有约束保证
