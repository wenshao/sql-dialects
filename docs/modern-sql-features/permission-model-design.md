# 权限模型设计

从 ACL 到 RBAC 到 ABAC，数据库的权限模型随着安全需求的增长不断演进。行级安全 (RLS) 和列级安全是差异化竞争的关键能力。

## 权限模型演进

| 模型 | 含义 | 代表引擎 | 复杂度 | 灵活性 |
|------|------|---------|-------|-------|
| ACL | Access Control List | PostgreSQL, Oracle | 低 | 低 |
| RBAC | Role-Based Access Control | MySQL 8.0+, Snowflake, SQL Server | 中 | 中 |
| ABAC | Attribute-Based Access Control | 应用层实现, 部分云服务 | 高 | 高 |
| IAM | Identity and Access Management | BigQuery (GCP), Redshift (AWS) | 高 | 高 |

## ACL: 访问控制列表

### PostgreSQL 的 GRANT/REVOKE

```sql
-- PostgreSQL 的权限模型基于 ACL (Access Control List)

-- 对象权限: 直接授予用户
GRANT SELECT ON employees TO alice;
GRANT INSERT, UPDATE ON employees TO bob;
GRANT ALL PRIVILEGES ON employees TO admin;

-- 列级权限
GRANT SELECT (name, email) ON employees TO intern;
GRANT UPDATE (status) ON employees TO manager;
-- intern 只能查看 name 和 email 列
-- manager 只能更新 status 列

-- Schema 权限
GRANT USAGE ON SCHEMA hr TO alice;
GRANT CREATE ON SCHEMA hr TO admin;

-- 数据库权限
GRANT CONNECT ON DATABASE mydb TO alice;
GRANT CREATE ON DATABASE mydb TO admin;

-- 撤销权限
REVOKE INSERT ON employees FROM bob;
REVOKE ALL PRIVILEGES ON employees FROM alice;

-- 查看权限
\dp employees
-- 显示: Access privileges
-- alice=r/postgres     (r=SELECT)
-- bob=w/postgres       (w=UPDATE)
-- 格式: grantee=privileges/grantor
```

### ACL 的编码格式

```
PostgreSQL ACL 权限字母:
  r = SELECT (read)
  w = UPDATE (write)
  a = INSERT (append)
  d = DELETE
  D = TRUNCATE
  x = REFERENCES
  t = TRIGGER
  X = EXECUTE
  U = USAGE
  C = CREATE
  c = CONNECT
  T = TEMPORARY
  * = WITH GRANT OPTION (可以将权限授予他人)

示例:
  alice=arwd*/postgres
  含义: alice 拥有 INSERT, SELECT, UPDATE, DELETE 权限
        由 postgres 授予, 并可以将这些权限授予他人
```

### GRANT OPTION: 权限传递

```sql
-- WITH GRANT OPTION: 允许被授权者将权限转授给他人
GRANT SELECT ON employees TO alice WITH GRANT OPTION;
-- alice 现在可以:
-- 1. SELECT employees
-- 2. GRANT SELECT ON employees TO 其他人

-- alice 转授:
-- (以 alice 身份)
GRANT SELECT ON employees TO bob;

-- 级联撤销:
REVOKE SELECT ON employees FROM alice CASCADE;
-- alice 的权限被撤销, bob 从 alice 获得的权限也被撤销!

-- 非级联撤销:
REVOKE SELECT ON employees FROM alice RESTRICT;
-- 如果 alice 已将权限转授给他人, RESTRICT 会报错而非级联撤销
```

## RBAC: 基于角色的访问控制

### 核心概念

```
RBAC 引入"角色" (Role) 作为权限的中间层:

传统 ACL: 用户 -> 权限
RBAC:     用户 -> 角色 -> 权限

好处:
  - 一个角色可以包含多个权限
  - 一个用户可以拥有多个角色
  - 修改角色的权限会影响所有拥有该角色的用户
  - 简化权限管理 (管理角色而非逐个用户)
```

### MySQL 8.0+ RBAC

