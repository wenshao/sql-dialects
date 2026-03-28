# MaxCompute (ODPS): 权限管理

> 参考资料:
> - [1] MaxCompute - Security Overview
>   https://help.aliyun.com/zh/maxcompute/user-guide/security-overview
> - [2] MaxCompute - Authorization
>   https://help.aliyun.com/zh/maxcompute/user-guide/authorization


## 1. 四层安全模型 —— MaxCompute 的安全架构


 第一层: RAM（阿里云资源访问管理）
   控制"谁能访问 MaxCompute 服务"
   在阿里云控制台配置，不在 SQL 中操作
   JSON 策略示例:
   {"Statement": [{"Action": ["odps:*"], "Effect": "Allow",
     "Resource": ["acs:odps:*:*:projects/myproject"]}], "Version": "1"}

 第二层: ACL（访问控制列表）
   控制"用户在项目内能做什么"（SQL 中操作）

 第三层: Policy（策略授权）
   更灵活的条件授权（基于时间、IP、标签等）

 第四层: Label Security（列级安全标签）
   控制"用户能看到哪些敏感列"

 设计分析: 为什么需要四层?
   第一层（RAM）: 云平台级身份认证（谁是谁）
   第二层（ACL）: 项目级授权（能做什么）
   第三层（Policy）: 条件授权（在什么条件下能做什么）
   第四层（Label）: 数据级保护（能看到什么数据）

   对比:
     MySQL:      用户+权限（一层，简单但不够灵活）
     PostgreSQL: 角色+权限+行级安全策略（两层半）
     BigQuery:   GCP IAM + Dataset/Table 权限 + 列级安全（三层）
     Snowflake:  RBAC + DAC + 行访问策略 + 动态数据掩码（四层）

## 2. ACL 授权操作


创建角色

```sql
CREATE ROLE analyst;
CREATE ROLE data_engineer;

```

表权限

```sql
GRANT SELECT ON TABLE users TO USER alice;
GRANT SELECT, INSERT ON TABLE users TO USER alice;
GRANT ALL ON TABLE users TO ROLE analyst;
GRANT DESCRIBE ON TABLE users TO USER RAM$bob;

```

项目权限

```sql
GRANT CREATETABLE ON PROJECT myproject TO USER alice;
GRANT CREATEINSTANCE ON PROJECT myproject TO USER alice;

```

Schema 权限（3.0+）

```sql
GRANT SELECT ON SCHEMA myschema TO ROLE analyst;

```

角色授予用户

```sql
GRANT analyst TO USER alice;
GRANT data_engineer TO USER bob;

```

撤销权限

```sql
REVOKE SELECT ON TABLE users FROM USER alice;
REVOKE ALL ON TABLE users FROM ROLE analyst;
REVOKE analyst FROM USER alice;

```

查看权限

```sql
SHOW GRANTS FOR USER alice;
SHOW GRANTS ON TABLE users;
WHOAMI;                                     -- 查看当前身份
LIST ROLES;

```

内置角色:
ProjectOwner: 项目所有者（最高权限）
Admin: 项目管理员
Super: 超级管理员


```sql
DROP ROLE analyst;

```

## 3. Label Security（列级安全标签）


标签级别: 0（公开）→ 4（最高机密）

设置列的安全级别

```sql
SET LABEL 2 TO TABLE users;                 -- 整表设为级别 2
SET LABEL 3 TO TABLE users(email, phone);   -- 特定列设为级别 3
SET LABEL 4 TO TABLE users(id_card);        -- 身份证设为级别 4

```

授予用户标签权限

```sql
GRANT LABEL 2 TO USER alice;                -- alice 可访问级别 0-2
GRANT LABEL 3 TO USER bob;                  -- bob 可访问级别 0-3

```

查看标签

```sql
SHOW LABEL GRANTS ON TABLE users;
SHOW LABEL GRANTS FOR USER alice;

```

清除标签

```sql
SET LABEL 0 TO TABLE users(email);

```

 Label Security 的工作原理:
   用户 alice（级别 2）查询 SELECT * FROM users:
     id, username: 级别 0 → 可见
     email, phone: 级别 3 → 不可见（被掩码或报错）
     id_card: 级别 4 → 不可见

   这比逐列 GRANT/REVOKE 高效得多:
     100 个敏感列 × 50 个用户 = 5000 条 GRANT 语句
     Label Security: 设置列级别 + 设置用户级别 = 150 条语句

 对比:
   Oracle:     Label Security（最早的实现，独立模块）
   BigQuery:   Policy Tags（类似标签机制）
   Snowflake:  Dynamic Data Masking + Row Access Policy
   PostgreSQL: 行级安全策略（Row Level Security，无列级标签）

## 4. Package —— 跨项目安全数据共享


项目 A 中:

```sql
CREATE PACKAGE my_package;
ADD TABLE users TO PACKAGE my_package;
ADD TABLE orders TO PACKAGE my_package;
ALLOW PROJECT project_b TO INSTALL PACKAGE my_package;

```

项目 B 中:

```sql
INSTALL PACKAGE project_a.my_package;
```

 访问: SELECT * FROM project_a.my_package.users;

 Package 的设计价值:
   跨项目共享数据而不暴露底层表结构
   可以精确控制共享哪些表/视图
   对比: BigQuery 的 Authorized Views / Datasets

## 5. ProjectProtection —— 数据不出项目


```sql
SET ProjectProtection = true;               -- 禁止数据流出项目

```

例外: 允许向特定项目流出

```sql
ADD TRUSTED PROJECT project_b;

```

查看安全配置

```sql
SHOW SecurityConfiguration;

```

 ProjectProtection 的场景:
   金融/医疗数据: 数据不能离开指定项目
   多租户隔离: 租户 A 的数据不能流向租户 B
   合规要求: GDPR/等保等合规要求数据不出区域

## 6. IP 白名单与审计


IP 白名单: 在阿里云控制台设置（非 SQL）
审计日志: INFORMATION_SCHEMA.TASKS_HISTORY

```sql
SELECT * FROM INFORMATION_SCHEMA.TASKS_HISTORY
WHERE task_type = 'SQL'
ORDER BY create_time DESC LIMIT 10;

```

## 7. 横向对比: 安全能力


 身份认证:
MaxCompute: 阿里云 RAM           | BigQuery: GCP IAM
Snowflake:  内部用户 + SSO       | PostgreSQL: 内部用户 + LDAP

 列级安全:
MaxCompute: Label Security       | BigQuery: Policy Tags
Snowflake:  Dynamic Data Masking | PostgreSQL: 视图（无原生列级安全）

 行级安全:
MaxCompute: 不支持               | PostgreSQL: Row Level Security
Snowflake:  Row Access Policy    | BigQuery: 不支持（原生）

 跨项目共享:
MaxCompute: Package              | BigQuery: Authorized Views/Datasets
Snowflake:  Data Sharing         | PostgreSQL: 不支持

 数据流出控制:
MaxCompute: ProjectProtection    | BigQuery: VPC Service Controls
Snowflake:  不支持               | PostgreSQL: 不支持

## 8. 对引擎开发者的启示


1. Label Security 是列级安全最简洁的方案（比逐列 GRANT 高效得多）

2. 与云平台 IAM 集成（而非自建用户系统）是云数仓的最佳实践

3. ProjectProtection 类数据流出控制是企业客户的刚需

4. Package 类跨项目共享机制解决了多租户数据协作问题

5. 行级安全（RLS）在数据仓库中越来越重要 — 应纳入规划

6. 审计日志是安全合规的基础 — 所有操作应可追溯

