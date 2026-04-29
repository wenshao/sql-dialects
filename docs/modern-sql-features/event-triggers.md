# 事件触发器 (Event Triggers)

DDL 被执行的瞬间、用户登入数据库的瞬间、实例启动或异常崩溃的瞬间——这些事件全都发生在"普通行级触发器"管不到的层面。事件触发器（event triggers）是数据库引擎对自身行为的反向钩子：它不响应行的 INSERT/UPDATE/DELETE，而是响应 DDL 语句、登入登出、启动关闭、错误抛出这类系统级事件。在合规审计、Schema 强制约束、Fail-fast 防御性 DDL 拦截等场景下，事件触发器是无可替代的最后一道防线，但它从未被 SQL 标准化，每一个支持它的引擎都用截然不同的语法和语义实现这个能力。

> 边界说明：本文专注于 DDL 触发器、LOGON/LOGOFF 触发器、STARTUP/SHUTDOWN 触发器、SERVERERROR 触发器、数据库级事件触发器。普通的 DML 触发器（行级 INSERT/UPDATE/DELETE）请参考 [`triggers.md`](triggers.md)；审计日志的整体能力对比请参考 [`audit-logging.md`](audit-logging.md)。

## 为什么没有 SQL 标准

ISO/IEC 9075 系列标准（SQL:1999 至 SQL:2023）定义了 DML 触发器的完整语法（参见 SQL:1999 Section 11.39 与 SQL:2003 后续修订），但**从未涉及 DDL 触发器、登入/登出触发器、实例事件触发器**这一类系统级事件钩子。原因有三：

1. **DDL 语义的差异极大**：标准的 DML 操作 (`INSERT` / `UPDATE` / `DELETE`) 在不同引擎语义高度一致，可以提炼出 `OLD ROW` / `NEW ROW` / `OLD TABLE` / `NEW TABLE` 这样的过渡变量；而 DDL 操作（`CREATE TABLE` / `ALTER TABLE` / `DROP TABLE` / `GRANT` / `RENAME` ...）在不同引擎、甚至同一引擎不同版本之间，元数据模型和原子性边界都不同，难以提炼通用接口。
2. **登入/启动事件高度依赖部署模型**：单机引擎、分布式引擎、Serverless 引擎对"会话开始"和"实例启动"的概念定义都不同。SQL 标准刻意避开会话生命周期。
3. **多数 SQL 标准委员会成员引擎并未优先实现**：Oracle 1999 年（8i）就有了完整的系统触发器；SQL Server 2005 引入了 DDL 触发器；PostgreSQL 直到 2013 年（9.3）才补上事件触发器；MySQL/SQLite 至今（截止本文 2026-04 撰写时）仍然没有原生 DDL 触发器。这种参差不齐让标准化不具备共识基础。

结果是：事件触发器是 SQL 世界中**支持度差异最大、语法分化最严重**的特性之一。本文系统对比 49 个 SQL 引擎在 DDL 触发器、LOGON/LOGOFF 触发器、STARTUP/SHUTDOWN 触发器、SERVERERROR 触发器、数据库事件触发器五个维度上的能力差异。

## 关键时间线

| 年份 | 事件 |
|------|------|
| 1999 | Oracle 8i 引入完整的系统触发器（DDL、LOGON、LOGOFF、STARTUP、SHUTDOWN、SERVERERROR） |
| 2005 | SQL Server 2005 引入 DDL 触发器（数据库级与服务器级），同时引入 LOGON 触发器（2005 SP2，2007 年 2 月） |
| 2007 | DB2 9.5 引入审计策略（不是触发器，但覆盖类似场景） |
| 2010 | SAP HANA 1.0 起逐步加入 SYSTEM 触发器与数据库事件钩子 |
| 2013-09 | PostgreSQL 9.3 引入 EVENT TRIGGER 与 `ddl_command_start` / `ddl_command_end` / `sql_drop` |
| 2014 | PostgreSQL 9.4 增加 `table_rewrite` 事件触发器 |
| 2018 | MySQL 8.0 仍未实现 DDL 触发器，但完善了 audit_log 插件 |
| 2020+ | 云数仓 (Snowflake / BigQuery / Databricks) 用账户事件 / Unity Catalog 审计代替触发器 |

## 支持矩阵

### 1. DDL 触发器总览

| 引擎 | DDL 触发器 | 触发时机 | 作用域 | 引入版本 |
|------|-----------|---------|--------|---------|
| PostgreSQL | 是（EVENT TRIGGER） | `ddl_command_start` / `ddl_command_end` / `table_rewrite` / `sql_drop` | 数据库级 | 9.3 (2013) |
| Oracle | 是（系统触发器） | `BEFORE` / `AFTER` `DDL` (`CREATE` / `ALTER` / `DROP` / `TRUNCATE` / `GRANT` / `REVOKE` / `RENAME` / `ANALYZE` / `ASSOCIATE STATISTICS` 等) | `SCHEMA` 或 `DATABASE` | 8i (1999) |
| SQL Server | 是 | `FOR` / `AFTER` DDL 事件 (例如 `CREATE_TABLE`、`ALTER_DATABASE`) | 数据库级 (`ON DATABASE`) 或服务器级 (`ON ALL SERVER`) | 2005 |
| DB2 (LUW) | 部分（审计策略 + 通过 SYSPROC 存储过程实现 BEFORE-DDL 钩子） | 通过审计策略捕获 DDL 事件 | 实例级 | 9.5 (2007) |
| MySQL | 否 | -- | -- | 截至 9.x 不支持 |
| MariaDB | 否 | -- | -- | 截至 11.x 不支持 |
| SQLite | 否 | -- | -- | 不支持 |
| SAP HANA | 是 | `BEFORE` / `AFTER` 系统事件（DDL、用户操作） | 数据库级 | 1.0+ |
| Informix | 是（部分） | DDL 通过 `dbcron` / 审计实现，无独立 DDL 触发器语句 | 实例级 | 12.10+ |
| Firebird | 是 | `ON {CREATE \| ALTER \| DROP} ANY {TABLE \| VIEW \| ...}` (Database Trigger) | 数据库级 | 3.0 (2016) |
| Teradata | 否（用 DBQL 替代） | -- | -- | 不支持 |
| Snowflake | 否（账户/会话事件用 ACCESS_HISTORY） | -- | -- | 不支持 |
| BigQuery | 否（用 Cloud Audit Logs） | -- | -- | 不支持 |
| Redshift | 否（系统表 STL_DDLTEXT） | -- | -- | 不支持 |
| DuckDB | 否 | -- | -- | 不支持 |
| ClickHouse | 否（用 system.query_log） | -- | -- | 不支持 |
| Trino / Presto | 否（用 EventListener SPI） | -- | -- | 不支持 |
| Spark SQL | 否（QueryExecutionListener） | -- | -- | 不支持 |
| Hive | 否（HiveServer2 hooks） | -- | -- | 不支持 |
| Flink SQL | 否 | -- | -- | 不支持 |
| Databricks | 否（Unity Catalog 审计） | -- | -- | 不支持 |
| Greenplum | 是（继承 PG） | 同 PostgreSQL 9.3 | 数据库级 | 6.0 (2019) |
| CockroachDB | 否 | -- | -- | 不支持 |
| TiDB | 否 | -- | -- | 不支持 |
| OceanBase | 是（Oracle 模式） | 同 Oracle | `SCHEMA` 或 `DATABASE` | 4.0+ |
| YugabyteDB | 是（继承 PG） | 同 PostgreSQL 9.3 | 数据库级 | 2.0+ |
| SingleStore | 否 | -- | -- | 不支持 |
| Vertica | 否（用审计） | -- | -- | 不支持 |
| Impala | 否 | -- | -- | 不支持 |
| StarRocks | 否 | -- | -- | 不支持 |
| Doris | 否 | -- | -- | 不支持 |
| MonetDB | 否 | -- | -- | 不支持 |
| CrateDB | 否 | -- | -- | 不支持 |
| TimescaleDB | 是（继承 PG） | 同 PostgreSQL 9.3 | 数据库级 | 继承 PG |
| QuestDB | 否 | -- | -- | 不支持 |
| Exasol | 否 | -- | -- | 不支持 |
| H2 | 否（DML 触发器是 Java 实现） | -- | -- | 不支持 |
| HSQLDB | 否 | -- | -- | 不支持 |
| Derby | 否 | -- | -- | 不支持 |
| Amazon Athena | 否 | -- | -- | 不支持 |
| Azure Synapse | 是（继承 SQL Server） | 同 SQL Server | 数据库级 / 服务器级 | GA |
| Google Spanner | 否 | -- | -- | 不支持 |
| Materialize | 否 | -- | -- | 不支持 |
| RisingWave | 否 | -- | -- | 不支持 |
| InfluxDB (SQL) | 否 | -- | -- | 不支持 |
| Databend | 否 | -- | -- | 不支持 |
| Yellowbrick | 否 | -- | -- | 不支持 |
| Firebolt | 否 | -- | -- | 不支持 |

