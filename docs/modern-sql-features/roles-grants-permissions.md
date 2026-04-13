# 角色与授权语法详解 (Roles, Grants, and Privilege Granularity)

> 与本仓库现有的 `permission-security-model.md`（GRANT/REVOKE 总览、行列级安全、认证审计）以及 `permission-model-design.md`（ACL/RBAC/ABAC/IAM 的概念演进）形成互补，本文不再重复总览矩阵，而是**深入到 ROLE 子系统的语法细节、各引擎独有的角色生命周期管理、以及"权限粒度"——从实例到列、从 EXECUTE 到 USAGE 的完整层级**。行级安全请参见 `row-level-security.md`。

SQL:1999 在二十多年前就已经把 `CREATE ROLE`、`SET ROLE`、`WITH ADMIN OPTION` 写进了标准。然而打开任何一本生产手册，PostgreSQL、MySQL、Oracle、SQL Server、Snowflake 在角色这件事上仍然有着截然不同的"哲学"：PostgreSQL 把用户与角色彻底合并、Oracle 用 `IDENTIFIED BY` 把角色变成一种带密码的开关、Snowflake 强制每个会话必须激活某个角色才能执行任何语句、MySQL 直到 8.0 (2018) 才补齐角色功能、而 SQLite 则干脆没有任何用户系统。本文以 45+ 个 SQL 引擎为样本，把"角色与授权"这件事拆成 14 个维度逐一对齐。

## SQL 标准中的角色与授权

### SQL:1999 — 引入 ROLE

ISO/IEC 9075-2:1999 第 12 章正式定义了角色：

```sql
<role definition> ::=
    CREATE ROLE <role name> [ WITH ADMIN <grantor> ]

<grant role statement> ::=
    GRANT <role granted> [ { , <role granted> }... ]
        TO <grantee> [ { , <grantee> }... ]
        [ WITH ADMIN OPTION ]
        [ GRANTED BY <grantor> ]

<set role statement> ::=
    SET ROLE { <role name> | NONE }
```

关键概念：

1. **ROLE 是被授权的命名集合**：可被授予权限，也可被授予给用户或其它角色，形成有向无环图。
2. **WITH ADMIN OPTION**：被授予者可以再把这个角色授给别人（区别于对象权限的 `WITH GRANT OPTION`）。
3. **SET ROLE**：会话内激活角色，决定后续语句可见的权限集合。
4. **角色不是 schema 的一部分**：标准把角色定义在"集群级别"，与表所在的 schema 无关。

### SQL:2003 — INSTEAD OF 触发器与列级 GRANT

SQL:2003 (Part 2, Section 12.3) 进一步细化了 `<privilege>` 的语法，明确允许列级授权：

```sql
GRANT SELECT ( first_name, last_name ),
      UPDATE ( salary )
    ON employees
    TO compensation_admin
    WITH GRANT OPTION;
```

同时 SQL:2003 引入了 `INSTEAD OF` 触发器——使可更新视图成为绕过基表权限的安全模式：用户只对视图持有 `INSERT/UPDATE/DELETE`，触发器以视图所有者身份重写到底层表。这是行级安全（SQL:2016 的 `ROW-LEVEL` policies 之前）的"穷人版"实现。

### SQL:2008 — TRUNCATE TABLE 语句标准化

SQL:2008 把 `TRUNCATE TABLE` 作为**语句**正式纳入标准（在此之前它是各家厂商的扩展），但**并未**在标准中定义独立的 `TRUNCATE` 对象权限——标准并不要求 GRANT 体系包含 `TRUNCATE`。把 `TRUNCATE` 当作独立对象权限（`GRANT TRUNCATE ON …`）的做法是 **PostgreSQL 自 8.4 起的扩展**，并非 SQL:2008 的硬性要求。其他厂商各行其道：Oracle 把 TRUNCATE 视为 DDL（需要 `DROP ANY TABLE` 系统权限），MySQL 把它隐式归入 `DROP` 权限。

### SQL:2011 — 安全标签 (Security Labels) 与 SQL/MED 中的远程权限

SQL:2011 增加了一组与 LBAC（Label-Based Access Control）相关的语法，主要被 DB2 LBAC、Oracle Label Security 实现。同时 SQL/MED 部分定义了 `USAGE ON FOREIGN SERVER`、`USAGE ON FOREIGN DATA WRAPPER` 等远程对象权限，PostgreSQL 完整实现了这一部分。

### SQL:2016 — 行级 / 列级安全成为正式特性

SQL:2016 对 `<row pattern recognition clause>`、`<row level security>` 进行了规范化，但实现差异极大；本文不展开，留给 `row-level-security.md`。

## 矩阵一：CREATE ROLE / DROP ROLE 语法

| 引擎 | CREATE ROLE | 用户 vs 角色 | 角色密码 | DROP ROLE | 备注 |
|------|------------|-------------|---------|-----------|------|
| PostgreSQL | `CREATE ROLE r [LOGIN]` | 8.1+ 完全合并 | `PASSWORD '...'` | `DROP ROLE r` | 用户即"带 LOGIN 的角色" |
| MySQL | `CREATE ROLE r` | 分离 (8.0+) | -- | `DROP ROLE r` | 角色是无密码的"用户" |
| MariaDB | `CREATE ROLE r` | 分离 (10.0.5+) | -- | `DROP ROLE r` | 早于 MySQL 引入 |
| SQLite | -- | -- | -- | -- | 无用户系统 |
| Oracle | `CREATE ROLE r [IDENTIFIED BY pwd]` | 分离 | 是 | `DROP ROLE r` | 可设密码激活 |
| SQL Server | `CREATE ROLE r [AUTHORIZATION owner]` | 分离 | -- | `DROP ROLE r` | 区分 server / database role |
| DB2 | `CREATE ROLE r` | 分离 (9.5+) | -- | `DROP ROLE r` | 早期靠 OS 组 |
| Snowflake | `CREATE ROLE r [COMMENT '...']` | 分离 | -- | `DROP ROLE r` | RBAC 强制模型 |
| BigQuery | (无 CREATE ROLE) | IAM 主体 | -- | -- | 角色由 GCP IAM 提供 |
| Redshift | `CREATE ROLE r [EXTERNALID '...']` | 分离 (2022+) | -- | `DROP ROLE r` | 早期仅有 GROUP |
| DuckDB | `CREATE ROLE r` (实验) | -- | -- | -- | 嵌入式默认无权限 |
| ClickHouse | `CREATE ROLE r [ON CLUSTER c]` | 分离 (20.4+) | -- | `DROP ROLE r` | RBAC 完整子系统 |
| Trino | `CREATE ROLE r IN catalog` | 分离 | -- | `DROP ROLE r` | 角色挂在 catalog 下 |
| Presto | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 同 Trino |
| Spark SQL | (取决于 catalog) | 视实现 | -- | -- | Hive/Iceberg 透传 |
| Hive | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | SQL Std Auth 模式 |
| Flink SQL | -- | -- | -- | -- | 计算引擎，无内置权限 |
| Databricks | `CREATE ROLE` (Unity Catalog) | 分离 | -- | `DROP ROLE` | UC 提供 RBAC |
| Teradata | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | Teradata V2R5+ |
| Greenplum | `CREATE ROLE r` | 8.1+ 合并 | `PASSWORD` | `DROP ROLE r` | 继承 PG |
| CockroachDB | `CREATE ROLE r [WITH LOGIN]` | 合并 | `PASSWORD` | `DROP ROLE r` | 21.1+ 完整 RBAC |
| TiDB | `CREATE ROLE r` | 分离 (3.0+) | -- | `DROP ROLE r` | 兼容 MySQL 8.0 |
| OceanBase | `CREATE ROLE r` | 分离 | 是 (Oracle 模式) | `DROP ROLE r` | 双模式 |
| YugabyteDB | `CREATE ROLE r [LOGIN]` | 合并 | `PASSWORD` | `DROP ROLE r` | 继承 PG |
| SingleStore | `CREATE ROLE r` | 分离 (7.5+) | -- | `DROP ROLE r` | 兼容 MySQL |
| Vertica | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 早期 |
| Impala | `CREATE ROLE r` | 分离 (Sentry/Ranger) | -- | `DROP ROLE r` | 透传给 Sentry |
| StarRocks | `CREATE ROLE r` | 分离 (2.0+) | -- | `DROP ROLE r` | 兼容 MySQL |
| Doris | `CREATE ROLE r` | 分离 (1.2+) | -- | `DROP ROLE r` | 兼容 MySQL |
| MonetDB | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 标准化实现 |
| CrateDB | `CREATE USER` (4.5+) | -- | `WITH (password='..')` | `DROP USER` | 仅 USER，无 ROLE |
| TimescaleDB | `CREATE ROLE r` | 继承 PG | `PASSWORD` | `DROP ROLE r` | -- |
| QuestDB | -- | -- | -- | -- | Enterprise 才有 |
| Exasol | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 完整 |
| SAP HANA | `CREATE ROLE r [NO GRANT TO CREATOR]` | 分离 | -- | `DROP ROLE r` | 支持 catalog 角色与 repository 角色 |
| Informix | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | -- |
| Firebird | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 2.0+ |
| H2 | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 标准实现 |
| HSQLDB | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 标准实现 |
| Derby | -- | -- | -- | -- | 仅简单 GRANT，无 ROLE |
| Amazon Athena | -- | -- | -- | -- | Lake Formation/IAM 管理 |
| Azure Synapse | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | T-SQL 兼容 |
| Google Spanner | -- | IAM | -- | -- | IAM only |
| Materialize | `CREATE ROLE r` | 合并 | -- | `DROP ROLE r` | 继承 PG 思路 |
| RisingWave | `CREATE USER`/`CREATE ROLE` | 合并 | `PASSWORD` | `DROP USER` | 继承 PG 思路 |
| InfluxDB (SQL) | -- | -- | -- | -- | Token 制 |
| Databend | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | 兼容 MySQL |
| Yellowbrick | `CREATE ROLE r` | 继承 PG | `PASSWORD` | `DROP ROLE r` | -- |
| Firebolt | `CREATE ROLE r` | 分离 | -- | `DROP ROLE r` | -- |

