# 行级安全 (Row-Level Security, RLS)

数据库层面控制"谁能看到哪些行"——多租户、数据权限、GDPR 合规的基础能力。

## 支持矩阵

| 引擎 | 特性名称 | 版本 | 实现方式 | 备注 |
|------|---------|------|---------|------|
| PostgreSQL | Row Level Security (RLS) | 9.5+ | CREATE POLICY | **最灵活的开源实现** |
| SQL Server | Row-Level Security | 2016+ | SECURITY POLICY + 谓词函数 | 基于内联表值函数 |
| Oracle | Virtual Private Database (VPD) | 8i+ | DBMS_RLS.ADD_POLICY | **最早的实现** |
| Snowflake | Row Access Policies | GA | CREATE ROW ACCESS POLICY | 企业级方案 |
| BigQuery | Row-Level Security | GA | CREATE ROW ACCESS POLICY | 基于 IAM 集成 |
| Db2 | Row and Column Access Control | 10.1+ | CREATE PERMISSION | - |
| MySQL | 不支持 | - | - | 需视图或应用层模拟 |
| SQLite | 不支持 | - | - | - |
| ClickHouse | Row Policies | 21.8+ | CREATE ROW POLICY | - |
| MariaDB | 不支持 | - | - | - |

## 设计动机

### 问题场景

```sql
-- 多租户 SaaS 系统: 每个租户只能看到自己的数据
-- 传统方式: 在每个查询中手动加 WHERE tenant_id = ?
SELECT * FROM orders WHERE tenant_id = 'acme';        -- 开发者必须记得加条件
SELECT * FROM customers WHERE tenant_id = 'acme';     -- 每个表、每个查询都要加
SELECT * FROM invoices WHERE tenant_id = 'acme';      -- 遗漏一次就是安全事故

-- 问题:
-- 1. 开发者遗忘 WHERE 条件 → 数据泄露
-- 2. 复杂查询（JOIN、子查询）中难以确保每处都加了条件
-- 3. ad-hoc 查询（BI 工具直连数据库）无法控制
-- 4. 审计困难: 无法确认所有查询路径都安全
```

### RLS 的解决方案

```sql
-- 数据库层面自动注入 WHERE 条件
-- 不管查询怎么写，都只能看到属于自己的数据

-- 1. 定义策略: tenant_id 必须等于当前用户的 tenant
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.current_tenant'));

-- 2. 启用 RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 3. 之后所有查询自动过滤
SELECT * FROM orders;  -- 实际执行: SELECT * FROM orders WHERE tenant_id = 'acme'
-- 开发者不需要写 WHERE 条件，数据库自动保证隔离
```

## 各引擎语法对比

### PostgreSQL (9.5+)

```sql
-- 1. 创建表
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    owner TEXT NOT NULL,
    department TEXT NOT NULL,
    content TEXT,
    classification TEXT DEFAULT 'public'  -- public, internal, secret
);

-- 2. 启用 RLS（必须显式启用）
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- 3. 创建策略

-- 策略: 用户只能看到自己部门的文档
CREATE POLICY dept_policy ON documents
    FOR SELECT                              -- 适用于 SELECT
    TO PUBLIC                               -- 适用于所有角色
    USING (department = current_setting('app.department'));

-- 策略: 用户只能修改自己的文档
CREATE POLICY owner_update ON documents
    FOR UPDATE
    USING (owner = current_user)             -- 已有行的条件（可见性）
    WITH CHECK (owner = current_user);       -- 新值的条件（写入检查）

-- 策略: 插入时必须是自己的文档
CREATE POLICY owner_insert ON documents
    FOR INSERT
    WITH CHECK (owner = current_user);

-- 策略: 只能删除自己的文档
CREATE POLICY owner_delete ON documents
    FOR DELETE
    USING (owner = current_user);

-- 多个策略的组合逻辑:
-- 同一命令类型(SELECT)的多个策略: OR 关系（满足任一即可）
-- 不同命令类型(SELECT vs UPDATE)的策略: 独立生效

-- PERMISSIVE(默认) vs RESTRICTIVE 策略
-- PERMISSIVE: 多个策略之间是 OR 关系
-- RESTRICTIVE: 与 PERMISSIVE 策略是 AND 关系

CREATE POLICY classification_restrict ON documents
    AS RESTRICTIVE                          -- 限制性策略
    FOR SELECT
    USING (classification != 'secret' OR
           current_user = ANY(SELECT username FROM secret_clearance));
-- 结果: (dept_policy 通过) AND (classification_restrict 通过) 才能看到

-- 表的所有者（superuser）默认绕过 RLS
-- 要强制所有者也受限:
ALTER TABLE documents FORCE ROW LEVEL SECURITY;

-- 设置会话变量（通常在连接池的连接初始化中设置）
SET app.current_tenant = 'acme';
SET app.department = 'engineering';
```