> 统计：约 9 个引擎提供原生 DDL 触发器语法（PostgreSQL、Oracle、SQL Server、SAP HANA、Firebird、Informix、Greenplum、TimescaleDB、YugabyteDB、Azure Synapse、OceanBase Oracle 模式），约 40 个引擎不支持，需用审计日志、事件监听器或外部工具替代。

### 2. LOGON / LOGOFF 触发器

| 引擎 | LOGON | LOGOFF | 触发上下文 | 引入版本 |
|------|:-----:|:------:|------------|---------|
| Oracle | 是 (`AFTER LOGON ON DATABASE` / `ON SCHEMA`) | 是 (`BEFORE LOGOFF ON DATABASE` / `ON SCHEMA`) | 用户连接成功后 / 主动断开前 | 8i (1999) |
| SQL Server | 是 (`FOR LOGON`) | 否 | 身份验证成功后但会话建立前 | 2005 SP2（2007 年 2 月） |
| Azure Synapse | 是（继承 SQL Server） | 否 | 同 SQL Server | GA |
| OceanBase (Oracle 模式) | 是 | 是 | 兼容 Oracle 语法 | 4.0+ |
| SAP HANA | 否（用 SESSION_VARIABLE 与审计） | 否 | -- | 不支持原生 |
| PostgreSQL | 否（仅 `client_connection_check_interval` 与登录钩子扩展） | 否 | 通过 `pg_hooks`/`session_preload_libraries` 实现 | 不原生支持 |
| MySQL | 否（用 `init_connect` 系统变量） | 否 | `init_connect` 是会话建立时执行的 SQL（半替代） | -- |
| MariaDB | 否（同 MySQL） | 否 | `init_connect` | -- |
| DB2 | 否（用审计 EXECUTE/CONTEXT） | 否 | -- | -- |
| Snowflake | 否（用 `LOGIN_HISTORY` 视图） | 否 | -- | -- |
| BigQuery | 否（Cloud Audit Logs） | 否 | -- | -- |
| Redshift | 否（用 `STL_CONNECTION_LOG`） | 否 | -- | -- |
| ClickHouse | 否（`session_log` 系统表） | 否 | -- | -- |
| Teradata | 否（DBQL 的 `LogonOff` 部分替代） | 否 | -- | -- |
| Firebird | 是 (`ON CONNECT` / `ON DISCONNECT` 数据库触发器) | 是 | 用户连接后 / 断开前 | 2.1+ |
| Informix | 是（连接事件审计 + sysdbopen 函数） | 是 | -- | 11.50+ |
| 其他引擎 | 否 | 否 | 用审计日志或外部工具 | -- |

> 注：MySQL 的 `init_connect` 系统变量执行的 SQL 在每个非 SUPER 用户登录时运行，可以用作"伪 LOGON 触发器"，但语义上有诸多差别（不是事务的一部分、出错时连接被断开、SUPER 用户绕过、不能拦截连接）。Oracle 的 LOGON 触发器执行失败默认不会拒绝连接（除非用户没有 ADMINISTER DATABASE TRIGGER 权限），这与 SQL Server 的 LOGON 触发器（执行失败拒绝登录）有显著差异。

### 3. STARTUP / SHUTDOWN 触发器

| 引擎 | STARTUP | SHUTDOWN | 备注 | 引入版本 |
|------|:-------:|:--------:|------|---------|
| Oracle | 是 (`AFTER STARTUP ON DATABASE`) | 是 (`BEFORE SHUTDOWN ON DATABASE`) | 实例打开后 / 关闭前；`SHUTDOWN ABORT` 不触发 | 8i (1999) |
| SAP HANA | 部分（系统事件 hook） | 部分 | 通过事件订阅 | 2.0+ |
| PostgreSQL | 否（仅 `shared_preload_libraries` 钩子） | 否 | 用 `pg_hooks` C 扩展可拦截 | -- |
| SQL Server | 否（用 SQL Agent Job 启动时运行） | 否 | -- | -- |
| Firebird | 否（数据库级触发器仅 ON CONNECT/DISCONNECT/TRANSACTION） | 否 | -- | -- |
| Informix | 否 | 否 | 用 `oninit` 启动脚本 | -- |
| 其他引擎 | 否 | 否 | -- | -- |

> 关键陷阱：Oracle 的 `STARTUP` 触发器在实例打开（OPEN）后立即执行，如果触发器代码故障，可能导致实例无法正常运行，必须以 SYSDBA 身份重新连接并 disable 该触发器。`SHUTDOWN ABORT` 不会触发 `BEFORE SHUTDOWN` 触发器（因为是异常关机）；`SHUTDOWN NORMAL` / `IMMEDIATE` / `TRANSACTIONAL` 会触发。

### 4. SERVERERROR 与异常事件触发器

| 引擎 | SERVERERROR | 错误事件钩子 | 引入版本 |
|------|:-----------:|------------|---------|
| Oracle | 是 (`AFTER SERVERERROR ON DATABASE`) | 任何 ORA-NNNNN 抛出后触发 | 8i |
| SQL Server | 否（用 Extended Events / DDL 触发器 ROLLBACK） | -- | -- |
| PostgreSQL | 否（`emit_log_hook` C 钩子） | -- | -- |
| SAP HANA | 部分（错误日志监控） | -- | -- |
| 其他引擎 | 否 | 用日志监控外部触发 | -- |

### 5. 数据库级 / 服务器级事件触发器

| 引擎 | 数据库级 | 服务器级 / 实例级 | 备注 |
|------|:-------:|:----------------:|------|
| Oracle | 是 (`ON DATABASE`) | 是 (`ON DATABASE` 全局) | DATABASE > SCHEMA 双层 |
| SQL Server | 是 (`ON DATABASE`) | 是 (`ON ALL SERVER`) | 服务器级触发器存储在 `master` |
| PostgreSQL | 是（事件触发器作用于整个数据库） | 否（无跨数据库触发器） | 每个 DB 独立 |
| Firebird | 是（数据库触发器） | 否 | DB 级 |
| OceanBase (Oracle 模式) | 是 | 是 | 兼容 Oracle |
| Greenplum / TimescaleDB / YugabyteDB | 是（继承 PG） | 否 | -- |