```sql
-- MySQL 8.0 引入角色支持

-- 创建角色
CREATE ROLE 'analyst', 'developer', 'admin';

-- 给角色授权
GRANT SELECT ON mydb.* TO 'analyst';
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.* TO 'developer';
GRANT ALL PRIVILEGES ON mydb.* TO 'admin';

-- 将角色分配给用户
GRANT 'analyst' TO 'alice'@'%';
GRANT 'developer' TO 'bob'@'%';
GRANT 'admin', 'developer' TO 'carol'@'%';

-- MySQL 的角色需要显式激活!
-- 方法 1: 每次登录后手动激活
SET ROLE 'analyst';
SET ROLE ALL;  -- 激活所有被授予的角色

-- 方法 2: 设置默认角色 (自动激活)
SET DEFAULT ROLE 'analyst' TO 'alice'@'%';
SET DEFAULT ROLE ALL TO 'carol'@'%';

-- 方法 3: 全局自动激活
SET GLOBAL activate_all_roles_on_login = ON;

-- 查看当前活跃的角色
SELECT CURRENT_ROLE();

-- 查看角色的权限
SHOW GRANTS FOR 'analyst';

-- 角色继承: MySQL 8.0 支持角色之间的授予
GRANT 'analyst' TO 'developer';
-- developer 角色包含 analyst 角色的所有权限
```

### Snowflake RBAC

```sql
-- Snowflake 的 RBAC 是最成熟的实现之一

-- 系统预定义角色层次:
-- ACCOUNTADMIN (最高权限)
--   └── SECURITYADMIN (管理用户和角色)
--       └── USERADMIN (管理用户)
--   └── SYSADMIN (管理对象)
--       └── 自定义角色
--   └── PUBLIC (所有用户默认拥有)

-- 创建自定义角色
CREATE ROLE analyst;
CREATE ROLE data_engineer;

-- 角色层次: 将自定义角色挂到 SYSADMIN 下
GRANT ROLE analyst TO ROLE sysadmin;
GRANT ROLE data_engineer TO ROLE sysadmin;

-- 授权
GRANT USAGE ON DATABASE analytics TO ROLE analyst;
GRANT USAGE ON SCHEMA analytics.public TO ROLE analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics.public TO ROLE analyst;

-- 未来授权 (Future Grants): 自动给未来创建的对象授权
GRANT SELECT ON FUTURE TABLES IN SCHEMA analytics.public TO ROLE analyst;

-- 分配角色给用户
GRANT ROLE analyst TO USER alice;

-- 切换角色
USE ROLE analyst;
USE ROLE accountadmin;

-- Snowflake 的最佳实践:
-- 1. 不要直接使用 ACCOUNTADMIN 进行日常操作
-- 2. 创建细粒度的自定义角色
-- 3. 使用 FUTURE GRANTS 自动化权限管理
-- 4. 定期审计权限: SHOW GRANTS TO ROLE analyst;
```

### SQL Server RBAC

```sql
-- SQL Server 有丰富的角色体系

-- 服务器级角色 (固定):
-- sysadmin: 最高权限
-- securityadmin: 管理登录和权限
-- dbcreator: 创建数据库
-- bulkadmin: 执行 BULK INSERT

-- 数据库级角色 (固定):
-- db_owner: 数据库所有者
-- db_datareader: 读所有表
-- db_datawriter: 写所有表
-- db_ddladmin: 执行 DDL

-- 自定义角色:
CREATE ROLE analyst;
GRANT SELECT ON SCHEMA::dbo TO analyst;
ALTER ROLE analyst ADD MEMBER alice;

-- SQL Server 的 DENY: 明确拒绝 (优先于 GRANT!)
DENY SELECT ON employees(salary) TO analyst;
-- 即使 analyst 有 SELECT ON employees 的权限
-- 也不能查看 salary 列!
```

## SQL Server 的 DENY 优先级设计

### DENY > GRANT 原则

```sql
-- SQL Server 独特的权限模型: DENY 优先于 GRANT

-- 场景: alice 属于 analyst 和 manager 两个角色
-- analyst 角色: GRANT SELECT ON employees
-- manager 角色: DENY SELECT ON employees(salary)

-- 结果: alice 可以 SELECT employees, 但不能看 salary 列!
-- DENY 在任何角色中出现, 都会覆盖其他角色的 GRANT

-- 这与 PostgreSQL 不同:
-- PostgreSQL: 权限是累加的 (additive)
-- 没有 DENY 的概念, 只有 GRANT 和 REVOKE
-- REVOKE 只是移除之前的 GRANT, 不能"禁止"

-- SQL Server DENY 的典型用法:
-- 1. 隐藏薪资数据
DENY SELECT ON employees(salary) TO PUBLIC;
GRANT SELECT ON employees(salary) TO hr_manager;
-- 只有 hr_manager 角色能看薪资

-- 2. 禁止删除操作
DENY DELETE ON critical_data TO PUBLIC;
-- 所有人都不能删除 (除非 sysadmin)

-- 3. 阻断权限继承
-- 角色层次: junior -> senior -> admin
-- 但 junior 不应该访问某些表:
DENY SELECT ON secret_table TO junior;
-- 即使 junior 通过继承获得了 SELECT 权限, DENY 也会阻断
```

