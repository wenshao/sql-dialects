# 审计日志 (Audit Logging)

谁在什么时候用什么 SQL 访问了哪些数据——这是合规审查、事故溯源和数据安全治理的根本问题。审计日志是 SQL 数据库面对监管 (HIPAA、SOX、GDPR、PCI-DSS) 的第一道也是最后一道防线，但它从未进入 SQL 标准，每个引擎都用截然不同的语法和架构来回答这个相同的问题。

## 为什么没有 SQL 标准

ISO/IEC 9075 系列标准 (SQL:1992 至 SQL:2023) 从未定义任何审计相关的语句、视图或语义。没有 `AUDIT` 关键字，没有 `INFORMATION_SCHEMA.AUDIT_LOG`，也没有标准化的"谁访问了什么"的查询接口。原因有三：

1. **审计本质上是带外功能 (out-of-band)**：审计日志是数据库引擎对自身行为的元观察，而不是 DML/DDL 操作的一部分。把它写进语言层并不自然。
2. **存储与传输高度厂商相关**：写入系统表、操作系统文件、syslog、SIEM、云日志服务……每个厂商的最佳路径都不同，标准化代价过高。
3. **合规需求多变**：HIPAA 关注 PHI 字段读取，SOX 关注金融表的修改，GDPR 关注个人数据的访问，PCI-DSS 关注卡号的明文出现位置——一个标准无法覆盖。

结果是：**审计是 SQL 世界中标准化程度最低的特性之一**。Oracle 1980 年代就有了 `AUDIT` 语句，PostgreSQL 直到今天 (2026) 内核仍未提供任何 SQL 级审计语句，必须依赖 `pgaudit` 扩展。本文系统对比 49 个 SQL 引擎在审计日志方面的能力差异。

## 合规法规与审计要求速览

| 法规 | 适用领域 | 核心审计要求 |
|------|---------|-------------|
| HIPAA (美) | 医疗 / 健康数据 PHI | 必须记录所有对受保护健康信息的访问 (含 SELECT) |
| SOX (美) | 上市公司财报 | 财务系统所有 DML/DDL/DCL 必须可追溯 6+ 年 |
| GDPR (欧) | 个人数据 | 数据主体有权了解谁、何时、为何访问其数据 |
| PCI-DSS | 信用卡 | 持卡人数据的所有访问必须记录 (Req 10) |
| 等保 2.0 (中) | 关基系统 | 三级以上系统须审计用户行为且日志保留至少 6 个月 |
| ISO 27001 | 通用信息安全 | A.12.4 控制族要求审计日志生成、保护与监控 |

这些法规在审计层面的共同点：**记录主体 (谁) + 客体 (访问了什么) + 时间 + 操作类型 + 操作结果 + 不可篡改**。下面的对比矩阵围绕这些维度展开。

## 支持矩阵

### 1. 基础审计能力总览

| 引擎 | SQL 级 AUDIT 语句 | 审计策略 (Policy) | 统一审计 (Unified) | 细粒度审计 (FGA) | 引入版本 |
|------|------------------|-------------------|-------------------|----------------|---------|
| Oracle | `AUDIT` / `NOAUDIT` | `CREATE AUDIT POLICY` | 是 (12c+) | DBMS_FGA | 6.0 / 12c (2013) |
| SQL Server | `CREATE SERVER AUDIT` | Server + Database 规范 | 是 (统一框架) | -- | 2008 |
| PostgreSQL | -- | pgaudit 扩展 | -- | pgaudit 对象审计 | pgaudit 1.0 (2016) |
| MySQL | `INSTALL PLUGIN audit_log` | Enterprise 过滤规则 | -- | -- | 5.5 Enterprise |
| MariaDB | `INSTALL SONAME 'server_audit'` | 规则 (变量) | -- | -- | 5.5+ |
| SQLite | -- | -- | -- | -- | 不支持 |
| DB2 | `AUDIT` 语句 | `CREATE AUDIT POLICY` | 是 (9.5+) | -- | 早期 / 9.5 (2007) |
| Snowflake | -- (视图查询) | -- | `ACCESS_HISTORY` 视图 | 行/列级 | 2020 preview / 2021 GA |
| BigQuery | -- (Cloud Logging) | IAM 审计配置 | Cloud Audit Logs | -- | GA |
| Redshift | -- (参数 + STL) | `enable_user_activity_logging` | -- | -- | 早期 |
| DuckDB | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- (系统表查询) | -- | `query_log` 默认开 | -- | 早期 |
| Trino | -- (event listener) | EventListener SPI | -- | -- | 早期 |
| Presto | -- (event listener) | EventListener SPI | -- | -- | 早期 |
| Spark SQL | -- (Listener API) | QueryExecutionListener | -- | -- | 2.0+ |
| Hive | -- (HiveServer2 hook) | Ranger 策略 | -- | Ranger | 早期 |
| Flink SQL | -- | -- | -- | -- | 不支持原生 |
| Databricks | -- (System Tables) | Unity Catalog 审计 | `system.access.audit` | 列级 | 2023 GA |
| Teradata | `BEGIN LOGGING` | DBQL 规则 | DBQL | -- | V2 / DBQL |
| Greenplum | -- | pgaudit 扩展 | -- | pgaudit 对象审计 | 继承 PG |
| CockroachDB | `ALTER TABLE ... EXPERIMENTAL_AUDIT` | -- | -- | -- | 2.0+ |
| TiDB | -- (Enterprise plugin) | Enterprise 过滤 | -- | -- | TiDB Enterprise |
| OceanBase | -- (Oracle 模式 AUDIT) | 是 (兼容 Oracle) | -- | -- | 4.0+ Oracle 兼容 |
| YugabyteDB | -- | pgaudit 扩展 | -- | pgaudit 对象审计 | 继承 PG |
| SingleStore | `CREATE AUDIT` | 是 | -- | -- | 7.5+ |
| Vertica | -- (内置 + Voltage) | -- | -- | -- | 早期 |
| Impala | -- (Lineage + Ranger) | Ranger 策略 | -- | Ranger | 早期 |
| StarRocks | -- (Audit Loader plugin) | FE 插件 | -- | -- | 1.x+ |
| Doris | -- (Audit Loader plugin) | FE 插件 | -- | -- | 早期 |
| MonetDB | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | 不支持 |
| TimescaleDB | -- | pgaudit 扩展 | -- | pgaudit 对象审计 | 继承 PG |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | -- (开关) | EXAOPERATION 配置 | -- | -- | 早期 |
| SAP HANA | `CREATE AUDIT POLICY` | 是 | 是 | 是 (条件) | 1.0+ |
| Informix | `onaudit` | 掩码 (Masks) | -- | -- | 早期 |
| Firebird | -- (trace API) | trace 配置文件 | -- | -- | 2.5+ |
| H2 | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- (CloudTrail) | IAM 审计 | CloudTrail Data Events | -- | GA |
| Azure Synapse | `CREATE SERVER AUDIT` | 是 (兼容 SQL Server) | 是 | -- | GA |
| Google Spanner | -- (Cloud Audit Logs) | IAM 审计 | Cloud Audit Logs | -- | GA |
| Materialize | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| Databend | -- (query_log 表) | -- | query_history | -- | GA |
| Yellowbrick | -- (sys.log_query) | -- | -- | -- | GA |
| Firebolt | -- (information_schema) | -- | engine history | -- | GA |

