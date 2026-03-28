# Snowflake: 权限管理 (RBAC)

> 参考资料:
> - [1] Snowflake SQL Reference - GRANT
>   https://docs.snowflake.com/en/sql-reference/sql/grant-privilege
> - [2] Snowflake Documentation - Access Control
>   https://docs.snowflake.com/en/user-guide/security-access-control


## 1. 基本语法


角色层次（Snowflake 预定义）:
ACCOUNTADMIN（最高权限，包含 SECURITYADMIN + SYSADMIN）
`├── SECURITYADMIN（管理用户和角色）`
`│   └── USERADMIN（创建和管理用户）`
`├── SYSADMIN（管理数据库和仓库）`
`└── PUBLIC（所有用户默认拥有）`

创建自定义角色

```sql
CREATE ROLE analyst;
CREATE ROLE data_engineer;
CREATE ROLE app_reader;

```

角色继承

```sql
GRANT ROLE analyst TO ROLE data_engineer;  -- data_engineer 继承 analyst
GRANT ROLE data_engineer TO ROLE SYSADMIN; -- SYSADMIN 继承 data_engineer

```

将角色授予用户

```sql
GRANT ROLE analyst TO USER alice;

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 RBAC + DAC 双模型

 Snowflake 结合了两种访问控制模型:
   RBAC (Role-Based): 所有权限必须授予角色，用户通过角色获得权限
   DAC (Discretionary): 对象所有者自动拥有对象的全部权限

 关键设计决策: 权限只能授予角色，不能直接授予用户
 这与大多数数据库不同:
   MySQL:      GRANT SELECT ON db.* TO 'user'@'host';  -- 直接授予用户
   PostgreSQL: GRANT SELECT ON table TO user;           -- 直接授予用户
   Snowflake:  GRANT SELECT ON TABLE t TO ROLE r;       -- 只能授予角色

 设计理由:
   强制通过角色管理权限 → 权限管理更规范，避免"权限散落"
   每个用户可以有多个角色，切换角色改变权限上下文

 对比:
   Oracle:     RBAC（角色和用户都可以直接被授予权限）
   SQL Server: RBAC（角色和用户都可以）+ Windows 集成认证
   BigQuery:   IAM 模型（Project/Dataset/Table 三级，基于 Google IAM）
   Redshift:   类似 PostgreSQL（用户和角色都可以被授予权限）
   Databricks: Unity Catalog + IAM（元数据级别权限控制）

 对引擎开发者的启示:
   纯 RBAC 模型（只对角色授权）比混合模型更清晰，但灵活性稍低。
   Snowflake 的实践证明纯 RBAC 在企业级场景下更易管理。

### 2.2 Warehouse 权限: 计算资源的访问控制

Snowflake 独有: Warehouse（计算资源）也需要授权

```sql
GRANT USAGE ON WAREHOUSE compute_wh TO ROLE analyst;
```

 没有 WAREHOUSE 的 USAGE 权限 → 无法执行任何查询（即使有表的 SELECT 权限）
 这实现了: (a) 计算资源隔离 (b) 成本分摊 (c) 防止资源滥用

 对比: 传统数据库没有"计算资源权限"概念
   MySQL/PG/Oracle: 连接后直接使用服务器算力
   BigQuery: 按项目计费（Project 级别的隔离）

## 3. 权限层级


数据库级

```sql
GRANT USAGE ON DATABASE mydb TO ROLE analyst;
GRANT CREATE SCHEMA ON DATABASE mydb TO ROLE data_engineer;
GRANT ALL PRIVILEGES ON DATABASE mydb TO ROLE data_engineer;

```

Schema 级

```sql
GRANT USAGE ON SCHEMA mydb.public TO ROLE analyst;
GRANT CREATE TABLE ON SCHEMA mydb.public TO ROLE data_engineer;

```

表级

```sql
GRANT SELECT ON TABLE mydb.public.users TO ROLE analyst;
GRANT SELECT, INSERT, UPDATE ON TABLE mydb.public.users TO ROLE data_engineer;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA mydb.public TO ROLE data_engineer;