> 统计：约 38 个引擎实现了某种形式的 `CREATE ROLE`；SQLite、Flink、纯 IAM 引擎（BigQuery、Spanner、Athena）、以及 InfluxDB 完全不在 SQL 层暴露角色 DDL。

## 矩阵二：角色继承与 WITH ADMIN OPTION

SQL:1999 区分两种"再授权"权力：

- **WITH ADMIN OPTION**：用于 `GRANT role TO grantee`，允许接收者把同一角色再授给他人。
- **WITH GRANT OPTION**：用于 `GRANT privilege ON object TO grantee`，允许接收者把同一对象权限再授给他人。

PostgreSQL 还引入了一个 SQL 标准没有的开关 `INHERIT / NOINHERIT`：决定一个角色被授予另一个角色后，是否**自动**继承其权限，或者必须显式 `SET ROLE` 才能使用。

| 引擎 | WITH ADMIN OPTION | INHERIT/NOINHERIT | 角色嵌套层数 | 循环检测 |
|------|------------------|-------------------|------------|---------|
| PostgreSQL | 是 | 是 (默认 INHERIT) | 无明确上限 | 是 |
| MySQL | -- (8.0 仅 `WITH ADMIN OPTION` 形式) | 必须 `SET ROLE` 激活；可设默认 | 无明确上限 | 是 |
| MariaDB | 是 | 必须 `SET ROLE` | 无明确上限 | 是 |
| Oracle | 是 | 默认继承（无 NOINHERIT） | 无明确上限 | 是 |
| SQL Server | -- (用 `ALTER ROLE … ADD MEMBER`) | 自动继承 | 无明确上限 | 是 |
| DB2 | 是 | 自动继承 | -- | 是 |
| Snowflake | 是（GRANT ROLE r1 TO ROLE r2 …） | 强制继承（角色层级） | 无上限 | 是 |
| Redshift | 是 | 自动继承 | -- | 是 |
| ClickHouse | 是 | 默认继承；可与 `DEFAULT ROLE` 结合 | -- | 是 |
| CockroachDB | 是 | 是（兼容 PG） | -- | 是 |
| TiDB | 是 | 必须 `SET ROLE` | -- | 是 |
| OceanBase | 是 | Oracle 模式继承；MySQL 模式需 SET | -- | 是 |
| Vertica | 是 | 必须 `SET ROLE` | -- | 是 |
| SAP HANA | 是 | 自动继承 | -- | 是 |
| Greenplum / YugabyteDB / Materialize / RisingWave | 是 | 是（兼容 PG） | -- | 是 |
| StarRocks / Doris / SingleStore | 是 | 必须 `SET ROLE` | -- | 是 |
| Trino | 是 | 必须 `SET ROLE` | -- | 是 |
| Hive | 是 | 自动继承 | -- | 是 |
| Firebird | -- | 必须 `SET ROLE` | -- | 是 |

```sql
-- PostgreSQL: INHERIT 控制自动继承
CREATE ROLE app_reader;
CREATE ROLE app_writer INHERIT;        -- 默认 INHERIT
CREATE ROLE bob LOGIN NOINHERIT;       -- bob 即使被 GRANT 也不会自动继承
GRANT app_reader, app_writer TO bob;
-- bob 必须显式 SET ROLE app_writer 才能写入
```

```sql
-- Oracle: WITH ADMIN OPTION 让角色再授权
GRANT dba TO scott WITH ADMIN OPTION;
-- scott 现在可以 GRANT dba TO any_other_user;
```

## 矩阵三：SET ROLE 与默认角色

`SET ROLE` 决定**当前会话**激活哪个（或哪些）角色：

```sql
-- SQL 标准
SET ROLE { <role_name> | NONE }

-- PostgreSQL 扩展
SET ROLE r;                  -- 切换到某个角色（前提是已经是其成员）
RESET ROLE;                  -- 回到登录角色

-- MySQL 8.0
SET ROLE NONE;                       -- 清空
SET ROLE ALL;                        -- 激活所有授予的角色
SET ROLE 'r1', 'r2';                 -- 激活指定角色
SET DEFAULT ROLE ALL TO 'alice'@'%'; -- 登录时自动激活

-- Oracle
SET ROLE ALL EXCEPT dba;
SET ROLE r1 IDENTIFIED BY pwd;       -- 角色带密码时

-- ClickHouse
SET ROLE r;
SET DEFAULT ROLE r TO alice;

-- SQL Server
EXEC sp_addrolemember 'r', 'alice';   -- 旧语法
ALTER ROLE r ADD MEMBER alice;        -- 2012+
-- T-SQL 中没有 SET ROLE，权限自动生效
```

| 引擎 | SET ROLE | SET ROLE ALL | DEFAULT ROLE | 多角色同时激活 |
|------|---------|-------------|--------------|--------------|
| PostgreSQL | 是 | -- (一次只能一个) | -- | -- (但 INHERIT 可见所有) |
| MySQL 8.0+ | 是 | 是 | `SET DEFAULT ROLE` | 是 |
| MariaDB | 是 | 是 | `SET DEFAULT ROLE` | 是 |
| Oracle | 是 | 是 (含 EXCEPT) | `ALTER USER … DEFAULT ROLE` | 是 |
| SQL Server | -- (自动) | -- | -- | 自动全部 |
| DB2 | -- (自动) | -- | -- | 自动全部 |
| Snowflake | 是 (`USE ROLE`) | -- | `ALTER USER … SET DEFAULT_ROLE` | -- (一次一个) |
| Redshift | 是 | 是 | -- | 是 |
| ClickHouse | 是 | 是 | `SET DEFAULT ROLE` | 是 |
| CockroachDB | 是 | -- | -- | -- |
| TiDB | 是 | 是 | `SET DEFAULT ROLE` | 是 |
| Vertica | 是 | 是 | `ALTER USER … DEFAULT ROLE` | 是 |
| SAP HANA | 是 | -- | 自动 | 自动 |
| Trino | 是 | 是 | -- | 是 |
| Hive | 是 | 是 | -- | 是 |

> Snowflake 的 `USE ROLE` 是一个核心设计：每个会话**有且仅有**一个"当前活动角色"，所有 GRANT 检查都基于这一个角色。这与 PostgreSQL/Oracle "多个角色同时生效"的模型截然不同，也是 Snowflake RBAC 设计的关键约束。

## 矩阵四：登录角色 vs 组角色（PostgreSQL 的特殊设计）

PostgreSQL 8.1 (2005) 把 `CREATE USER` 和 `CREATE GROUP` 合并为 `CREATE ROLE`：

```sql
-- 登录角色（"用户"）
CREATE ROLE alice LOGIN PASSWORD 'secret';
-- 等价于
CREATE USER alice PASSWORD 'secret';

-- 组角色（不能直接登录）
CREATE ROLE app_team NOLOGIN;
-- 把 alice 加入组
GRANT app_team TO alice;
-- 给组授权
GRANT SELECT ON employees TO app_team;
```

