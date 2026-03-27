-- Hive: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Apache Hive - DDL: Database
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-Create/Drop/Alter/UseDatabase
--   [2] Apache Hive - Authorization
--       https://cwiki.apache.org/confluence/display/Hive/SQL+Standard+Based+Hive+Authorization

-- ============================================================
-- Hive 中 DATABASE 和 SCHEMA 是同义词
-- 命名层级: database(schema) > table
-- 默认数据库: default
-- 数据存储在 HDFS / S3 / 对象存储上
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    COMMENT 'Main application database'
    LOCATION '/user/hive/warehouse/myapp.db'    -- HDFS 路径
    WITH DBPROPERTIES (
        'owner' = 'data_team',
        'env' = 'production',
        'created_date' = '2024-01-01'
    );

-- SCHEMA 是同义词
CREATE SCHEMA myapp;

-- 修改数据库
ALTER DATABASE myapp SET DBPROPERTIES ('env' = 'staging');
ALTER DATABASE myapp SET OWNER USER hive_admin;
ALTER DATABASE myapp SET OWNER ROLE admin_role;
ALTER DATABASE myapp SET LOCATION '/new/path/myapp.db';  -- Hive 2.2.1+

-- 删除数据库
DROP DATABASE myapp;                            -- 必须为空
DROP DATABASE myapp CASCADE;                    -- 级联删除所有表
DROP DATABASE IF EXISTS myapp CASCADE;
DROP DATABASE myapp RESTRICT;                   -- 非空则报错（默认）

-- 切换数据库
USE myapp;

-- 查看数据库
SHOW DATABASES;
SHOW DATABASES LIKE 'my*';
DESCRIBE DATABASE myapp;
DESCRIBE DATABASE EXTENDED myapp;               -- 包含 DBPROPERTIES

-- ============================================================
-- 2. 用户管理（通过授权机制）
-- ============================================================

-- Hive 本身不创建用户
-- 用户由底层系统管理（Kerberos / LDAP / OS 用户）
-- Hive 通过角色和授权来管理权限

-- ============================================================
-- 3. 角色管理
-- ============================================================

-- Hive 预定义角色：admin, public
CREATE ROLE analyst;
CREATE ROLE developer;

-- 授予角色给用户
GRANT ROLE analyst TO USER alice;
GRANT ROLE developer TO USER bob;
GRANT ROLE analyst TO ROLE developer;           -- 角色继承

-- 收回角色
REVOKE ROLE analyst FROM USER alice;

-- 查看角色
SHOW ROLES;
SHOW ROLE GRANT USER alice;
SHOW CURRENT ROLES;

SET ROLE analyst;                               -- 切换角色
SET ROLE ALL;
SET ROLE NONE;

DROP ROLE analyst;

-- ============================================================
-- 4. 权限管理（SQL Standard Based Authorization）
-- ============================================================

-- 需要启用: hive.security.authorization.enabled=true
-- 推荐使用 SQL Standard Based Authorization

-- 数据库权限
GRANT ALL ON DATABASE myapp TO USER alice;
GRANT SELECT ON DATABASE myapp TO ROLE analyst;

-- 表权限
GRANT SELECT ON TABLE myapp.users TO USER alice;
GRANT INSERT, UPDATE, DELETE ON TABLE myapp.users TO ROLE developer;
GRANT ALL ON TABLE myapp.users TO USER admin WITH GRANT OPTION;

-- 列权限（Hive 0.12+）
GRANT SELECT (id, username) ON TABLE myapp.users TO ROLE analyst;

-- 查看权限
SHOW GRANT USER alice ON DATABASE myapp;
SHOW GRANT ROLE analyst ON TABLE myapp.users;

-- 收回权限
REVOKE SELECT ON TABLE myapp.users FROM USER alice;
REVOKE ALL ON DATABASE myapp FROM ROLE analyst;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

-- 当前数据库
SELECT current_database();

-- 查看所有数据库
SHOW DATABASES;

-- 查看表
SHOW TABLES IN myapp;

-- 数据库详细信息
DESCRIBE DATABASE EXTENDED myapp;

-- ============================================================
-- 6. Ranger / Sentry 集成
-- ============================================================

-- 企业环境通常使用 Apache Ranger 或 Sentry 进行权限管理
-- Ranger 提供：
-- - 细粒度的行/列级权限
-- - 数据脱敏
-- - 审计日志
-- - 与 LDAP/AD 集成

-- 注意：Hive 的 default 数据库映射到 /user/hive/warehouse/
-- 其他数据库映射到 /user/hive/warehouse/dbname.db/
