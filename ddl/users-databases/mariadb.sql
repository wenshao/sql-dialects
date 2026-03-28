-- MariaDB: 用户与数据库管理
-- 认证和权限系统与 MySQL 有关键差异
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Account Management
--       https://mariadb.com/kb/en/account-management-sql-commands/

-- ============================================================
-- 1. 数据库管理
-- ============================================================
CREATE DATABASE myapp DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS myapp;
CREATE OR REPLACE DATABASE myapp;       -- MariaDB 独有
ALTER DATABASE myapp CHARACTER SET utf8mb4;
DROP DATABASE IF EXISTS myapp;

-- ============================================================
-- 2. 用户管理
-- ============================================================
CREATE USER 'appuser'@'%' IDENTIFIED BY 'password123';
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'password123';
CREATE OR REPLACE USER 'appuser'@'%' IDENTIFIED BY 'password123';  -- MariaDB 独有

-- 认证插件差异 (最重要的 fork 差异之一):
-- MariaDB 默认: mysql_native_password (保持传统兼容)
-- MySQL 8.0+: 默认 caching_sha2_password (更安全但破坏旧客户端兼容)
-- MariaDB 不支持 caching_sha2_password
-- 这是升级/迁移时最常见的兼容性问题

-- ============================================================
-- 3. 权限管理
-- ============================================================
GRANT SELECT, INSERT, UPDATE ON myapp.* TO 'appuser'@'%';
GRANT ALL PRIVILEGES ON myapp.* TO 'admin'@'%';
REVOKE DELETE ON myapp.* FROM 'appuser'@'%';

-- 角色 (10.0.5+, 比 MySQL 8.0 更早支持)
CREATE ROLE app_reader;
GRANT SELECT ON myapp.* TO app_reader;
GRANT app_reader TO 'appuser'@'%';
SET DEFAULT ROLE app_reader FOR 'appuser'@'%';

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- MariaDB 保持 mysql_native_password 的决定反映了:
--   兼容性 > 安全性 的优先级选择
-- MySQL 选择 caching_sha2_password 的决定反映了:
--   安全性 > 兼容性 的优先级选择
-- 作为引擎开发者: 认证协议的变更是破坏性最大的变更之一
--   建议: 支持多认证插件, 通过配置选择, 而非硬编码默认值