## PostgreSQL EVENT TRIGGER 深入解析

PostgreSQL 9.3（2013 年 9 月发布）引入了独立于 `CREATE TRIGGER` 之外的 `CREATE EVENT TRIGGER` 语法，专门用于响应 DDL 事件。它**不绑定到任何具体的表**，而是绑定到整个数据库。

### 5.1 语法

```sql
CREATE EVENT TRIGGER <event_trigger_name>
    ON <event>
    [ WHEN <filter_variable> IN (<filter_value> [, ...]) ]
    EXECUTE { FUNCTION | PROCEDURE } <function_name>();
```

四种事件类型：

1. `ddl_command_start`：DDL 解析后、执行前触发。可拒绝 DDL（通过抛出异常）。
2. `ddl_command_end`：DDL 执行成功后触发。可读取被改动的对象列表。
3. `sql_drop`：在每个 DROP 命令的对象被删除后、命令完成前触发。可读取被删除的对象列表。
4. `table_rewrite`：在 `ALTER TABLE` 触发表重写前触发（例如更改列类型、改 tablespace）。9.4+。

### 5.2 完整示例：拦截非维护窗口的 DDL

```sql
-- 创建函数：检查当前是否在维护窗口
CREATE OR REPLACE FUNCTION abort_ddl_outside_window()
RETURNS event_trigger AS $$
BEGIN
    IF EXTRACT(hour FROM CURRENT_TIMESTAMP) NOT BETWEEN 2 AND 4 THEN
        RAISE EXCEPTION
            'DDL only permitted between 02:00 and 04:00 (current=%, command=%)',
            CURRENT_TIMESTAMP, tg_tag;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 创建事件触发器：在所有 DDL 开始前触发
CREATE EVENT TRIGGER ddl_window_guard
    ON ddl_command_start
    EXECUTE FUNCTION abort_ddl_outside_window();

-- 测试：在白天执行 DDL 会被拒绝
CREATE TABLE foo (id int);
-- ERROR:  DDL only permitted between 02:00 and 04:00 ...
```

### 5.3 ddl_command_end：读取被改动的对象

```sql
CREATE OR REPLACE FUNCTION log_ddl_change()
RETURNS event_trigger AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO ddl_audit (
            event_time, classid, objid, objsubid,
            command_tag, object_type, schema_name, object_identity,
            in_extension, query
        )
        VALUES (
            CURRENT_TIMESTAMP, r.classid, r.objid, r.objsubid,
            r.command_tag, r.object_type, r.schema_name, r.object_identity,
            r.in_extension, current_query()
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER ddl_audit_trigger
    ON ddl_command_end
    EXECUTE FUNCTION log_ddl_change();
```

`pg_event_trigger_ddl_commands()` 函数返回当前 DDL 命令影响的所有对象（一条 `CREATE TABLE foo ...` 可能创建表本身、序列、约束、索引等多个对象）。

### 5.4 sql_drop：读取被删除的对象

```sql
CREATE OR REPLACE FUNCTION block_drop_critical_table()
RETURNS event_trigger AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP
        IF r.object_identity LIKE 'public.audit_%' THEN
            RAISE EXCEPTION 'Cannot drop audit table: %', r.object_identity;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER protect_audit_tables
    ON sql_drop
    EXECUTE FUNCTION block_drop_critical_table();

DROP TABLE audit_login;
-- ERROR:  Cannot drop audit table: public.audit_login
```

### 5.5 table_rewrite：拦截高代价 ALTER

```sql
CREATE OR REPLACE FUNCTION block_table_rewrite()
RETURNS event_trigger AS $$
DECLARE
    obj_oid oid := pg_event_trigger_table_rewrite_oid();
    obj_reason int := pg_event_trigger_table_rewrite_reason();
    table_name text;
BEGIN
    SELECT relname INTO table_name FROM pg_class WHERE oid = obj_oid;

    -- reason 是 bitmask: 1=ALTER COLUMN TYPE, 2=DEFAULT, 4=...
    RAISE EXCEPTION
        'Table rewrite blocked on % (reason=%); requires offline maintenance',
        table_name, obj_reason;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER prevent_rewrite
    ON table_rewrite
    EXECUTE FUNCTION block_table_rewrite();

ALTER TABLE big_table ALTER COLUMN amount TYPE numeric;
-- ERROR:  Table rewrite blocked on big_table (reason=1); requires offline maintenance
```

### 5.6 WHEN 子句过滤

```sql
-- 仅在 CREATE TABLE / ALTER TABLE / DROP TABLE 时触发
CREATE EVENT TRIGGER table_only
    ON ddl_command_start
    WHEN tag IN ('CREATE TABLE', 'ALTER TABLE', 'DROP TABLE')
    EXECUTE FUNCTION on_table_change();

-- 注意：仅 ddl_command_start / ddl_command_end / sql_drop 支持 WHEN tag
-- table_rewrite 不支持 WHEN tag 过滤
```

支持过滤的变量：

| 事件 | 支持的过滤变量 |
|------|-------------|
| `ddl_command_start` | `tag` |
| `ddl_command_end` | `tag` |
| `sql_drop` | `tag` |
| `table_rewrite` | 不支持 WHEN |

### 5.7 PostgreSQL 事件触发器的限制

1. **不能拦截 `CREATE`/`DROP DATABASE`、`ALTER DATABASE`**：因为事件触发器附加于具体数据库，而这些操作改变数据库本身。
2. **不能拦截 `CREATE`/`DROP ROLE`、`CREATE`/`DROP TABLESPACE`**：这些是集群级（cluster-wide）操作。
3. **超级用户绕过**：`ALTER EVENT TRIGGER ... DISABLE` 由超级用户随时可执行，事件触发器无法阻止超级用户禁用自己。
4. **递归调用风险**：在事件触发器函数内部执行 DDL 会再次触发自身。需要用 `pg_event_trigger_in_progress()`（社区扩展）或全局变量护栏。
5. **不能修改 DDL 内容**：与 DML 触发器不同，事件触发器不能改写正在执行的 DDL 语句，只能允许或拒绝。
6. **9.3 仅 ddl_command_start/end + sql_drop**；`table_rewrite` 在 9.4 加入。

### 5.8 启用 / 禁用 / 复制场景

```sql
-- 临时禁用单个事件触发器
ALTER EVENT TRIGGER ddl_audit_trigger DISABLE;

-- 修复或维护期间用 ALWAYS（仅 ALWAYS 模式在 session_replication_role = replica 下也会触发）
ALTER EVENT TRIGGER ddl_audit_trigger ENABLE ALWAYS;

-- 复制场景：副本上的 DDL（来自逻辑复制）默认不触发本地事件触发器
SET session_replication_role = replica;
-- 此时 mode=ENABLE 的触发器不触发，只有 ENABLE ALWAYS 的触发
```

### 5.9 PostgreSQL 与 SQL Server / Oracle 的语义差异

| 特性 | PostgreSQL | SQL Server | Oracle |
|------|-----------|------------|--------|
| 触发器命名空间 | 独立的 `CREATE EVENT TRIGGER` | 与 DML 触发器共用 `CREATE TRIGGER` | 与 DML 触发器共用 `CREATE TRIGGER` |
| BEFORE 拒绝 DDL | `ddl_command_start` + 抛异常 | `FOR DDL` + ROLLBACK | `BEFORE DDL` + RAISE_APPLICATION_ERROR |
| 读取改动的对象 | `pg_event_trigger_ddl_commands()` | `EVENTDATA()` XML | `ORA_DICT_OBJ_*` 函数 |
| 事件 ID | 4 种内置事件 | 100+ 种 DDL 事件类型 | 30+ 种 DDL 事件 |
| 跨数据库 | 否（每个 DB 独立） | 是（`ON ALL SERVER`） | 是（`ON DATABASE`） |
| LOGON 触发器 | 否 | 是 | 是 |
| 拦截内容修改 | 否（只能允许/拒绝） | 否 | 否 |

