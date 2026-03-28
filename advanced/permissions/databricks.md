# Databricks SQL: 权限管理


Databricks 使用 Unity Catalog 进行统一的权限管理
三级命名空间：catalog.schema.object

## Unity Catalog 层级


Metastore（顶级容器，通常每个区域一个）
└── Catalog（逻辑分组，如 prod、dev）
└── Schema（数据库）
└── Table / View / Function / Model

创建 Catalog
```sql
CREATE CATALOG IF NOT EXISTS prod_catalog;
CREATE CATALOG IF NOT EXISTS dev_catalog;
```


创建 Schema
```sql
CREATE SCHEMA IF NOT EXISTS prod_catalog.analytics;
CREATE SCHEMA IF NOT EXISTS prod_catalog.raw_data;
```


## 授权


Catalog 级权限
```sql
GRANT USE CATALOG ON CATALOG prod_catalog TO `analysts`;
GRANT CREATE SCHEMA ON CATALOG prod_catalog TO `data_engineers`;
GRANT ALL PRIVILEGES ON CATALOG dev_catalog TO `data_engineers`;
```


Schema 级权限
```sql
GRANT USE SCHEMA ON SCHEMA prod_catalog.analytics TO `analysts`;
GRANT CREATE TABLE ON SCHEMA prod_catalog.raw_data TO `data_engineers`;
GRANT ALL PRIVILEGES ON SCHEMA prod_catalog.analytics TO `data_engineers`;
```


表级权限
```sql
GRANT SELECT ON TABLE prod_catalog.analytics.users TO `analysts`;
GRANT SELECT, MODIFY ON TABLE prod_catalog.analytics.users TO `data_engineers`;
GRANT ALL PRIVILEGES ON TABLE prod_catalog.analytics.users TO `data_admins`;
```


视图权限
```sql
GRANT SELECT ON VIEW prod_catalog.analytics.v_active_users TO `analysts`;
```


函数权限
```sql
GRANT EXECUTE ON FUNCTION prod_catalog.analytics.my_udf TO `analysts`;
```


外部位置权限
```sql
GRANT READ FILES ON EXTERNAL LOCATION my_location TO `data_engineers`;
GRANT WRITE FILES ON EXTERNAL LOCATION my_location TO `data_engineers`;
```


Storage Credential 权限
```sql
GRANT READ FILES ON STORAGE CREDENTIAL my_credential TO `data_engineers`;
```


## 撤销权限


```sql
REVOKE SELECT ON TABLE prod_catalog.analytics.users FROM `analysts`;
REVOKE ALL PRIVILEGES ON SCHEMA prod_catalog.raw_data FROM `data_engineers`;
```


DENY（显式拒绝，Unity Catalog 2024+）
```sql
DENY SELECT ON TABLE prod_catalog.analytics.sensitive_data TO `analysts`;
```


## 用户和组


Unity Catalog 从身份提供商同步用户和组
支持 Azure AD、AWS IAM、GCP 等

查看当前用户
```sql
SELECT current_user();
```


## 所有者


修改对象所有者
```sql
ALTER TABLE prod_catalog.analytics.users SET OWNER TO `data_admins`;
ALTER SCHEMA prod_catalog.analytics SET OWNER TO `data_admins`;
ALTER CATALOG prod_catalog SET OWNER TO `platform_team`;
```


## 行级过滤和列级掩码


行级过滤函数
```sql
CREATE FUNCTION prod_catalog.analytics.region_filter(region STRING)
RETURN IF(IS_ACCOUNT_GROUP_MEMBER('global_team'), true, region = current_user_region());
```


应用行级过滤
```sql
ALTER TABLE prod_catalog.analytics.users
SET ROW FILTER prod_catalog.analytics.region_filter ON (region);
```


列级掩码函数
```sql
CREATE FUNCTION prod_catalog.analytics.email_mask(email STRING)
RETURN IF(IS_ACCOUNT_GROUP_MEMBER('data_admins'), email, REGEXP_REPLACE(email, '(.).*@', '$1***@'));
```


应用列级掩码
```sql
ALTER TABLE prod_catalog.analytics.users
ALTER COLUMN email SET MASK prod_catalog.analytics.email_mask;
```


移除过滤/掩码
```sql
ALTER TABLE prod_catalog.analytics.users DROP ROW FILTER;
ALTER TABLE prod_catalog.analytics.users ALTER COLUMN email DROP MASK;
```


## 标签（Tags）


添加标签（用于数据治理）
```sql
ALTER TABLE prod_catalog.analytics.users SET TAGS ('pii' = 'true', 'team' = 'analytics');
ALTER TABLE prod_catalog.analytics.users ALTER COLUMN email SET TAGS ('pii_type' = 'email');
ALTER SCHEMA prod_catalog.analytics SET TAGS ('env' = 'prod');
```


## 查看权限


```sql
SHOW GRANTS ON TABLE prod_catalog.analytics.users;
SHOW GRANTS ON SCHEMA prod_catalog.analytics;
SHOW GRANTS ON CATALOG prod_catalog;
SHOW GRANTS TO `analysts`;
```


## 共享（Delta Sharing）


创建共享
```sql
CREATE SHARE my_share;
ALTER SHARE my_share ADD TABLE prod_catalog.analytics.users;
ALTER SHARE my_share ADD TABLE prod_catalog.analytics.orders PARTITION (region = 'US');
```


授予共享权限给接收者
```sql
GRANT SELECT ON SHARE my_share TO RECIPIENT external_partner;
```


创建接收者
```sql
CREATE RECIPIENT external_partner;
```


## 旧版权限（Hive Metastore，非 Unity Catalog）


如果未使用 Unity Catalog，使用旧版权限模型：
GRANT SELECT ON TABLE users TO `alice@example.com`;
GRANT ALL PRIVILEGES ON DATABASE default TO `data_engineers`;

注意：Unity Catalog 是推荐的权限管理方案
注意：权限继承：Catalog → Schema → Table
注意：行级过滤和列级掩码提供细粒度数据保护
注意：Delta Sharing 允许跨组织共享数据
注意：标签（Tags）用于数据分类和治理
注意：用户/组从身份提供商（IdP）同步
注意：所有者自动拥有对象的 ALL PRIVILEGES