> 统计：约 17 个引擎提供 SQL 级审计语法 (AUDIT/CREATE AUDIT POLICY)，约 12 个引擎依赖系统表/视图查询，约 8 个引擎需要扩展或外部插件 (pgaudit、Ranger、Audit Loader)，约 12 个引擎完全没有内置审计能力。

### 2. 审计粒度：DML / DDL / DCL / SELECT

| 引擎 | DML | DDL | DCL (GRANT) | SELECT 读审计 | 登录/登出 | Schema 级 | User 级 |
|------|-----|-----|-------------|--------------|---------|---------|---------|
| Oracle | 是 | 是 | 是 | 是 (FGA / Unified) | 是 | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 是 (`SELECT` action) | 是 | 是 | 是 |
| PostgreSQL (pgaudit) | 是 | 是 | 是 (ROLE 类) | 是 (`READ` 类) | 服务器日志 | 通过角色 | 是 |
| MySQL Enterprise | 是 | 是 | 是 | 是 | 是 | 是 (过滤) | 是 |
| MariaDB plugin | 是 | 是 | 是 | 是 | 是 | 是 (规则) | 是 |
| DB2 | 是 | 是 | 是 | 是 (`EXECUTE` 类) | 是 | 是 | 是 |
| Snowflake | 是 (`QUERY_HISTORY`) | 是 | 是 | 是 (`ACCESS_HISTORY`) | `LOGIN_HISTORY` | 是 | 是 |
| BigQuery | 是 | 是 | 是 | 是 (Data Access) | -- | 是 | 是 |
| Redshift | 是 | 是 | 是 | 是 (`STL_QUERY`) | `STL_CONNECTION_LOG` | -- | 是 |
| ClickHouse | 是 | 是 | 是 | 是 | `session_log` | -- | 是 |
| Teradata DBQL | 是 | 是 | 是 | 是 | 是 (`LogonOff`) | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 是 | -- | 是 |
| CockroachDB | 是 | 是 | 是 | 是 (按表配置) | 是 | -- | 是 |
| Databricks | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 是 | 是 (Oracle 模式) | 是 | 是 | 是 |

### 3. 审计追踪存储后端

| 引擎 | 系统表 | OS 文件 | syslog | 云日志 | SIEM 集成 | XML | JSON |
|------|--------|--------|--------|-------|----------|-----|------|
| Oracle | `UNIFIED_AUDIT_TRAIL` | 是 (`AUDIT_FILE_DEST`) | 是 | OCI Logging | 是 | 是 | 是 (21c+) |
| SQL Server | -- | `.sqlaudit` 文件 | 是 (Linux) | Azure Monitor | 是 | -- | -- |
| PostgreSQL pgaudit | -- | 服务器日志 | 是 | -- | 经日志转发 | -- | -- |
| MySQL Enterprise | -- | 文件 | 是 | -- | 是 | 是 | 是 |
| MariaDB | -- | 文件 | 是 | -- | 是 | -- | -- |
| DB2 | 表 (`AUDIT EXTRACT`) | 二进制日志 | 是 | -- | 是 | -- | -- |
| Snowflake | `ACCOUNT_USAGE` 视图 | -- | -- | -- | 经导出 | -- | 是 |
| BigQuery | `INFORMATION_SCHEMA.JOBS` | -- | -- | Cloud Logging | 是 | -- | 是 |
| Redshift | `STL_*` / `SVL_*` | S3 (审计日志) | -- | CloudWatch | 经导出 | -- | 是 |
| ClickHouse | `system.query_log` | -- | -- | -- | 经导出 | -- | -- |
| Teradata | `DBC.DBQLogTbl` | -- | -- | -- | 是 | -- | -- |
| SAP HANA | `M_AUDIT_LOG` | 是 | 是 | -- | 是 | -- | -- |
| SingleStore | -- | 文件 | -- | -- | 是 | -- | 是 |
| Databricks | `system.access.audit` | -- | -- | -- | 经 Delta Sharing | -- | 是 |
| Cloud (Spanner/Athena) | -- | -- | -- | Cloud Audit Logs | 是 | -- | 是 |

### 4. 高级特性：FGA、查询文本、参数捕获、掩码

| 引擎 | 条件审计 (FGA) | 查询文本捕获 | 绑定参数捕获 | 敏感数据掩码 | 不可篡改 (Tamper-proof) |
|------|---------------|-------------|-------------|-------------|----------------------|
| Oracle | DBMS_FGA + Unified Policy `WHEN` | 是 | 是 | DDM / Vault | Audit Vault |
| SQL Server | `WHERE` 谓词 (2012+) | 是 | 部分 | DDM | 是 (CC 认证) |
| PostgreSQL pgaudit | -- | 是 | 是 (`pgaudit.log_parameter`) | 无原生 | 依赖 OS |
| MySQL Enterprise | 过滤规则 | 是 | 是 | -- | -- |
| MariaDB | 规则 (loggable) | 是 | 是 | -- | -- |
| DB2 | -- | 是 | 是 | -- | -- |
| Snowflake | 行/列访问策略联动 | 是 | 是 | Dynamic Masking | -- |
| BigQuery | -- | 是 | 是 | Policy Tags | Bucket Lock |
| Teradata | DBQL 规则条件 | 是 | 是 | -- | -- |
| SAP HANA | `WHEN` 子句 | 是 | 是 | DDM | -- |
| Databricks | 列级 | 是 | 是 | Unity Catalog Mask | Delta Lake 时间旅行 |
| OceanBase | DBMS_FGA (Oracle 模式) | 是 | 是 | -- | -- |

> "不可篡改" 指的是审计日志的写入是否能保证 DBA 也无法修改，这通常需要写入只读介质、远程聚合或专门的 Audit Vault 设备。

## 详细语法对比

### Oracle：从传统 AUDIT 到 Unified Auditing

Oracle 是 SQL 审计的开创者。从 Oracle 6.0 开始就有 `AUDIT` 语句。Oracle 12c (2013) 引入 **Unified Auditing**，把分散在 `AUD$`、`FGA_LOG$`、`DV$`、`OLS$` 等 6 个表的审计数据统一到 `UNIFIED_AUDIT_TRAIL` 视图。

**传统 AUDIT (11g 及之前)**：

```sql
-- 语句审计
AUDIT SELECT, INSERT, UPDATE, DELETE ON hr.employees BY ACCESS;

-- 权限审计
AUDIT CREATE TABLE BY scott BY SESSION;

-- 对象审计
AUDIT ALL ON hr.salaries WHENEVER SUCCESSFUL;

-- 关闭审计
NOAUDIT SELECT ON hr.employees;

-- 查询
SELECT username, action_name, obj_name, timestamp
  FROM dba_audit_trail
 WHERE owner = 'HR';
```

**统一审计 (12c+)**：