## SQL Server DDL 触发器深入解析

SQL Server 2005 引入 DDL 触发器，是除 Oracle 外最早提供完整 DDL 钩子的主流引擎。

### 6.1 数据库级 DDL 触发器

```sql
CREATE TRIGGER trg_db_ddl_audit
    ON DATABASE
    FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    DECLARE @event_data XML = EVENTDATA();
    INSERT INTO ddl_audit (
        event_type, post_time, login_name, host_name,
        schema_name, object_name, sql_command
    )
    VALUES (
        @event_data.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME'),
        @event_data.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/HostName)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)')
    );
END;
GO
```

`DDL_DATABASE_LEVEL_EVENTS` 是 SQL Server 预定义的事件分组，覆盖该数据库内所有 DDL 操作。其他常用分组：

| 分组名 | 覆盖事件 |
|--------|----------|
| `DDL_DATABASE_LEVEL_EVENTS` | 数据库内所有 DDL（约 200+ 种） |
| `DDL_TABLE_EVENTS` | `CREATE_TABLE`, `ALTER_TABLE`, `DROP_TABLE` |
| `DDL_INDEX_EVENTS` | `CREATE_INDEX`, `ALTER_INDEX`, `DROP_INDEX` |
| `DDL_TRIGGER_EVENTS` | `CREATE_TRIGGER`, `ALTER_TRIGGER`, `DROP_TRIGGER` |
| `DDL_LOGIN_EVENTS` | `CREATE_LOGIN`, `ALTER_LOGIN`, `DROP_LOGIN`（仅服务器级有效） |
| `DDL_TABLE_VIEW_EVENTS` | 表 + 视图 DDL |
| `DDL_PROCEDURE_EVENTS` | 存储过程 DDL |
| `DDL_FUNCTION_EVENTS` | 函数 DDL |

### 6.2 服务器级 DDL 触发器

```sql
-- 必须在 master 数据库下创建（实际存储在 master）
USE master;
GO

CREATE TRIGGER trg_server_ddl_audit
    ON ALL SERVER
    FOR CREATE_DATABASE, DROP_DATABASE, ALTER_DATABASE
AS
BEGIN
    DECLARE @event_data XML = EVENTDATA();
    PRINT 'Server-level DDL detected: ' + 
        CAST(@event_data.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)') AS NVARCHAR(100));
    -- 写入跨 DB 审计表（必须使用 fully qualified name）
    INSERT INTO master.dbo.server_ddl_audit (event_type, login_name, sql_text)
    VALUES (
        @event_data.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(100)'),
        @event_data.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)')
    );
END;
GO
```

### 6.3 ROLLBACK：拒绝 DDL

```sql
CREATE TRIGGER trg_block_drop_table
    ON DATABASE
    FOR DROP_TABLE
AS
BEGIN
    DECLARE @event_data XML = EVENTDATA();
    DECLARE @table_name NVARCHAR(200) = 
        @event_data.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(200)');

    IF @table_name LIKE 'audit_%'
    BEGIN
        RAISERROR('Cannot drop audit table: %s', 16, 1, @table_name);
        ROLLBACK;
    END
END;
GO

DROP TABLE audit_login;
-- Msg 50000, Level 16, State 1, Procedure trg_block_drop_table
-- Cannot drop audit table: audit_login
```

### 6.4 LOGON 触发器（SQL Server）

LOGON 触发器在身份验证成功后、会话建立完成前触发。失败会**拒绝登录**，因此实现时必须极度小心。

```sql
USE master;
GO

CREATE TRIGGER trg_block_app_login_outside_hours
    ON ALL SERVER WITH EXECUTE AS 'sa'
    FOR LOGON
AS
BEGIN
    DECLARE @login NVARCHAR(100) = ORIGINAL_LOGIN();
    DECLARE @hour INT = DATEPART(hour, GETDATE());

    IF @login = 'app_user' AND (@hour < 7 OR @hour > 19)
    BEGIN
        ROLLBACK;  -- 拒绝登录
    END

    -- 记录所有登录事件
    INSERT INTO master.dbo.logon_audit (login_name, login_time, host)
    VALUES (@login, GETDATE(), HOST_NAME());
END;
GO
```

> 警告：LOGON 触发器中如果出现未捕获的异常或不可达的资源，会导致**所有登录被拒绝**（包括 sysadmin）。修复方法：用 DAC（专用管理员连接）登录，禁用触发器：`ALTER TABLE ALL SERVER DISABLE TRIGGER trg_block_app_login_outside_hours`。

### 6.5 EVENTDATA() 详解

EVENTDATA() 返回 XML 类型，包含触发该事件的元信息：

```xml
<EVENT_INSTANCE>
    <EventType>CREATE_TABLE</EventType>
    <PostTime>2026-04-29T10:23:45.123</PostTime>
    <SPID>54</SPID>
    <ServerName>SQLPROD01</ServerName>
    <LoginName>DOMAIN\jdoe</LoginName>
    <UserName>dbo</UserName>
    <DatabaseName>SalesDB</DatabaseName>
    <SchemaName>dbo</SchemaName>
    <ObjectName>orders_2026</ObjectName>
    <ObjectType>TABLE</ObjectType>
    <TSQLCommand>
        <SetOptions ANSI_NULLS="ON" ... />
        <CommandText>CREATE TABLE orders_2026 (id INT, ts DATETIME)</CommandText>
    </TSQLCommand>
</EVENT_INSTANCE>
```

LOGON 触发器的 EVENTDATA() 结构略有不同：

```xml
<EVENT_INSTANCE>
    <EventType>LOGON</EventType>
    <PostTime>...</PostTime>
    <SPID>54</SPID>
    <ServerName>...</ServerName>
    <LoginName>...</LoginName>
    <LoginType>SQL Login</LoginType>
    <SID>...</SID>
    <ClientHost>192.168.1.10</ClientHost>
    <IsPooled>0</IsPooled>
</EVENT_INSTANCE>
```

### 6.6 限制与陷阱

1. **DDL 触发器不能用于 `ALTER DATABASE` 的所有子事件**：例如 `ALTER DATABASE ... SET ONLINE` 不触发数据库级触发器。
2. **DROP TRIGGER 与 ALTER TRIGGER 触发自身风险**：禁用自身的触发器后才能正常修改。
3. **某些临时表 DDL 不触发**：本地临时表 (`#temp`) 的 DDL 不触发 DDL 触发器（设计如此，避免性能影响）。
4. **批处理范围**：DDL 触发器在批处理结束时触发，而非语句结束。一个 GO 块中的多条 DDL 共享一次触发上下文（事件触发器列表）。
5. **某些 DBCC 命令不触发**：`DBCC FREEPROCCACHE` 等不算 DDL。

## Oracle 系统触发器深入解析

Oracle 8i（1999）就引入了完整的系统触发器，至今仍是行业最完整的实现。

### 7.1 完整事件清单