| 概念 | PostgreSQL | Oracle | SQL Server | MySQL | Snowflake |
|------|-----------|--------|-----------|-------|-----------|
| 登录主体 | ROLE WITH LOGIN | USER | LOGIN (服务器级) + USER (库级) | `'user'@'host'` | USER |
| 权限分组 | ROLE NOLOGIN | ROLE | DATABASE ROLE | ROLE | ROLE |
| 是否同一对象 | 是 | 否 | 否 | 否 | 否 |
| 主机名约束 | -- | -- | -- | 是 (`@'%'`) | -- |
| Schema = 用户 | 不强制 | 是 | 不（独立） | -- (Schema=DB) | 不 |

PostgreSQL 这种"角色就是用户"的设计有两点直接后果：

1. 一个 NOLOGIN 角色可以拥有对象（`OWNER TO app_team`），所有组员都自动是所有者。
2. `pg_dump --role=` 可以让任意脚本以指定角色身份运行，方便迁移。

## 矩阵五：GRANT 系统权限 vs 对象权限

SQL 标准只定义了**对象权限**（SELECT/INSERT/UPDATE/DELETE/REFERENCES/USAGE/EXECUTE/TRIGGER/UNDER）。**系统权限**（CREATE TABLE / DROP ANY TABLE / ALTER SYSTEM）是 Oracle 引入并被广泛模仿的概念。

Oracle 风格的系统权限：

```sql
-- 系统权限：跨所有 schema 的能力
GRANT CREATE SESSION TO alice;        -- 允许登录
GRANT CREATE TABLE TO alice;          -- 允许在自己的 schema 建表
GRANT CREATE ANY TABLE TO migrator;   -- 允许在任意 schema 建表
GRANT SELECT ANY TABLE TO auditor;    -- 允许读任意 schema 的任意表
GRANT ALTER SYSTEM TO dba;
```

PostgreSQL 风格——把"系统权限"拆解到不同对象上：

```sql
-- 数据库级
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE mydb TO alice;
-- Schema 级
GRANT USAGE, CREATE ON SCHEMA hr TO alice;
-- 表空间
GRANT CREATE ON TABLESPACE fast_ssd TO alice;
-- 默认权限（影响未来创建的对象）
ALTER DEFAULT PRIVILEGES IN SCHEMA hr
    GRANT SELECT ON TABLES TO read_only;
```

| 引擎 | 系统权限模型 | 典型语法 | 影响范围 |
|------|------------|---------|---------|
| Oracle | 强 (200+ 系统权限) | `GRANT SELECT ANY TABLE` | 整个实例 |
| DB2 | 强 (DBADM/SECADM/SQLADM 等 authority) | `GRANT DBADM ON DATABASE` | 整个数据库 |
| SQL Server | 强 (server 权限 + db 权限) | `GRANT ALTER ANY LOGIN` | 实例/数据库 |
| Snowflake | 强 (account 级 + 对象级) | `GRANT CREATE WAREHOUSE ON ACCOUNT` | account |
| PostgreSQL | 弱 (拆解到对象 + `superuser` 属性) | `ALTER ROLE bypassrls` | 集群 |
| MySQL | 中 (`*.*` 通配 + 全局动态权限) | `GRANT BACKUP_ADMIN ON *.* TO …` | 实例 |
| ClickHouse | 中 (`SYSTEM …` 权限族) | `GRANT SYSTEM SHUTDOWN` | 集群 |
| Vertica | 中 | `GRANT EXECUTE ON FUNCTION` | -- |
| SAP HANA | 强 (system + analytic + package 权限) | `GRANT CATALOG READ` | 系统 |
| Teradata | 强 | `GRANT EXECUTE PROCEDURE` | -- |

## 矩阵六：对象权限粒度全景

下表比较各引擎对**单张表**支持的对象权限种类。括号里的 `(列)` 表示该权限可下放到列级。

| 引擎 | SELECT | INSERT | UPDATE | DELETE | TRUNCATE | REFERENCES | TRIGGER | RULE/POLICY | ALTER | DROP |
|------|--------|--------|--------|--------|---------|-----------|---------|------------|-------|------|
| PostgreSQL | 是(列) | 是(列) | 是(列) | 是 | 是 (8.4+) | 是(列) | 是 | -- (RLS 通过 OWNER/BYPASSRLS) | -- (OWNER) | -- (OWNER) |
| MySQL | 是(列) | 是(列) | 是(列) | 是 | 隐含 DROP | 是(列) | 是 | -- | 是 | 是 |
| Oracle | 是 | 是(列) | 是(列) | 是 | 隐含 DDL | 是(列) | 是 | -- | 是 | -- (DDL) |
| SQL Server | 是(列) | 是 | 是(列) | 是 | -- (需 ALTER) | 是(列) | -- | -- | 是 | -- (CONTROL) |
| DB2 | 是(列) | 是(列) | 是(列) | 是 | 隐含 DROP | 是(列) | 是 | -- | 是 | -- |
| Snowflake | 是 | 是 | 是 | 是 | 是 | 是 | -- | 是（POLICY） | -- (OWNERSHIP) | -- |
| BigQuery | 是 | -- (作业级) | 是 (DML) | 是 (DML) | -- | -- | -- | 是 (POLICY TAG) | -- | -- |
| Redshift | 是(列) | 是 | 是 | 是 | 是 | 是 | -- | -- | -- | -- (OWNER) |
| ClickHouse | 是(列) | 是(列) | 是 (`ALTER UPDATE`) | 是 (`ALTER DELETE`) | 是 | -- | -- | 是 (ROW POLICY) | 是 | 是 |
| Trino | 是(列) | 是 | 是 | 是 | -- | -- | -- | -- | -- | 是 |
| Spark SQL | 是(列, ACL plugin) | 是 | -- | -- | -- | -- | -- | -- | -- | -- |
| Hive | 是(列) | 是 | 是 (ACID) | 是 (ACID) | -- | -- | -- | -- | -- | -- |
| Databricks (UC) | 是(列, mask) | 是 | 是 | 是 | -- | -- | -- | 是 (row filter) | 是 | 是 |
| Vertica | 是(列, GRANT 列) | 是 | 是 | 是 | 是 | 是 | -- | 是 (Access Policy) | -- | -- |
| Greenplum | 是(列) | 是(列) | 是(列) | 是 | 是 | 是(列) | 是 | -- | -- | -- |
| CockroachDB | 是 | 是 | 是 | 是 | -- | -- | -- | 是 (RLS 22.2+) | -- | -- |
| TiDB | 是(列) | 是(列) | 是(列) | 是 | -- | 是(列) | 是 | -- | 是 | 是 |
| StarRocks | 是 | 是 | 是 | 是 | -- | -- | -- | -- | 是 | 是 |
| Doris | 是(列, 2.0+) | 是 | 是 | 是 | -- | -- | -- | -- | 是 | 是 |
| SAP HANA | 是(列, masking) | 是 | 是 | 是 | -- | 是 | 是 | 是 (analytic privilege) | 是 | 是 |
| DuckDB | 是 | 是 | 是 | 是 | -- | -- | -- | -- | -- | -- |

> 行级安全（RLS / ROW POLICY）在 PostgreSQL 9.5+、SQL Server 2016+、Oracle VPD、ClickHouse 20.7+、CockroachDB 22.2+、Vertica、Snowflake、Databricks 上都有原生实现，但语法千差万别——详见 `row-level-security.md`。

## 矩阵七：列级权限

列级权限是 SQL:2003 标准的一部分，但实现差异极大。

