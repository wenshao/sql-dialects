# Apache Derby: 数据库、模式与用户管理

> 参考资料:
> - [Apache Derby Documentation - CREATE SCHEMA](https://db.apache.org/derby/docs/10.16/ref/rrefsqlj31580.html)
> - [Apache Derby Documentation - GRANT / REVOKE](https://db.apache.org/derby/docs/10.16/ref/rrefsqljgrant.html)
> - ============================================================
> - Derby 特性：
> - 嵌入式 Java 数据库
> - 数据库 = 一个目录
> - 支持 schema
> - 简单的权限管理
> - 命名层级: database > schema > object
> - ============================================================
> - ============================================================
> - 1. 数据库管理
> - ============================================================
> - 数据库通过 JDBC 连接字符串创建（非 SQL）
> - 嵌入式：jdbc:derby:myapp;create=true
> - 网络：jdbc:derby://localhost:1527/myapp;create=true
> - 删除数据库 = 删除目录（文件系统操作）
> - 数据库属性
> - CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY('derby.database.fullAccessUsers', 'admin');
> - ============================================================
> - 2. 模式管理
> - ============================================================

```sql
CREATE SCHEMA myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;
```

## 删除模式

```sql
DROP SCHEMA myschema RESTRICT;                  -- 必须为空
```

## 设置当前模式

```sql
SET SCHEMA myschema;
SET CURRENT SCHEMA myschema;
```

## 默认模式 = 用户名（大写）

## 用户管理


Derby 使用外部认证或内建认证
用户不通过 SQL 创建
内建认证（通过数据库属性设置）
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
'derby.user.myuser', 'secret123');
启用认证
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
'derby.connection.requireAuthentication', 'true');
设置认证提供者
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
'derby.authentication.provider', 'BUILTIN');

## 权限管理


需要启用 SQL 授权
CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(
'derby.database.sqlAuthorization', 'true');

```sql
GRANT SELECT ON TABLE myschema.users TO myuser;
GRANT INSERT, UPDATE, DELETE ON TABLE myschema.users TO myuser;
GRANT ALL PRIVILEGES ON TABLE myschema.users TO myuser;
GRANT EXECUTE ON PROCEDURE my_proc TO myuser;
```

## 角色（Derby 10.5+）

```sql
CREATE ROLE analyst;
GRANT SELECT ON TABLE myschema.users TO analyst;
GRANT analyst TO myuser;

SET ROLE analyst;

REVOKE SELECT ON TABLE myschema.users FROM myuser;
REVOKE analyst FROM myuser;
DROP ROLE analyst;
```

## 查询元数据


```sql
VALUES CURRENT_USER;
VALUES CURRENT SCHEMA;
```

## 系统表

```sql
SELECT SCHEMANAME FROM SYS.SYSSCHEMAS;
SELECT TABLENAME FROM SYS.SYSTABLES;
SELECT * FROM SYS.SYSROLES;
```

## 数据库属性

```sql
VALUES SYSCS_UTIL.SYSCS_GET_DATABASE_PROPERTY('derby.database.fullAccessUsers');
```

注意：Derby 是轻量级嵌入式 Java 数据库
功能比 SQLite 丰富（支持 schema、角色、权限）
但用户管理仍然比较简单