```sql
-- 创建审计策略
CREATE AUDIT POLICY hr_sensitive_policy
    ACTIONS SELECT, UPDATE, DELETE ON hr.salaries
    WHEN 'SYS_CONTEXT(''USERENV'', ''CLIENT_PROGRAM_NAME'') != ''sqlplus'''
    EVALUATE PER SESSION;

-- 启用策略
AUDIT POLICY hr_sensitive_policy;
AUDIT POLICY hr_sensitive_policy BY scott;
AUDIT POLICY hr_sensitive_policy EXCEPT sysadm;

-- 查询统一审计视图
SELECT dbusername, event_timestamp, action_name, object_name, sql_text
  FROM unified_audit_trail
 WHERE unified_audit_policies = 'HR_SENSITIVE_POLICY'
 ORDER BY event_timestamp DESC;
```

**细粒度审计 (FGA, since 9i)**：

```sql
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'audit_high_salary',
    audit_condition => 'SALARY > 100000',
    audit_column    => 'SALARY,COMMISSION_PCT',
    statement_types => 'SELECT,UPDATE',
    handler_schema  => 'SEC',
    handler_module  => 'NOTIFY_SECURITY_OFFICER'
  );
END;
/
```

FGA 的核心价值：**只在条件成立时记录**，避免审计泛洪。例如只审计访问年薪 10 万以上员工记录的 SELECT。

### SQL Server：Server Audit + Database Audit Specification

SQL Server 2008 引入 **SQL Server Audit**，是 Microsoft 第一个能满足 Common Criteria EAL4+ 认证的审计框架。架构分两层：

1. **Server Audit**：定义日志的目的地 (文件 / Windows Application 日志 / Windows Security 日志)
2. **Audit Specification**：分服务器级和数据库级，定义记录哪些事件

```sql
-- 1) 创建 Server Audit (写入文件)
CREATE SERVER AUDIT FinanceAudit
TO FILE (
    FILEPATH = 'D:\AuditLogs\',
    MAXSIZE  = 1 GB,
    MAX_ROLLOVER_FILES = 10,
    RESERVE_DISK_SPACE = OFF
)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = SHUTDOWN);

ALTER SERVER AUDIT FinanceAudit WITH (STATE = ON);

-- 2) 服务器级规范 (登录、CREATE LOGIN 等)
CREATE SERVER AUDIT SPECIFICATION FinanceServerSpec
FOR SERVER AUDIT FinanceAudit
ADD (FAILED_LOGIN_GROUP),
ADD (SUCCESSFUL_LOGIN_GROUP),
ADD (DATABASE_PRINCIPAL_CHANGE_GROUP)
WITH (STATE = ON);

-- 3) 数据库级规范 (针对具体表)
USE Finance;
CREATE DATABASE AUDIT SPECIFICATION FinanceDbSpec
FOR SERVER AUDIT FinanceAudit
ADD (SELECT, UPDATE, DELETE ON dbo.Salaries BY public),
ADD (EXECUTE ON SCHEMA::dbo BY [Auditor])
WITH (STATE = ON);

-- 4) 带谓词的过滤 (2012+)
CREATE SERVER AUDIT FilteredAudit
TO FILE (FILEPATH = 'D:\AuditLogs\')
WHERE database_name = N'Finance' AND server_principal_name <> N'sa';

-- 查询审计文件
SELECT event_time, action_id, succeeded, server_principal_name,
       database_name, object_name, statement
  FROM sys.fn_get_audit_file('D:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT);
```

SQL Server 2012 起 Server Audit 的 `WHERE` 谓词使审计可以根据条件过滤，避免记录无关事件。Azure SQL Database 把审计输出到 Azure Storage / Log Analytics / Event Hubs。

### PostgreSQL：pgaudit 扩展

PostgreSQL 内核**至今没有**任何 SQL 级审计语句。社区共识是审计应作为扩展实现，pgaudit (由 Crunchy Data 维护) 已是事实标准，被 AWS RDS、Google Cloud SQL、Azure Database 等托管服务全面支持。

```sql
-- 安装 (作为共享库)
-- shared_preload_libraries = 'pgaudit'

CREATE EXTENSION pgaudit;

-- 会话级审计 (粗粒度)
SET pgaudit.log = 'read, write, ddl, role';
SET pgaudit.log_catalog = off;
SET pgaudit.log_parameter = on;
SET pgaudit.log_statement_once = on;

-- 对象级审计 (基于角色的细粒度)
CREATE ROLE auditor;
GRANT SELECT ON sensitive.salaries TO auditor;
ALTER SYSTEM SET pgaudit.role = 'auditor';
SELECT pg_reload_conf();
-- 之后所有对 auditor 有权限的对象的访问都会被记录

-- 输出 (写入 PostgreSQL 服务器日志)
-- AUDIT: SESSION,1,1,READ,SELECT,,, "SELECT * FROM salaries WHERE id = $1", "1001"
```

`pgaudit.log` 支持的类别：`READ`、`WRITE`、`FUNCTION`、`ROLE`、`DDL`、`MISC`、`MISC_SET`、`ALL`。所有审计记录通过 `ereport(LOG, ...)` 写入 PostgreSQL 主日志，配合 `log_destination = syslog,csvlog` 可路由到外部系统。

`log_statement = 'all'` 是 PostgreSQL 内核层面唯一的"准审计"设施，但它没有结构化字段，也无法过滤对象级权限。

### MySQL / MariaDB：插件之争

MySQL **企业版**自 5.5 起提供 `audit_log` 插件，**社区版从未**包含审计能力。MariaDB 5.5 起提供了**开源**的 `server_audit` 插件，是社区版用户的首选。

**MySQL Enterprise**：

```sql
-- 加载插件
INSTALL PLUGIN audit_log SONAME 'audit_log.so';

-- 配置 (my.cnf)
-- audit_log_format = JSON
-- audit_log_policy = ALL
-- audit_log_file = /var/log/mysql/audit.log

-- 过滤 API (5.7.20+)
SELECT audit_log_filter_set_filter('log_dml', '{ "filter": {
   "class": [ { "name": "table_access",
                "event": [ { "name": "insert" },
                           { "name": "update" },
                           { "name": "delete" } ] } ] } }');

SELECT audit_log_filter_set_user('app@%', 'log_dml');
```

**MariaDB**：

```sql
INSTALL SONAME 'server_audit';

SET GLOBAL server_audit_logging = ON;
SET GLOBAL server_audit_events = 'CONNECT,QUERY_DDL,QUERY_DML,QUERY_DCL';
SET GLOBAL server_audit_file_path = '/var/log/mysql/audit.log';
SET GLOBAL server_audit_excl_users = 'monitoring';
SET GLOBAL server_audit_query_log_limit = 1024;
```

输出 (CSV 格式)：

```
20260413 12:00:01,db1,scott,localhost,42,1234,QUERY,finance,'SELECT * FROM salaries',0
```

MariaDB 的插件输出格式简单 (CSV)，易于被 Splunk / ELK 解析；MySQL Enterprise 的 JSON 格式更结构化但闭源。

### DB2：AUDIT POLICY

DB2 9.5 (2007) 引入了基于策略的审计，取代了之前的 `db2audit` 命令行配置。

