-- MaxCompute (ODPS): 数据库、模式与用户管理
--
-- 参考资料:
--   [1] MaxCompute Documentation - 项目管理
--       https://help.aliyun.com/document_detail/27818.html
--   [2] MaxCompute Documentation - 用户与权限
--       https://help.aliyun.com/document_detail/27935.html

-- ============================================================
-- MaxCompute 命名层级:
--   项目(Project) > Schema(3.0+) > 对象
-- Project 类似 database，通过控制台创建
-- Schema 在 MaxCompute 3.0（数据治理版）引入
-- ============================================================

-- ============================================================
-- 1. 项目（Project）管理
-- ============================================================

-- Project 通过阿里云控制台或 CLI 创建，不支持 SQL 创建
-- $ odpscmd --project=myproject

-- 项目属性设置（在 odpscmd 中执行）
-- setproject odps.sql.type.system.odps2=true;
-- setproject odps.schema.model.enabled=true;    -- 启用 Schema 模式

-- ============================================================
-- 2. Schema 管理（MaxCompute 3.0+）
-- ============================================================

-- 需要先启用 schema 模式
CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;

-- 完整引用: project.schema.table
SELECT * FROM myproject.myschema.users;

-- 删除 schema
DROP SCHEMA myschema;
DROP SCHEMA IF EXISTS myschema;

-- 切换 schema
USE myschema;

-- 查看 schema
SHOW SCHEMAS;

-- ============================================================
-- 3. 用户管理
-- ============================================================

-- 添加用户（RAM 账号）
ADD USER ALIYUN$alice@example.com;
ADD USER RAM$alice;                             -- RAM 子账号

-- 添加角色关联
GRANT analyst TO ALIYUN$alice@example.com;

-- 删除用户
REMOVE USER ALIYUN$alice@example.com;

-- 查看用户
LIST USERS;

-- ============================================================
-- 4. 角色管理
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE developer;

-- 系统角色: Admin, Super, ProjectOwner

GRANT analyst TO ALIYUN$alice@example.com;
REVOKE analyst FROM ALIYUN$alice@example.com;

-- 查看角色
LIST ROLES;
SHOW GRANTS FOR ALIYUN$alice@example.com;

DROP ROLE analyst;

-- ============================================================
-- 5. 权限管理（ACL 方式）
-- ============================================================

-- 表权限
GRANT SELECT ON TABLE users TO USER ALIYUN$alice@example.com;
GRANT ALL ON TABLE users TO ROLE analyst;
GRANT DESCRIBE ON TABLE users TO USER RAM$alice;

-- 项目权限
GRANT CREATETABLE ON PROJECT myproject TO USER ALIYUN$alice@example.com;

-- Schema 权限（3.0+）
GRANT SELECT ON SCHEMA myschema TO ROLE analyst;

-- 收回权限
REVOKE SELECT ON TABLE users FROM USER ALIYUN$alice@example.com;

-- 查看权限
SHOW GRANTS FOR USER ALIYUN$alice@example.com;
SHOW GRANTS ON TABLE users;

-- ============================================================
-- 6. 安全策略
-- ============================================================

-- 项目安全配置
-- set ProjectProtection=true;                  -- 禁止数据流出
-- set LabelSecurity=true;                      -- 启用标签安全

-- 列级安全（标签方式）
SET LABEL 2 TO TABLE users(email, phone);       -- 设置列敏感级别
GRANT LABEL 2 TO USER ALIYUN$alice@example.com; -- 授予访问级别

-- Package（跨项目数据共享）
CREATE PACKAGE my_package;
ADD TABLE users TO PACKAGE my_package;
ALLOW PROJECT other_project TO INSTALL PACKAGE my_package;

-- ============================================================
-- 7. 查询元数据
-- ============================================================

LIST TABLES;
LIST SCHEMAS;
LIST USERS;
LIST ROLES;

DESC TABLE users;
SHOW GRANTS FOR USER ALIYUN$alice@example.com;

-- 注意：MaxCompute 是阿里云大数据计算服务
-- Project 是最基本的资源管理单元
-- 计费按扫描量或预留资源
-- 权限完全通过 ACL + 标签安全管理