```sql
-- PostgreSQL / Greenplum / YugabyteDB
GRANT SELECT (id, name), UPDATE (status) ON employees TO alice;

-- MySQL / MariaDB / TiDB
GRANT SELECT (id, name) ON db.employees TO 'alice'@'%';

-- Oracle: 仅 INSERT/UPDATE/REFERENCES 支持列级
GRANT INSERT (name, email) ON employees TO alice;
-- SELECT 列级要靠 VIEW 或 Data Redaction Policy

-- SQL Server: 列级 GRANT 全支持
GRANT SELECT ON employees(id, name) TO alice;
GRANT UPDATE ON employees(status) TO alice;
DENY SELECT ON employees(salary) TO alice;  -- 唯一支持 DENY 的引擎

-- DB2
GRANT SELECT (id, name) ON employees TO alice;

-- Snowflake: 不支持列级 GRANT，但支持 MASKING POLICY
CREATE MASKING POLICY mask_ssn AS (val string) RETURNS string ->
    CASE WHEN current_role() IN ('HR_ROLE') THEN val
         ELSE 'XXX-XX-' || RIGHT(val, 4) END;
ALTER TABLE employees MODIFY COLUMN ssn SET MASKING POLICY mask_ssn;

-- BigQuery: POLICY TAG（绑定到 IAM）
ALTER TABLE employees ALTER COLUMN ssn
    SET OPTIONS (policy_tags = ['projects/p/locations/l/taxonomies/t/policyTags/pii']);

-- Databricks Unity Catalog: COLUMN MASK
ALTER TABLE employees ALTER COLUMN ssn SET MASK mask_func USING COLUMNS(role);
```

| 引擎 | 列级 SELECT | 列级 INSERT/UPDATE | 列级 REFERENCES | 实现机制 |
|------|------------|-------------------|----------------|---------|
| PostgreSQL | 是 | 是 | 是 | ACL 中按列存储 |
| MySQL/MariaDB/TiDB | 是 | 是 | 是 | mysql.columns_priv |
| Oracle | -- (用 VIEW/Redaction) | 是 | 是 | 列级 ACL 字典 |
| SQL Server | 是 (含 DENY) | 是 | 是 | sys.column_permissions |
| DB2 | 是 | 是 | 是 | catalog 列级 ACL |
| Snowflake | -- | -- | -- | MASKING POLICY |
| BigQuery | 是 (POLICY TAG) | -- | -- | Data Catalog Taxonomy |
| Redshift | 是 (RA3+, 2020) | 是 | -- | sys.column_privileges |
| ClickHouse | 是 (21.x+) | 是 | -- | RBAC catalog |
| Vertica | 是 (column-level access policy) | -- | -- | CREATE ACCESS POLICY |
| Greenplum | 是 | 是 | 是 | 同 PG |
| CockroachDB | -- | -- | -- | 用 VIEW |
| Hive | 是 (Ranger) | -- | -- | Apache Ranger plugin |
| Databricks UC | 是 (mask) | -- | -- | COLUMN MASK |
| StarRocks | 是 (3.x+) | -- | -- | RBAC |
| Doris | 是 (2.0+) | -- | -- | RBAC |
| SAP HANA | 是 (Data Masking) | -- | -- | catalog 级 |

## 矩阵八：函数 / 过程 / 类型 上的权限

| 引擎 | EXECUTE FUNCTION | EXECUTE PROCEDURE | USAGE TYPE | USAGE SEQUENCE | USAGE LANGUAGE |
|------|-----------------|-------------------|-----------|---------------|---------------|
| PostgreSQL | 是 | 是 (11+) | 是 | 是 | 是 |
| MySQL | 是 | 是 | -- | -- | -- |
| Oracle | 是 | 是 | 是 (TYPE) | -- (sequence 用 SELECT) | -- |
| SQL Server | 是 | 是 | -- | -- | -- |
| DB2 | 是 | 是 | 是 | 是 | -- |
| Snowflake | 是 | 是 | -- | 是 | -- |
| ClickHouse | -- (函数本身无权限) | -- | -- | -- | -- |
| Redshift | 是 | 是 | -- | -- | -- |
| Greenplum | 是 | 是 | 是 | 是 | 是 |
| Vertica | 是 | 是 | -- | 是 | -- |
| SAP HANA | 是 | 是 | 是 | 是 | -- |
| Trino | -- (函数无 GRANT) | -- | -- | -- | -- |
| Spark SQL | 是 (UDF 注册) | -- | -- | -- | -- |
| Databricks UC | 是 | 是 | -- | -- | -- |

```sql
-- PostgreSQL
GRANT EXECUTE ON FUNCTION calc_tax(numeric) TO alice;
GRANT USAGE ON SEQUENCE order_id_seq TO app_writer;
GRANT USAGE ON LANGUAGE plpgsql TO developer;
GRANT USAGE ON TYPE address_type TO app_reader;

-- Oracle
GRANT EXECUTE ON pkg_payroll TO hr_manager;
GRANT EXECUTE ON TYPE address_t TO PUBLIC;

-- SQL Server
GRANT EXECUTE ON dbo.calc_tax TO alice;
GRANT EXECUTE ON SCHEMA::reporting TO analyst;
```

## 矩阵九：Schema / Database / Catalog 级权限

不同引擎对"namespace"层级数量分歧严重：

```
PostgreSQL    cluster  →  database  →  schema  →  object
Oracle        instance →  user(=schema)         →  object
SQL Server    instance →  database  →  schema  →  object
MySQL         instance →  database(=schema)     →  object
Snowflake     account  →  database  →  schema  →  object
BigQuery      project  →  dataset(=schema)      →  object
Trino         catalog  →  schema                →  object
Hive          metastore → database(=schema)     →  object
```

每一层都可独立授权：

```sql
-- PostgreSQL
GRANT CONNECT ON DATABASE app_db TO alice;
GRANT USAGE  ON SCHEMA hr TO alice;
GRANT SELECT ON ALL TABLES IN SCHEMA hr TO alice;
GRANT SELECT ON ALL TABLES IN SCHEMA hr TO alice;
ALTER DEFAULT PRIVILEGES IN SCHEMA hr
    GRANT SELECT ON TABLES TO alice;   -- 对未来表也生效

-- Snowflake — 三级命名空间，每级都需 USAGE
GRANT USAGE ON DATABASE prod TO ROLE analyst;
GRANT USAGE ON SCHEMA prod.public TO ROLE analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA prod.public TO ROLE analyst;
GRANT SELECT ON FUTURE TABLES IN SCHEMA prod.public TO ROLE analyst;  -- 未来对象

-- Trino — catalog 是顶层
GRANT SELECT ON hive.sales.orders TO alice;
GRANT CREATE ON SCHEMA hive.sales TO alice;

-- BigQuery
GRANT `roles/bigquery.dataViewer` ON SCHEMA project.dataset TO 'user:alice@x.com';
```

| 引擎 | DATABASE 级 | SCHEMA 级 | "未来对象" / `ALL` 通配 |
|------|-------------|-----------|----------------------|
| PostgreSQL | 是 | 是 | `ALL TABLES IN SCHEMA` + `ALTER DEFAULT PRIVILEGES` |
| Oracle | -- (用 system priv) | 是 (= 用户) | -- (用系统权限 SELECT ANY TABLE) |
| SQL Server | 是 | 是 | `GRANT … ON SCHEMA::s` |
| MySQL | 是 (`db.*`) | -- (Schema=DB) | `db.*` 通配 |
| Snowflake | 是 | 是 | `ON ALL` + `ON FUTURE` (核心特性) |
| BigQuery | 项目级 IAM | 数据集级 | -- |
| Redshift | 是 | 是 | `ALL TABLES IN SCHEMA` + `ALTER DEFAULT PRIVILEGES` |
| ClickHouse | 是 | -- (扁平) | 是 (`*.*`, `db.*`) |
| Trino | catalog 级 | 是 | -- (但 `ALL TABLES` 部分支持) |
| Hive | 是 | 是 | -- |
| Databricks UC | catalog | schema | `GRANT … ON ALL TABLES` |
| Vertica | 是 | 是 | `ALTER DEFAULT PRIVILEGES` |
| CockroachDB | 是 | 是 (22.1+) | `ALTER DEFAULT PRIVILEGES` |
| StarRocks/Doris | 是 | 是 | -- |

> Snowflake 的 `GRANT SELECT ON FUTURE TABLES` 是非常独特的设计：在 schema 上声明一个"未来权限规则"，新建的对象自动继承。这是 PostgreSQL `ALTER DEFAULT PRIVILEGES` 的强化版——后者只对**当前会话用户创建的对象**生效，而 Snowflake 的 FUTURE GRANTS 对**任何人**新建的对象都生效。

## 矩阵十：REVOKE 的 CASCADE / RESTRICT

SQL 标准要求 `REVOKE` 必须显式指定 `CASCADE` 或 `RESTRICT`：

```sql
REVOKE [GRANT OPTION FOR] <privilege> ON <object>
    FROM <grantee>
    { CASCADE | RESTRICT }
```

含义：

- `RESTRICT`：如果撤销会导致依赖的子授权被破坏，则**整个 REVOKE 失败**。
- `CASCADE`：连带撤销所有"依赖"的子授权。