```sql
-- 创建审计策略
CREATE AUDIT POLICY finance_policy
  CATEGORIES EXECUTE WITH DATA STATUS BOTH,
             OBJMAINT STATUS BOTH,
             SECMAINT STATUS BOTH
  ERROR TYPE NORMAL;

-- 应用到对象 / 数据库 / 用户
AUDIT TABLE finance.salaries USING POLICY finance_policy;
AUDIT USER scott USING POLICY finance_policy;
AUDIT DATABASE USING POLICY finance_policy;

-- 提取审计日志 (db2audit 工具)
-- db2audit extract file finance.del from files
-- 然后导入表
LOAD FROM finance.del OF DEL INSERT INTO sysibmadm.audit_finance;
```

DB2 的审计写入二进制文件，必须用 `db2audit extract` 转换为可查询格式。DB2 还支持把审计目录设为多个节点共享 (NFS) 以集中管理。

### Snowflake：ACCESS_HISTORY 与 LOGIN_HISTORY

Snowflake 没有 `AUDIT` 语句。所有审计能力通过 `SNOWFLAKE.ACCOUNT_USAGE` schema 中的视图暴露：

```sql
-- 查询历史 (所有用户最近 365 天)
SELECT query_id, user_name, role_name, warehouse_name,
       query_text, start_time, total_elapsed_time, error_code
  FROM snowflake.account_usage.query_history
 WHERE database_name = 'FINANCE'
   AND start_time > DATEADD('day', -7, CURRENT_TIMESTAMP());

-- 登录历史
SELECT user_name, client_ip, reported_client_type,
       first_authentication_factor, second_authentication_factor,
       is_success, error_message, event_timestamp
  FROM snowflake.account_usage.login_history
 WHERE event_timestamp > DATEADD('day', -1, CURRENT_TIMESTAMP())
   AND is_success = 'NO';

-- ACCESS_HISTORY (列级访问追踪，2021 GA)
SELECT query_id, user_name,
       direct_objects_accessed, base_objects_accessed,
       objects_modified
  FROM snowflake.account_usage.access_history
 WHERE query_start_time > DATEADD('hour', -1, CURRENT_TIMESTAMP())
   AND ARRAY_SIZE(base_objects_accessed) > 0;
```

`ACCESS_HISTORY` 是 Snowflake 审计的旗舰特性：它不仅记录 SQL 文本，还**解析**出每个查询实际访问了哪些列 (区分 `direct` 和 `base` 是因为视图会展开为底层表)。这对 GDPR "数据主体访问报告" 至关重要——你可以精确回答"哪些查询读取了 customers.email 列"。

延迟约 45 分钟到 3 小时；保留 365 天 (Enterprise+)。

### BigQuery：Cloud Audit Logs 自动化

BigQuery 不需要任何配置：所有 API 调用都自动写入 GCP **Cloud Audit Logs**，分三类：

- **Admin Activity**：DDL、IAM 变更 (永久免费保留 400 天)
- **Data Access**：读、写 (默认对 BigQuery 数据访问开启)
- **System Event**：GCP 内部事件

```sql
-- 通过 Information Schema 查询作业历史
SELECT job_id, user_email, query, statement_type,
       creation_time, total_bytes_processed, error_result
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
 WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
   AND statement_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE');

-- 列级访问 (Resource Manager + Policy Tag)
-- 需结合 Cloud Audit Logs:
-- protoPayload.metadata.tableDataRead.fields = ["customer_id","email"]
```

BigQuery 把审计完全外置到 GCP 的日志基础设施。优势是天然不可篡改 (Bucket Lock)、与 Cloud Logging 链路天然集成、Sink 到 BigQuery 自身可形成"审计审计"; 劣势是日志成本独立于 BigQuery 计费。

### ClickHouse：query_log 默认开启

ClickHouse 是少数**默认开启**查询日志的 OLAP 引擎。`system.query_log` 是一个 MergeTree 表，每个查询写两条 (开始 + 结束)。

```sql
-- 配置 (config.xml)
-- <query_log><database>system</database><table>query_log</table>
--   <flush_interval_milliseconds>7500</flush_interval_milliseconds></query_log>

-- 查询日志
SELECT event_time, user, query_kind, query, exception,
       read_rows, read_bytes, query_duration_ms,
       client_hostname, http_user_agent
  FROM system.query_log
 WHERE event_date = today()
   AND type = 'QueryFinish'
   AND user != 'monitoring'
 ORDER BY event_time DESC
 LIMIT 100;

-- 会话日志 (登录登出，需要在 config 中开启)
SELECT event_time, type, user, auth_type, client_address
  FROM system.session_log
 WHERE event_date = today()
   AND type IN ('LoginSuccess', 'LoginFailure');

-- 部件日志 / 文本日志 / 跟踪日志 / 异步插入日志……
```

ClickHouse 的优势是**查询审计本身就是 SQL 表**，可用任何 ClickHouse 函数分析。劣势是这些表受 TTL 管理 (默认 30 天)，且 DBA 可以 `TRUNCATE` 它们——不可篡改性需要外部手段。

### Teradata：DBQL (Database Query Log)

Teradata 的 **DBQL** 是商业数据库中粒度最高的审计系统。管理员可以为每个用户/账户配置不同的日志级别。

```sql
-- 启用日志 (粗粒度)
BEGIN LOGGING ON ALL FOR scott;

-- 完整 DBQL 配置
BEGIN QUERY LOGGING WITH SQL, OBJECTS, STEPINFO, EXPLAIN
  LIMIT SQLTEXT=10000
  ON scott;

-- 关闭
END QUERY LOGGING ON scott;

-- 查询 DBQL
SELECT UserName, StartTime, NumResultRows, AmpCPUTime,
       QueryText, ErrorCode
  FROM DBC.DBQLogTbl
 WHERE LogDate = CURRENT_DATE
   AND ErrorCode <> 0
 ORDER BY StartTime DESC;

-- 对象级审计 (DBQLObjTbl)
SELECT o.ObjectDatabaseName, o.ObjectTableName, o.ObjectColumnName,
       l.UserName, l.StartTime
  FROM DBC.DBQLObjTbl o
  JOIN DBC.DBQLogTbl l ON o.QueryID = l.QueryID
 WHERE o.ObjectDatabaseName = 'FINANCE'
   AND l.LogDate = CURRENT_DATE;
```

DBQL 把每个查询的**步骤**、**对象**、**SQL 文本**、**EXPLAIN**、**XML 计划** 分别写到不同的表，是已知 SQL 引擎中审计字段最细的。

### SAP HANA：CREATE AUDIT POLICY

SAP HANA 的审计语法借鉴了 Oracle，是少数原生支持 SQL 级 AUDIT POLICY 创建的开源以外引擎。

```sql
-- 创建审计策略
CREATE AUDIT POLICY salary_policy
  AUDITING SUCCESSFUL SELECT, UPDATE
  ON finance.salaries
  LEVEL CRITICAL;

-- 启用
ALTER AUDIT POLICY salary_policy ENABLE;

-- 全局开关
ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM')
  SET ('auditing configuration', 'global_auditing_state') = 'true' WITH RECONFIGURE;

-- 查询
SELECT user_name, statement_string, timestamp, audit_action_name
  FROM sys.audit_log
 WHERE policy_name = 'SALARY_POLICY'
   AND timestamp > ADD_DAYS(CURRENT_TIMESTAMP, -1);
```

