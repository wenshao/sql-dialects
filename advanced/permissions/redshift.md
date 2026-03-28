# Redshift: 权限管理

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


创建用户
```sql
CREATE USER alice PASSWORD 'Password123!';
CREATE USER alice PASSWORD 'Password123!' CREATEDB;  -- 允许创建数据库
CREATE USER alice PASSWORD 'Password123!' SYSLOG ACCESS UNRESTRICTED;
```


创建组（角色）
```sql
CREATE GROUP analysts;
CREATE GROUP data_engineers;
```


添加用户到组
```sql
ALTER GROUP analysts ADD USER alice;
ALTER GROUP analysts ADD USER bob, charlie;
```


从组中移除用户
```sql
ALTER GROUP analysts DROP USER alice;
```


授权（表级）
```sql
GRANT SELECT ON users TO alice;
GRANT SELECT, INSERT, UPDATE ON users TO alice;
GRANT ALL PRIVILEGES ON users TO alice;
```


授权到组
```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO GROUP analysts;
GRANT ALL ON ALL TABLES IN SCHEMA public TO GROUP data_engineers;
```


列级权限
```sql
GRANT SELECT (username, email) ON users TO alice;
```


Schema 权限
```sql
GRANT USAGE ON SCHEMA myschema TO alice;
GRANT CREATE ON SCHEMA myschema TO alice;
GRANT USAGE ON SCHEMA myschema TO GROUP analysts;
```


数据库权限
```sql
GRANT CREATE ON DATABASE mydb TO alice;
```


函数权限
```sql
GRANT EXECUTE ON FUNCTION my_function(INT) TO alice;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO GROUP analysts;
```


存储过程权限
```sql
GRANT EXECUTE ON PROCEDURE my_proc(BIGINT) TO alice;
```


默认权限（对将来创建的对象自动授权）
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO GROUP analysts;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON FUNCTIONS TO GROUP data_engineers;
```


撤销权限
```sql
REVOKE SELECT ON users FROM alice;
REVOKE ALL PRIVILEGES ON users FROM alice;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM GROUP analysts;
```


查看权限
```sql
SELECT * FROM svv_relation_privileges WHERE identity_name = 'alice';
SELECT * FROM pg_user WHERE usename = 'alice';
SELECT * FROM pg_group;
```


修改密码
```sql
ALTER USER alice PASSWORD 'NewPassword456!';
```


删除用户/组
```sql
DROP USER alice;
DROP GROUP analysts;
```


超级用户
只有超级用户可以：创建超级用户、访问系统表、修改系统设置
```sql
ALTER USER alice CREATEUSER;                 -- 提升为超级用户
ALTER USER alice NOCREATEUSER;               -- 取消超级用户
```


## Redshift Spectrum 外部 Schema 权限


```sql
GRANT USAGE ON EXTERNAL SCHEMA spectrum_schema TO alice;
GRANT SELECT ON ALL TABLES IN SCHEMA spectrum_schema TO GROUP analysts;
```


## 行级安全（RLS，Redshift 2022+）


创建 RLS 策略
```sql
CREATE RLS POLICY policy_region
WITH (region VARCHAR(50))
USING (region = current_setting('app.user_region'));
```


附加策略到表
```sql
ATTACH RLS POLICY policy_region ON users TO alice;
ATTACH RLS POLICY policy_region ON users TO GROUP analysts;
```


启用 RLS
```sql
ALTER TABLE users ROW LEVEL SECURITY ON;
```


分离策略
```sql
DETACH RLS POLICY policy_region ON users FROM alice;
```


删除策略
```sql
DROP RLS POLICY policy_region;
```


## 数据共享（Datasharing）


创建数据共享（生产者）
```sql
CREATE DATASHARE my_share SET PUBLICACCESSIBLE = FALSE;
ALTER DATASHARE my_share ADD SCHEMA public;
ALTER DATASHARE my_share ADD TABLE users;
GRANT USAGE ON DATASHARE my_share TO NAMESPACE '...consumer-namespace...';
```


使用数据共享（消费者）
```sql
CREATE DATABASE shared_db FROM DATASHARE my_share OF NAMESPACE '...producer-namespace...';
GRANT USAGE ON DATABASE shared_db TO alice;
```


注意：Redshift 支持用户、组和角色（RBAC，2022+ 新增角色支持）
注意：旧版使用 GROUP 关键字，新版推荐使用 CREATE ROLE / GRANT ROLE
注意：默认权限适用于未来创建的对象
注意：RLS（行级安全）是 2022+ 的功能
注意：超级用户可以绕过所有权限检查
注意：Datasharing 允许跨集群共享数据
