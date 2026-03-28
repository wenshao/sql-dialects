# SQL 标准: 权限管理

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - GRANT / REVOKE](https://modern-sql.com/feature/grant)

## SQL-86 (SQL-1): 基本权限

定义了 GRANT 和 REVOKE

```sql
GRANT SELECT ON users TO alice;
REVOKE SELECT ON users FROM alice;
```

## SQL-89 (SQL-1, 修正版): 增强

更完善的 GRANT/REVOKE

```sql
GRANT SELECT, INSERT ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
GRANT SELECT ON users TO alice WITH GRANT OPTION;  -- 允许再授权
```

## SQL-92 (SQL2): 完善的权限模型

权限类型完善
新增 PUBLIC 关键字

标准权限类型
```sql
GRANT SELECT ON users TO alice;
GRANT INSERT ON users TO alice;
GRANT UPDATE ON users TO alice;
GRANT DELETE ON users TO alice;
GRANT REFERENCES ON users TO alice;  -- 创建引用此表的外键
GRANT ALL PRIVILEGES ON users TO alice;
```

列级权限
```sql
GRANT SELECT (username, email) ON users TO alice;
GRANT UPDATE (email) ON users TO alice;
```

授权给所有用户
```sql
GRANT SELECT ON users TO PUBLIC;
```

WITH GRANT OPTION（允许再授权）
```sql
GRANT SELECT ON users TO alice WITH GRANT OPTION;
```

撤销权限
```sql
REVOKE SELECT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
```

CASCADE / RESTRICT
```sql
REVOKE SELECT ON users FROM alice CASCADE;   -- 级联撤销（alice 授予他人的也撤销）
REVOKE SELECT ON users FROM alice RESTRICT;  -- 如果 alice 已授权他人则拒绝
```

## SQL:1999 (SQL3): 角色（ROLE）

新增 CREATE ROLE
新增角色授权

创建角色
```sql
CREATE ROLE analyst;
CREATE ROLE data_engineer;
```

授权给角色
```sql
GRANT SELECT ON users TO analyst;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO data_engineer;
```

将角色授予用户
```sql
GRANT analyst TO alice;
GRANT data_engineer TO bob;
```

角色继承
```sql
GRANT analyst TO data_engineer;
```

设置当前角色
```sql
SET ROLE analyst;
SET ROLE NONE;  -- 取消角色
```

删除角色
```sql
DROP ROLE analyst;
```

## SQL:2003: TRIGGER 和 EXECUTE 权限

新增 TRIGGER 权限
新增 EXECUTE 权限（函数和过程）

```sql
GRANT TRIGGER ON users TO data_engineer;
GRANT EXECUTE ON FUNCTION my_func TO analyst;
GRANT EXECUTE ON PROCEDURE my_proc TO analyst;
```

## SQL:2003: USAGE 权限

USAGE 用于类型、域、序列等

```sql
GRANT USAGE ON SEQUENCE users_id_seq TO alice;
GRANT USAGE ON DOMAIN email_type TO alice;
GRANT USAGE ON TYPE address_type TO alice;
```

## SQL:2011: 增强

更多对象类型的权限管理

## 标准中的权限体系

对象权限（Object Privileges）:
SELECT: 读取表/视图数据
INSERT: 插入数据
UPDATE: 更新数据
DELETE: 删除数据
REFERENCES: 创建外键引用
TRIGGER: 创建触发器
EXECUTE: 执行函数/过程
USAGE: 使用序列/类型/域等

系统权限（标准中未定义，各数据库自行扩展）:
CREATE TABLE, CREATE VIEW, CREATE USER, etc.
这些都不在标准中

## 各数据库实现对比

MySQL: 'user'@'host' 模式，全局/库/表/列四级权限
PostgreSQL: ROLE 体系，最接近标准，支持 RLS
Oracle: 系统权限 + 对象权限，Profile
SQL Server: 登录(Login) + 用户(User) 分离，SCHEMA
SQLite: 无内置权限系统
BigQuery: IAM，不使用 SQL GRANT
Snowflake: RBAC，所有权限必须通过角色
ClickHouse: RBAC (20.1+)，Quota，Settings Profile

- **注意：GRANT/REVOKE 是标准中最早定义的权限语句**
- **注意：ROLE 在 SQL:1999 标准化**
- **注意：各数据库的权限系统差异很大**
- **注意：标准没有定义 CREATE USER 语法**
- **注意：行级安全（RLS）不在标准中，是 PostgreSQL 的扩展**