```sql
-- DDL 事件
CREATE -- AFTER CREATE / BEFORE CREATE
ALTER
DROP
TRUNCATE
GRANT
REVOKE
RENAME
ANALYZE
ASSOCIATE STATISTICS
DISASSOCIATE STATISTICS
AUDIT
NOAUDIT
COMMENT
DDL                       -- 任意 DDL（聚合事件）

-- 会话事件
LOGON                     -- AFTER LOGON
LOGOFF                    -- BEFORE LOGOFF

-- 实例事件
STARTUP                   -- AFTER STARTUP
SHUTDOWN                  -- BEFORE SHUTDOWN
DB_ROLE_CHANGE            -- 主备切换（Oracle 11g+ Data Guard）

-- 错误事件
SERVERERROR               -- AFTER SERVERERROR
```

### 7.2 完整 LOGON 触发器示例

```sql
CREATE OR REPLACE TRIGGER trg_logon_audit
AFTER LOGON ON DATABASE
DECLARE
    v_session_id NUMBER;
BEGIN
    -- 拒绝特定时段的登录
    IF SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_BATCH' AND
       TO_CHAR(SYSDATE, 'HH24') BETWEEN '08' AND '17' THEN
        RAISE_APPLICATION_ERROR(-20001,
            'APP_BATCH not allowed during business hours');
    END IF;

    -- 记录登录
    SELECT SYS_CONTEXT('USERENV', 'SESSIONID') INTO v_session_id FROM DUAL;
    INSERT INTO logon_audit (
        session_id, username, os_user, machine, ip_address, logon_time
    ) VALUES (
        v_session_id,
        SYS_CONTEXT('USERENV', 'SESSION_USER'),
        SYS_CONTEXT('USERENV', 'OS_USER'),
        SYS_CONTEXT('USERENV', 'HOST'),
        SYS_CONTEXT('USERENV', 'IP_ADDRESS'),
        SYSDATE
    );
END;
/
```

### 7.3 SCHEMA 级 vs DATABASE 级

```sql
-- DATABASE 级：对所有 schema 生效（必须有 ADMINISTER DATABASE TRIGGER 权限）
CREATE OR REPLACE TRIGGER trg_db_ddl
AFTER DDL ON DATABASE
BEGIN
    INSERT INTO global_ddl_log VALUES (...);
END;
/

-- SCHEMA 级：只对当前 schema（owner）的 DDL 生效
CREATE OR REPLACE TRIGGER trg_my_schema_ddl
AFTER DDL ON SCHEMA
BEGIN
    INSERT INTO my_ddl_log VALUES (...);
END;
/

-- 指定 schema（必须是同名 schema）
CREATE OR REPLACE TRIGGER hr.trg_hr_ddl
AFTER DDL ON hr.SCHEMA
BEGIN
    INSERT INTO hr.ddl_log VALUES (...);
END;
/
```

### 7.4 元数据访问函数

Oracle 提供丰富的 `ORA_*` 系统函数访问事件元数据：

| 函数 / 属性 | 说明 |
|------------|------|
| `ORA_SYSEVENT` | 触发事件名称（'CREATE', 'ALTER', 'LOGON' ...） |
| `ORA_LOGIN_USER` | 触发事件的登录用户 |
| `ORA_DICT_OBJ_NAME` | 受影响的对象名 |
| `ORA_DICT_OBJ_TYPE` | 对象类型（'TABLE', 'INDEX', 'VIEW' ...） |
| `ORA_DICT_OBJ_OWNER` | 对象所有者 |
| `ORA_DICT_OBJ_NAME_LIST(n, list)` | 受影响对象列表（DDL 一次影响多个对象时） |
| `ORA_SQL_TXT(sql_text OUT VARCHAR2_TABLE)` | 触发事件的完整 SQL 文本 |
| `ORA_INSTANCE_NUM` | RAC 实例编号 |
| `ORA_DATABASE_NAME` | 数据库名 |
| `ORA_GRANTEE(user_list OUT)` | GRANT 时的被授权者列表 |
| `ORA_PRIVILEGE_LIST(priv_list OUT)` | GRANT/REVOKE 的权限列表 |
| `ORA_REVOKEE(user_list OUT)` | REVOKE 时被收回权限的用户 |
| `ORA_IS_ALTER_COLUMN(column_name)` | 当前 ALTER 是否修改了指定列 |
| `ORA_IS_DROP_COLUMN(column_name)` | 当前 ALTER 是否删除了指定列 |
| `ORA_DES_ENCRYPTED_PASSWORD` | (LOGON) 加密密码 |
| `ORA_CLIENT_IP_ADDRESS` | 客户端 IP 地址 |
| `ORA_SERVER_ERROR(position)` | (SERVERERROR) 错误堆栈中第 N 个错误码 |
| `ORA_SERVER_ERROR_MSG(position)` | (SERVERERROR) 错误消息文本 |
| `ORA_SERVER_ERROR_DEPTH` | (SERVERERROR) 错误堆栈深度 |

### 7.5 SERVERERROR 触发器示例

```sql
CREATE OR REPLACE TRIGGER trg_log_server_errors
AFTER SERVERERROR ON DATABASE
DECLARE
    v_error_code NUMBER;
    v_error_msg  VARCHAR2(2000);
BEGIN
    FOR i IN 1..ORA_SERVER_ERROR_DEPTH LOOP
        v_error_code := ORA_SERVER_ERROR(i);
        v_error_msg := ORA_SERVER_ERROR_MSG(i);

        -- 仅记录关键错误（避开 ORA-00942 等高频错误）
        IF v_error_code IN (-1, -1438, -1722, -2291, -4031, -1555) THEN
            INSERT INTO error_audit (
                error_code, error_msg, username, ts
            ) VALUES (
                v_error_code, v_error_msg,
                SYS_CONTEXT('USERENV', 'SESSION_USER'),
                SYSDATE
            );
        END IF;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN NULL;  -- 切勿让 SERVERERROR 触发器抛错
END;
/
```

> 警告：在 `AFTER SERVERERROR` 触发器中**绝对不要让异常逃逸**。否则触发器自身的异常会再次进入 SERVERERROR 处理路径，可能导致死循环、连接断开或实例日志泛滥。`WHEN OTHERS THEN NULL` 是必备的最后防线。

### 7.6 复合触发器与 FOLLOWS / PRECEDES

Oracle 11g 引入复合触发器（`COMPOUND TRIGGER`），主要用于 DML，但 11g+ 系统触发器也支持 `FOLLOWS` / `PRECEDES` 控制多个相同事件触发器的执行顺序：

```sql
CREATE OR REPLACE TRIGGER trg_audit_first
AFTER LOGON ON DATABASE
BEGIN
    -- 优先执行
END;
/

CREATE OR REPLACE TRIGGER trg_audit_second
AFTER LOGON ON DATABASE
FOLLOWS trg_audit_first
BEGIN
    -- 在 trg_audit_first 之后执行
END;
/
```

### 7.7 STARTUP / SHUTDOWN 触发器示例

```sql
-- STARTUP：实例启动后执行管理任务
CREATE OR REPLACE TRIGGER trg_post_startup
AFTER STARTUP ON DATABASE
BEGIN
    -- 启动 Job
    DBMS_SCHEDULER.ENABLE('NIGHTLY_MAINT_JOB');
    -- 重建临时统计
    EXECUTE IMMEDIATE 'ALTER SESSION SET ddl_lock_timeout=60';
    -- 记录启动
    INSERT INTO instance_log (event, ts)
    VALUES ('STARTUP_' || ORA_INSTANCE_NUM, SYSDATE);
END;
/

-- SHUTDOWN：关机前清理
CREATE OR REPLACE TRIGGER trg_pre_shutdown
BEFORE SHUTDOWN ON DATABASE
BEGIN
    -- 警告活跃用户（实际应用中需用 alerter 而非触发器内 SLEEP）
    INSERT INTO instance_log (event, ts)
    VALUES ('SHUTDOWN_' || ORA_INSTANCE_NUM, SYSDATE);
    COMMIT;
END;
/
```