| 引擎 | 默认行为 | 显式 CASCADE | 显式 RESTRICT | GRANT OPTION FOR |
|------|---------|-------------|--------------|-----------------|
| PostgreSQL | RESTRICT | 是 | 是 | 是 |
| MySQL | -- (无依赖追踪) | -- | -- | -- |
| Oracle | RESTRICT | 是 (`CASCADE CONSTRAINTS`) | 是 | -- |
| SQL Server | -- (默认 CASCADE) | 是 | -- | 是 |
| DB2 | RESTRICT | 是 | 是 | 是 |
| Snowflake | -- (CASCADE 隐式) | -- | -- | -- |
| Redshift | RESTRICT | 是 | 是 | 是 |
| ClickHouse | -- | -- | -- | -- |
| Vertica | RESTRICT | 是 | 是 | 是 |

```sql
-- PostgreSQL: 完整标准实现
GRANT SELECT ON employees TO alice WITH GRANT OPTION;
-- alice 接着 GRANT 给 bob
SET ROLE alice;
GRANT SELECT ON employees TO bob;
RESET ROLE;
-- 此时若想撤销 alice 的权限：
REVOKE SELECT ON employees FROM alice;            -- 失败：bob 依赖
REVOKE SELECT ON employees FROM alice CASCADE;    -- 成功：连带 bob

-- 仅撤销 GRANT 选项，保留权限
REVOKE GRANT OPTION FOR SELECT ON employees FROM alice CASCADE;
```

## 各引擎语法详解

### PostgreSQL — 最完整的 ACL 实现

PostgreSQL 的角色系统是 SQL 标准最严格的开源实现，并加上了大量扩展：

```sql
-- 创建角色，复合属性
CREATE ROLE alice
    LOGIN
    PASSWORD 'secret'
    VALID UNTIL '2026-12-31'
    CONNECTION LIMIT 50
    INHERIT
    CREATEDB
    NOCREATEROLE
    NOSUPERUSER
    NOBYPASSRLS;

-- 把角色加入另一角色
GRANT app_writer TO alice WITH ADMIN OPTION;

-- ALL 通配 + IN SCHEMA
GRANT SELECT ON ALL TABLES IN SCHEMA hr TO read_only;
GRANT USAGE  ON ALL SEQUENCES IN SCHEMA hr TO read_only;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hr TO read_only;

-- 默认权限：影响以后创建的对象
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA hr
    GRANT SELECT ON TABLES TO read_only;

-- BYPASSRLS 让超级查询绕过行级安全
ALTER ROLE auditor BYPASSRLS;

-- 角色作为对象 OWNER
CREATE TABLE hr.employees (...) OWNER TO app_owner;

-- 切换执行身份
SET LOCAL ROLE alice;
-- ... 仅本事务内生效
```

要点：

1. `LOGIN/NOLOGIN` 决定能否直接登录数据库——这是用户/组的唯一区别。
2. `INHERIT/NOINHERIT` 控制成员是否自动继承被授予角色的权限。
3. `CREATEDB / CREATEROLE / SUPERUSER / REPLICATION / BYPASSRLS` 是属性而非权限——只能由 SUPERUSER 设置。
4. `ALTER DEFAULT PRIVILEGES` 只影响**之后**创建的对象，且按"创建者 + schema"过滤。

### Oracle — 系统权限的代表

Oracle 把权限分为 **System Privileges**（200+ 种）、**Object Privileges**（约 20 种）、**Roles**（命名集合）三层：

```sql
-- 创建角色
CREATE ROLE app_admin;
CREATE ROLE secure_role IDENTIFIED BY rolepwd;   -- 带密码的角色
CREATE ROLE ext_role IDENTIFIED EXTERNALLY;      -- 外部认证

-- 系统权限
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE TO app_admin;
GRANT SELECT ANY TABLE, INSERT ANY TABLE TO data_loader;

-- 对象权限
GRANT SELECT, INSERT ON hr.employees TO app_admin WITH GRANT OPTION;

-- 把角色授给用户
GRANT app_admin TO scott WITH ADMIN OPTION;

-- 角色嵌套
GRANT app_read TO app_admin;
GRANT app_admin TO senior_dba;

-- 设置默认角色（登录自动激活）
ALTER USER scott DEFAULT ROLE app_admin, app_read;
ALTER USER scott DEFAULT ROLE ALL EXCEPT secure_role;

-- 在会话中激活带密码的角色
SET ROLE secure_role IDENTIFIED BY rolepwd;
```

Oracle 独特之处：

1. **用户即 Schema**：`scott` 既是登录账号也是名为 `SCOTT` 的 schema。
2. **PUBLIC 角色**：每个用户自动是 PUBLIC 成员，授给 PUBLIC 等于授给所有人。
3. **`ANY` 关键字**：`SELECT ANY TABLE` 等系统权限跨所有 schema 生效，是数据库的"半超级用户"。
4. **角色密码**：让某个角色仅在显式 `SET ROLE … IDENTIFIED BY` 后才生效——可用作"敏感操作前的二次验证"。
5. **没有列级 SELECT GRANT**：必须依赖 VIEW、VPD（Virtual Private Database）或 12c+ 的 Data Redaction。

### SQL Server — Server Role / Database Role 双层

T-SQL 把角色严格分为两层：

```sql
-- Server-level (跨数据库)
USE master;
CREATE SERVER ROLE devops AUTHORIZATION sa;
ALTER SERVER ROLE sysadmin ADD MEMBER alice_login;
GRANT VIEW SERVER STATE TO devops;

-- Database-level
USE app_db;
CREATE ROLE app_writer AUTHORIZATION dbo;
ALTER ROLE app_writer ADD MEMBER alice;       -- 2012+ 语法
EXEC sp_addrolemember 'app_writer', 'alice'; -- 旧语法

-- Schema 级权限（SQL Server 中 schema 是命名空间）
GRANT SELECT, INSERT ON SCHEMA::reporting TO app_writer;

-- DENY 优先于 GRANT（独家特性）
GRANT SELECT ON employees TO app_writer;
DENY SELECT ON employees(salary) TO app_writer;
-- app_writer 可读其它列，但 salary 被拒绝

-- 应用程序角色（Application Role）
CREATE APPLICATION ROLE accounting_app
    WITH PASSWORD = 'AppSecret#2026',
         DEFAULT_SCHEMA = accounting;
-- 应用启动后 EXEC sp_setapprole 'accounting_app', 'AppSecret#2026'
```

要点：

1. `Login`（服务器对象）与 `User`（数据库对象）解耦：一个 login 可在多个数据库中映射不同的 user。
2. 唯一支持 `DENY` 的主流引擎，`DENY > GRANT > REVOKE` 的优先级模型。
3. **Application Role**：会话激活后**完全替换**当前用户身份，常用于"应用统一连接 + 按功能切换权限"模式。
4. 内置固定 server role：`sysadmin`、`securityadmin`、`dbcreator`、`bulkadmin` 等。

### MySQL / MariaDB — 用户带主机的 GRANT

MySQL 的权限模型直到 8.0 (2018) 才引入角色，此前完全靠 `'user'@'host'` 加全局/库/表/列的 GRANT：

```sql
-- 用户 = 名字 + 主机
CREATE USER 'alice'@'10.%' IDENTIFIED BY 'secret';
CREATE USER 'alice'@'localhost' IDENTIFIED BY 'secret2';

-- 全局权限 (`*.*`)
GRANT BACKUP_ADMIN, REPLICATION_SLAVE ON *.* TO 'repl'@'%';

-- 数据库级 (`db.*`)
GRANT SELECT, INSERT, UPDATE ON app.* TO 'alice'@'10.%';

-- 表级
GRANT SELECT ON app.employees TO 'alice'@'10.%';

-- 列级
GRANT SELECT (id, name), UPDATE (status) ON app.employees TO 'alice'@'10.%';

-- 角色 (8.0+)
CREATE ROLE 'app_read', 'app_write';
GRANT SELECT ON app.* TO 'app_read';
GRANT INSERT, UPDATE, DELETE ON app.* TO 'app_write';
GRANT 'app_read', 'app_write' TO 'alice'@'10.%';

-- 必须显式激活
SET ROLE 'app_write';
-- 或者设默认
SET DEFAULT ROLE ALL TO 'alice'@'10.%';
```

MySQL 8.0 的"动态权限"机制把 `SUPER` 拆解为 30+ 个细粒度权限：`BACKUP_ADMIN`、`BINLOG_ADMIN`、`CONNECTION_ADMIN`、`REPLICATION_APPLIER`、`SET_USER_ID`……让 DBA 可以授出最小权限。