SAP HANA 的 `LEVEL` 取值有 `EMERGENCY` / `ALERT` / `CRITICAL` / `WARNING` / `INFO`，方便和 syslog 严重等级映射。

### Redshift：STL 系统表与 enable_audit_logging

Redshift 没有 SQL 级审计语句。审计依赖两个机制：

1. **STL 系统表**：每个 leader 节点保留约 7 天的查询历史
2. **集群审计日志**：通过 `enable_audit_logging` 参数把连接和用户活动日志导出到 S3

```sql
-- 查询最近活动
SELECT q.starttime, q.endtime, u.usename, q.querytxt, q.aborted
  FROM stl_query q
  JOIN pg_user u ON q.userid = u.usesysid
 WHERE q.starttime > GETDATE() - INTERVAL '1 hour'
 ORDER BY q.starttime DESC;

-- 连接日志
SELECT event, recordtime, username, dbname, remotehost, authmethod
  FROM stl_connection_log
 WHERE recordtime > GETDATE() - INTERVAL '1 day'
   AND event = 'authentication failure';

-- DDL 历史
SELECT * FROM stl_ddltext WHERE starttime > GETDATE() - 1;
```

Redshift Serverless 通过 `sys_query_history` 视图取代了 STL，并把日志统一写入 CloudWatch / S3。

### Databricks：Unity Catalog System Tables

Databricks 在 2023 年随 Unity Catalog GA 推出了 `system.access` schema：

```sql
-- 表访问审计
SELECT event_time, user_identity.email, action_name,
       request_params, response.status_code,
       request_params.full_name_arg AS table_accessed
  FROM system.access.audit
 WHERE service_name = 'unityCatalog'
   AND action_name IN ('getTable', 'createTable', 'updateTable')
   AND event_date = current_date();

-- 列级访问 (Lineage)
SELECT source_table_full_name, source_column_name,
       entity_run_id, event_time
  FROM system.access.column_lineage
 WHERE event_date >= current_date() - INTERVAL 7 DAYS;
```

Unity Catalog 的审计粒度可达**列级访问血缘**，且 Delta Lake 的时间旅行使审计表本身具有不可篡改属性 (旧版本不会被新版本覆盖)。

### CockroachDB：EXPERIMENTAL_AUDIT

CockroachDB 是少数支持 SQL 级 `ALTER TABLE ... EXPERIMENTAL_AUDIT` 的分布式数据库。审计在表级别开启，所有访问该表的语句被写到结构化日志通道。

```sql
-- 启用某张表的读写审计
ALTER TABLE finance.salaries EXPERIMENTAL_AUDIT SET READ WRITE;

-- 关闭
ALTER TABLE finance.salaries EXPERIMENTAL_AUDIT SET OFF;

-- 集群设置开启 SQL 执行通道
SET CLUSTER SETTING server.auth_log.sql_sessions.enabled = true;
SET CLUSTER SETTING sql.log.slow_query.latency_threshold = '500ms';
```

输出的审计行写到 `cockroach-sql-audit.log` 文件，每行 JSON 格式，包含 `user`、`stmt`、`tag`、`affected_rows`、`duration` 等字段。CockroachDB 设计上把"敏感表清单 + 写入审计通道 + 路由到 SIEM"作为合规标准链路。

### OceanBase：双模式审计

OceanBase 4.x 在 Oracle 兼容模式下完全支持 Oracle 风格的 `AUDIT` / `NOAUDIT` / `CREATE AUDIT POLICY` 语法；在 MySQL 模式下则提供基于 `audit_log` 插件的兼容方案。

```sql
-- Oracle 模式
AUDIT SELECT, INSERT, UPDATE, DELETE
  ON finance.salaries
  BY ACCESS WHENEVER SUCCESSFUL;

-- 查询审计视图 (Oracle 兼容)
SELECT username, action_name, obj_name, returncode, timestamp
  FROM dba_audit_trail
 WHERE owner = 'FINANCE'
 ORDER BY timestamp DESC;

-- MySQL 模式
SET GLOBAL audit_log_enable = ON;
SET GLOBAL audit_log_format = JSON;
```

OceanBase 的双模式策略反映了其同时承接 Oracle 迁移和 MySQL 兼容场景的设计目标。

### SingleStore：CREATE AUDIT

SingleStore (前 MemSQL) 7.5+ 引入了简洁的 SQL 级审计语法。

```sql
CREATE AUDIT 'finance_audit'
  WITH FORMAT = JSON, OUTPUT = FILE, FILE_PATH = '/var/lib/audit/finance';

-- 选择记录的事件
ALTER AUDIT 'finance_audit' EVENTS = 'CONNECT,DISCONNECT,QUERY,DDL,DCL';

-- 启用
ALTER AUDIT 'finance_audit' ENABLE;
```

SingleStore 的审计直接写文件，不占用 leaf 节点的存储引擎缓存，对 OLTP 路径影响极小。

### Trino / Presto：EventListener SPI

Trino 和 Presto 都不在 SQL 层提供审计，而是通过 Java SPI (`io.trino.spi.eventlistener.EventListener`) 让用户实现自定义监听器。事件包括：

- `QueryCreatedEvent`：查询提交时触发
- `QueryCompletedEvent`：查询完成时触发，包含完整 SQL、用户、catalog、列引用
- `SplitCompletedEvent`：每个 split 完成时触发 (详细但量大)

```java
public class AuditListener implements EventListener {
  @Override public void queryCompleted(QueryCompletedEvent e) {
    AuditRecord r = new AuditRecord();
    r.user = e.getContext().getUser();
    r.sql  = e.getMetadata().getQuery();
    r.tables = e.getMetadata().getTables();      // 表级血缘
    r.columns = e.getMetadata().getColumns();    // 列级血缘
    siem.send(r);
  }
}
```

打包为 plugin 并注册到 `etc/event-listener.properties`。这种 hook 模型让 Trino/Presto 可以直接对接任何 SIEM (Splunk HEC、Datadog、ELK)，但要求自行编码。AWS Athena 内部正是基于 Trino EventListener，把事件统一路由到 CloudTrail。

### StarRocks / Doris：Audit Loader Plugin

StarRocks 和 Apache Doris 共享同一个开源的 `audit_loader` FE 插件。它读取 FE 自己的 audit.log 文件，把每条审计记录回写到一张内部 OLAP 表，从而支持用 SQL 自查询。

```sql
-- audit_loader 插件创建的表 (典型结构)
CREATE TABLE audit_table (
    query_id   VARCHAR(48),
    `time`     DATETIME,
    client_ip  VARCHAR(32),
    `user`     VARCHAR(64),
    db         VARCHAR(96),
    state      VARCHAR(8),
    query_time BIGINT,
    scan_bytes BIGINT,
    return_rows BIGINT,
    stmt_id    INT,
    is_query   TINYINT,
    stmt       VARCHAR(2048)
)
DUPLICATE KEY(query_id)
DISTRIBUTED BY HASH(query_id) BUCKETS 3;

-- 之后可以直接 SQL 分析
SELECT user, COUNT(*) AS cnt, AVG(query_time) AS avg_ms
  FROM audit_table
 WHERE `time` > NOW() - INTERVAL 1 DAY
 GROUP BY user
 ORDER BY cnt DESC;
```

