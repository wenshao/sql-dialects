# 权限与安全模型：各 SQL 方言全对比

> 参考资料:
> - [PostgreSQL - Privileges](https://www.postgresql.org/docs/current/ddl-priv.html)
> - [MySQL 8.0 - Access Control](https://dev.mysql.com/doc/refman/8.0/en/access-control.html)
> - [Oracle - Database Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/)
> - [SQL Server - Security](https://learn.microsoft.com/en-us/sql/relational-databases/security/)
> - [Snowflake - Access Control](https://docs.snowflake.com/en/user-guide/security-access-control)
> - [BigQuery - IAM and Access Control](https://cloud.google.com/bigquery/docs/access-control)
> - [ClickHouse - Access Control](https://clickhouse.com/docs/en/guides/sre/user-management)

权限与安全是生产环境数据库的第一道防线。但不同引擎的安全模型差异极大——从 PostgreSQL 的 ACL 到 Snowflake 的 RBAC 层级，从 Oracle VPD 到 BigQuery 的 IAM 集成，从传统密码认证到 OAuth/IAM 联邦身份。本文从 GRANT/REVOKE 语法、角色体系、行列级安全、认证方式、审计能力六个维度，对 17+ 个 SQL 引擎进行全面对比。

## 权限体系矩阵

### GRANT/REVOKE 语法差异

```
引擎            GRANT/REVOKE  对象级权限  列级权限  Schema级  数据库级  DENY    WITH GRANT OPTION
──────────────  ──────────── ─────────  ───────  ───────  ───────  ──────  ─────────────────
MySQL            ✓            ✓          ✓        ✗(*)     ✓        ✗       ✓
PostgreSQL       ✓            ✓          ✓        ✓        ✓        ✗       ✓
Oracle           ✓            ✓          ✗(*)     ✓(*)     ✗(*)     ✗       ✓ (对象: WITH GRANT OPTION; 系统/角色: WITH ADMIN OPTION)
SQL Server       ✓            ✓          ✓        ✓        ✓        ✓       ✓
SQLite           ✗            ✗          ✗        ✗        ✗        ✗       无权限系统(应用层控制)
BigQuery         ✗(IAM)       ✓(IAM)     ✓(*)     ✓(IAM)   ✓(IAM)   ✗       IAM 条件绑定
Snowflake        ✓            ✓          ✗(*)     ✓        ✓        ✗       ✗(使用角色层级)
ClickHouse       ✓            ✓          ✓        ✗(*)     ✓        ✗       ✓
Hive             ✓            ✓          ✓(*)     ✗        ✓        ✗       ✓
Spark SQL        ✓            ✓          ✓(*)     ✗        ✓        ✗       ✓
Trino/Presto     ✓(*)         ✓(*)       ✗        ✓(*)     ✓(*)     ✗       插件决定
Redshift         ✓            ✓          ✓        ✓        ✓        ✗       ✓
TiDB             ✓            ✓          ✓        ✗(*)     ✓        ✗       ✓
OceanBase        ✓            ✓          ✓(*)     ✓(*)     ✓        ✗       ✓
CockroachDB      ✓            ✓          ✓        ✓        ✓        ✗       ✓
DuckDB           ✗            ✗          ✗        ✗        ✗        ✗       嵌入式, 无权限系统
StarRocks        ✓            ✓          ✗        ✗        ✓        ✗       ✓
Doris            ✓            ✓          ✗        ✗        ✓        ✗       ✓

✓(*) = 支持但有限制或语法不同于标准 SQL
```

### 关键差异说明

```
1. MySQL: 没有 Schema 概念 (Schema = Database), 用 db.* 语法授权
2. Oracle: 支持列级 GRANT (SELECT/INSERT/UPDATE), 但实践中更常用 VPD/Fine-Grained Access Control
3. SQL Server: 唯一支持 DENY 的主流引擎, DENY 优先于 GRANT
4. SQLite/DuckDB: 嵌入式数据库, 无多用户权限系统
5. BigQuery: 完全依赖 GCP IAM, 无传统 GRANT SQL 语句
6. Snowflake: 不支持列级 GRANT, 但通过 Dynamic Data Masking 实现列级安全
7. Trino/Presto: 权限由底层 connector 和 access control 插件决定
```

### 各引擎 GRANT 语法对比

```sql
-- MySQL: db.table 语法, 用户需带主机
GRANT SELECT, INSERT ON mydb.employees TO 'alice'@'%';
GRANT SELECT (name, email) ON mydb.employees TO 'intern'@'%';    -- 列级
GRANT ALL PRIVILEGES ON mydb.* TO 'admin'@'%';                   -- 库级

-- PostgreSQL: 分层授权, 需先 GRANT USAGE ON SCHEMA
GRANT USAGE ON SCHEMA hr TO alice;
GRANT SELECT ON hr.employees TO alice;
GRANT SELECT (name, email) ON hr.employees TO intern;            -- 列级
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA hr TO admin;

-- Oracle: 系统权限 vs 对象权限分开管理
GRANT SELECT ON hr.employees TO alice;
GRANT CREATE SESSION TO alice;                                    -- 系统权限
GRANT CREATE TABLE TO alice;
GRANT SELECT ANY TABLE TO admin;                                  -- ANY = 跨 Schema

-- SQL Server: 支持 DENY, Schema 隔离
GRANT SELECT ON dbo.employees TO alice;
GRANT SELECT ON SCHEMA::hr TO analyst;                            -- Schema 级
DENY SELECT ON dbo.employees(salary) TO intern;                   -- 列级 DENY
DENY DELETE ON dbo.critical_data TO PUBLIC;                       -- 全局禁止删除

-- Snowflake: 权限授予角色, 角色分配给用户
GRANT USAGE ON DATABASE analytics TO ROLE analyst;
GRANT USAGE ON SCHEMA analytics.public TO ROLE analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics.public TO ROLE analyst;
-- ⚠️ Snowflake 中 DATABASE/SCHEMA 级别用 USAGE，TABLE/VIEW 级别用 SELECT
GRANT SELECT ON FUTURE TABLES IN SCHEMA analytics.public TO ROLE analyst;  -- 未来对象

-- ClickHouse: 类似标准 SQL, 但有特殊权限
GRANT SELECT ON mydb.employees TO alice;
GRANT INSERT ON mydb.logs TO logger;
GRANT dictGet ON mydb.my_dict TO alice;                           -- 字典查询权限

-- CockroachDB: 兼容 PostgreSQL 语法
GRANT SELECT ON TABLE employees TO alice;
GRANT ALL ON DATABASE mydb TO admin;
GRANT USAGE ON SCHEMA public TO analyst;

-- Redshift: 结合 SQL GRANT 与 AWS IAM
GRANT SELECT ON employees TO GROUP analysts;
GRANT ALL ON SCHEMA public TO admin;
-- 也可通过 IAM 角色控制
```

## 角色体系

### 角色支持矩阵

```
引擎            CREATE ROLE  角色继承  默认角色  SET ROLE  预定义角色        权限原则
──────────────  ──────────  ───────  ───────  ───────  ──────────────  ──────────────
MySQL 8.0+       ✓           ✓        ✓(*)     ✓        ✗               需显式激活角色
PostgreSQL       ✓           ✓        ✓        ✓        pg_read_all_data 等  自动继承(INHERIT)
Oracle           ✓           ✓        ✓        ✓        DBA, CONNECT 等     DEFAULT/NON-DEFAULT
SQL Server       ✓           ✓(*)     ✗        ✗(*)     sysadmin, db_owner  固定角色+自定义角色
Snowflake        ✓           ✓        ✓        ✓        ACCOUNTADMIN 等    严格角色层级
ClickHouse       ✓           ✓        ✓        ✓        ✗               类 PostgreSQL
Hive             ✓           ✗        ✗        ✗        admin            Sentry/Ranger 集成
Redshift         ✗(GROUP)    ✗        ✗        ✗        ✗               GROUP 而非 ROLE
TiDB             ✓           ✓        ✓        ✓        ✗               兼容 MySQL 8.0
OceanBase        ✓           ✓        ✓        ✓        DBA(Oracle模式)    MySQL/Oracle 双模式
CockroachDB      ✓           ✓        ✓        ✓        admin            兼容 PostgreSQL
BigQuery         ✗(IAM)      ✓(IAM)   ✗        ✗        预定义 IAM 角色    GCP IAM 管理
StarRocks        ✓           ✗        ✗        ✗        root, admin      简单 RBAC
Doris            ✓           ✗        ✗        ✗        admin            简单 RBAC

✓(*) MySQL: 角色不会自动激活, 需 SET DEFAULT ROLE 或 activate_all_roles_on_login
     SQL Server: 角色"继承"通过嵌套角色实现, 无 SET ROLE 但通过 EXECUTE AS 模拟
```

### 角色继承模型对比

```sql
-- PostgreSQL: INHERIT 是默认行为, 角色自动获得父角色权限
CREATE ROLE analyst;
CREATE ROLE senior_analyst;
GRANT analyst TO senior_analyst;          -- senior_analyst 自动继承 analyst 的权限
-- NOINHERIT: 需要 SET ROLE 才能使用父角色权限
CREATE ROLE auditor NOINHERIT;
GRANT admin TO auditor;                   -- 需 SET ROLE admin 才能使用 admin 权限

-- MySQL 8.0: 角色不自动激活, 需要额外步骤
CREATE ROLE 'analyst', 'senior_analyst';
GRANT 'analyst' TO 'senior_analyst';
GRANT 'analyst' TO 'alice'@'%';
-- 必须激活:
SET DEFAULT ROLE 'analyst' TO 'alice'@'%';
-- 或全局设置:
SET GLOBAL activate_all_roles_on_login = ON;

-- Snowflake: 严格的角色层级, 权限向上聚合
-- 系统角色层级:
-- ACCOUNTADMIN
--   ├── SECURITYADMIN → USERADMIN
--   └── SYSADMIN → 自定义角色
--       └── PUBLIC
CREATE ROLE junior_analyst;
CREATE ROLE senior_analyst;
GRANT ROLE junior_analyst TO ROLE senior_analyst;   -- 层级继承
GRANT ROLE senior_analyst TO ROLE sysadmin;         -- 挂到 SYSADMIN 下
-- 最佳实践: 所有自定义角色最终应挂到 SYSADMIN 下
-- 否则只有 ACCOUNTADMIN 能管理这些"悬挂"角色

-- Oracle: 角色可以有密码保护
CREATE ROLE hr_admin IDENTIFIED BY secret123;
-- 使用时需提供密码:
SET ROLE hr_admin IDENTIFIED BY secret123;
-- DEFAULT vs NON-DEFAULT 角色:
ALTER USER alice DEFAULT ROLE analyst;    -- 登录时自动激活
-- NON-DEFAULT 角色需要 SET ROLE 激活

-- SQL Server: 固定角色 + 自定义角色, 通过嵌套实现继承
CREATE ROLE junior_analyst;
CREATE ROLE senior_analyst;
ALTER ROLE junior_analyst ADD MEMBER alice;
ALTER ROLE senior_analyst ADD MEMBER junior_analyst;  -- 嵌套角色
-- 注意: SQL Server 不能 SET ROLE, 用户同时拥有所有被授予角色的权限
-- 使用 EXECUTE AS 可以临时切换安全上下文:
EXECUTE AS USER = 'alice';
REVERT;                                               -- 恢复原始上下文
```

### 最大权限原则 vs 最小权限原则

```
权限累加模型 (Most Permissive):
  PostgreSQL, MySQL, Oracle, CockroachDB
  → 用户拥有所有角色权限的并集
  → 如果任一角色有 SELECT 权限, 用户就能 SELECT
  → 只有 REVOKE 能移除权限, 没有"否定"权限

DENY 优先模型 (Least Permissive):
  SQL Server
  → DENY 优先于所有 GRANT
  → 如果任一角色对某对象有 DENY, 即使其他角色有 GRANT, 也被拒绝
  → 可以精确"打洞": 先 GRANT ALL, 再 DENY 特定权限

角色激活模型 (Explicit Activation):
  MySQL 8.0, Oracle
  → 用户可以有角色但不激活
  → 只有激活的角色的权限才生效
  → 可以按需切换角色, 实现最小权限
```

```sql
-- 最大权限原则示例 (PostgreSQL):
-- alice 属于 analyst(SELECT) 和 editor(INSERT, UPDATE) 角色
-- alice 的有效权限 = SELECT + INSERT + UPDATE (并集)

-- DENY 优先示例 (SQL Server):
-- alice 属于 analyst(GRANT SELECT) 和 restricted(DENY SELECT ON salary)
-- alice 对 salary 列: DENY 生效, 无法查看
-- 即使 analyst 有全表 SELECT 权限

-- 角色激活示例 (MySQL):
SET ROLE 'analyst';            -- 只有 analyst 角色权限生效
SET ROLE 'analyst', 'editor';  -- analyst + editor 权限生效
SET ROLE ALL;                  -- 所有角色权限生效
SET ROLE NONE;                 -- 无角色权限生效
```

## 行级安全 (RLS)

### 支持矩阵

```
引擎            特性名称                版本       实现方式                         灵活度
──────────────  ────────────────────  ─────────  ─────────────────────────────  ──────
PostgreSQL      Row Level Security    9.5+       CREATE POLICY                  ★★★★★
SQL Server      Row-Level Security    2016+      SECURITY POLICY + 谓词函数       ★★★★
Oracle          Virtual Private DB    8i+        DBMS_RLS.ADD_POLICY            ★★★★★
Snowflake       Row Access Policies   GA         CREATE ROW ACCESS POLICY       ★★★★
BigQuery        Row-Level Security    GA         CREATE ROW ACCESS POLICY       ★★★
ClickHouse      Row Policies          21.8+      CREATE ROW POLICY              ★★★
Db2             Row Access Control    10.1+      CREATE PERMISSION              ★★★★
MySQL           不支持                 -          需视图/应用层模拟                 -
SQLite          不支持                 -          -                              -
MariaDB         不支持                 -          -                              -
TiDB            不支持                 -          -                              -
Redshift        不支持(原生)           -          通过视图模拟                     ★★
StarRocks       不支持                 -          -                              -
Doris           不支持                 -          行级权限通过 Ranger              ★★
DuckDB          不支持                 -          -                              -
CockroachDB     不支持                 -          通过视图模拟                     ★★
OceanBase       支持(Oracle 模式)      -          兼容 Oracle VPD                 ★★★★
```

### 各引擎 RLS 语法对比

```sql
-- PostgreSQL: 最灵活的 RLS 实现
-- 支持 PERMISSIVE / RESTRICTIVE 策略组合
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON orders
    FOR ALL
    USING (tenant_id = current_setting('app.tenant_id'))
    WITH CHECK (tenant_id = current_setting('app.tenant_id'));

-- PERMISSIVE (默认): 多个策略之间 OR
-- RESTRICTIVE: 与 PERMISSIVE 策略之间 AND
CREATE POLICY geo_restrict ON orders
    AS RESTRICTIVE
    FOR SELECT
    USING (region = current_setting('app.region'));
-- 最终条件: (tenant_isolation通过) AND (geo_restrict通过)

-- 强制表所有者也受 RLS 限制:
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

```sql
-- SQL Server: 基于安全策略 + 内联表值函数
CREATE FUNCTION dbo.fn_tenant_filter(@tenant_id NVARCHAR(50))
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
    SELECT 1 AS result
    WHERE @tenant_id = SESSION_CONTEXT(N'tenant_id')
       OR IS_MEMBER('db_owner') = 1;

CREATE SECURITY POLICY TenantFilter
    ADD FILTER PREDICATE dbo.fn_tenant_filter(tenant_id) ON dbo.orders,
    ADD BLOCK PREDICATE dbo.fn_tenant_filter(tenant_id) ON dbo.orders AFTER INSERT,
    ADD BLOCK PREDICATE dbo.fn_tenant_filter(tenant_id) ON dbo.orders AFTER UPDATE
    WITH (STATE = ON);

-- FILTER PREDICATE: 控制可见行 (SELECT/UPDATE/DELETE)
-- BLOCK PREDICATE: 控制可写行 (INSERT/UPDATE)
EXEC sp_set_session_context @key = N'tenant_id', @value = N'acme';
```

```sql
-- Oracle VPD: 最早的行级安全实现, PL/SQL 函数动态生成 WHERE
CREATE OR REPLACE FUNCTION tenant_policy(
    p_schema VARCHAR2, p_object VARCHAR2
) RETURN VARCHAR2 IS
BEGIN
    IF SYS_CONTEXT('userenv', 'session_user') = 'ADMIN' THEN
        RETURN NULL;  -- 无限制
    END IF;
    RETURN 'tenant_id = SYS_CONTEXT(''app_ctx'', ''tenant_id'')';
END;
/

BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema   => 'HR',
        object_name     => 'ORDERS',
        policy_name     => 'TENANT_POLICY',
        function_schema => 'HR',
        policy_function => 'TENANT_POLICY',
        statement_types => 'SELECT, INSERT, UPDATE, DELETE',
        update_check    => TRUE
    );
END;
/
```

```sql
-- Snowflake: Row Access Policy, 基于角色的行过滤
CREATE OR REPLACE ROW ACCESS POLICY rap_tenant
AS (tenant_id VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN')
    OR tenant_id = CURRENT_ACCOUNT();

-- 绑定到表
ALTER TABLE orders ADD ROW ACCESS POLICY rap_tenant ON (tenant_id);

-- 一个表只能绑定一个 Row Access Policy
-- 解绑:
ALTER TABLE orders DROP ROW ACCESS POLICY rap_tenant;
```

```sql
-- BigQuery: Row-Level Security, 基于 IAM 集成
CREATE ROW ACCESS POLICY rap_region
ON project.dataset.orders
GRANT TO ('user:alice@example.com', 'group:analysts@example.com')
FILTER USING (region = 'US');

-- 可同时创建多个 policy, 同表多个 policy 是 OR 关系
CREATE ROW ACCESS POLICY rap_admin
ON project.dataset.orders
GRANT TO ('user:admin@example.com')
FILTER USING (TRUE);  -- 管理员看所有数据
```

```sql
-- ClickHouse: Row Policy, 简洁但有效
CREATE ROW POLICY tenant_filter ON orders
    FOR SELECT
    USING tenant_id = currentUser()
    TO alice, bob;

-- 默认行为: 没有 policy 的用户看到所有行
-- 如果任一 policy 匹配用户, 则只看到 policy 允许的行
CREATE ROW POLICY deny_all ON orders
    FOR SELECT
    USING 0                    -- 拒绝所有
    TO ALL EXCEPT admin;       -- 除了 admin
```

## 列级安全

### 支持矩阵

```
引擎            列级GRANT  列加密    动态数据脱敏(DDM)  列级安全策略
──────────────  ───────  ───────  ──────────────  ──────────────
PostgreSQL       ✓        pgcrypto  ✗(需扩展/视图)    ✗
MySQL            ✓        AES_ENCRYPT  ✗(企业版)      ✗
Oracle           ✗(*)     TDE + 列加密  Data Redaction   ✓ (OLS)
SQL Server       ✓ + DENY  Always Encrypted  DDM (2016+)   ✗
Snowflake        ✗        自动加密     Dynamic Data Masking  ✗
BigQuery         ✗        AEAD 函数   Column-Level Security  ✓ (policy tag)
ClickHouse       ✓        ✗          ✗               ✗
Redshift         ✓        ✗          DDM (2023+)      ✗
Db2              ✓        列加密      Column Mask       ✓
Hive             ✗        ✗          Ranger Column Masking ✗
Doris            ✗        ✗          ✗               ✗
StarRocks        ✗        ✗          ✗               ✗
CockroachDB      ✓        ✗          ✗               ✗
TiDB             ✓        ✗          ✗               ✗
OceanBase        ✓(*)     ✗          ✗               ✗
```

### 动态数据脱敏 (DDM) 对比

```sql
-- SQL Server Dynamic Data Masking (2016+)
-- 定义时指定脱敏函数, 查询时自动脱敏
CREATE TABLE employees (
    id          INT PRIMARY KEY,
    name        NVARCHAR(100),
    email       NVARCHAR(100) MASKED WITH (FUNCTION = 'email()'),
    phone       NVARCHAR(20)  MASKED WITH (FUNCTION = 'partial(0,"XXX-XXX-",4)'),
    salary      DECIMAL(10,2) MASKED WITH (FUNCTION = 'random(1000, 9999)'),
    ssn         NVARCHAR(11)  MASKED WITH (FUNCTION = 'default()')
);

-- 脱敏函数:
-- default(): 根据数据类型替换 (字符串→XXXX, 数字→0, 日期→2000-01-01)
-- email(): 显示首字母 + XXX@XXXX.com
-- partial(前缀长度, 填充, 后缀长度): 自定义部分脱敏
-- random(起始, 结束): 随机数替换

-- 授权查看未脱敏数据:
GRANT UNMASK TO hr_manager;
-- SQL Server 2022+ 支持粒度 UNMASK:
GRANT UNMASK ON employees(salary) TO hr_manager;  -- 仅 salary 列

-- 普通用户看到:
-- name: Alice    email: aXXX@XXXX.com    phone: XXX-XXX-1234    salary: 5678    ssn: XXXX
-- hr_manager 看到:
-- name: Alice    email: alice@corp.com   phone: 555-123-1234    salary: 85000   ssn: 123-45-6789
```

```sql
-- Snowflake Dynamic Data Masking
CREATE OR REPLACE MASKING POLICY mask_email
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ANALYST', 'PUBLIC')
            THEN REGEXP_REPLACE(val, '.+@', '***@')     -- ***@example.com
        ELSE val                                          -- 原始值
    END;

-- 绑定到列
ALTER TABLE employees MODIFY COLUMN email
    SET MASKING POLICY mask_email;

-- 一个列只能绑定一个 masking policy
-- 解绑:
ALTER TABLE employees MODIFY COLUMN email
    UNSET MASKING POLICY;

-- Snowflake 还支持 External Tokenization:
-- 通过外部函数将敏感数据替换为 token
```

```sql
-- Oracle Data Redaction (12c+)
-- 实时脱敏, 数据存储不变, 查询时动态替换
BEGIN
    DBMS_REDACT.ADD_POLICY(
        object_schema  => 'HR',
        object_name    => 'EMPLOYEES',
        column_name    => 'SALARY',
        policy_name    => 'REDACT_SALARY',
        function_type  => DBMS_REDACT.FULL,           -- 完全隐藏
        expression     => 'SYS_CONTEXT(''userenv'',''session_user'') != ''HR_ADMIN'''
    );
END;
/

-- 脱敏类型:
-- FULL: 完全替换 (数字→0, 字符串→空)
-- PARTIAL: 部分脱敏 (如手机号中间4位)
-- RANDOM: 随机值替换
-- REGEXP: 正则表达式替换
-- NONE: 不脱敏 (用于测试)
```

```sql
-- BigQuery Column-Level Security (基于 Policy Tag)
-- 1. 在 Data Catalog 中创建 policy tag taxonomy
-- 2. 将 tag 绑定到列
-- 3. 通过 IAM 控制谁能访问带 tag 的列

-- 通过 SQL 设置:
ALTER TABLE dataset.employees
ALTER COLUMN salary
SET OPTIONS (policy_tags = 'projects/myproj/locations/us/taxonomies/123/policyTags/456');

-- 无 Fine-Grained Reader 权限的用户查询该列会报错:
-- Access Denied: User does not have permission to access policy tag "PII/Salary"

-- 授权:
-- 在 IAM 中授予 roles/datacatalog.categoryFineGrainedReader
```

```sql
-- Redshift Dynamic Data Masking (2023+)
CREATE MASKING POLICY mask_ssn
WITH (ssn VARCHAR(11))
USING ('XXX-XX-' || RIGHT(ssn, 4));

ATTACH MASKING POLICY mask_ssn
ON employees(ssn)
TO ROLE analyst;

-- analyst 角色看到: XXX-XX-1234
-- 未绑定 policy 的角色看到原始值

-- 多角色优先级:
ATTACH MASKING POLICY mask_ssn_full ON employees(ssn) TO ROLE intern PRIORITY 10;
ATTACH MASKING POLICY mask_ssn_partial ON employees(ssn) TO ROLE analyst PRIORITY 20;
-- 同时属于 intern 和 analyst 的用户, 使用高优先级 (20) 的策略
```

## 认证方式支持矩阵

```
引擎            密码     Kerberos  LDAP    OAuth 2.0   IAM       证书/mTLS  MFA     SAML
──────────────  ──────  ───────  ──────  ─────────  ─────────  ───────  ──────  ──────
MySQL            ✓       ✓(插件)   ✓(插件)  ✗          ✗          ✓(SSL)    ✗       ✗
PostgreSQL       ✓       ✓(GSSAPI) ✓       ✗(*)       ✗          ✓(SSL)    ✗       ✗
Oracle           ✓       ✓        ✓       ✓(21c+)    ✗          ✓(SSL)    ✓(*)    ✗
SQL Server       ✓       ✓(AD)    ✓(AD)   ✓(Azure)   ✓(Azure)   ✓        ✓(Azure) ✗
Snowflake        ✓       ✗        ✗       ✓          ✗          ✓        ✓       ✓
BigQuery         ✗       ✗        ✗       ✓(GCP)     ✓(GCP)     ✓(SA)    ✓(GCP)  ✓(GCP)
ClickHouse       ✓       ✓        ✓       ✗          ✗          ✓(SSL)    ✗       ✗
Hive             ✓(*)    ✓        ✓       ✗          ✗          ✓(SSL)    ✗       ✗
Redshift         ✓       ✗        ✗       ✗          ✓(AWS)     ✓(SSL)    ✓(AWS)  ✓(AWS)
TiDB             ✓       ✗        ✓       ✗          ✗          ✓(SSL)    ✗       ✗
OceanBase        ✓       ✗        ✓(*)    ✗          ✗          ✓(SSL)    ✗       ✗
CockroachDB      ✓       ✓(GSSAPI) ✓(*)   ✓(*)       ✗          ✓        ✓(*)    ✗
StarRocks        ✓       ✗        ✓       ✗          ✗          ✗        ✗       ✗
Doris            ✓       ✗        ✓       ✗          ✗          ✗        ✗       ✗
DuckDB           ✗       ✗        ✗       ✗          ✗          ✗        ✗       ✗
SQLite           ✗       ✗        ✗       ✗          ✗          ✗        ✗       ✗
Trino/Presto     ✓       ✓        ✓       ✓          ✗          ✓        ✗       ✗

✓(*) = 通过插件或扩展支持
```

### 各引擎认证配置示例

```sql
-- PostgreSQL: pg_hba.conf 控制认证方式
-- host  database  user    address         method
-- host  all       all     192.168.0.0/16  scram-sha-256    -- 密码
-- host  all       all     10.0.0.0/8      gss              -- Kerberos
-- host  all       all     172.16.0.0/12   ldap             -- LDAP
-- hostssl all     all     0.0.0.0/0       cert             -- 证书

-- PostgreSQL LDAP 配置:
-- host all all 0.0.0.0/0 ldap ldapserver=ldap.example.com ldapbasedn="dc=example,dc=com"

-- MySQL: CREATE USER 时指定认证插件
CREATE USER 'alice'@'%' IDENTIFIED WITH caching_sha2_password BY 'password';
CREATE USER 'bob'@'%' IDENTIFIED WITH authentication_ldap_simple;
CREATE USER 'carol'@'%' IDENTIFIED WITH authentication_kerberos;

-- SQL Server: Windows 认证 (Kerberos/NTLM via Active Directory)
CREATE LOGIN [DOMAIN\alice] FROM WINDOWS;
-- Azure AD 认证:
CREATE LOGIN [alice@example.com] FROM EXTERNAL PROVIDER;

-- Snowflake: 多种认证
ALTER USER alice SET
    PASSWORD = 'StrongP@ss'               -- 密码
    RSA_PUBLIC_KEY = 'MIIBIjANBg...'      -- Key Pair
    ;
-- OAuth: 通过 Security Integration
CREATE SECURITY INTEGRATION oauth_integration
    TYPE = OAUTH
    ENABLED = TRUE
    OAUTH_CLIENT = CUSTOM
    OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
    OAUTH_REDIRECT_URI = 'https://app.example.com/callback'
    OAUTH_ISSUE_REFRESH_TOKENS = TRUE
    OAUTH_REFRESH_TOKEN_VALIDITY = 86400;
-- SAML:
CREATE SECURITY INTEGRATION saml_integration
    TYPE = SAML2
    ENABLED = TRUE
    SAML2_ISSUER = 'https://idp.example.com'
    SAML2_SSO_URL = 'https://idp.example.com/sso'
    SAML2_PROVIDER = 'CUSTOM'
    SAML2_X509_CERT = '...';

-- BigQuery: 完全依赖 GCP 认证
-- 服务账号 (Service Account) JSON key
-- OAuth 2.0 用户凭据
-- Workload Identity Federation (无密钥)
-- gcloud auth login                        -- 用户 OAuth
-- gcloud auth activate-service-account     -- 服务账号
-- export GOOGLE_APPLICATION_CREDENTIALS=key.json  -- 应用默认凭据
```

## 审计能力

### 审计支持矩阵

```
引擎            原生审计日志  查询日志  DDL审计  DML审计  登录审计  细粒度审计  第三方集成
──────────────  ──────────  ───────  ──────  ──────  ──────  ────────  ──────────
PostgreSQL       ✓(pgaudit)  ✓        ✓       ✓       ✓       ✓         pgaudit扩展
MySQL            ✓(企业审计)  ✓(general) ✓      ✓       ✓       ✗         审计插件
Oracle           ✓(统一审计)  ✓        ✓       ✓       ✓       ✓(FGA)    原生
SQL Server       ✓(SQL Audit) ✓       ✓       ✓       ✓       ✓         原生
Snowflake        ✓           ✓        ✓       ✓       ✓       ✓         QUERY_HISTORY
BigQuery         ✓           ✓        ✓       ✓       ✓       ✓         Cloud Audit Logs
ClickHouse       ✓(部分)      ✓        ✓       ✗(*)    ✓       ✗         query_log 表
Hive             ✗(原生)      ✓(*)     ✓(*)    ✓(*)    ✗       ✗         Ranger Audit
Redshift         ✓           ✓        ✓       ✓       ✓       ✓         STL/SVL 系统表
TiDB             ✓           ✓        ✓       ✓       ✓       ✗         慢日志+通用日志
OceanBase        ✓           ✓        ✓       ✓       ✓       ✗         审计系统
CockroachDB      ✓           ✓        ✓       ✓       ✓       ✗         SQL Audit 日志
StarRocks        ✓(部分)      ✓        ✓       ✗       ✓       ✗         审计日志插件
Doris            ✓(部分)      ✓        ✓       ✗       ✓       ✗         审计日志
DuckDB           ✗           ✗        ✗       ✗       ✗       ✗         嵌入式, 无审计
SQLite           ✗           ✗        ✗       ✗       ✗       ✗         嵌入式, 无审计
```

### 各引擎审计配置

```sql
-- PostgreSQL: pgaudit 扩展 (社区标准)
-- 安装: CREATE EXTENSION pgaudit;
-- postgresql.conf:
-- shared_preload_libraries = 'pgaudit'
-- pgaudit.log = 'ddl, write, role'       -- 记录 DDL, 写操作, 角色变更
-- pgaudit.log_catalog = off              -- 不记录系统表查询
-- pgaudit.log_relation = on              -- 记录涉及的表名

-- 对象级审计 (Fine-Grained):
-- pgaudit.role = 'auditor';
-- GRANT SELECT ON employees TO auditor;  -- 审计所有对 employees 的 SELECT

-- 审计日志输出到标准 PostgreSQL 日志:
-- 2024-01-15 10:30:00 UTC AUDIT: SESSION,1,1,DDL,CREATE TABLE,TABLE,public.orders,CREATE TABLE orders...
```

```sql
-- Oracle: 统一审计 (Unified Auditing, 12c+)
-- 创建审计策略
CREATE AUDIT POLICY salary_audit
    ACTIONS SELECT ON hr.employees,
            UPDATE ON hr.employees
    WHEN 'SYS_CONTEXT(''userenv'', ''session_user'') != ''HR_ADMIN'''
    EVALUATE PER SESSION;

-- 启用审计策略
AUDIT POLICY salary_audit;

-- 查看审计记录
SELECT event_timestamp, dbusername, sql_text, object_name, action_name
FROM unified_audit_trail
WHERE object_name = 'EMPLOYEES'
ORDER BY event_timestamp DESC;

-- Fine-Grained Auditing (FGA): 基于数据值的审计
BEGIN
    DBMS_FGA.ADD_POLICY(
        object_schema  => 'HR',
        object_name    => 'EMPLOYEES',
        policy_name    => 'SALARY_LOOKUP',
        audit_column   => 'SALARY',
        audit_condition => 'SALARY > 100000',  -- 只审计高薪查询
        statement_types => 'SELECT'
    );
END;
/
```

```sql
-- SQL Server: SQL Server Audit
-- 1. 创建审计对象 (输出到文件)
CREATE SERVER AUDIT MainAudit
TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 1 GB, MAX_ROLLOVER_FILES = 10)
WITH (ON_FAILURE = CONTINUE);
ALTER SERVER AUDIT MainAudit WITH (STATE = ON);

-- 2. 服务器级审计规格
CREATE SERVER AUDIT SPECIFICATION LoginAudit
FOR SERVER AUDIT MainAudit
ADD (FAILED_LOGIN_GROUP),                  -- 失败登录
ADD (LOGIN_CHANGE_PASSWORD_GROUP)          -- 密码修改
WITH (STATE = ON);

-- 3. 数据库级审计规格
CREATE DATABASE AUDIT SPECIFICATION DataAudit
FOR SERVER AUDIT MainAudit
ADD (SELECT ON dbo.employees BY PUBLIC),   -- 所有用户对 employees 的 SELECT
ADD (INSERT, UPDATE, DELETE ON dbo.orders BY PUBLIC)
WITH (STATE = ON);

-- 查看审计日志:
SELECT event_time, action_id, succeeded, server_principal_name, statement
FROM fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT);
```

```sql
-- Snowflake: 内置查询历史 + Access History
-- 查询历史 (最近 14 天):
SELECT query_id, user_name, query_text, start_time, execution_status
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;

-- 访问历史 (谁访问了哪些列):
SELECT query_id, user_name,
       direct_objects_accessed,             -- 直接访问的表/列
       base_objects_accessed,               -- 底层访问的表/列 (视图展开)
       objects_modified                      -- 修改的对象
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE query_start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP());

-- 登录历史:
SELECT event_timestamp, user_name, client_ip, reported_client_type,
       is_success, error_code, error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
ORDER BY event_timestamp DESC;
```

```sql
-- BigQuery: Cloud Audit Logs (自动启用)
-- Admin Activity 日志: 默认开启, 不可关闭
-- Data Access 日志: 需手动开启

-- 通过 BigQuery 查询审计日志:
SELECT
    protopayload_auditlog.methodName,
    protopayload_auditlog.authenticationInfo.principalEmail,
    protopayload_auditlog.resourceName,
    timestamp
FROM `project.dataset.cloudaudit_googleapis_com_data_access_*`
WHERE _TABLE_SUFFIX >= '20240101'
ORDER BY timestamp DESC;

-- 通过 gcloud 查看:
-- gcloud logging read "resource.type=bigquery_resource" --limit=10
```

```sql
-- ClickHouse: 内置 query_log 系统表
SELECT
    event_time, user, query, type,
    read_rows, written_rows,
    query_duration_ms, memory_usage
FROM system.query_log
WHERE event_date = today()
  AND type = 'QueryFinish'           -- QueryStart, QueryFinish, ExceptionWhileProcessing
ORDER BY event_time DESC
LIMIT 100;

-- 开启查询日志 (config.xml):
-- <query_log>
--     <database>system</database>
--     <table>query_log</table>
--     <flush_interval_milliseconds>7500</flush_interval_milliseconds>
-- </query_log>
```

## 安全最佳实践总结

### 按场景选择安全策略

```
场景                    推荐方案                           代表引擎
──────────────────    ─────────────────────────────    ──────────────────
多租户 SaaS            RLS (行级安全)                     PostgreSQL, Oracle VPD
数据脱敏/合规          DDM (动态数据脱敏)                   SQL Server, Snowflake
最小权限原则           RBAC + DENY                        SQL Server
云原生权限管理         IAM 集成                            BigQuery, Redshift
数据分类分级           Column-Level Security + Policy Tag  BigQuery, Snowflake
审计合规              统一审计 + FGA                       Oracle, SQL Server
嵌入式应用            应用层权限控制                        SQLite, DuckDB
大数据平台            Ranger + Sentry                     Hive, Spark, Trino
```

### 各引擎安全能力评级

```
引擎            权限体系  角色模型  行级安全  列级安全  认证方式  审计能力  综合评级
──────────────  ──────  ──────  ──────  ──────  ──────  ──────  ──────
PostgreSQL       ★★★★   ★★★★   ★★★★★  ★★★    ★★★★   ★★★★   ★★★★
Oracle           ★★★★★  ★★★★   ★★★★★  ★★★★★  ★★★★★  ★★★★★  ★★★★★
SQL Server       ★★★★★  ★★★★   ★★★★   ★★★★★  ★★★★★  ★★★★★  ★★★★★
MySQL            ★★★    ★★★    ★       ★★     ★★★    ★★★    ★★★
Snowflake        ★★★★   ★★★★★  ★★★★   ★★★★   ★★★★   ★★★★   ★★★★
BigQuery         ★★★★   ★★★★   ★★★    ★★★★   ★★★★★  ★★★★★  ★★★★
ClickHouse       ★★★    ★★★    ★★★    ★★     ★★★    ★★★    ★★★
Redshift         ★★★★   ★★★    ★★     ★★★    ★★★★   ★★★★   ★★★
TiDB             ★★★    ★★★    ★       ★★     ★★★    ★★★    ★★★
CockroachDB      ★★★★   ★★★★   ★★     ★★     ★★★    ★★★    ★★★
Hive             ★★     ★★     ★       ★      ★★     ★★     ★★
DuckDB           ★       ★      ★       ★      ★      ★       ★
SQLite           ★       ★      ★       ★      ★      ★       ★
```
