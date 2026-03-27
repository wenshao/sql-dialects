-- StarRocks: 权限管理
--
-- 参考资料:
--   [1] StarRocks - GRANT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/account-management/GRANT/
--   [2] StarRocks - CREATE USER
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/account-management/CREATE_USER/

-- StarRocks 使用 RBAC（基于角色的访问控制，3.0+）

-- ============================================================
-- 创建用户
-- ============================================================

CREATE USER 'alice' IDENTIFIED BY 'StrongP@ss123';
CREATE USER 'bob' IDENTIFIED BY 'password';

-- 限制访问 IP
CREATE USER 'alice'@'192.168.1.%' IDENTIFIED BY 'password';

-- 修改密码
ALTER USER 'alice' IDENTIFIED BY 'NewP@ss456';
SET PASSWORD FOR 'alice' = PASSWORD('NewP@ss456');

-- 删除用户
DROP USER 'alice';

-- ============================================================
-- 内置角色
-- ============================================================

-- root: 最高权限（系统内置用户）
-- db_admin: 数据库管理
-- cluster_admin: 集群管理
-- user_admin: 用户管理
-- public: 所有用户默认拥有

-- ============================================================
-- 创建角色（3.0+）
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE data_engineer;
CREATE ROLE app_reader;

-- 授予角色给用户
GRANT analyst TO 'alice';
GRANT data_engineer TO 'bob';

-- 角色继承
GRANT analyst TO ROLE data_engineer;

-- 设置默认角色
SET DEFAULT ROLE analyst TO 'alice';
SET DEFAULT ROLE ALL TO 'bob';

-- ============================================================
-- Catalog 权限（3.0+，多源数据访问）
-- ============================================================

GRANT USAGE ON CATALOG hive_catalog TO ROLE analyst;
GRANT ALL ON CATALOG hive_catalog TO ROLE data_engineer;

-- ============================================================
-- 数据库权限
-- ============================================================

GRANT ALL ON DATABASE mydb TO ROLE data_engineer;
GRANT SELECT ON ALL TABLES IN DATABASE mydb TO ROLE analyst;

-- ============================================================
-- 表权限
-- ============================================================

GRANT SELECT ON TABLE mydb.users TO ROLE analyst;
GRANT SELECT, INSERT ON TABLE mydb.users TO ROLE data_engineer;
GRANT ALL ON TABLE mydb.users TO ROLE data_engineer;

-- 所有表
GRANT SELECT ON ALL TABLES IN DATABASE mydb TO ROLE analyst;

-- ============================================================
-- 全局权限
-- ============================================================

-- 全局函数权限
GRANT USAGE ON ALL GLOBAL FUNCTIONS TO ROLE analyst;

-- 资源组权限
GRANT USAGE ON RESOURCE GROUP rg_analyst TO ROLE analyst;

-- 导入权限
GRANT INSERT ON TABLE mydb.orders TO ROLE data_engineer;

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE SELECT ON TABLE mydb.users FROM ROLE analyst;
REVOKE ALL ON DATABASE mydb FROM ROLE analyst;
REVOKE analyst FROM 'alice';

-- ============================================================
-- 旧版权限模型（3.0 之前）
-- ============================================================

-- 3.0 之前使用简单的 GRANT 模型
-- GRANT SELECT_PRIV ON mydb.users TO 'alice';
-- GRANT LOAD_PRIV ON mydb.users TO 'alice';

-- 权限类型（旧版）：
-- SELECT_PRIV: 读取
-- LOAD_PRIV: 导入
-- ALTER_PRIV: ALTER TABLE
-- CREATE_PRIV: CREATE TABLE
-- DROP_PRIV: DROP TABLE
-- NODE_PRIV: 集群管理
-- ADMIN_PRIV: 管理员
-- GRANT_PRIV: 授权

-- ============================================================
-- 安全配置
-- ============================================================

-- 密码策略
-- 通过 FE 配置文件设置最小密码长度、复杂度等
-- password_min_length = 8
-- password_max_length = 64

-- 审计日志
-- 通过 FE 审计插件记录所有操作
-- 安装审计插件：INSTALL PLUGIN FROM "/path/to/audit_plugin"

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANTS;
SHOW GRANTS FOR 'alice';
SHOW GRANTS FOR ROLE analyst;
SHOW ROLES;
SHOW ALL AUTHENTICATION;

-- 查看权限信息
SELECT * FROM information_schema.user_privileges;

-- 注意：3.0+ 推荐使用 RBAC 新权限模型
-- 注意：旧版权限模型在 3.0+ 仍然兼容但不推荐
-- 注意：root 用户不能被删除或修改
-- 注意：Catalog 权限支持多源数据的访问控制
-- 注意：资源组权限可以控制查询资源隔离