### Snowflake — 强制 RBAC + 角色层级

Snowflake 的安全模型是"必须有一个当前活动角色"，所有权限检查都基于这一个角色：

```sql
-- 创建角色层级
CREATE ROLE SYSADMIN;            -- 内置
CREATE ROLE APP_OWNER;
CREATE ROLE APP_READ;
CREATE ROLE APP_WRITE;

-- 角色挂在层级树上
GRANT ROLE APP_READ  TO ROLE APP_WRITE;   -- WRITE 继承 READ
GRANT ROLE APP_WRITE TO ROLE APP_OWNER;
GRANT ROLE APP_OWNER TO ROLE SYSADMIN;    -- 让 SYSADMIN 能管理

-- 给用户授角色 + 设默认
GRANT ROLE APP_READ TO USER alice;
ALTER USER alice SET DEFAULT_ROLE = APP_READ;

-- 三级命名空间，每层 USAGE
GRANT USAGE ON WAREHOUSE compute_wh TO ROLE APP_READ;
GRANT USAGE ON DATABASE  prod_db    TO ROLE APP_READ;
GRANT USAGE ON SCHEMA    prod_db.public TO ROLE APP_READ;
GRANT SELECT ON ALL TABLES IN SCHEMA prod_db.public TO ROLE APP_READ;

-- 未来对象自动继承（核心特性）
GRANT SELECT ON FUTURE TABLES IN SCHEMA prod_db.public TO ROLE APP_READ;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA prod_db.public TO ROLE APP_READ;

-- OWNERSHIP 是一种特殊的"独占"权限
GRANT OWNERSHIP ON TABLE prod_db.public.orders TO ROLE APP_OWNER;

-- MANAGE GRANTS：可以管理任意对象的授权（即便不是 owner）
GRANT MANAGE GRANTS ON ACCOUNT TO ROLE security_admin;

-- 切换角色
USE ROLE APP_WRITE;
```

要点：

1. **强制角色层级**：所有角色最终都应挂到 `SYSADMIN` 之下（最佳实践）。
2. **FUTURE GRANTS**：对"以后才会创建的对象"声明权限——这是其它引擎所没有的。
3. **OWNERSHIP 独占**：一个对象只能有一个 owner 角色，必须 `REVOKE` 后才能 `GRANT` 给新角色。
4. **MANAGE GRANTS**：把"授权管理"权力本身分离出来，让 security admin 可以为任意 owner 的对象执行 GRANT。
5. **ACCESS HISTORY** / **OBJECT TAGGING**：审计与 governance 一体化。

### BigQuery — IAM 优先，SQL GRANT 是包装

BigQuery 的根权限模型是 GCP IAM。直到 2021 年才在 SQL 层加入 `GRANT/REVOKE`，本质上是创建/修改一个 IAM Policy Binding：

```sql
-- 数据集级
GRANT `roles/bigquery.dataViewer`
    ON SCHEMA `project.dataset`
    TO 'user:alice@example.com', 'group:analysts@example.com';

-- 表级
GRANT `roles/bigquery.dataEditor`
    ON TABLE `project.dataset.orders`
    TO 'serviceAccount:etl@p.iam.gserviceaccount.com';

-- 列级 = Policy Tags
CREATE SCHEMA `project.dataset` OPTIONS (...);
ALTER TABLE `project.dataset.users` ALTER COLUMN ssn
    SET OPTIONS (
        policy_tags=['projects/p/locations/us/taxonomies/t/policyTags/PII']
    );

-- 行级 = ROW ACCESS POLICY
CREATE ROW ACCESS POLICY us_only ON `project.dataset.orders`
    GRANT TO ('group:us-team@example.com')
    FILTER USING (region = 'US');
```

BigQuery 没有 `CREATE ROLE` 的概念——"角色"是 IAM 角色，必须在 GCP 控制台或 `gcloud iam roles create` 中创建。

### Redshift — 从 GROUP 到 ROLE 的过渡

Redshift 早期（2013–2022）只有 `CREATE GROUP`：

```sql
CREATE GROUP analysts;
ALTER GROUP analysts ADD USER alice;
GRANT SELECT ON ALL TABLES IN SCHEMA prod TO GROUP analysts;
```

2022 年后引入 SQL:1999 风格的 ROLE：

```sql
CREATE ROLE app_read;
GRANT SELECT ON ALL TABLES IN SCHEMA prod TO ROLE app_read;
GRANT ROLE app_read TO alice;
GRANT ROLE app_read TO ROLE senior_analyst WITH ADMIN OPTION;

-- 系统权限（仅角色可持有）
GRANT CREATE TABLE TO ROLE app_owner;
GRANT TRUNCATE TABLE TO ROLE app_owner;
```

Redshift 是少数把**系统权限**只能授给 ROLE、不能直接授给 USER 的引擎。

### ClickHouse — RBAC 与 SETTINGS PROFILE

ClickHouse 在 20.4+ 引入完整 RBAC，独特点是把"会话设置"也当作一种权限对象：

```sql
CREATE ROLE analyst ON CLUSTER prod;
GRANT SELECT ON db.* TO analyst;
GRANT SHOW ON db.* TO analyst;
GRANT INSERT ON db.events_local TO analyst;

-- 列级
GRANT SELECT(id, name, email) ON db.users TO analyst;

-- 行级
CREATE ROW POLICY us_only ON db.events
    FOR SELECT USING country = 'US'
    TO analyst;

-- SETTINGS PROFILE：把 max_memory_usage 等当作"权限"
CREATE SETTINGS PROFILE heavy_query SETTINGS
    max_memory_usage = 100000000000,
    max_execution_time = 600;
ALTER USER alice SETTINGS PROFILE 'heavy_query';

-- QUOTA：限制查询次数和数据量
CREATE QUOTA q1 FOR INTERVAL 1 hour MAX queries 100, errors 10
    TO analyst;
```

ClickHouse 通过 `SYSTEM` 权限族（`SYSTEM SHUTDOWN`、`SYSTEM DROP CACHE`、`SYSTEM RELOAD CONFIG`、`SYSTEM FLUSH LOGS`）把运维操作做成细粒度权限。

### DB2 — Authority + Privilege 双层

DB2 把"高权限身份"称为 **authority**（DBADM、SECADM、SQLADM、ACCESSCTRL、DATAACCESS、WLMADM、EXPLAIN），把对象权限称为 **privilege**：

```sql
-- 授予 authority
GRANT DBADM ON DATABASE TO USER alice;
GRANT SECADM ON DATABASE TO ROLE security_team;
GRANT DATAACCESS ON DATABASE TO ROLE etl_role;

-- 授予 privilege
GRANT SELECT, UPDATE ON TABLE hr.employees TO ROLE app_writer;
GRANT EXECUTE ON FUNCTION calc_tax TO PUBLIC;

-- 角色
CREATE ROLE security_team;
GRANT ROLE security_team TO USER alice WITH ADMIN OPTION;

-- 把角色授给组（DB2 早期只有组）
GRANT ROLE app_writer TO GROUP devs;

-- LBAC（Label-Based Access Control）
CREATE SECURITY LABEL COMPONENT classification
    TREE ('TS' UNDER 'S' UNDER 'C' UNDER 'U');
CREATE SECURITY POLICY confidentiality
    COMPONENTS classification
    WITH DB2LBACRULES;
ALTER TABLE employees
    ADD COLUMN sec_label DB2SECURITYLABEL;
```

### SAP HANA — Catalog Role / Repository Role / Analytic Privilege

HANA 的角色分两类：

- **Catalog roles**：通过 `CREATE ROLE` 在 catalog 中存储，传统方式。
- **Repository roles**：通过 HDI 容器以代码形式部署，便于版本控制。

```sql
-- Catalog role
CREATE ROLE app_read NO GRANT TO CREATOR;
GRANT SELECT ON SCHEMA hr TO app_read;
GRANT EXECUTE ON PROCEDURE calc_tax TO app_read;

-- Analytic Privilege —— 行级 + 列级 + 维度过滤的复合
CREATE STRUCTURED PRIVILEGE us_sales_view
    FOR SELECT
    ON CALCULATION VIEW sales.total_sales
    CONDITION (region = 'US');
GRANT STRUCTURED PRIVILEGE us_sales_view TO app_read;

-- System Privilege
GRANT CATALOG READ TO app_read;
GRANT BACKUP ADMIN TO db_admin;
```

