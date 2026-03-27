-- Snowflake: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] Snowflake Documentation - CREATE DATABASE
--       https://docs.snowflake.com/en/sql-reference/sql/create-database
--   [2] Snowflake Documentation - CREATE USER / ROLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-user
--   [3] Snowflake Documentation - Access Control
--       https://docs.snowflake.com/en/user-guide/security-access-control

-- ============================================================
-- Snowflake 命名层级: account > database > schema > object
-- 完整引用: database.schema.object
-- ============================================================

-- ============================================================
-- 1. 数据库管理
-- ============================================================

CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    DATA_RETENTION_TIME_IN_DAYS = 30             -- Time Travel 保留天数
    MAX_DATA_EXTENSION_TIME_IN_DAYS = 10
    COMMENT = 'Main application database';

-- 瞬态数据库（无 Fail-safe）
CREATE TRANSIENT DATABASE staging;

-- 从共享创建数据库
CREATE DATABASE shared_db FROM SHARE provider_account.my_share;

-- 克隆数据库（零拷贝）
CREATE DATABASE myapp_clone CLONE myapp;
CREATE DATABASE myapp_clone CLONE myapp AT (TIMESTAMP => '2024-06-01 10:00:00'::TIMESTAMP);

-- 修改数据库
ALTER DATABASE myapp SET DATA_RETENTION_TIME_IN_DAYS = 90;
ALTER DATABASE myapp SET COMMENT = 'Updated comment';
ALTER DATABASE myapp RENAME TO myapp_v2;

-- 删除数据库
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
UNDROP DATABASE myapp;                          -- 恢复（在 Time Travel 期内）

-- 切换数据库
USE DATABASE myapp;

-- ============================================================
-- 2. 模式管理
-- ============================================================

CREATE SCHEMA myapp.myschema;
CREATE SCHEMA IF NOT EXISTS myschema;

CREATE SCHEMA myschema
    DATA_RETENTION_TIME_IN_DAYS = 14
    WITH MANAGED ACCESS                         -- 仅 schema owner 和被授权者可管理
    COMMENT = 'Application schema';

-- 瞬态模式
CREATE TRANSIENT SCHEMA staging;

-- 克隆模式
CREATE SCHEMA myschema_clone CLONE myschema;

-- 修改模式
ALTER SCHEMA myschema RENAME TO myschema_v2;
ALTER SCHEMA myschema SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- 删除模式
DROP SCHEMA myschema;
DROP SCHEMA myschema CASCADE;
UNDROP SCHEMA myschema;                         -- 恢复

-- 切换模式
USE SCHEMA myapp.myschema;
USE myapp.myschema;

-- ============================================================
-- 3. 用户管理
-- ============================================================

CREATE USER myuser
    PASSWORD = 'Secret123!'
    DEFAULT_ROLE = analyst
    DEFAULT_WAREHOUSE = compute_wh
    DEFAULT_NAMESPACE = myapp.public
    MUST_CHANGE_PASSWORD = TRUE
    COMMENT = 'Application user';

-- 修改用户
ALTER USER myuser SET PASSWORD = 'NewSecret456!';
ALTER USER myuser SET DEFAULT_ROLE = developer;
ALTER USER myuser SET DISABLED = TRUE;          -- 禁用
ALTER USER myuser SET DAYS_TO_EXPIRY = 90;

-- 删除用户
DROP USER myuser;
DROP USER IF EXISTS myuser;

-- ============================================================
-- 4. 角色管理（RBAC）
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;
CREATE ROLE IF NOT EXISTS data_engineer;

-- 角色层级
GRANT ROLE analyst TO ROLE developer;           -- developer 继承 analyst
GRANT ROLE developer TO USER myuser;

-- 系统角色：
-- ACCOUNTADMIN > SECURITYADMIN > SYSADMIN > PUBLIC
-- ACCOUNTADMIN: 最高权限
-- SECURITYADMIN: 管理用户和角色
-- SYSADMIN: 管理数据库和仓库
-- PUBLIC: 所有用户默认角色

-- 切换角色
USE ROLE analyst;

-- 删除角色
DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理
-- ============================================================

-- 数据库权限
GRANT USAGE ON DATABASE myapp TO ROLE analyst;
GRANT CREATE SCHEMA ON DATABASE myapp TO ROLE developer;
GRANT ALL ON DATABASE myapp TO ROLE data_engineer;

-- 模式权限
GRANT USAGE ON SCHEMA myapp.public TO ROLE analyst;
GRANT CREATE TABLE ON SCHEMA myapp.public TO ROLE developer;

-- 表权限
GRANT SELECT ON ALL TABLES IN SCHEMA myapp.public TO ROLE analyst;
GRANT SELECT ON FUTURE TABLES IN SCHEMA myapp.public TO ROLE analyst;  -- 未来表
GRANT INSERT, UPDATE, DELETE ON TABLE myapp.public.users TO ROLE developer;

-- 仓库权限
GRANT USAGE ON WAREHOUSE compute_wh TO ROLE analyst;

-- 收回权限
REVOKE SELECT ON ALL TABLES IN SCHEMA myapp.public FROM ROLE analyst;

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SHOW DATABASES;
SHOW SCHEMAS IN DATABASE myapp;
SHOW USERS;
SHOW ROLES;
SHOW GRANTS TO USER myuser;
SHOW GRANTS TO ROLE analyst;
SHOW GRANTS ON DATABASE myapp;

-- 当前上下文
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_ROLE(),
       CURRENT_USER(), CURRENT_WAREHOUSE();

-- ============================================================
-- 7. 仓库管理（计算资源）
-- ============================================================

CREATE WAREHOUSE compute_wh
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 300                          -- 5 分钟空闲自动挂起
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3                       -- 多集群仓库
    SCALING_POLICY = 'STANDARD';

ALTER WAREHOUSE compute_wh SET WAREHOUSE_SIZE = 'MEDIUM';
ALTER WAREHOUSE compute_wh SUSPEND;
ALTER WAREHOUSE compute_wh RESUME;

DROP WAREHOUSE compute_wh;

USE WAREHOUSE compute_wh;