### 权限检查优先级

```
SQL Server 的权限检查顺序:

1. 服务器级 DENY -> 拒绝
2. 服务器级 GRANT -> 允许 (但继续检查数据库级)
3. 数据库级 DENY -> 拒绝
4. 数据库级 GRANT -> 允许 (但继续检查对象级)
5. Schema 级 DENY -> 拒绝
6. Schema 级 GRANT -> 允许
7. 对象级 DENY -> 拒绝
8. 对象级 GRANT -> 允许
9. 列级 DENY -> 拒绝
10. 列级 GRANT -> 允许

规则: 在任何层级遇到 DENY, 立即拒绝, 不再检查后续层级
```

## ABAC: 基于属性的访问控制

```
ABAC 基于动态属性做权限决策:

属性来源:
  用户属性: 部门, 职级, 地区, 入职时间
  资源属性: 数据分类, 敏感等级, 创建时间
  环境属性: 时间, IP 地址, 设备类型
  操作属性: 读/写/删除

策略示例:
  "允许 部门=HR 且 职级>=3 的用户 在工作时间 从公司网络 访问 薪资数据"

  这在传统 RBAC 中很难表达:
  - 需要为每个 (部门, 职级, 时间, 网络) 组合创建角色
  - 角色爆炸!

数据库中的 ABAC:
  很少有数据库原生支持纯 ABAC
  通常通过 RLS (Row-Level Security) + 应用层 session 变量模拟:
```

```sql
-- PostgreSQL: 用 RLS + session 变量模拟 ABAC
-- 设置用户属性
SET app.current_department = 'HR';
SET app.current_level = '3';

-- 策略引用这些属性
CREATE POLICY salary_access ON employees
    FOR SELECT
    USING (
        current_setting('app.current_department') = 'HR'
        AND current_setting('app.current_level')::int >= 3
    );
```

## IAM 集成

### BigQuery (GCP IAM)

```sql
-- BigQuery 完全使用 GCP IAM 管理权限
-- 没有传统的 GRANT/REVOKE SQL 语句

-- IAM 角色 (预定义):
-- roles/bigquery.dataViewer   -> 查看数据集和表
-- roles/bigquery.dataEditor   -> 编辑数据
-- roles/bigquery.dataOwner    -> 完全控制数据
-- roles/bigquery.jobUser      -> 执行查询
-- roles/bigquery.admin        -> 完全管理权限

-- 通过 gcloud 命令授权:
-- gcloud projects add-iam-policy-binding myproject \
--   --member="user:alice@example.com" \
--   --role="roles/bigquery.dataViewer"

-- 数据集级别:
-- gcloud bigquery datasets add-iam-policy-binding mydataset \
--   --member="user:alice@example.com" \
--   --role="roles/bigquery.dataViewer"

-- BigQuery 也支持表级别的 IAM:
-- 在 BigQuery UI 或 API 中设置

-- 自定义角色:
-- 可以组合细粒度权限创建自定义角色:
-- bigquery.tables.getData     -> 读取表数据
-- bigquery.tables.create      -> 创建表
-- bigquery.tables.delete      -> 删除表
-- bigquery.jobs.create         -> 创建查询任务
```

### Amazon Redshift (AWS IAM)

```sql
-- Redshift 混合使用 SQL GRANT/REVOKE 和 AWS IAM

-- SQL 级别权限 (传统):
GRANT SELECT ON employees TO GROUP analysts;
GRANT ALL ON SCHEMA public TO admin;

-- IAM 身份认证:
-- 用户可以通过 IAM 角色登录 Redshift
-- 无需创建数据库用户和密码

-- IAM 策略控制的权限:
-- redshift:GetClusterCredentials -> 获取临时密码
-- redshift:JoinGroup             -> 加入 Redshift 组
-- redshift:CreateClusterUser     -> 自动创建数据库用户

-- 联邦查询的 IAM:
-- Redshift Spectrum 查询 S3 数据时, 使用 IAM 角色:
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'my_glue_db'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftSpectrumRole';
-- IAM 角色需要 S3 读取权限和 Glue 目录权限
```

## Row-Level Security (行级安全)

### PostgreSQL RLS