这是一种把审计转回数据库自身能力的优雅闭环，但缺点是 audit_loader 本身的写入也会被审计 (递归性问题)，需要白名单排除。

### Apache Hive / Impala：Apache Ranger 路径

Hive 和 Impala 的"原生"审计能力都不充分。事实标准是 **Apache Ranger** (前身 Apache Argus)：在 HiveServer2 / Impala coordinator 上挂 Ranger Plugin，所有授权决策通过 Ranger，所有授权决策本身被记录到 Ranger Audit (HDFS 或 Solr)。

```
HiveServer2 ──┬── Ranger Hive Plugin ──┐
              │                         ├── Ranger Audit Sink ──→ HDFS / Solr / Kafka
Impala     ───┴── Ranger Impala Plugin ─┘
```

Ranger 的审计粒度是**授权级**：能记录"用户 A 试图 SELECT finance.salaries 是否被允许"，但不一定能记录每个 SELECT 实际读了哪些行。对于绕过 HiveServer2 直接读 HDFS / S3 文件的访问，Ranger 无法看到——这是 Hadoop 生态审计的著名盲区，必须在存储层 (HDFS 自身审计、S3 Bucket Logging) 同时开启。

### Vertica：内置 + Voltage SecureData

Vertica 的审计结合三层：

1. **dc_requests_issued** 等数据收集器表 (DC) 记录所有请求
2. `AUDIT()` SQL 函数用于估算许可使用 (合规计费而非安全)
3. 可集成 Voltage SecureData 实现字段级 tokenization

```sql
-- 查询请求历史
SELECT request_id, user_name, request, success
  FROM dc_requests_issued
 WHERE time > NOW() - INTERVAL '1 hour'
   AND request ILIKE '%FROM finance.salaries%';

-- 登录历史
SELECT * FROM dc_session_starts WHERE session_start_time > NOW() - INTERVAL '1 day';
```

Vertica DC 表受 retention policy (默认 30 天) 控制，可通过 `ALTER RESOURCE POOL dctable SET retain_in_days = 365` 延长。

### Exasol：审计开关与 EXA_DBA_AUDIT_SQL

Exasol 的审计是全局开关，启用后所有 SQL 被写入 `EXA_DBA_AUDIT_SQL` 系统视图。

```sql
-- 启用 (需要 SYS 权限)
ALTER SYSTEM SET sql_audit = 'ON';

SELECT user_name, sql_text, start_time, duration, success
  FROM exa_dba_audit_sql
 WHERE start_time > NOW() - INTERVAL '1' DAY
   AND user_name <> 'SYS'
 ORDER BY start_time DESC;
```

Exasol 的审计粒度无法细到对象或语句类别，只能"全开"或"全关"，是较粗放的设计。

### Firebird：Trace API

Firebird 2.5+ 提供了独立的 Trace API，通过配置文件 `fbtrace.conf` 启用：

```ini
<database financedb>
  enabled true
  log_statement_finish true
  log_statement_start  false
  log_initfini false
  print_perf  true
  time_threshold 0
</database>
```

Trace 输出文件可被 `fbtracemgr` 工具读取，或通过 `RDB$ADMIN` 角色由 SQL 触发。Firebird 没有 SQL 级 AUDIT 语句。

### Informix：onaudit 与 Audit Masks

Informix 使用 `onaudit` 命令行工具 + **审计掩码 (masks)**：每个用户绑定一个掩码，掩码定义哪些事件被记录。

```bash
# 创建系统级掩码
onaudit -a -u _require -e +RDRW,+UPRW,+CRTB

# 把掩码绑定到用户
onaudit -a -u scott -e +RDRW

# 把审计输出路由到 syslog
onaudit -p /var/audit -s 1024
```

Informix 是 SQL 数据库中较早把审计完全做成"OS 工具 + 用户掩码"模型的代表，便于 Unix 系统管理员集成。

### Amazon Athena / Spanner：CloudTrail Data Events

Athena 和 Spanner 都没有 SQL 层审计接口，全部依赖云平台日志：

- **Athena**：CloudTrail 自动记录所有 `StartQueryExecution` API 调用 (含完整 SQL)。开启 **CloudTrail Data Events** 后，连查询触发的 S3 GetObject 也被记录，覆盖了"读底层文件" 这个传统 Hadoop 盲区。
- **Spanner**：Cloud Audit Logs 自动开启 Admin Activity，Data Access 需手动开启；`session_id` / `transaction_id` 让审计可与查询追踪对应。

```sql
-- Athena 查询自身执行历史 (通过 INFORMATION_SCHEMA 不可见，但 boto3 / CLI 可拉)
-- aws athena list-query-executions --work-group primary
-- aws athena get-query-execution --query-execution-id <id>
```

### Databend：query_history 表

Databend 把审计统一在 `system.query_history` 系统表中。

```sql
SELECT query_id, sql_user, query_kind, query_text,
       query_start_time, query_duration_ms, exception_text
  FROM system.query_history
 WHERE event_date = today()
   AND query_kind = 'SELECT'
 ORDER BY query_start_time DESC
 LIMIT 100;
```

Databend 模仿 Snowflake 的 `query_history` 视图，路径上是 ClickHouse `query_log` 与 Snowflake `account_usage` 的折中。

## SIEM 集成模式

无论引擎本身的审计能力如何强，企业级合规几乎都要求把审计日志最终汇总到独立的 SIEM (Security Information and Event Management)。常见集成路径：

| 引擎 | 推荐路径 | SIEM 后端示例 |
|------|---------|--------------|
| Oracle | Audit Vault → SIEM Connector | Splunk / QRadar |
| SQL Server | Windows Event Log → Log Forwarder | Splunk / Sentinel |
| PostgreSQL pgaudit | csvlog → Filebeat → Logstash | ELK / Splunk |
| MariaDB | server_audit → Filebeat | ELK |
| Snowflake | Storage Integration → S3 → Splunk Cloud | Splunk |
| BigQuery | Cloud Logging → Pub/Sub Sink → SIEM | Chronicle / Splunk |
| Redshift | enable_audit_logging → S3 → SIEM | Splunk / Sumo Logic |
| Databricks | system.access → Delta Sharing → SIEM | Splunk |
| ClickHouse | Materialized View → Kafka → SIEM | ELK |
| Hive/Impala | Ranger Audit → Solr / Kafka | Splunk / ELK |

关键设计原则：
1. **本地缓冲 + 异步推送**：避免 SIEM 短暂故障导致数据库阻塞
2. **格式归一化**：SIEM 端把不同引擎的日志映射到统一字段 (CIM、ECS schema)
3. **完整性校验**：每批日志的序号 + 哈希，便于发现丢失
4. **关联用户身份**：把数据库内部用户名映射到企业 SSO 身份 (LDAP / OIDC)
5. **保留分层**：SIEM 热数据 90 天，冷归档到对象存储 7 年

## 查询历史与日志保留对比

