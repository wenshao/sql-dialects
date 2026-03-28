# Apache Impala: 权限管理


Impala 通过 Ranger 或 Sentry 管理权限
以下使用 Ranger 语法（CDH/CDP 推荐）

## GRANT / REVOKE（Ranger 集成）


服务器级别
```sql
GRANT ALL ON SERVER TO alice;
GRANT ALL ON SERVER TO ROLE admin_role;
```


数据库级别
```sql
GRANT ALL ON DATABASE mydb TO alice;
GRANT SELECT ON DATABASE mydb TO ROLE app_read;
GRANT CREATE ON DATABASE mydb TO alice;
```


表级别
```sql
GRANT SELECT ON TABLE mydb.users TO alice;
GRANT INSERT ON TABLE mydb.users TO alice;
GRANT ALL ON TABLE mydb.users TO alice;
```


列级别（Ranger 支持）
```sql
GRANT SELECT (username, email) ON TABLE mydb.users TO alice;
```


URI 权限（HDFS 路径）
```sql
GRANT ALL ON URI 'hdfs:///data/users/' TO alice;
```


## 角色管理


创建角色
```sql
CREATE ROLE app_read;
CREATE ROLE app_write;
CREATE ROLE admin_role;
```


给角色授权
```sql
GRANT SELECT ON DATABASE mydb TO ROLE app_read;
GRANT INSERT ON DATABASE mydb TO ROLE app_write;
GRANT ALL ON DATABASE mydb TO ROLE admin_role;
```


将角色授予用户/组
```sql
GRANT ROLE app_read TO GROUP analysts;
GRANT ROLE app_write TO GROUP etl_users;
```


删除角色
```sql
DROP ROLE app_read;
```


## 撤销权限


```sql
REVOKE SELECT ON TABLE mydb.users FROM alice;
REVOKE ALL ON DATABASE mydb FROM alice;
REVOKE ROLE app_read FROM GROUP analysts;
```


## 查看权限


```sql
SHOW GRANT USER alice;
SHOW GRANT USER alice ON DATABASE mydb;
SHOW GRANT ROLE app_read;
SHOW ROLE GRANT GROUP analysts;
SHOW CURRENT ROLES;
```


## 权限类型


SELECT: 查询
INSERT: 插入/加载数据
CREATE: 创建表/数据库
ALTER: 修改表
DROP: 删除表/数据库
ALL: 所有权限
REFRESH: 刷新元数据（INVALIDATE METADATA / REFRESH）

## Kudu 表权限


Kudu 表遵循 Impala 的权限模型
```sql
GRANT SELECT ON TABLE mydb.users_kudu TO alice;
GRANT INSERT ON TABLE mydb.users_kudu TO alice;
```


## Ranger 策略（通过 Ranger UI 管理）


行级过滤（Row-Level Filter）
在 Ranger UI 中配置：WHERE city = 'Beijing'

列级掩码（Column Masking）
在 Ranger UI 中配置：MASK email 列

## Sentry（旧版本）


Sentry 语法类似，但已在新版本中被 Ranger 替代
GRANT SELECT ON DATABASE mydb TO ROLE app_read;

注意：Impala 权限通过 Ranger 或 Sentry 管理
注意：权限检查在 Impalad 级别执行
注意：Ranger 支持行级过滤和列级掩码
注意：HDFS 文件权限和 Impala 权限是独立的
注意：需要 REFRESH 权限才能执行 INVALIDATE METADATA