### SQL Server (2016+)

```sql
-- SQL Server 使用安全策略 + 内联表值函数

-- 1. 创建谓词函数
CREATE FUNCTION dbo.fn_securitypredicate(@tenant_id NVARCHAR(50))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE @tenant_id = SESSION_CONTEXT(N'tenant_id')
   OR IS_MEMBER('db_owner') = 1;              -- DBA 可以看到所有

-- 2. 创建安全策略
CREATE SECURITY POLICY TenantFilter
ADD FILTER PREDICATE dbo.fn_securitypredicate(tenant_id) ON dbo.orders,
ADD BLOCK PREDICATE dbo.fn_securitypredicate(tenant_id) ON dbo.orders
    AFTER INSERT,                              -- 插入后检查
ADD BLOCK PREDICATE dbo.fn_securitypredicate(tenant_id) ON dbo.orders
    AFTER UPDATE                               -- 更新后检查
WITH (STATE = ON);

-- 3. 设置会话上下文
EXEC sp_set_session_context @key = N'tenant_id', @value = N'acme';

-- FILTER PREDICATE: 控制可见性（SELECT/UPDATE/DELETE 能看到哪些行）
-- BLOCK PREDICATE: 控制写入（INSERT/UPDATE 后的行是否合法）
-- BLOCK 的时机:
--   AFTER INSERT: 插入后检查新行
--   AFTER UPDATE: 更新后检查新值
--   BEFORE UPDATE: 更新前检查旧行（限制可更新的行）
--   BEFORE DELETE: 删除前检查（限制可删除的行）

-- 查看安全策略
SELECT * FROM sys.security_policies;
SELECT * FROM sys.security_predicates;
```

### Oracle VPD (Virtual Private Database)

```sql
-- Oracle 的 VPD 是最早的行级安全实现
-- 通过 PL/SQL 函数动态生成 WHERE 子句

-- 1. 创建策略函数
CREATE OR REPLACE FUNCTION tenant_policy(
    p_schema IN VARCHAR2,
    p_object IN VARCHAR2
) RETURN VARCHAR2
IS
BEGIN
    -- 返回 WHERE 子句的条件部分
    IF SYS_CONTEXT('userenv', 'session_user') = 'ADMIN' THEN
        RETURN NULL;           -- NULL 表示无限制
    ELSE
        RETURN 'tenant_id = SYS_CONTEXT(''app_ctx'', ''tenant_id'')';
    END IF;
END;
/

-- 2. 绑定策略到表
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema   => 'APP',
        object_name     => 'ORDERS',
        policy_name     => 'TENANT_ISOLATION',
        function_schema => 'APP',
        policy_function => 'TENANT_POLICY',
        statement_types => 'SELECT, INSERT, UPDATE, DELETE',
        update_check    => TRUE          -- UPDATE/INSERT 后检查新值
    );
END;
/

-- 3. 设置应用上下文
CREATE OR REPLACE CONTEXT app_ctx USING set_tenant_proc;

CREATE OR REPLACE PROCEDURE set_tenant_proc(
    p_tenant_id IN VARCHAR2
) IS
BEGIN
    DBMS_SESSION.SET_CONTEXT('app_ctx', 'tenant_id', p_tenant_id);
END;
/

-- VPD 的高级特性:
-- 列级 VPD: 只在查询特定列时才触发策略
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_name     => 'EMPLOYEES',
        policy_name     => 'SALARY_POLICY',
        policy_function => 'SALARY_FILTER',
        sec_relevant_cols => 'salary, bonus',     -- 只在查询这些列时触发
        sec_relevant_cols_opt => DBMS_RLS.ALL_ROWS  -- 显示所有行但敏感列为NULL
    );
END;
/
```