```sql
-- PostgreSQL: 最灵活的 RLS 实现

-- 启用 RLS
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- 创建策略: 用户只能看到自己部门的数据
CREATE POLICY dept_isolation ON employees
    FOR ALL                    -- 对所有操作生效
    TO PUBLIC                  -- 对所有用户
    USING (dept_id = current_setting('app.dept_id')::int);

-- 多个策略 (OR 关系):
CREATE POLICY own_data ON employees
    FOR SELECT
    USING (user_id = current_user);

CREATE POLICY manager_view ON employees
    FOR SELECT
    TO manager_role
    USING (true);  -- 管理员可以看所有数据

-- 策略组合规则:
-- 同一角色的多个策略: OR (任一满足即允许)
-- 不同角色的策略: 每个角色独立检查

-- WITH CHECK: 控制写入 (INSERT/UPDATE)
CREATE POLICY write_own_dept ON employees
    FOR INSERT
    WITH CHECK (dept_id = current_setting('app.dept_id')::int);
-- 只能插入自己部门的数据

-- USING vs WITH CHECK:
-- USING: 控制可见行 (SELECT/UPDATE/DELETE 的 WHERE)
-- WITH CHECK: 控制可写行 (INSERT 的新行, UPDATE 的新值)

-- 超级用户和表所有者默认绕过 RLS!
-- 要强制所有人都受 RLS 限制:
ALTER TABLE employees FORCE ROW LEVEL SECURITY;
```

### SQL Server 安全策略

```sql
-- SQL Server: 通过内联表值函数实现 RLS

-- 步骤 1: 创建谓词函数
CREATE FUNCTION dbo.fn_securitypredicate(@dept_id INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE @dept_id = (
    SELECT dept_id FROM dbo.user_departments
    WHERE user_name = USER_NAME()
);

-- 步骤 2: 创建安全策略
CREATE SECURITY POLICY dbo.EmployeePolicy
ADD FILTER PREDICATE dbo.fn_securitypredicate(dept_id) ON dbo.employees,
ADD BLOCK PREDICATE dbo.fn_securitypredicate(dept_id) ON dbo.employees AFTER INSERT
WITH (STATE = ON);

-- FILTER PREDICATE: 控制可见行 (类似 PG 的 USING)
-- BLOCK PREDICATE: 控制可写行 (类似 PG 的 WITH CHECK)
--   AFTER INSERT: 插入后检查
--   BEFORE UPDATE: 更新前检查
--   BEFORE DELETE: 删除前检查

-- 优点: 函数可以包含复杂逻辑 (查表、计算等)
-- 缺点: 函数性能至关重要 (每行都调用!)
```

### Oracle VPD (Virtual Private Database)

```sql
-- Oracle: VPD (也叫 FGAC - Fine-Grained Access Control)

-- 步骤 1: 创建策略函数
CREATE OR REPLACE FUNCTION dept_policy(
    p_schema VARCHAR2,
    p_table VARCHAR2
) RETURN VARCHAR2 AS
BEGIN
    RETURN 'dept_id = SYS_CONTEXT(''USERENV'', ''CLIENT_INFO'')';
END;

-- 步骤 2: 应用策略
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema => 'HR',
        object_name => 'EMPLOYEES',
        policy_name => 'DEPT_ISOLATION',
        function_schema => 'HR',
        policy_function => 'DEPT_POLICY',
        statement_types => 'SELECT, INSERT, UPDATE, DELETE'
    );
END;

-- 效果: 所有查询自动附加 WHERE dept_id = ...
-- 对应用透明, 无需修改 SQL

-- Oracle Data Redaction (动态数据掩码):
BEGIN
    DBMS_REDACT.ADD_POLICY(
        object_schema => 'HR',
        object_name => 'EMPLOYEES',
        column_name => 'SALARY',
        policy_name => 'SALARY_MASK',
        function_type => DBMS_REDACT.PARTIAL,
        function_parameters => '0,1,6'  -- 掩码中间部分
    );
END;
-- 普通用户查询时: salary 显示为 0
-- 特权用户查询时: 显示真实值
```

## Column-Level Security (列级安全)

### 列级权限

```sql
-- PostgreSQL:
GRANT SELECT (name, email) ON employees TO analyst;
-- analyst 只能查询 name 和 email, 不能查询 salary

-- MySQL:
GRANT SELECT (name, email) ON mydb.employees TO 'analyst'@'%';

-- SQL Server:
GRANT SELECT ON employees(name, email) TO analyst;
DENY SELECT ON employees(salary) TO analyst;

-- 限制:
-- 列级权限管理繁琐 (每个用户/角色 * 每张表 * 每列)
-- SELECT * 在有列级限制时可能报错或返回部分列
```

### 动态数据掩码 (Dynamic Data Masking)