### 7.8 Oracle 系统触发器的关键陷阱

1. **STARTUP 触发器故障会让实例无法上线**：必须以 SYSDBA 身份启动（`STARTUP RESTRICT`）后禁用触发器。
2. **LOGON 触发器对 SYSDBA 默认不生效**：除非显式不排除（避免锁死管理员）。
3. **SHUTDOWN ABORT 不触发 BEFORE SHUTDOWN**：仅 NORMAL/IMMEDIATE/TRANSACTIONAL。
4. **触发器内的 DML 不会立即可见**：因为系统触发器在自治事务（autonomous transaction）外运行，需要手动 COMMIT 才能持久化日志记录。
5. **SERVERERROR 触发器对所有错误都触发**，包括语法错、权限错、表不存在——日志膨胀风险极高，必须过滤错误码。
6. **DATABASE 级触发器需要 `ADMINISTER DATABASE TRIGGER` 权限**：只有 SYS 默认拥有，普通 DBA 需显式授予。

## SAP HANA / Firebird 等其他引擎

### 8.1 SAP HANA 数据库事件触发器

```sql
-- HANA 触发器可以绑定到 DDL 事件（系统触发器）
CREATE TRIGGER ddl_audit_trigger
AFTER CREATE TABLE OR ALTER TABLE OR DROP TABLE
ON DATABASE
BEGIN
    INSERT INTO ddl_audit_log VALUES (
        CURRENT_TIMESTAMP,
        SESSION_USER,
        :EVENT_NAME,           -- HANA 特有的隐式上下文变量
        :OBJECT_SCHEMA,
        :OBJECT_NAME
    );
END;
```

HANA 也通过审计策略（`CREATE AUDIT POLICY`）覆盖大量事件，与触发器互补。

### 8.2 Firebird 数据库触发器

Firebird 2.1+ 支持数据库级触发器（DB triggers），事件类型有限但覆盖关键场景：

```sql
SET TERM ^ ;

CREATE TRIGGER trg_db_connect
ACTIVE ON CONNECT POSITION 0
AS
BEGIN
    -- 在用户连接成功后触发
    INSERT INTO connection_log (username, ts)
    VALUES (CURRENT_USER, CURRENT_TIMESTAMP);
END^

CREATE TRIGGER trg_db_disconnect
ACTIVE ON DISCONNECT POSITION 0
AS
BEGIN
    -- 在用户断开前触发
    INSERT INTO disconnect_log (username, ts)
    VALUES (CURRENT_USER, CURRENT_TIMESTAMP);
END^

CREATE TRIGGER trg_tx_start
ACTIVE ON TRANSACTION START POSITION 0
AS
BEGIN
    -- 事务开始时触发（每个新事务）
END^

CREATE TRIGGER trg_tx_commit
ACTIVE ON TRANSACTION COMMIT POSITION 0
AS
BEGIN
    -- 事务即将提交前触发（可拒绝提交）
END^

SET TERM ; ^

-- Firebird 3.0 增加了 DDL 数据库触发器
CREATE TRIGGER trg_ddl_create
ACTIVE BEFORE CREATE TABLE
POSITION 0
AS
BEGIN
    -- 拦截 CREATE TABLE
    IF (RDB$GET_CONTEXT('DDL_TRIGGER', 'OBJECT_NAME') LIKE 'TEMP_%') THEN
        EXCEPTION CUSTOM 'temp tables not allowed';
END;
```

Firebird 数据库触发器的事件清单：

| 事件 | 时机 |
|------|------|
| `ON CONNECT` | 连接成功后 |
| `ON DISCONNECT` | 连接断开前 |
| `ON TRANSACTION START` | 事务启动 |
| `ON TRANSACTION COMMIT` | 事务提交前 |
| `ON TRANSACTION ROLLBACK` | 事务回滚前 |
| `BEFORE/AFTER CREATE/ALTER/DROP {TABLE\|VIEW\|...}` | DDL 事件（3.0+） |

### 8.3 Informix 数据库事件

Informix 的等价能力来自 `sysdbopen()` / `sysdbclose()` 存储过程：

```sql
-- 名为 sysdbopen 的过程在每次用户打开数据库时被调用
CREATE PROCEDURE sysdbopen()
    INSERT INTO connection_log VALUES (USER, CURRENT);
    SET ISOLATION TO DIRTY READ;  -- 默认隔离级别
END PROCEDURE;

-- sysdbclose 在关闭时调用
CREATE PROCEDURE sysdbclose()
    INSERT INTO disconnect_log VALUES (USER, CURRENT);
END PROCEDURE;
```

### 8.4 MySQL/MariaDB 的伪 LOGON 钩子

虽然 MySQL/MariaDB 没有原生的 LOGON 触发器和 DDL 触发器，但可以用以下机制部分模拟：

```sql
-- init_connect 系统变量：每个非 SUPER 用户登录时执行的 SQL
SET GLOBAL init_connect='CALL audit_login()';

-- audit_login 过程
DELIMITER //
CREATE PROCEDURE audit_login()
BEGIN
    INSERT INTO login_audit (user, host, ts)
    VALUES (CURRENT_USER, CONNECTION_ID(), NOW());
END//
DELIMITER ;
```

限制：

1. SUPER/SYSTEM_VARIABLES_ADMIN 用户**绕过** `init_connect`。
2. `init_connect` 出错会**断开连接**。
3. 不能拦截连接（只能记录或失败连接）。
4. 不能用作 DDL 钩子，DDL 必须用审计插件 (`audit_log` 或 `server_audit`)。

DDL 审计的替代方案：

```sql
-- MySQL Enterprise audit_log 插件：可过滤 DDL 事件
INSTALL PLUGIN audit_log SONAME 'audit_log.so';
SET GLOBAL audit_log_format = 'JSON';
SET GLOBAL audit_log_filter_id = 'ddl_only';

-- 创建过滤规则（仅记录 DDL 类）
SELECT audit_log_filter_set_filter('ddl_only', '{
    "filter": {
        "class": [
            { "name": "general",
              "event": [{ "name": "log",
                          "log": { "field": { "name": "general_command.str",
                                              "value": "Query" }}}]}
        ]
    }
}');
```

### 8.5 ClickHouse / Snowflake / BigQuery 等的事件审计替代

这些引擎完全没有触发器机制，但提供完整的事件日志查询能力：

```sql
-- ClickHouse: 通过 system.query_log 反查 DDL
SELECT
    event_time, user, query_kind, query, exception_code
FROM system.query_log
WHERE query_kind IN ('Create', 'Drop', 'Alter', 'Rename')
    AND event_time > now() - INTERVAL 1 DAY
ORDER BY event_time DESC;

-- Snowflake: ACCESS_HISTORY + QUERY_HISTORY 反查 DDL
SELECT
    query_id, user_name, query_text, execution_status, start_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_type IN ('CREATE_TABLE', 'ALTER_TABLE', 'DROP_TABLE')
    AND start_time > DATEADD(day, -7, CURRENT_TIMESTAMP);

-- BigQuery: INFORMATION_SCHEMA.JOBS 或 Cloud Audit Logs
SELECT
    job_id, user_email, query, statement_type, creation_time
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE statement_type LIKE '%TABLE%'
    AND creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);
```

这种"事后查询日志"模式的优劣：

- **优势**：不影响 DDL 执行性能、零运行时开销、易于跨账户聚合。
- **劣势**：不能拦截/拒绝 DDL（只能记录）、有延迟（日志异步写入）、不能在事件发生瞬间执行业务逻辑。