### Snowflake Row Access Policies

```sql
-- 1. 创建行访问策略
CREATE OR REPLACE ROW ACCESS POLICY tenant_policy AS (tenant_id VARCHAR)
RETURNS BOOLEAN ->
    tenant_id = CURRENT_ROLE()
    OR IS_ROLE_IN_SESSION('ADMIN');

-- 2. 应用策略到表
ALTER TABLE orders ADD ROW ACCESS POLICY tenant_policy ON (tenant_id);

-- 更复杂的策略: 基于映射表
CREATE OR REPLACE ROW ACCESS POLICY data_access AS (region VARCHAR)
RETURNS BOOLEAN ->
    EXISTS (
        SELECT 1 FROM access_control.region_mapping
        WHERE role_name = CURRENT_ROLE()
          AND allowed_region = region
    );

ALTER TABLE sales ADD ROW ACCESS POLICY data_access ON (region);

-- 一个表只能有一个行访问策略
-- 要替换需要先移除再添加
ALTER TABLE orders DROP ROW ACCESS POLICY tenant_policy;
ALTER TABLE orders ADD ROW ACCESS POLICY new_policy ON (tenant_id);
```

### BigQuery Row Access Policies

```sql
-- BigQuery 的 RLS 基于 IAM 集成
-- 使用 TRUE/FALSE FILTER 控制行可见性

CREATE ROW ACCESS POLICY region_filter
ON project.dataset.sales
GRANT TO ('user:analyst@example.com', 'group:us-team@example.com')
FILTER USING (region = 'US');

-- 多个策略: OR 关系
CREATE ROW ACCESS POLICY eu_filter
ON project.dataset.sales
GRANT TO ('group:eu-team@example.com')
FILTER USING (region = 'EU');

-- 管理员可以看到所有数据
CREATE ROW ACCESS POLICY admin_access
ON project.dataset.sales
GRANT TO ('group:admins@example.com')
FILTER USING (TRUE);                    -- TRUE = 无限制

-- 没有任何策略匹配的用户: 看不到任何行
```

## MySQL 替代方案

```sql
-- MySQL 不支持原生 RLS，常见替代方案:

-- 方案 1: 视图 + 会话变量
SET @current_tenant = 'acme';

CREATE VIEW orders_secure AS
SELECT * FROM orders WHERE tenant_id = @current_tenant;

GRANT SELECT ON orders_secure TO app_user;
REVOKE SELECT ON orders FROM app_user;
-- 问题: 会话变量可被用户修改

-- 方案 2: 视图 + USER() 函数
CREATE VIEW orders_secure AS
SELECT * FROM orders
WHERE tenant_id = (
    SELECT tenant_id FROM user_tenant_mapping WHERE db_user = USER()
);
-- 更安全，但每次查询都要子查询映射表

-- 方案 3: 应用层中间件
-- 在 ORM/框架层面自动注入 WHERE 条件
-- Django: 自定义 Manager
-- Rails: default_scope
-- 风险: 绕过框架直接查询时无保护
```

## 实现原理: 查询重写

```sql
-- RLS 的核心实现: 在查询优化阶段自动注入 WHERE 条件

-- 用户提交的查询:
SELECT o.*, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.amount > 1000;

-- 引擎重写后的查询（用户不可见）:
SELECT o.*, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.amount > 1000
  AND o.tenant_id = 'acme'             -- orders 表的 RLS 策略
  AND c.tenant_id = 'acme';            -- customers 表的 RLS 策略

-- 子查询中也会注入:
SELECT * FROM (SELECT * FROM orders) t
→ SELECT * FROM (SELECT * FROM orders WHERE tenant_id = 'acme') t

-- VIEW 上的 RLS:
CREATE VIEW order_summary AS SELECT dept, SUM(amount) FROM orders GROUP BY dept;
SELECT * FROM order_summary;
→ SELECT * FROM (
    SELECT dept, SUM(amount) FROM orders WHERE tenant_id = 'acme' GROUP BY dept
  ) order_summary;
```