```

Warehouse 级

```sql
GRANT USAGE ON WAREHOUSE compute_wh TO ROLE analyst;
GRANT OPERATE ON WAREHOUSE compute_wh TO ROLE data_engineer;  -- 启停
GRANT MODIFY ON WAREHOUSE compute_wh TO ROLE data_engineer;   -- 修改属性

```

## 4. FUTURE GRANTS: 自动授权新对象


```sql
GRANT SELECT ON FUTURE TABLES IN SCHEMA mydb.public TO ROLE analyst;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN DATABASE mydb TO ROLE data_engineer;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA mydb.public TO ROLE analyst;

```

 FUTURE GRANTS 的实现:
   在 Schema/Database 元数据中记录授权规则。
   每次 CREATE TABLE/VIEW 时，自动检查并应用 FUTURE GRANT 规则。
   这消除了最大的运维痛点: 忘记给新表授权。

 对比:
   PostgreSQL:  ALTER DEFAULT PRIVILEGES（功能类似）
   MySQL:       无等价功能
   Oracle:      无等价功能（通常用同义词 + 角色）
   BigQuery:    IAM 继承（Dataset 级别自动继承）

## 5. 数据保护策略


### 5.1 列级数据脱敏 (Dynamic Data Masking)

```sql
CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ADMIN', 'DATA_ENGINEER') THEN val
        ELSE REGEXP_REPLACE(val, '.+@', '***@')
    END;

ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;
ALTER TABLE users ALTER COLUMN email UNSET MASKING POLICY;

```

 Masking Policy 在存储层强制执行（不是视图层面的过滤）
 即使用户有 SELECT 权限，也只能看到脱敏后的数据
 对比:
   Oracle VPD:       行级虚拟私有数据库（类似但更复杂）
   PostgreSQL:       无原生列级脱敏（需要视图或 RLS）
   BigQuery:         列级安全 + 数据策略标签

### 5.2 行级访问策略 (Row Access Policy)

```sql
CREATE ROW ACCESS POLICY region_policy AS (region_val VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ADMIN') OR region_val = CURRENT_USER();

ALTER TABLE orders ADD ROW ACCESS POLICY region_policy ON (region);
ALTER TABLE orders DROP ROW ACCESS POLICY region_policy;

```

 对比:
   PostgreSQL RLS: CREATE POLICY ... USING (region = current_user)
   Oracle VPD:     DBMS_RLS.ADD_POLICY
   SQL Server:     Security predicate functions

### 5.3 网络策略

```sql
CREATE NETWORK POLICY office_only
    ALLOWED_IP_LIST = ('203.0.113.0/24', '198.51.100.0/24')
    BLOCKED_IP_LIST = ('203.0.113.100');
ALTER USER alice SET NETWORK_POLICY = office_only;

```

## 6. 撤销权限

```sql
REVOKE SELECT ON TABLE mydb.public.users FROM ROLE analyst;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA mydb.public FROM ROLE analyst;
REVOKE ROLE analyst FROM USER alice;

```

## 7. 权限查看

```sql
SHOW GRANTS TO ROLE analyst;
SHOW GRANTS ON TABLE mydb.public.users;
SHOW GRANTS TO USER alice;
SHOW ROLES;
SHOW USERS;

```

## 横向对比: 权限模型矩阵

| 能力               | Snowflake   | BigQuery    | PostgreSQL  | Oracle |
|------|------|------|------|------|
| 权限模型           | 纯 RBAC     | IAM         | RBAC+DAC    | RBAC+DAC |
| 直接授权用户       | 不支持      | 支持(IAM)   | 支持        | 支持 |
| 角色继承           | 支持        | N/A(IAM)    | 支持        | 支持 |
| 计算资源权限       | Warehouse   | Project     | 无          | 无 |
| FUTURE GRANTS      | 原生支持    | IAM继承     | DEFAULT PRIV| 无 |
| 列级脱敏           | Masking Pol | 数据策略    | 无原生      | VPD |
| 行级安全           | Row Access  | Row-level   | RLS         | VPD/FGAC |
| 网络策略           | Network Pol | VPC SC      | pg_hba.conf | 监听器配置 |