## 典型应用场景

### 9.1 审计与合规

```sql
-- PostgreSQL：完整的 DDL 审计链
CREATE TABLE ddl_audit_log (
    log_id bigserial PRIMARY KEY,
    event_time timestamptz DEFAULT clock_timestamp(),
    db_user text DEFAULT current_user,
    client_addr inet DEFAULT inet_client_addr(),
    application_name text DEFAULT current_setting('application_name'),
    command_tag text,
    object_type text,
    schema_name text,
    object_identity text,
    sql_command text DEFAULT current_query()
);

CREATE OR REPLACE FUNCTION fn_log_ddl()
RETURNS event_trigger AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO ddl_audit_log
            (command_tag, object_type, schema_name, object_identity)
        VALUES
            (r.command_tag, r.object_type, r.schema_name, r.object_identity);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER ddl_audit_ddl_end
    ON ddl_command_end
    EXECUTE FUNCTION fn_log_ddl();
```

### 9.2 Schema 强制约束

```sql
-- 例：所有表必须以模块前缀命名（auth_, billing_, ...）
CREATE OR REPLACE FUNCTION enforce_table_naming()
RETURNS event_trigger AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands()
        WHERE object_type = 'table'
              AND command_tag = 'CREATE TABLE' LOOP
        IF r.object_identity NOT SIMILAR TO
            '%(auth_|billing_|core_|user_)%' THEN
            RAISE EXCEPTION
                'Table % does not match naming convention (auth_/billing_/core_/user_)',
                r.object_identity;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER enforce_naming
    ON ddl_command_end
    EXECUTE FUNCTION enforce_table_naming();

-- 测试
CREATE TABLE foo (id int);
-- ERROR: Table public.foo does not match naming convention ...
```

### 9.3 Fail-fast 防御性 DDL 拦截

```sql
-- Oracle：拦截没有 PRIMARY KEY 的 CREATE TABLE
CREATE OR REPLACE TRIGGER trg_require_pk
BEFORE CREATE ON DATABASE
DECLARE
    v_sql_text DBMS_STANDARD.ORA_NAME_LIST_T;
    v_lines    PLS_INTEGER;
    v_full_sql CLOB;
BEGIN
    IF ORA_DICT_OBJ_TYPE != 'TABLE' THEN RETURN; END IF;

    v_lines := ORA_SQL_TXT(v_sql_text);
    FOR i IN 1..v_lines LOOP
        v_full_sql := v_full_sql || v_sql_text(i);
    END LOOP;

    IF UPPER(v_full_sql) NOT LIKE '%PRIMARY KEY%' AND
       UPPER(v_full_sql) NOT LIKE '%CONSTRAINT%PK%' THEN
        RAISE_APPLICATION_ERROR(-20002,
            'CREATE TABLE without PRIMARY KEY is not allowed: ' ||
            ORA_DICT_OBJ_OWNER || '.' || ORA_DICT_OBJ_NAME);
    END IF;
END;
/
```

### 9.4 用户行为分析与审计

```sql
-- SQL Server：记录所有失败登录尝试
CREATE TRIGGER trg_failed_login
    ON ALL SERVER WITH EXECUTE AS 'sa'
    FOR LOGON
AS
BEGIN
    DECLARE @ip NVARCHAR(50) = EVENTDATA().value(
        '(/EVENT_INSTANCE/ClientHost)[1]', 'NVARCHAR(50)');
    DECLARE @login NVARCHAR(100) = ORIGINAL_LOGIN();

    -- 检查近 5 分钟内来自同一 IP 的失败次数
    DECLARE @recent_fails INT;
    SELECT @recent_fails = COUNT(*)
    FROM master.dbo.failed_login_log
    WHERE client_ip = @ip
        AND event_time > DATEADD(minute, -5, GETDATE());

    IF @recent_fails > 5
    BEGIN
        ROLLBACK;  -- 拒绝
    END
END;
GO
```

### 9.5 自动化运维（Oracle STARTUP）

```sql
-- 实例启动后自动启动后台 Job
CREATE OR REPLACE TRIGGER trg_post_startup_jobs
AFTER STARTUP ON DATABASE
BEGIN
    DBMS_SCHEDULER.ENABLE('STATS_JOB');
    DBMS_SCHEDULER.ENABLE('CLEANUP_JOB');
    DBMS_SCHEDULER.ENABLE('REPLICATION_HEARTBEAT');
END;
/
```

### 9.6 异常追踪与告警

```sql
-- Oracle：高优先级错误立即触发外部告警
CREATE OR REPLACE TRIGGER trg_critical_errors
AFTER SERVERERROR ON DATABASE
DECLARE
    v_code NUMBER;
BEGIN
    FOR i IN 1..ORA_SERVER_ERROR_DEPTH LOOP
        v_code := ORA_SERVER_ERROR(i);
        -- ORA-00600 ORA-07445 表示内部错误
        IF v_code IN (-600, -7445) THEN
            UTL_HTTP.REQUEST(
                'https://alert.internal/api/page?code=' || v_code ||
                '&db=' || ORA_DATABASE_NAME);
        END IF;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/
```

## 性能与故障考量

### 10.1 性能开销

事件触发器在每次匹配的事件发生时同步执行，对热路径有显著影响：

| 触发器类型 | 频率 | 性能影响 |
|-----------|------|---------|
| DDL 触发器 | DDL 是低频操作（每天 0 - 数千次） | 通常可忽略 |
| LOGON 触发器 | 每个新连接 | 高敏感（连接池场景） |
| SHUTDOWN 触发器 | 实例关机时一次 | 不敏感 |
| STARTUP 触发器 | 实例启动时一次 | 不敏感 |
| SERVERERROR 触发器 | 每次错误 | 极高敏感（错误高频时） |
| ddl_command_end | 每次 DDL 完成 | 通常可忽略 |
| sql_drop | 每个 DROP | 通常可忽略 |
| table_rewrite | 仅 ALTER TABLE 触发重写时 | 罕见 |

实际数字（参考）：

- PostgreSQL 简单 ddl_command_end + INSERT：单次开销约 0.5 - 2ms。
- Oracle LOGON 触发器（含查询 + INSERT）：单次开销约 5 - 20ms（连接池场景每秒 100+ 次会显著放大）。
- SQL Server LOGON 触发器（EVENTDATA 解析 + 写表）：单次约 10 - 50ms。
- SERVERERROR 触发器在 ORA-00942 高频抛出场景下，每秒可触发 1000+ 次，需严格过滤。

### 10.2 死锁风险

事件触发器内部访问的表如果与正在执行的 DDL 涉及的对象有锁冲突，可能导致死锁。常见场景：

1. **DDL 触发器写入审计表，而审计表本身被 ALTER**：审计触发器持有审计表的写锁，被 ALTER 阻塞。
2. **LOGON 触发器查询的统计视图被 DDL 锁定**：连接被阻塞。
3. **PostgreSQL ddl_command_end 内对 pg_class 的查询**：该 catalog 在某些 DDL 期间有共享锁。

### 10.3 安全考量

LOGON 触发器和 DDL 触发器是攻击者建立后门的常见目标：

1. **隐藏的 LOGON 触发器**：攻击者创建一个隐式 elevation 的 LOGON 触发器，让特定用户连接时自动获得管理员权限。
2. **审计绕过**：攻击者修改审计触发器，让自己的 DDL 不被记录。
3. **超级用户依赖**：PostgreSQL 事件触发器 owner 必须是超级用户，超级用户可禁用所有事件触发器。
4. **服务器级触发器在 master 库**：SQL Server 服务器级触发器对管理员可见，但代码可加密 (`WITH ENCRYPTION`) 以隐藏意图。

