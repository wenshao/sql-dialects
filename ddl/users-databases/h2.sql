-- H2 Database: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] H2 Documentation - CREATE SCHEMA
--       https://h2database.com/html/commands.html#create_schema
--   [2] H2 Documentation - CREATE USER
--       https://h2database.com/html/commands.html#create_user

-- ============================================================
-- H2 特性：
-- - 嵌入式 Java 数据库（也支持服务器模式）
-- - 数据库 = 一个文件（或内存）
-- - 支持 schema 和用户管理
-- - 命名层级: database > schema > object
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

-- 通过 JDBC URL 创建（非 SQL）
-- 嵌入式：jdbc:h2:~/myapp
-- 内存：jdbc:h2:mem:myapp
-- 服务器：jdbc:h2:tcp://localhost/~/myapp

-- 关闭数据库
SHUTDOWN;
SHUTDOWN COMPACT;                               -- 压缩后关闭
SHUTDOWN IMMEDIATELY;                           -- 立即关闭

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;

-- 删除模式
DROP SCHEMA myschema;
DROP SCHEMA IF EXISTS myschema CASCADE;

-- 设置当前模式
SET SCHEMA myschema;

-- 默认模式: PUBLIC

-- ============================================================
-- 3. 用户管理
-- ============================================================

CREATE USER myuser PASSWORD 'secret123';
CREATE USER IF NOT EXISTS myuser PASSWORD 'secret123';

CREATE USER myuser PASSWORD 'secret123' ADMIN;  -- 管理员用户

-- 修改用户
ALTER USER myuser SET PASSWORD 'newsecret';
ALTER USER myuser RENAME TO newuser;
ALTER USER myuser ADMIN TRUE;                   -- 设为管理员
ALTER USER myuser ADMIN FALSE;

-- 删除用户
DROP USER myuser;
DROP USER IF EXISTS myuser;

-- ============================================================
-- 4. 权限管理
-- ============================================================

GRANT SELECT ON myschema.users TO myuser;
GRANT INSERT, UPDATE, DELETE ON myschema.users TO myuser;
GRANT ALL ON myschema.users TO myuser;

GRANT SELECT ON SCHEMA myschema TO myuser;
GRANT ALL ON SCHEMA myschema TO myuser;

-- 角色（H2 1.4.200+）
CREATE ROLE analyst;
GRANT SELECT ON myschema.users TO analyst;
GRANT analyst TO myuser;

REVOKE SELECT ON myschema.users FROM myuser;
REVOKE analyst FROM myuser;
DROP ROLE analyst;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

SELECT CURRENT_USER(), CURRENT_SCHEMA();

SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA;
SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES;

-- H2 系统表
SELECT * FROM INFORMATION_SCHEMA.USERS;
SELECT * FROM INFORMATION_SCHEMA.ROLES;
SELECT * FROM INFORMATION_SCHEMA.TABLE_PRIVILEGES;

-- ============================================================
-- 6. 数据库设置
-- ============================================================

SET TRACE_LEVEL_SYSTEM_OUT 1;                   -- 调试
SET MODE PostgreSQL;                            -- 兼容模式
SET MODE MySQL;

-- H2 支持多种兼容模式：
-- PostgreSQL, MySQL, Oracle, MS SQL Server, DB2, HSQLDB
