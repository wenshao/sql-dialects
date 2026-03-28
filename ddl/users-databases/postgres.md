# PostgreSQL: 用户与数据库管理

> 参考资料:
> - [PostgreSQL Documentation - Database Roles](https://www.postgresql.org/docs/current/user-manag.html)
> - [PostgreSQL Documentation - CREATE DATABASE](https://www.postgresql.org/docs/current/sql-createdatabase.html)
> - [PostgreSQL Documentation - Schemas](https://www.postgresql.org/docs/current/ddl-schemas.html)

## 命名层级: Cluster > Database > Schema > Object

PostgreSQL 的三级命名空间设计:
  Cluster: 一个 PostgreSQL 实例（一个 data directory，一个 postmaster 进程）
  Database: 物理隔离的命名空间（不能跨库 JOIN）
  Schema:   逻辑隔离的命名空间（同库内可跨 schema JOIN）

对比:
  MySQL:      Database ≈ Schema（两者等价，只有两级）
  Oracle:     User ≈ Schema（每个用户自动拥有同名 schema）
  SQL Server: Server > Database > Schema（三级，同 PostgreSQL）

设计影响:
  PostgreSQL 不能跨库 JOIN（每个 database 有独立的系统表副本）
  如需跨库查询，使用 dblink 或 postgres_fdw 扩展

## 数据库管理

```sql
CREATE DATABASE myapp;

CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0           -- 使用干净模板（避免模板中的脏对象）
    CONNECTION LIMIT = 100;
```

设计分析: TEMPLATE 机制
  CREATE DATABASE 实际上是对模板数据库做物理拷贝（文件系统级别）。
  template1: 默认模板，可以往里加扩展/表，新库会继承
  template0: 干净模板，不可修改，用于恢复或指定不同编码
  这意味着 CREATE DATABASE 的速度取决于模板大小（通常毫秒级）

```sql
ALTER DATABASE myapp SET timezone TO 'Asia/Shanghai';
ALTER DATABASE myapp SET search_path TO myschema, public;
DROP DATABASE IF EXISTS myapp;
DROP DATABASE myapp WITH (FORCE);   -- 13+: 强制断开所有连接
```

## Schema 管理与 search_path

```sql
CREATE SCHEMA myschema;
CREATE SCHEMA myschema AUTHORIZATION myuser;
```

search_path: PostgreSQL 的 schema 解析机制
```sql
SET search_path TO myschema, public;
```

效果: 不限定 schema 时，按 search_path 顺序查找对象
创建对象时默认放入 search_path 的第一个 schema

search_path 的安全问题:
  如果 search_path 包含 public，恶意用户可以在 public 中创建同名函数
  覆盖系统函数（schema 劫持攻击）。
  最佳实践: REVOKE CREATE ON SCHEMA public FROM PUBLIC;

```sql
DROP SCHEMA myschema CASCADE;       -- 级联删除所有对象
```

## 角色与用户: PostgreSQL 的统一模型

PostgreSQL 中 USER 和 ROLE 的唯一区别:
```sql
  CREATE USER = CREATE ROLE WITH LOGIN
```

  角色是权限的容器，用户是可登录的角色

```sql
CREATE USER app_user WITH PASSWORD 'secret123';

CREATE ROLE app_admin WITH
    LOGIN CREATEDB CREATEROLE
    VALID UNTIL '2027-12-31'
    CONNECTION LIMIT 10;
```

角色继承（RBAC 模型）
```sql
CREATE ROLE readonly NOLOGIN;
CREATE ROLE readwrite NOLOGIN;
GRANT readonly TO readwrite;       -- readwrite 继承 readonly 的权限
GRANT readwrite TO app_user;       -- app_user 继承 readwrite 的权限
```

14+: 角色权限可以不自动继承，需要 SET ROLE 激活
```sql
GRANT admin TO app_user WITH INHERIT FALSE;
```

app_user 需要 SET ROLE admin 才能使用 admin 的权限

预定义角色（系统角色，14+）
pg_read_all_data:    可以读取所有表
pg_write_all_data:   可以写入所有表
pg_monitor:          可以读取监控视图
pg_signal_backend:   可以发送信号给其他后端
```sql
GRANT pg_read_all_data TO readonly;
```

## 权限系统: GRANT / REVOKE / DEFAULT PRIVILEGES

表权限
```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO app_user;
```

列级权限
```sql
GRANT SELECT (username, email) ON users TO analyst;
GRANT UPDATE (email) ON users TO app_user;
```

Schema 权限（必须先 GRANT USAGE 才能访问 schema 内的对象）
```sql
GRANT USAGE ON SCHEMA myschema TO app_user;
GRANT CREATE ON SCHEMA myschema TO app_user;
```

默认权限: 自动授权给将来创建的对象
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE ON SEQUENCES TO app_user;
```

设计分析: DEFAULT PRIVILEGES
  PostgreSQL 的权限是"显式授予"模型——新对象默认只有 owner 有权限。
  ALTER DEFAULT PRIVILEGES 解决了"每次建表都要手动 GRANT"的问题。
> **注意**: DEFAULT PRIVILEGES 绑定到执行 ALTER 的角色！
  如果 alice 设了 DEFAULT PRIVILEGES，只有 alice 创建的表才会生效。

## 行级安全 (RLS, 9.5+): 数据库级多租户隔离

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
```

用户只能看到自己的行
```sql
CREATE POLICY user_isolation ON users
    USING (username = current_user);
```

写入时也检查
```sql
CREATE POLICY user_insert ON users
    FOR INSERT WITH CHECK (username = current_user);
```

RLS 设计分析:
  RLS 策略在查询优化器中作为隐式 WHERE 条件注入。
  即使 SQL 注入成功，也无法读取其他用户的数据。
  表 owner 和 SUPERUSER 默认绕过 RLS（可用 FORCE ROW LEVEL SECURITY 强制）

对比:
  Oracle:    VPD (Virtual Private Database) — 功能类似但更复杂
  SQL Server: RLS (2016+) — 语法不同但概念相同
  MySQL:     不支持 RLS（需要视图或应用层实现）

## 横向对比: 认证与权限模型

### 认证配置

  PostgreSQL: pg_hba.conf（基于客户端IP、数据库、用户的规则文件）
  MySQL:      mysql.user 表 + GRANT 语句
  Oracle:     listener.ora + sqlnet.ora + tnsnames.ora
  SQL Server: SQL 认证 + Windows 认证

### 权限粒度

  PostgreSQL: Database > Schema > Table > Column > Row(RLS)
  MySQL:      Database > Table > Column（无 Schema 级，无原生 RLS）
  Oracle:     Schema > Table > Column > Row(VPD)

### 权限立即生效

  PostgreSQL: 权限立即生效（无需 FLUSH PRIVILEGES）
  MySQL:      GRANT 立即生效，但 REVOKE 可能需要重连才生效

## 对引擎开发者的启示

(1) 三级命名空间（Database > Schema > Object）是成熟的设计。
    Database 级隔离保证安全性，Schema 级隔离提供灵活性。
    MySQL 将 Database=Schema 的简化设计在多租户场景下力不从心。

(2) 角色继承（RBAC）比直接授权更易管理。
    CREATE ROLE 定义权限集合，用户通过角色获得权限，
    权限变更只需修改角色定义，不需要逐用户修改。

(3) RLS 是安全的最后一道防线:
    即使应用层有 SQL 注入漏洞，RLS 也能保证数据隔离。
    这种"纵深防御"思想值得所有引擎学习。

(4) search_path 是便利性与安全性的 trade-off:
    方便: 不用写 schema 前缀
    风险: schema 劫持攻击（特别是 public schema）

## 版本演进

PostgreSQL 8.1:  角色系统（ROLE 替代 USER/GROUP）
PostgreSQL 9.5:  行级安全 (RLS)
PostgreSQL 10:   SCRAM-SHA-256 认证（替代 MD5）
PostgreSQL 13:   DROP DATABASE WITH (FORCE)
PostgreSQL 14:   预定义角色（pg_read_all_data 等），INHERIT 选项
PostgreSQL 15:   GRANT 支持 PUBLIC schema 限制默认权限
PostgreSQL 16:   pg_use_reserved_connections 预定义角色