HANA 的 **Analytic Privilege** 把"行级安全 + 列级隐藏 + 计算视图维度过滤"统一成一种声明，是与其它引擎差异最大的设计。

### Trino / Presto — 插件化访问控制

Trino 的访问控制由 `SystemAccessControl` 和 `ConnectorAccessControl` 插件提供，SQL `GRANT/REVOKE` 仅是语法外壳：

```sql
-- 创建角色（在 catalog 内）
CREATE ROLE admin IN hive;
GRANT admin TO USER alice IN hive;

-- 对象权限
GRANT SELECT ON hive.sales.orders TO ROLE admin;
GRANT INSERT ON TABLE hive.sales.orders TO USER bob;

-- Schema 级
GRANT CREATE ON SCHEMA hive.sales TO USER alice;

-- 切换激活角色
SET ROLE admin IN hive;
```

不同 connector 的实现差异巨大：Hive connector 透传给 Apache Ranger / Sentry，Iceberg connector 把 ACL 写入 metadata，PostgreSQL connector 直接转发 `GRANT` 给后端 PG。这意味着**同一份 GRANT 语句在不同 catalog 上的行为可能不同**。

### Hive — SQL Std Auth vs Ranger

Hive 有三套互斥的授权模式：

1. **Storage-Based**：靠 HDFS 文件权限，无 GRANT/REVOKE。
2. **SQL Standard Authorization**：原生 GRANT/REVOKE + ROLE。
3. **Apache Ranger**：策略服务器，提供列级、行级、动态掩码。

```sql
-- SQL Std Auth
SET hive.security.authorization.enabled = true;
SET hive.security.authorization.manager =
    org.apache.hadoop.hive.ql.security.authorization.plugin.sqlstd.SQLStdHiveAuthorizerFactory;

CREATE ROLE app_read;
GRANT SELECT ON DATABASE app TO ROLE app_read;
GRANT ROLE app_read TO USER alice;
SET ROLE app_read;
```

## 角色层级设计：Snowflake 严格树 vs PostgreSQL 角色链

两种主流的角色组织哲学：

### Snowflake 的"严格层级树"

Snowflake 的最佳实践要求角色组成一棵从 `SYSADMIN` 向下的树：

```
              ACCOUNTADMIN
             /            \
       SYSADMIN        SECURITYADMIN
        /     \              \
   APP_OWNER  ETL_OWNER    USERADMIN
     /    \       \
APP_READ APP_WRITE ETL_READ
   |         |
 USER A   USER B
```

权限授予自下而上：底层角色拿到对象 GRANT，上层角色通过 `GRANT ROLE child TO parent` 继承。`SYSADMIN` 是所有非安全角色的公共祖先，因此 `SYSADMIN` 可以管理一切对象。这种设计的优点是**结构清晰、追踪简单**：要查"谁能读 orders 表"，只需从拥有 SELECT 的角色出发向下遍历。

### PostgreSQL 的"任意有向无环图"

PostgreSQL 不强制层级形状，角色可以构成任意 DAG。这带来灵活性也带来复杂性：

```sql
GRANT app_read TO senior_analyst;
GRANT app_read TO junior_analyst;
GRANT senior_analyst TO bob;
GRANT junior_analyst TO bob;
GRANT app_admin TO bob;
-- bob 通过 4 条不同路径继承 app_read
```

PostgreSQL 用 `pg_has_role(role, member, 'USAGE')` 函数检查传递成员关系。`information_schema.applicable_roles` 视图可遍历整张图。对运维而言，**审计某个用户的有效权限往往需要写递归 CTE**。

### 设计权衡总结

| 维度 | 严格层级 (Snowflake) | DAG (PostgreSQL/Oracle) |
|------|---------------------|------------------------|
| 学习曲线 | 陡峭（必须遵守约定） | 平缓（按需扩展） |
| 审计可见性 | 高（树状） | 低（图状） |
| 灵活性 | 中 | 高 |
| 误授权风险 | 低 | 高 |
| 多团队共享对象 | 难（要重新授权） | 易（多链路继承） |
| 适合场景 | 大型企业、合规 | 中小团队、快速演进 |

## "默认权限" / "未来权限" 机制对比

让"以后创建的对象"自动获得权限，是大型仓库的刚需。

```sql
-- PostgreSQL: ALTER DEFAULT PRIVILEGES
-- 必须按"创建者 + schema"限定
ALTER DEFAULT PRIVILEGES
    FOR ROLE app_owner          -- 谁创建的
    IN SCHEMA hr                -- 在哪个 schema
    GRANT SELECT ON TABLES TO read_only;
-- 仅对"app_owner 在 hr schema 下创建的新表"自动生效

-- Snowflake: GRANT ON FUTURE
GRANT SELECT ON FUTURE TABLES IN SCHEMA prod.public TO ROLE app_read;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA prod.public TO ROLE app_read;
GRANT SELECT ON FUTURE TABLES IN DATABASE prod        TO ROLE app_read;
-- 任何人在该 schema 创建的任何新表都自动生效
-- 注意：FUTURE GRANT 与已存在对象的 GRANT 是独立的两套规则

-- Redshift: 同 PostgreSQL
ALTER DEFAULT PRIVILEGES IN SCHEMA prod
    GRANT SELECT ON TABLES TO GROUP analysts;

-- Vertica: 同 PostgreSQL
ALTER DEFAULT PRIVILEGES FOR ROLE alice IN SCHEMA hr
    GRANT SELECT ON TABLES TO read_only;

-- Databricks Unity Catalog: 通过 Inherited Privileges
GRANT SELECT ON SCHEMA prod.sales TO `account users`;
-- schema 的 SELECT 自动应用到下属所有当前与未来的表
```

| 引擎 | 机制 | 影响范围 | 创建者过滤 |
|------|------|---------|-----------|
| PostgreSQL | `ALTER DEFAULT PRIVILEGES` | 当前/未来对象 | 可按 ROLE 限定 |
| Snowflake | `GRANT ON FUTURE` | 未来对象 | 不限创建者 |
| Redshift | `ALTER DEFAULT PRIVILEGES` | 未来对象 | 可按用户限定 |
| Vertica | `ALTER DEFAULT PRIVILEGES` | 未来对象 | 可按 ROLE 限定 |
| Databricks UC | Schema 继承 | 当前 + 未来 | -- |
| Oracle | -- (用 `SELECT ANY TABLE`) | 全部 | -- |
| SQL Server | -- (用 `GRANT ON SCHEMA`) | 当前 + 未来 | -- |
| MySQL | `db.*` 通配 | 全部 | -- |

> SQL Server 的 `GRANT SELECT ON SCHEMA::reporting TO alice` 自动覆盖该 schema 下当前与未来的所有表，是这一机制最简洁的实现。

## OWNERSHIP / OWNER 的特殊地位

"对象所有者"在大多数引擎中是一种**特殊的隐含权限**——拥有对象的人自动持有所有对象权限，且可以撤销其它人的权限。

| 引擎 | OWNER 概念 | 转移语法 | 是否可被授权 |
|------|-----------|---------|-------------|
| PostgreSQL | 是 | `ALTER TABLE … OWNER TO new_role` | 否（OWNER 是属性） |
| MySQL | 隐式（创建者） | -- | 否 |
| Oracle | 是（schema = user） | `ALTER … RENAME` 或重建 | 否 |
| SQL Server | `AUTHORIZATION` | `ALTER AUTHORIZATION ON … TO …` | 否 |
| DB2 | 是 | `TRANSFER OWNERSHIP OF … TO …` | 是 |
| Snowflake | OWNERSHIP 权限 | `GRANT OWNERSHIP ON … TO ROLE …` | 是（独占） |
| Redshift | 是 | `ALTER … OWNER TO …` | 否 |
| BigQuery | -- (IAM 主体) | -- | 是 |
| ClickHouse | -- | -- | -- |

Snowflake 把 OWNERSHIP 视为一种**可被显式 GRANT 的独占权限**——同一时刻一个对象只能有一个 owner role；这与 PostgreSQL/Oracle "必须用单独 ALTER 语句改 owner"形成对比。

## SQLite 与无角色引擎的应对策略

`SQLite`、`DuckDB`（早期）、`Flink SQL`、`InfluxDB`、`QuestDB` 等嵌入式或单租户引擎完全没有用户系统。生产环境一般通过以下方式补救：

