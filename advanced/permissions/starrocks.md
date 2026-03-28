# StarRocks: 权限管理

> 参考资料:
> - [1] StarRocks Documentation - Privilege
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. 权限模型: 更接近 SQL 标准

 StarRocks 的 GRANT 语法更接近 SQL 标准(无 _PRIV 后缀)。
 对比 Doris: GRANT SELECT_PRIV ON db.* → StarRocks: GRANT SELECT ON db.*

## 2. 用户管理

```sql
CREATE USER 'alice'@'%' IDENTIFIED BY 'password123';
CREATE USER 'alice'@'10.0.0.%' IDENTIFIED BY 'password123';
ALTER USER 'alice' IDENTIFIED BY 'new_password';
DROP USER 'alice';

```

## 3. 角色管理

```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT ON db.* TO ROLE app_read;
GRANT INSERT, ALTER ON db.* TO ROLE app_write;
GRANT app_read TO 'alice'@'%';
DROP ROLE app_read;

```

## 4. 权限层级

```sql
GRANT ALL ON *.* TO 'alice'@'%';               -- 全局
GRANT SELECT ON db.* TO 'alice'@'%';           -- 数据库级
GRANT SELECT ON db.users TO 'alice'@'%';       -- 表级
GRANT INSERT ON db.users TO 'alice'@'%';
REVOKE SELECT ON db.* FROM 'alice'@'%';

```

External Catalog 权限(2.3+)

```sql
GRANT USAGE ON CATALOG hive_catalog TO 'alice'@'%';

```

## 5. Resource Group 权限

```sql
CREATE RESOURCE GROUP rg_report TO (user='alice')
WITH ('cpu_core_limit'='10', 'mem_limit'='30%');

```

## 6. 查看权限

```sql
SHOW GRANTS FOR 'alice'@'%';
SHOW ALL GRANTS;
SHOW ROLES;

```

## 7. StarRocks vs Doris 权限差异

语法:
StarRocks: GRANT SELECT ON db.* TO user (SQL 标准)
Doris:     GRANT SELECT_PRIV ON db.* TO user (_PRIV 后缀)

行级权限:
StarRocks: 不支持
Doris 2.1+: Row Policy(行级权限)

对引擎开发者的启示:
权限模型的设计需要在"MySQL 兼容"和"SQL 标准"之间选择。
StarRocks 选择了更标准的语法，Doris 保留了更多 MySQL 习惯。
迁移时需要注意 GRANT 语法的差异。

