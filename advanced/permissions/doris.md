# Apache Doris: 权限管理

 Apache Doris: 权限管理

 参考资料:
   [1] Doris Documentation - Privilege
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 权限模型: MySQL 协议兼容 + RBAC

 Doris 权限模型基于 MySQL 协议，使用 _PRIV 后缀(如 SELECT_PRIV)。
 对比 StarRocks: 更接近 SQL 标准(GRANT SELECT ON ...)。
 对比 MySQL: 语法类似但权限类型不同(Doris 有 LOAD_PRIV、NODE_PRIV)。

## 2. 用户管理

```sql
CREATE USER alice IDENTIFIED BY 'password123';
CREATE USER alice@'192.168.1.%' IDENTIFIED BY 'password123';
SET PASSWORD FOR alice = PASSWORD('new_password');
ALTER USER alice IDENTIFIED BY 'new_password';
DROP USER alice;

```

## 3. 角色管理

```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
GRANT SELECT_PRIV ON db.* TO ROLE app_read;
GRANT LOAD_PRIV, ALTER_PRIV ON db.* TO ROLE app_write;
GRANT app_read TO alice;
DROP ROLE app_read;

```

## 4. 权限层级

```sql
GRANT ADMIN_PRIV ON *.* TO alice;             -- 全局管理员
GRANT SELECT_PRIV ON db.* TO alice;           -- 数据库级
GRANT SELECT_PRIV ON db.users TO alice;       -- 表级
GRANT LOAD_PRIV ON db.users TO alice;
REVOKE SELECT_PRIV ON db.users FROM alice;

```

Catalog 权限(2.0+)

```sql
GRANT USAGE_PRIV ON CATALOG hive_catalog TO alice;

```

Workload Group 权限(2.1+)

```sql
GRANT USAGE_PRIV ON WORKLOAD GROUP 'normal' TO alice;

```

## 5. Row Policy (2.1+，行级权限，Doris 独有)

 CREATE ROW POLICY policy_name ON db.table
 AS RESTRICTIVE TO alice
 USING (city = 'Beijing');

 对比: StarRocks 不支持行级权限。
 对比: PostgreSQL 有 Row Level Security(RLS)——功能更完善。
 对比: BigQuery 有 Row Access Policy(类似)。

## 6. 查看权限

```sql
SHOW GRANTS FOR alice;
SHOW ALL GRANTS;
SHOW ROLES;

```

## 7. 权限类型

SELECT_PRIV:  查询
LOAD_PRIV:    导入(INSERT, Stream Load 等)
ALTER_PRIV:   ALTER TABLE
CREATE_PRIV:  创建表/数据库
DROP_PRIV:    删除
ADMIN_PRIV:   管理员(所有操作)
NODE_PRIV:    节点管理
USAGE_PRIV:   使用 Catalog/Resource