## 安全风险: 侧信道攻击

### 时间侧信道

```sql
-- 攻击者虽然看不到其他租户的数据，但可能通过执行时间推断:

-- 查询 1: 如果其他租户有大量数据，即使 RLS 过滤了，扫描时间也会变长
SELECT COUNT(*) FROM orders;
-- 如果总数据量从 100 万变到 1000 万，执行时间变化暴露了其他租户的数据规模

-- 防御: 使用索引让 RLS 条件在存储层就过滤（避免全表扫描）
CREATE INDEX idx_orders_tenant ON orders (tenant_id);
-- 这样查询计划从 SeqScan + Filter 变为 IndexScan，避免扫描其他租户的数据
```

### 错误信息侧信道

```sql
-- 攻击者可能通过唯一约束错误推断数据存在性:

INSERT INTO users (email, tenant_id) VALUES ('admin@other.com', 'attacker');
-- 如果报错 "duplicate key value violates unique constraint"
-- 攻击者知道 admin@other.com 存在于其他租户

-- 防御: 唯一约束应包含 tenant_id
CREATE UNIQUE INDEX idx_users_email ON users (tenant_id, email);
-- 而不是全局唯一: CREATE UNIQUE INDEX idx_users_email ON users (email);
```

### EXPLAIN 侧信道

```sql
-- EXPLAIN 可能泄露表的总行数
EXPLAIN SELECT * FROM orders WHERE amount > 1000;
-- "Seq Scan on orders (cost=... rows=50000)"
-- rows=50000 可能暴露总行数

-- PostgreSQL 的 EXPLAIN 会考虑 RLS 策略，但统计信息可能未更新
-- 建议: 限制普通用户使用 EXPLAIN
```

## 对引擎开发者的实现建议

### 1. 查询重写的时机

```
解析 → 语义分析 → 【RLS 策略注入】 → 查询优化 → 执行

在语义分析之后、优化器之前注入 RLS 条件:
- 太早（解析阶段）: 还不知道表的 schema 和策略
- 太晚（优化后）: 优化器无法利用 RLS 条件做索引选择和谓词下推
```

### 2. 策略缓存

```
-- 每次查询都要查询策略表是不可接受的
-- 建议: 在会话级别缓存策略定义

SessionCache {
    policies: Map<TableId, List<Policy>>
    last_refresh: Timestamp

    fn get_policy(table_id):
        if policies[table_id] is expired:
            policies[table_id] = load_from_catalog(table_id)
        return policies[table_id]
}

-- 策略变更时通过 DDL 事件通知各会话刷新缓存
```

### 3. 性能考量

RLS 策略中避免使用相关子查询或函数调用，因为这些会在每行上执行：

```sql
-- 差: 每行执行一次子查询
USING (tenant_id IN (SELECT tenant_id FROM user_tenants WHERE user_id = current_user))

-- 好: 预先计算并存入会话变量
SET app.tenant_id = 'acme';
USING (tenant_id = current_setting('app.tenant_id'))

-- 好: 使用缓存的角色信息
USING (tenant_id = current_user)
```

## 参考资料

- PostgreSQL: [Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- SQL Server: [Row-Level Security](https://learn.microsoft.com/en-us/sql/relational-databases/security/row-level-security)
- Oracle: [Virtual Private Database](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/using-oracle-virtual-private-database-to-control-data-access.html)
- Snowflake: [Row Access Policies](https://docs.snowflake.com/en/sql-reference/sql/create-row-access-policy)
- BigQuery: [Row-Level Security](https://cloud.google.com/bigquery/docs/row-level-security-intro)