| 引擎 | 默认保留 | 最大保留 | 存储位置 | 计入存储费 |
|------|---------|---------|---------|----------|
| Oracle Unified | 不限 (用户决定 PURGE) | 无限 | `AUDSYS.AUD$UNIFIED` | 是 |
| SQL Server | 文件大小 + rollover | 无限 (取决磁盘) | `.sqlaudit` | 是 |
| PostgreSQL pgaudit | 由 `log_rotation_*` 控制 | 取决 OS | 服务器日志 | 否 (操作系统) |
| MySQL Enterprise | 按文件 rotation | 取决磁盘 | 文件 | 否 |
| MariaDB | 按 `server_audit_file_rotate_size` | 取决磁盘 | 文件 | 否 |
| DB2 | 取决 db2audit 配置 | 无限 | 二进制文件 | 是 |
| Snowflake QUERY_HISTORY | 365 天 | 365 天 (Enterprise) | 内部 | 否 |
| Snowflake ACCESS_HISTORY | 365 天 | 365 天 (Enterprise) | 内部 | 否 |
| BigQuery Admin Activity | 400 天 | 400 天 (永久免费) | Cloud Logging | 仅超出额度 |
| BigQuery Data Access | 30 天 | 取决 Logging Sink | Cloud Logging | 是 (按读) |
| Redshift STL | 2-5 天 (循环) | 7 天 (硬性) | leader 节点 | 否 |
| Redshift Audit Logs | 永久 | 取决 S3 | S3 | 是 (S3) |
| ClickHouse query_log | 默认 30 天 (TTL) | 由 TTL 决定 | MergeTree 系统表 | 是 |
| Teradata DBQL | 取决 Archive 策略 | 无限 | DBC 表 | 是 |
| SAP HANA | 由 retention_policy 控制 | 无限 | 表或 syslog | 是 |
| Databricks system.access | 365 天 | 365 天 | Delta 系统表 | 是 |
| Athena | 90 天 (CloudTrail) | 永久 (S3 sink) | CloudTrail | 是 |
| Spanner Audit | 30 天 (Admin)/ 7 天 (Data) | 取决 Sink | Cloud Logging | 是 |

> 注意：Redshift STL 表只保留 2 到 7 天，对合规场景**远远不够**，必须配合 `enable_audit_logging` 把日志导出到 S3 才能满足 SOX 7 年保留要求。

## 关键设计议题

### 1. 审计风暴：不可避免的性能权衡

启用全 SELECT 审计在 OLTP 系统上会带来 5%-30% 的性能损失，原因是：

- 每个查询多一次同步写入 (取决于 sync 策略)
- 审计文件锁竞争 (Oracle 12.2 之前 `aud$` 是热点)
- 审计缓冲区刷盘的尾延迟

减轻策略：
- **Oracle**：`AUDIT_TRAIL=DB,EXTENDED` 只写本地缓冲，由后台 `MMON` 异步 flush
- **SQL Server**：`QUEUE_DELAY = 1000ms` 异步队列，可接受 1 秒丢失风险换吞吐
- **pgaudit**：只在 logical replication 节点开启读审计，OLTP 主节点只审计 DDL/DCL
- **Snowflake**：审计自动异步，对查询无可观测影响

### 2. SELECT 审计 vs DML 审计的非对称性

读审计 (SELECT) 比写审计昂贵得多：

- DML 频率通常远低于 SELECT (典型 OLTP 1:10 到 1:100)
- DML 有事务边界，审计写入可与事务日志合并
- SELECT 没有写路径，审计写入是纯额外开销

这是为什么 GDPR 合规对成本敏感：法规要求知道**谁读取了个人数据**，而 SELECT 恰恰是最贵的审计目标。FGA (Oracle) 和 `WHERE` 谓词 (SQL Server) 是降低成本的关键武器：**只在条件成立时审计**。

### 3. 不可篡改性 (Tamper-proof)

合规要求审计日志不能被 DBA 或应用篡改。技术手段：

- **写入只读介质**：Oracle Audit Vault 把日志写入专用设备，DBA 无法访问
- **远程聚合**：syslog 转发到独立 SIEM (Splunk / QRadar)；本地副本即使被删，远程仍在
- **追加日志**：S3 Object Lock、Azure Blob Immutability、GCS Bucket Lock
- **区块链/Merkle 链**：Snowflake 的 ACCOUNT_USAGE 内部使用元数据校验
- **数据库本身的安全角色分离**：SYSDBA 不能修改 AUD$ (Oracle Database Vault)

只有**外置**到非数据库系统的审计才是真正不可篡改的。任何写在数据库自己表里的审计，DBA 总有办法清空。

### 4. 字段级审计 vs 行级审计

字段级 (列级) 审计比行级更难实现，因为查询计划需要在编译时识别哪些列被引用。三种实现策略：

- **静态分析 (Snowflake ACCESS_HISTORY)**：解析查询树，提取列引用
- **运行时拦截 (Oracle FGA)**：执行算子触发回调，记录实际读取
- **血缘追踪 (Databricks Unity)**：把列血缘作为元数据，与执行计划绑定

对 GDPR "数据主体访问报告"，字段级审计是必需的——你不能告诉数据主体"我们查询了 customers 表"，必须告诉他"我们读取了你的 email 和 phone 列"。

### 5. 审计存储模型：表 vs 文件

写表 (Oracle 11g 之前的 AUD$、SQL Server 2008、Teradata DBQL) 的优点是 SQL 直接可查；缺点是审计写入与业务表共用 redo / WAL，互相干扰，且 DBA 容易篡改。

写文件 (SQL Server 推荐、MariaDB、Oracle OS 模式) 的优点是物理隔离、可经 syslog 远端聚合、不占用数据库缓冲；缺点是查询不便，需要导入工具。

云原生引擎 (Snowflake、BigQuery、Databricks) 选择了第三条路：**审计是云平台的内置服务**，与数据库引擎在物理上独立，但通过元数据 schema (`account_usage` / `INFORMATION_SCHEMA` / `system.access`) 让 SQL 查询可见。这是目前最优雅的折衷。

### 6. 绑定参数捕获与敏感数据泄露悖论

捕获 SQL 文本时，如果带绑定参数 (例如 `WHERE ssn = '123-45-6789'`)，审计日志本身就成了敏感数据，需要新的保护层。pgaudit 默认 `pgaudit.log_parameter = off`，正是为了避免这个悖论。

解决方向：
- **掩码后审计**：Dynamic Data Masking 在审计前对参数应用掩码 (Oracle DDM、SQL Server DDM)
- **令牌化**：把 PII 替换为 token，token 与原值的映射存于 Vault
- **审计加密**：审计文件本身加密 (TDE 或专用密钥)
- **分层访问**：审计员只能看到脱敏视图，原始日志由审计组长持有

### 7. SaaS / 云数据库的审计外包模型

云原生引擎一般不让用户配置审计目的地——审计是平台内置服务，用户只能查询：

- **Snowflake**：`account_usage` 视图唯一接口
- **BigQuery**：Cloud Logging 是唯一目的地
- **Databricks**：Unity Catalog system tables
- **Athena / Spanner**：Cloud Audit Logs 平台级开关