```sql
-- SQL Server: 内置动态数据掩码
CREATE TABLE employees (
    id INT,
    name VARCHAR(100),
    email VARCHAR(100) MASKED WITH (FUNCTION = 'email()'),
    phone VARCHAR(20) MASKED WITH (FUNCTION = 'partial(0,"XXX-",4)'),
    salary DECIMAL(10,2) MASKED WITH (FUNCTION = 'default()')
);

-- 无权限用户查询:
-- email: aXXX@XXXX.com
-- phone: XXX-1234
-- salary: 0.00

-- 有权限用户查询 (UNMASK 权限):
-- email: alice@example.com
-- phone: 138-1234-5678
-- salary: 50000.00

GRANT UNMASK TO manager;
-- manager 角色可以看到真实数据

-- 掩码函数:
-- default():    数字->0, 字符串->'XXXX', 日期->01-01-2000
-- email():      aXXX@XXXX.com
-- partial(prefix, padding, suffix): 保留前缀和后缀, 中间填充
-- random(start, end): 数字随机化

-- Snowflake: 类似功能 (Dynamic Data Masking)
CREATE MASKING POLICY salary_mask AS (val NUMBER)
RETURNS NUMBER ->
    CASE
        WHEN CURRENT_ROLE() IN ('HR_ADMIN') THEN val
        ELSE NULL
    END;

ALTER TABLE employees MODIFY COLUMN salary SET MASKING POLICY salary_mask;
```

## 对引擎开发者: RBAC 是最低要求，RLS 是差异化能力

### 权限模型实现路线图

```
阶段 1: 基础 ACL (最低要求)
  - GRANT/REVOKE 对象级权限
  - 用户管理 (CREATE USER, ALTER USER, DROP USER)
  - 超级用户 (bypass 所有检查)

阶段 2: RBAC (标准要求)
  - CREATE ROLE / DROP ROLE
  - GRANT role TO user / REVOKE role FROM user
  - 角色继承 (角色包含角色)
  - 默认角色设置

阶段 3: 细粒度控制 (竞争优势)
  - 列级权限
  - Schema 级权限
  - DENY (可选, SQL Server 模式)

阶段 4: RLS (差异化能力)
  - 行级安全策略
  - 策略函数 (引用 session 变量、系统函数)
  - 对应用透明 (自动注入 WHERE 条件)

阶段 5: 高级安全 (企业级)
  - 动态数据掩码
  - 审计日志
  - IAM 集成
  - 加密 (TDE, 列级加密)
```

### 权限检查的性能优化

```
权限检查在每条 SQL 的执行路径上, 必须高效:

1. 缓存:
   - 权限信息缓存在内存中 (权限矩阵)
   - 用户登录时加载, GRANT/REVOKE 时失效
   - 避免每条 SQL 都查询系统表

2. 编译期检查 vs 运行期检查:
   - 对象级权限: 编译期检查 (计划生成时)
   - RLS: 运行期检查 (作为 WHERE 条件注入)

3. RLS 策略的优化:
   - 策略条件注入到查询优化器
   - 优化器可以将策略条件与用户条件合并优化
   - 例: 策略 dept_id = 1 AND 用户 status = 'active'
     -> 优化器合并为单次索引扫描

4. 位图权限:
   - 用 bitmap 表示权限集合
   - 权限检查 = bitmap AND 操作
   - 极快: 单条 CPU 指令
```

### 设计决策

```
1. DENY 是否需要?
   - 有 DENY: 权限模型更灵活, 但检查逻辑更复杂
   - 无 DENY: 简单, 权限只做加法
   - 建议: 新引擎可以先不做 DENY, 后续按需添加

2. 权限粒度:
   - 过细: 管理负担大, 性能检查开销大
   - 过粗: 不够灵活
   - 建议: 对象级 + 列级 + RLS, 三层足够

3. 权限传播:
   - WITH GRANT OPTION 增加复杂度
   - 级联 REVOKE 的实现需要追踪权限来源图
   - 建议: 初期不支持 WITH GRANT OPTION

4. 系统表设计:
   - pg_auth_members: 角色成员关系
   - pg_class.relacl: 对象 ACL
   - 建议: 使用独立的权限表, 避免与元数据表耦合
```

## 参考资料

- NIST: [RBAC Standard](https://csrc.nist.gov/projects/role-based-access-control)
- PostgreSQL: [Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- SQL Server: [Row-Level Security](https://learn.microsoft.com/en-us/sql/relational-databases/security/row-level-security)
- Oracle: [Virtual Private Database](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/using-oracle-virtual-private-database-to-control-data-access.html)
- Snowflake: [Access Control](https://docs.snowflake.com/en/user-guide/security-access-control)
- BigQuery: [IAM Roles](https://cloud.google.com/bigquery/docs/access-control)