防御措施：

```sql
-- PostgreSQL：定期审计现有事件触发器
SELECT evtname, evtevent, evtenabled, evtfoid::regproc
FROM pg_event_trigger
ORDER BY evtname;

-- SQL Server：审计 DDL 与 LOGON 触发器
SELECT name, parent_class_desc, type, create_date, modify_date
FROM sys.server_triggers;

SELECT name, parent_class_desc, type, create_date, modify_date
FROM sys.triggers
WHERE parent_class_desc = 'DATABASE';

-- Oracle：审计系统触发器
SELECT trigger_name, trigger_type, triggering_event, status
FROM dba_triggers
WHERE base_object_type IN ('DATABASE', 'SCHEMA');
```

### 10.4 升级与数据迁移

事件触发器在版本升级和迁移时常被忽视：

1. **PostgreSQL pg_dump 默认不导出事件触发器**：必须使用 `pg_dumpall`（包含事件触发器）。
2. **SQL Server 数据库附加（attach）不带服务器级触发器**：需手动迁移到目标实例的 master。
3. **Oracle 跨平台迁移**：DBMS_DATA_PUMP 默认导出系统触发器，但目标平台可能 OS 用户不同。

## 与 SQL 标准的差距与未来

### 11.1 标准化呼声

近年（2020+）SQL 标准委员会陆续讨论以下提案，但截至 SQL:2023 都未纳入：

1. **CREATE EVENT TRIGGER 标准化**：参考 PostgreSQL 9.3 的语法。
2. **AFTER LOGON / BEFORE LOGOFF 标准化**：参考 Oracle 8i 的语法。
3. **统一的事件元数据访问 API**：取代 EVENTDATA() XML / pg_event_trigger_*() / ORA_*。

### 11.2 云原生引擎的方向

云数仓和分布式 SQL 引擎普遍**回避触发器路线**，转而提供：

1. **基于事件流的审计** (Snowflake ACCESS_HISTORY、Databricks System Tables)：异步、分析友好。
2. **基于 IAM 的 DDL 控制** (BigQuery / Spanner)：通过 IAM Condition 拒绝 DDL。
3. **外部 SDK 监听器** (Trino EventListener、Spark QueryExecutionListener)：JVM 级钩子，可挂载任意逻辑。
4. **政策即代码** (Databricks Unity Catalog)：将"哪些 schema 允许哪些 DDL"作为 declarative policy。

这些方向的共同特征：**降低触发器的语义复杂度，把事件响应解耦为独立服务**。从工程角度看，传统的 LOGON 触发器（同步、绑定执行路径、可拒绝连接）在云时代被认为是反模式（影响 SLA、不利水平扩展）。

## 关键发现

1. **支持度极度分化**：仅约 9 个引擎提供原生 DDL 触发器（Oracle、SQL Server、PostgreSQL、SAP HANA、Firebird、Informix、Greenplum、TimescaleDB、YugabyteDB、Azure Synapse、OceanBase Oracle 模式），其余 40 个引擎不支持。
2. **Oracle 仍是行业最完整实现**：1999 年 8i 发布的系统触发器至今覆盖最广（DDL、LOGON、LOGOFF、STARTUP、SHUTDOWN、SERVERERROR、DB_ROLE_CHANGE）。
3. **PostgreSQL 9.3 (2013) 的 EVENT TRIGGER 是最优雅的现代设计**：独立语法、四种内置事件、通过函数访问元数据、不与 DML 触发器共用命名空间。
4. **MySQL 至今（2026）无 DDL 触发器**：`init_connect` 仅是伪 LOGON 钩子，DDL 审计完全依赖 audit_log 插件。
5. **LOGON 触发器是云时代的反模式**：同步阻塞、影响连接 SLA、对水平扩展不友好；Snowflake、BigQuery、Databricks 全部回避此特性。
6. **EVENTDATA / pg_event_trigger_*() / ORA_* 没有标准化**：每个引擎的事件元数据 API 完全独立，迁移成本高。
7. **SQL Server 的事件分类最丰富**：DDL_DATABASE_LEVEL_EVENTS 覆盖 200+ 种事件类型，可精细到 `CREATE_INDEX_ALL` vs `CREATE_PRIMARY_KEY_CONSTRAINT`。
8. **STARTUP 触发器是实例可用性风险**：故障会让实例无法上线，需要应急 disable 路径。
9. **SERVERERROR 触发器极易引发日志爆炸**：必须基于错误码过滤，避免对 ORA-00942 等高频错误响应。
10. **递归调用 / 死锁 / 自禁用是事件触发器的三大陷阱**：实施前必须设计 fail-safe 路径（禁用机制、超级用户绕过、try/catch）。
11. **DDL 触发器无法修改 DDL 内容**：只能允许或拒绝；这与 BEFORE 行级 DML 触发器可改 NEW 行不同。
12. **复制场景下 DDL 触发器默认不在副本触发**：PostgreSQL 必须 `ENABLE ALWAYS`、SQL Server 必须显式部署到副本。
13. **table_rewrite 是 PostgreSQL 9.4 的独有能力**：可以在大表 ALTER 触发隐式重写前抛出异常，避免数小时的锁表。
14. **审计型用例正被云原生服务取代**：Cloud Audit Logs、Snowflake QUERY_HISTORY、Databricks System Tables 提供异步事件流，性能开销低于触发器。
15. **Firebird 是开源中数据库事件覆盖最完整的小众引擎**：除 DDL 之外还支持 ON TRANSACTION START/COMMIT/ROLLBACK，独此一家。

## 参考资料

- PostgreSQL 9.3 Release Notes (2013-09): [Event Triggers](https://www.postgresql.org/docs/release/9.3.0/)
- PostgreSQL: [Event Triggers Documentation](https://www.postgresql.org/docs/current/event-triggers.html)
- PostgreSQL: [pg_event_trigger system catalog](https://www.postgresql.org/docs/current/catalog-pg-event-trigger.html)
- PostgreSQL: [Functions for Event Triggers](https://www.postgresql.org/docs/current/functions-event-triggers.html)
- Oracle Database: [Triggers on System Events and User Events](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/plsql-triggers.html)
- Oracle: [LOGON / LOGOFF Triggers](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/plsql-triggers.html#GUID-5D8EC0D4-C0DB-44D2-AC95-7DB7BDD2DE26)
- SQL Server: [DDL Triggers](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/ddl-triggers)
- SQL Server: [Logon Triggers](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/logon-triggers)
- SQL Server: [DDL Events](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/ddl-events)
- SQL Server: [EVENTDATA](https://learn.microsoft.com/en-us/sql/t-sql/functions/eventdata-transact-sql)
- SAP HANA: [SQL Triggers](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Firebird: [Database Triggers](https://firebirdsql.org/file/documentation/chunk-html/fblangref50/fblangref50-ddl-trgr.html)
- Informix: [Database Open / Close Procedures](https://www.ibm.com/docs/en/informix-servers)
- MySQL: [init_connect System Variable](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_init_connect)
- MySQL Enterprise: [Audit Log Plugin](https://dev.mysql.com/doc/refman/8.0/en/audit-log.html)
- Snowflake: [ACCESS_HISTORY View](https://docs.snowflake.com/en/sql-reference/account-usage/access_history)
- BigQuery: [Cloud Audit Logs for BigQuery](https://cloud.google.com/bigquery/docs/reference/auditlogs)
- ISO/IEC 9075-2 SQL/Foundation：DDL 与触发器章节（事件触发器未纳入）