这种"审计即服务"模型的优势：DBA 无法关闭、自动持久化、跨租户隔离。劣势：用户失去对延迟和保留期的精细控制。

### 8. 流处理引擎的审计困境

Flink SQL、Materialize、RisingWave 都没有原生审计。原因不是被忽视，而是流处理的语义本身就模糊：

- "查询" 在流处理中是一个**长期运行的算子**，没有明确的开始/结束
- 数据持续流过，"谁读取了哪一行" 失去意义
- CDC 源 (Kafka topic) 的访问应在 Kafka 层审计而非流引擎层

实践中的折衷：在**部署作业**和**结果输出**两个边界点审计，而非中间的状态访问。

## 关键发现

1. **SQL 标准缺位 40+ 年**：从 Oracle 6.0 (1980 年代) 到 SQL:2023，审计始终未进入标准。每个引擎独立演化导致迁移成本极高，跨厂商审计聚合必须依赖 SIEM 而非 SQL 工具。

2. **Oracle 仍是最完整的内置审计**：AUDIT POLICY + Unified Auditing + DBMS_FGA + Audit Vault 构成业界唯一覆盖"创建、过滤、存储、不可篡改"全链路的方案。这也是 Oracle 在金融、政府、医疗领域不可替代的核心原因之一。

3. **PostgreSQL 内核审计能力为零**：只有 `log_statement = all` (无结构化、不可过滤对象) 这一项。所有可用的审计方案都是扩展 (pgaudit) 或托管服务包装。Postgres 长期把审计视为非内核职责，是开源 RDBMS 中的少数派。

4. **MySQL 社区 vs MariaDB 的关键差异**：MySQL Enterprise 的 audit_log 插件闭源，导致依赖 MySQL 社区版的合规场景不得不迁移到 MariaDB 或加 Percona Audit Plugin。这一点常被低估。

5. **云数据仓库审计普遍优秀**：Snowflake、BigQuery、Databricks 都把审计作为平台内置能力，覆盖列级访问、自动保留 365+ 天、SQL 可查询。这是云原生模型对传统 RDBMS 的真正超越——审计不再是 DBA 项目，而是默认开箱。

6. **Snowflake ACCESS_HISTORY 是列级审计的标杆**：它通过解析查询计划自动展开视图、CTE、JOIN，记录每个查询实际读取的**底层列**。这种"语义级"审计是 GDPR 数据主体报告的最佳基础。

7. **ClickHouse 把审计当数据**：query_log 默认开启、是 MergeTree 表、可被任何 SQL 函数分析、可用 TTL 自动清理——这是数据驱动的审计设计典范，但不可篡改性需要外部保证。

8. **Teradata DBQL 是粒度最细的传统方案**：把 SQL 文本、对象引用、步骤计划、XML 计划分别写到不同表，便于按维度检索。这种粒度直到 2023 年 Snowflake / Databricks 才在云端追上。

9. **BigQuery / Spanner / Athena 把审计完全外包给 GCP/AWS**：用户不能在 SQL 层启用或关闭审计——它由 Cloud Audit Logs 自动开启。这种"无开关"设计是合规最严格的模型，因为 DBA 无法绕过。

10. **Hive / Impala / 传统 OLAP 引擎依赖 Ranger / Sentry 外置**：这些引擎没有自身审计，依赖 Apache Ranger 或 Cloudera Sentry 在网关层拦截。这种 hook 模型成本低但有覆盖盲区 (绕过 HiveServer2 直接读 HDFS 文件无法被审计)。

11. **嵌入式 SQL 引擎 (SQLite、DuckDB、H2、HSQLDB、Derby) 完全没有审计**：原因是它们的使用场景 (单进程嵌入) 让审计没有意义——调用方应在自己的应用层审计。把嵌入式数据库用于受监管场景时，必须由应用层补足。

12. **流处理引擎 (Flink、Materialize、RisingWave) 的审计盲区**：长运行算子和持续状态使传统审计模型失效。这是 streaming SQL 与监管合规之间尚未解决的一个本质张力。

13. **不可篡改性始终需要外部手段**：无论引擎如何宣传"安全审计"，只要日志写在数据库自己的表或文件里，足够权限的用户总能销毁它。真正的合规架构必然依赖远程 SIEM、Audit Vault、对象存储不可变锁等带外保护。

14. **绑定参数捕获是把双刃剑**：捕获参数才能复现查询，但参数本身往往就是敏感数据 (身份证、卡号)。pgaudit 默认关闭参数日志、Oracle 提供 DDM 集成，都是为了缓解这个悖论。

15. **保留期分层是合规的关键工程问题**：典型架构是"近期热数据 30 天 + 冷归档 7 年"。Snowflake 365 天 / Redshift 7 天 / Cloud Audit Logs 30 天等默认值都不足以覆盖 SOX 的 7 年要求，必须建立 Sink → S3/Glacier/GCS Coldline 的导出流程。

16. **审计成本占总数据库 TCO 5%-15%**：典型企业级合规配置下，审计存储+计算成本约占数据库总成本的十分之一。这是合规非功能需求里最常被低估的开销。

17. **49 个引擎中只有约 17 个提供 SQL 级 AUDIT/CREATE AUDIT POLICY 语句**：Oracle、SQL Server、DB2、SAP HANA、SingleStore、CockroachDB (`EXPERIMENTAL_AUDIT`)、OceanBase (Oracle 模式)、Informix、Azure Synapse、Teradata (`BEGIN LOGGING`) 等。其余 32 个引擎或依赖系统表/视图、或依赖扩展、或完全不支持。SQL 级审计语法仍是少数派。

## 参考资料

- Oracle: [Auditing Database Activity](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/auditing-database-activity.html)
- Oracle: [DBMS_FGA Package](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_FGA.html)
- SQL Server: [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine)
- PostgreSQL: [pgaudit](https://github.com/pgaudit/pgaudit)
- MySQL: [Audit Log Plugin](https://dev.mysql.com/doc/refman/8.0/en/audit-log.html)
- MariaDB: [MariaDB Audit Plugin](https://mariadb.com/kb/en/mariadb-audit-plugin/)
- DB2: [Audit Policies](https://www.ibm.com/docs/en/db2/11.5?topic=security-audit-policies)
- Snowflake: [ACCESS_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/access_history)
- Snowflake: [LOGIN_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/login_history)
- BigQuery: [Audit logs](https://cloud.google.com/bigquery/docs/reference/auditlogs)
- Redshift: [Database audit logging](https://docs.aws.amazon.com/redshift/latest/mgmt/db-auditing.html)
- ClickHouse: [system.query_log](https://clickhouse.com/docs/en/operations/system-tables/query_log)
- Teradata: [Database Query Log (DBQL)](https://docs.teradata.com/r/Teradata-VantageTM-Database-Administration)
- SAP HANA: [Auditing Activity in SAP HANA](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Databricks: [Unity Catalog system tables](https://docs.databricks.com/en/admin/system-tables/audit-logs.html)
- Apache Ranger: [Auditing](https://ranger.apache.org/)
- HIPAA Security Rule: 45 CFR §164.312(b) Audit controls
- PCI-DSS v4.0: Requirement 10 Log and Monitor All Access
