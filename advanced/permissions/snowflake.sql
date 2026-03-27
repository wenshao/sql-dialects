-- Snowflake: 权限管理
--
-- 参考资料:
--   [1] Snowflake SQL Reference - GRANT
--       https://docs.snowflake.com/en/sql-reference/sql/grant-privilege
--   [2] Snowflake SQL Reference - CREATE ROLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-role
--   [3] Snowflake - Access Control
--       https://docs.snowflake.com/en/user-guide/security-access-control

-- Snowflake 使用 RBAC（基于角色的访问控制）

-- ============================================================
-- 角色层级
-- ============================================================

-- ACCOUNTADMIN（最高权限，包含 SECURITYADMIN + SYSADMIN）
-- ├── SECURITYADMIN（管理用户和角色）
-- │   └── USERADMIN（创建和管理用户）
-- ├── SYSADMIN（管理数据库和仓库）
-- └── PUBLIC（所有用户默认拥有）

-- ============================================================
-- 创建用户
-- ============================================================

CREATE USER alice
    PASSWORD = 'StrongP@ss123'
    DEFAULT_ROLE = analyst
    DEFAULT_WAREHOUSE = compute_wh
    MUST_CHANGE_PASSWORD = TRUE;

ALTER USER alice SET PASSWORD = 'NewP@ss456';
ALTER USER alice SET DISABLED = FALSE;
DROP USER IF EXISTS alice;

-- ============================================================
-- 创建角色
-- ============================================================

CREATE ROLE analyst;
CREATE ROLE data_engineer;
CREATE ROLE app_reader;

-- 角色继承
GRANT ROLE analyst TO ROLE data_engineer;  -- data_engineer 继承 analyst 的权限
GRANT ROLE data_engineer TO ROLE SYSADMIN; -- SYSADMIN 继承 data_engineer 的权限

-- 将角色授予用户
GRANT ROLE analyst TO USER alice;
ALTER USER alice SET DEFAULT_ROLE = analyst;

-- ============================================================
-- 数据库权限
-- ============================================================

GRANT USAGE ON DATABASE mydb TO ROLE analyst;
GRANT CREATE SCHEMA ON DATABASE mydb TO ROLE data_engineer;
GRANT ALL PRIVILEGES ON DATABASE mydb TO ROLE data_engineer;

-- ============================================================
-- Schema 权限
-- ============================================================

GRANT USAGE ON SCHEMA mydb.public TO ROLE analyst;
GRANT CREATE TABLE ON SCHEMA mydb.public TO ROLE data_engineer;
GRANT ALL PRIVILEGES ON SCHEMA mydb.public TO ROLE data_engineer;

-- ============================================================
-- 表权限
-- ============================================================

GRANT SELECT ON TABLE mydb.public.users TO ROLE analyst;
GRANT SELECT, INSERT, UPDATE ON TABLE mydb.public.users TO ROLE data_engineer;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA mydb.public TO ROLE data_engineer;

-- 未来创建的表自动授权
GRANT SELECT ON FUTURE TABLES IN SCHEMA mydb.public TO ROLE analyst;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN DATABASE mydb TO ROLE data_engineer;

-- ============================================================
-- 仓库（Warehouse）权限
-- ============================================================

GRANT USAGE ON WAREHOUSE compute_wh TO ROLE analyst;
GRANT OPERATE ON WAREHOUSE compute_wh TO ROLE data_engineer;
-- USAGE: 使用仓库运行查询
-- OPERATE: 启停仓库
-- MODIFY: 修改仓库属性
-- MONITOR: 监控仓库

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE SELECT ON TABLE mydb.public.users FROM ROLE analyst;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA mydb.public FROM ROLE analyst;
REVOKE ROLE analyst FROM USER alice;

-- ============================================================
-- 列级掩码策略
-- ============================================================

CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN current_role() IN ('ADMIN', 'DATA_ENGINEER') THEN val
        ELSE REGEXP_REPLACE(val, '.+@', '***@')
    END;

ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;
ALTER TABLE users ALTER COLUMN email UNSET MASKING POLICY;

-- ============================================================
-- 行级访问策略
-- ============================================================

CREATE ROW ACCESS POLICY region_policy AS (region_val VARCHAR) RETURNS BOOLEAN ->
    current_role() IN ('ADMIN') OR region_val = current_user();

ALTER TABLE orders ADD ROW ACCESS POLICY region_policy ON (region);
ALTER TABLE orders DROP ROW ACCESS POLICY region_policy;

-- ============================================================
-- 网络策略
-- ============================================================

CREATE NETWORK POLICY office_only
    ALLOWED_IP_LIST = ('203.0.113.0/24', '198.51.100.0/24')
    BLOCKED_IP_LIST = ('203.0.113.100');

ALTER USER alice SET NETWORK_POLICY = office_only;

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANTS TO ROLE analyst;
SHOW GRANTS ON TABLE mydb.public.users;
SHOW GRANTS TO USER alice;
SHOW ROLES;
SHOW USERS;

-- 注意：Snowflake 使用 RBAC（基于角色的访问控制）
-- 注意：所有权限必须授予角色，不能直接授予用户
-- 注意：ACCOUNTADMIN 是最高权限角色，应限制使用
-- 注意：FUTURE GRANTS 对将来创建的对象自动授权
-- 注意：掩码策略和行级策略提供细粒度的数据保护