1. **文件系统权限**：让 OS user 控制对 `.db` 文件的读写。
2. **应用层 ACL**：在应用网关层做 SQL 改写或 row filter。
3. **代理层**：PgBouncer / ProxySQL / Trino 这类中间件统一鉴权。
4. **只读快照**：把生产库以 `?mode=ro` 形式暴露给查询用户。

DuckDB 0.9+ 开始引入 `CREATE ROLE/USER`，但默认嵌入模式仍然假定调用进程已认证；只有在 server 模式（`duckdb-server`、HTTP server 扩展）下角色系统才有意义。

## 关键发现 (Key Findings)

1. **SQL:1999 的 ROLE 标准只是个起点**：标准只规定 `CREATE ROLE / GRANT … TO / SET ROLE / WITH ADMIN OPTION` 这四个语法元素，所有的"角色继承""默认角色""未来权限""列级 GRANT""DENY""OWNERSHIP""系统权限"全是引擎扩展。这让"角色与授权"成为 SQL 方言差异最大的领域之一。

2. **45+ 引擎中只有约 38 个有 SQL 层角色 DDL**。SQLite、Flink、纯 IAM 引擎（BigQuery、Spanner、Athena）、InfluxDB 完全把权限交给外部系统。Derby 仅有简单 GRANT 而无 ROLE。

3. **PostgreSQL 是唯一彻底合并"用户与角色"的主流引擎**（8.1, 2005）。这一设计让 NOLOGIN 角色可以拥有对象，组成员可以通过 `SET ROLE` 切换身份，是 ACL/RBAC 混合模型的优雅实现，但也让 `pg_dumpall --roles-only` 这类工具需要额外处理"含密码的角色 vs 不含密码的角色"。

4. **MySQL 直到 8.0 (2018) 才有 ROLE**，比 SQL 标准晚 19 年。在此之前所有权限都直接绑在 `'user'@'host'` 上，导致大型生产环境出现大量重复 GRANT。8.0 后角色仍需要 `SET ROLE` 显式激活，与 SQL Server / Oracle 的"自动生效"形成鲜明对比。

5. **`SET ROLE` 的语义在引擎间不统一**：PostgreSQL 一次只能激活一个角色（其余靠 INHERIT），MySQL/Oracle/ClickHouse 可以同时激活多个，Snowflake **强制只能有一个**当前活动角色。这直接影响应用层连接池设计——Snowflake 应用必须在 connection string 里固定 role，不能动态切换。

6. **Snowflake 的 "FUTURE GRANTS" 是独有创新**：把权限附加到"未来即将创建的对象"上。PostgreSQL 的 `ALTER DEFAULT PRIVILEGES` 只对**特定创建者**的新对象生效，Snowflake 则对任意创建者都生效——更接近"schema-level inheritance"的语义。

7. **列级权限的实现路径有四条**：(a) catalog 中按列存储 ACL（PostgreSQL/MySQL/SQL Server/DB2），(b) 视图 + 触发器（Oracle 经典做法），(c) MASKING POLICY（Snowflake/SAP HANA/Databricks），(d) Policy Tag 绑定 IAM（BigQuery）。其中 (c)/(d) 的优势在于**值依赖**——同一列对不同角色返回不同结果而非全有全无。

8. **DENY 是 SQL Server 独家特性**。所有其它引擎只有"GRANT 的并集"，没有"显式拒绝"。这让 SQL Server 在多角色叠加权限时具有更精细的控制能力，但也带来 `DENY > GRANT > REVOKE` 的优先级复杂性。

9. **REVOKE 的 CASCADE/RESTRICT 行为不一致**：SQL 标准要求显式指定，PostgreSQL/Vertica/DB2 严格遵循；SQL Server 默认 CASCADE；Snowflake、ClickHouse、MySQL 干脆不追踪权限依赖图，REVOKE 始终单点撤销。这使得跨引擎迁移授权脚本时容易出现"权限残留"。

10. **OWNERSHIP 在 Snowflake 是可 GRANT 的独占权限**，在其它引擎是"必须用 ALTER 改"的属性。这反映了 Snowflake 把所有权限都尝试统一到 GRANT/REVOKE 语法的设计哲学。

11. **系统权限的颗粒度差异极大**：Oracle 有 200+ 系统权限，DB2 有 7 大 authority，PostgreSQL 把它们拆解到对象级 GRANT + 角色属性，MySQL 8.0 把 `SUPER` 拆成 30+ 动态权限。倾向于"细粒度 + 角色组合"的引擎更符合最小权限原则；倾向于粗粒度 authority 的引擎在中小型部署下更易管理。

12. **角色层级的设计哲学分两派**：Snowflake 推崇严格树（自上而下层级、自下而上继承），PostgreSQL/Oracle 接受任意 DAG。前者审计可见性高、扩展受限；后者灵活、但审计需要递归遍历。两种哲学没有绝对优劣，取决于团队规模与合规要求。

13. **三层命名空间 (database → schema → object) 已成主流**，但 MySQL（Schema=Database 二层）、Oracle（User=Schema 二层）、Trino（Catalog → Schema → Object，Catalog 替代 Database）、Snowflake（Account → Database → Schema → Object，四层）保留了各自的特殊形态。这直接影响 GRANT 语法的层级数量——Snowflake 必须在三个 USAGE 之外再加一个对象 GRANT，共四步授权。

14. **角色密码是 Oracle/OceanBase 独有特性**：让"敏感角色"必须经过 `SET ROLE … IDENTIFIED BY` 才能激活，等价于一种"二次验证"。SQL Server 的 Application Role 也类似但作用于"应用启动"而非"操作前"。

15. **对纯 IAM 引擎 (BigQuery、Spanner、Athena)**，SQL 层的 GRANT/REVOKE 只是 IAM Policy Binding 的轻包装，不影响底层模型。这意味着用 SQL 脚本做权限迁移时，需要同时管理 IAM 策略与 SQL 授权，二者不能彼此覆盖。

## 参考资料

- ISO/IEC 9075-2:1999 §12 (Access control), §11 (Schema definition and manipulation)
- ISO/IEC 9075-2:2003 §12.3 (Privileges)
- ISO/IEC 9075-2:2008 §14.8 (TRUNCATE TABLE 语句)
- ISO/IEC 9075-2:2016 §13 (SQL/Foundation row level security)
- PostgreSQL: [Role Attributes](https://www.postgresql.org/docs/current/role-attributes.html), [GRANT](https://www.postgresql.org/docs/current/sql-grant.html), [ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/current/sql-alterdefaultprivileges.html)
- MySQL 8.0: [Roles](https://dev.mysql.com/doc/refman/8.0/en/roles.html), [Dynamic Privileges](https://dev.mysql.com/doc/refman/8.0/en/privileges-provided.html#dynamic-privileges)
- Oracle: [Database Security Guide — Configuring Privilege and Role Authorization](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/configuring-privilege-and-role-authorization.html)
- SQL Server: [CREATE ROLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-role-transact-sql), [Application Roles](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/application-roles)
- DB2: [Roles](https://www.ibm.com/docs/en/db2/11.5?topic=privileges-roles), [LBAC](https://www.ibm.com/docs/en/db2/11.5?topic=security-label-based-access-control-lbac)
- Snowflake: [Access Control Overview](https://docs.snowflake.com/en/user-guide/security-access-control-overview), [Future Grants](https://docs.snowflake.com/en/user-guide/security-access-control-considerations#future-grants)
- BigQuery: [GRANT statement](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-control-language#grant_statement), [Column-level access control](https://cloud.google.com/bigquery/docs/column-level-security-intro)
- Redshift: [CREATE ROLE](https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_ROLE.html)
- ClickHouse: [Access Control and Account Management](https://clickhouse.com/docs/en/operations/access-rights), [SETTINGS PROFILE](https://clickhouse.com/docs/en/sql-reference/statements/create/settings-profile)
- SAP HANA: [Authorization in SAP HANA](https://help.sap.com/docs/SAP_HANA_PLATFORM/b3ee5778bc2e4a089d3299b82ec762a7/c54550327a304bdb938b34f5cb6c5e3b.html)
- Trino: [SQL Access Control](https://trino.io/docs/current/security/built-in-system-access-control.html)
- Hive: [SQL Standard Based Authorization](https://cwiki.apache.org/confluence/display/Hive/SQL+Standard+Based+Hive+Authorization)
- Databricks Unity Catalog: [Privileges](https://docs.databricks.com/data-governance/unity-catalog/manage-privileges/privileges.html)
- 仓库内相关文档: `permission-security-model.md`, `permission-model-design.md`, `row-level-security.md`
