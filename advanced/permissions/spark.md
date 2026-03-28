# Spark SQL: 权限管理 (Permissions & Access Control)

> 参考资料:
> - [1] Databricks Unity Catalog
>   https://docs.databricks.com/en/data-governance/unity-catalog/index.html
> - [2] Apache Ranger
>   https://ranger.apache.org/
> - [3] Spark SQL - Security
>   https://spark.apache.org/docs/latest/security.html


## 1. 核心设计: Spark SQL 没有内建权限系统


 Spark SQL 本身不管理用户身份、角色和权限。
 这是"计算引擎"与"数据库"的根本差异:
   数据库（MySQL/PostgreSQL）: 内建完整的认证（Authentication）+ 授权（Authorization）
   计算引擎（Spark）: 安全由底层平台提供（存储层权限、外部策略引擎、平台 IAM）

 对比:
   MySQL:      CREATE USER + GRANT/REVOKE + 完整 RBAC
   PostgreSQL: 完整 RBAC + 行级安全（RLS）+ 列级权限
   Oracle:     VPD（Virtual Private Database）+ 标签安全 + FGA（细粒度审计）
   BigQuery:   依赖 Google Cloud IAM（项目/数据集/表级别）
   Snowflake:  内建完整 RBAC + 数据脱敏 + 行级安全
   Hive:       SQL Standard Authorization 或 Apache Ranger
   Flink SQL:  无权限管理（依赖部署平台）
   Trino:      可插拔授权（File-based / Ranger / OPA）
   MaxCompute: 内建 ACL + Policy + Label Security

## 2. 方案一: Databricks Unity Catalog（最完善）


 Unity Catalog 提供三级命名空间的统一权限管理:
 Catalog -> Schema -> Table/View/Function

 Catalog 级权限
 CREATE CATALOG analytics;
 GRANT USE CATALOG ON CATALOG analytics TO `alice@company.com`;
 GRANT CREATE SCHEMA ON CATALOG analytics TO `data_engineers`;

 Schema 级权限
 CREATE SCHEMA analytics.sales;
 GRANT USE SCHEMA ON SCHEMA analytics.sales TO `analysts`;
 GRANT SELECT ON SCHEMA analytics.sales TO `analysts`;
 GRANT CREATE TABLE ON SCHEMA analytics.sales TO `data_engineers`;

 表级权限
 GRANT SELECT ON TABLE analytics.sales.orders TO `alice@company.com`;
 GRANT MODIFY ON TABLE analytics.sales.orders TO `data_engineers`;

 列级权限（Unity Catalog 独有）
 GRANT SELECT (username, email) ON TABLE users TO `analysts`;

 行级安全（Row Filter）
 ALTER TABLE users SET ROW FILTER filter_by_department ON (department_id);

 列级脱敏（Column Masking）
 ALTER TABLE users ALTER COLUMN email SET MASK mask_email;

 Unity Catalog 的设计启示:
   统一 Catalog 层的权限管理是 Lakehouse 架构的关键——
   传统的存储层权限（HDFS ACL）粒度太粗（文件/目录级别），
   而表级/列级/行级的细粒度控制需要在 Catalog 层实现。

## 3. 方案二: SQL Standard Authorization（Thrift Server）


通过 HiveServer2 / Spark Thrift Server 启用标准 SQL 授权:
SET hive.security.authorization.manager =
org.apache.hadoop.hive.ql.security.authorization.plugin.sqlstd.SQLStdHiveAuthorizerFactory;


```sql
GRANT SELECT ON TABLE users TO USER alice;
GRANT SELECT, INSERT ON TABLE users TO USER alice;
GRANT ALL PRIVILEGES ON TABLE users TO USER alice;
GRANT SELECT ON DATABASE mydb TO USER alice;

REVOKE SELECT ON TABLE users FROM USER alice;
REVOKE ALL PRIVILEGES ON TABLE users FROM USER alice;

CREATE ROLE analyst;
GRANT SELECT ON TABLE users TO ROLE analyst;
GRANT ROLE analyst TO USER alice;

SHOW GRANT ON TABLE users;
SHOW GRANT USER alice ON TABLE users;

```

## 4. 方案三: Apache Ranger（企业级策略管理）


 Ranger 是 Hadoop 生态最广泛使用的授权框架:
   集中式策略管理（Web UI + REST API）
   支持 Spark、Hive、HBase、Kafka、HDFS 等
   提供列级、行级安全 + 审计日志
   通过 Ranger Plugin 在 Spark 执行前拦截 SQL 做权限检查

## 5. 方案四: 视图级访问控制（任何 Spark 环境）


通过视图限制数据访问（最简单、最通用的方案）

```sql
CREATE VIEW public_users AS
SELECT id, username, city FROM users;              -- 隐藏敏感列

CREATE VIEW my_department_orders AS
SELECT * FROM orders
WHERE department_id = current_user_department();   -- 行级过滤

```

## 6. 方案五: 存储层权限


 HDFS: hadoop fs -chmod 750 /data/users
 S3:   IAM Policy 控制 bucket/prefix 访问
 ADLS: Azure RBAC + ACL
 GCS:  Google Cloud IAM

 Spark ACL（UI 和 REST API 访问控制）:
 spark.acls.enable = true
 spark.admin.acls = admin_user
 spark.modify.acls = data_engineer

## 7. 安全设计建议（对引擎开发者）


 安全层次（从底到顶）:
   L1. 存储层权限（HDFS/S3 ACL）: 最底层保障，粒度粗（文件/目录）
   L2. 传输层加密（TLS/Kerberos）: 数据传输安全
   L3. 认证（Authentication）: 确认用户身份（Kerberos/LDAP/OAuth/SSO）
   L4. 授权（Authorization）: 确认用户权限（RBAC/ABAC/RLS）
   L5. 审计（Audit）: 记录谁做了什么操作
   L6. 数据保护（Masking/Encryption）: 敏感数据脱敏和加密

 Spark 本身只提供 L1 和 L2 的基础支持，L3-L6 需要外部系统:
   Unity Catalog: L3-L6 全覆盖（Databricks 平台）
   Ranger:        L3-L5 覆盖（开源 Hadoop 生态）
   Kerberos:      L2-L3 覆盖（身份认证）

## 8. 版本演进

Spark 2.0: SQL Standard Authorization（通过 Thrift Server）
Spark 3.0: 可插拔 Catalog 支持权限扩展
Spark 3.4: Catalog 级别权限 API 增强
Unity Catalog: 行级安全、列级脱敏、统一命名空间权限

限制:
开源 Spark SQL 无内建认证/授权
不支持 CREATE USER / ALTER USER / DROP USER
不支持行级安全策略（除非使用 Unity Catalog 或 Ranger）
不支持数据脱敏（除非使用 Unity Catalog）
无内建审计日志（依赖 Spark History Server 或平台审计）

