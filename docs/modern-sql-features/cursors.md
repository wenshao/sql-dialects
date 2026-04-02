# 游标 (Cursors)

游标是过程化 SQL 中逐行处理查询结果集的核心机制。在集合导向的 SQL 世界里，游标提供了一种命令式的"一次一行"访问模式，弥合了声明式查询与命令式控制流之间的鸿沟。尽管现代 SQL 引擎不断增强集合操作能力，游标在存储过程、复杂业务逻辑处理、客户端分页以及遗留系统维护中仍然不可替代。SQL 标准从 SQL:1992 开始定义游标语义，经 SQL:1999 扩展了可滚动游标和灵敏度模型，至今仍是 RDBMS 过程化编程的基础设施之一。

## SQL 标准中的游标

### SQL:1992 基础游标模型

SQL:1992 定义了游标的基本生命周期：DECLARE -- OPEN -- FETCH -- CLOSE 四步操作。

```sql
-- SQL:1992 标准语法
DECLARE cursor_name [INSENSITIVE] [SCROLL] CURSOR FOR
    select_statement
    [FOR {READ ONLY | UPDATE [OF column_list]}];

OPEN cursor_name;

FETCH [[NEXT | PRIOR | FIRST | LAST | ABSOLUTE n | RELATIVE n] FROM]
    cursor_name INTO variable_list;

CLOSE cursor_name;
```

### SQL:1999 / SQL:2003 扩展

SQL:1999 扩充了游标灵敏度（sensitivity）模型，增加了 WITH HOLD 和 WITH RETURN 语义：

```sql
DECLARE cursor_name
    [SENSITIVE | INSENSITIVE | ASENSITIVE]
    [SCROLL | NO SCROLL]
    CURSOR
    [WITH HOLD | WITHOUT HOLD]
    [WITH RETURN [TO CALLER | TO CLIENT] | WITHOUT RETURN]
    FOR select_statement
    [FOR {READ ONLY | UPDATE [OF column_list]}];
```

关键概念：

| 概念 | 说明 |
|------|------|
| SCROLL / NO SCROLL | 是否允许非顺序的 FETCH 方向（PRIOR, FIRST, LAST, ABSOLUTE, RELATIVE） |
| SENSITIVE | 通过游标能看到底层数据的并发修改 |
| INSENSITIVE | 游标打开时创建结果快照，不可见后续修改 |
| ASENSITIVE | 由实现决定是否可见并发修改（多数引擎的默认行为） |
| WITH HOLD | 游标在事务提交后仍然保持打开状态 |
| WITH RETURN | 允许存储过程将游标作为结果集返回给调用者 |
| FOR UPDATE | 标记游标为可更新，允许通过 WHERE CURRENT OF 定位修改 |

## 支持矩阵

### 基本游标支持

| 引擎 | DECLARE CURSOR | OPEN/FETCH/CLOSE | 存储过程中游标 | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ✅ (PL/pgSQL) | 7.0+ |
| MySQL | ✅ | ✅ | ✅ (仅存储过程内) | 5.0+ |
| MariaDB | ✅ | ✅ | ✅ (仅存储过程内) | 5.0+ |
| SQLite | ❌ | ❌ | ❌ | — |
| Oracle | ✅ | ✅ | ✅ (PL/SQL) | 6.0+ |
| SQL Server | ✅ | ✅ | ✅ (T-SQL) | 6.0+ |
| DB2 | ✅ | ✅ | ✅ (SQL PL) | 7.0+ |
| Snowflake | ✅ | ✅ | ✅ (Snowflake Scripting) | 2022+ |
| BigQuery | ❌ | ❌ | ❌ | — |
| Redshift | ✅ | ✅ | ✅ (PL/pgSQL 子集) | 2019+ |
| DuckDB | ❌ | ❌ | ❌ | — |
| ClickHouse | ❌ | ❌ | ❌ | — |
| Trino | ❌ | ❌ | ❌ | — |
| Presto | ❌ | ❌ | ❌ | — |
| Spark SQL | ❌ | ❌ | ❌ | — |
| Hive | ❌ | ❌ | ❌ | — |
| Flink SQL | ❌ | ❌ | ❌ | — |
| Databricks | ❌ | ❌ | ❌ | — |
| Teradata | ✅ | ✅ | ✅ (SPL) | V2R5+ |
| Greenplum | ✅ | ✅ | ✅ (PL/pgSQL) | 4.0+ |
| CockroachDB | ✅ | ✅ | ✅ (PL/pgSQL, v23.1+) | 23.1+ |
| TiDB | ✅ | ✅ | ✅ (存储过程) | 6.5+ |
| OceanBase | ✅ | ✅ | ✅ (Oracle 模式 PL/SQL; MySQL 模式存储过程) | 3.0+ |
| YugabyteDB | ✅ | ✅ | ✅ (PL/pgSQL) | 2.0+ |
| SingleStore | ✅ | ✅ | ✅ (存储过程) | 7.0+ |
| Vertica | ❌ | ❌ | ❌ | — |
| Impala | ❌ | ❌ | ❌ | — |
| StarRocks | ❌ | ❌ | ❌ | — |
| Doris | ❌ | ❌ | ❌ | — |
| MonetDB | ❌ | ❌ | ❌ | — |
| CrateDB | ❌ | ❌ | ❌ | — |
| TimescaleDB | ✅ | ✅ | ✅ (继承 PG) | 继承 PG |
| QuestDB | ❌ | ❌ | ❌ | — |
| Exasol | ✅ | ✅ | ✅ (Lua/SQL 脚本) | 6.0+ |
| SAP HANA | ✅ | ✅ | ✅ (SQLScript) | 1.0+ |
| Informix | ✅ | ✅ | ✅ (SPL) | 7.0+ |
| Firebird | ✅ | ✅ | ✅ (PSQL) | 1.5+ |
| H2 | ❌ | ❌ | ❌ | — |
| HSQLDB | ❌ | ❌ | ❌ | — |
| Derby | ❌ | ❌ | ❌ | — |
| Amazon Athena | ❌ | ❌ | ❌ | — |
| Azure Synapse | ✅ | ✅ | ✅ (T-SQL) | GA |
| Google Spanner | ❌ | ❌ | ❌ | — |
| Materialize | ✅ | ✅ | ❌ (仅 SQL 层面协议游标) | 0.27+ |
| RisingWave | ❌ | ❌ | ❌ | — |
| InfluxDB | ❌ | ❌ | ❌ | — |
| DatabendDB | ❌ | ❌ | ❌ | — |
| Yellowbrick | ✅ | ✅ | ✅ (PL/pgSQL 兼容) | 5.0+ |
| Firebolt | ❌ | ❌ | ❌ | — |

### 可滚动游标 (Scrollable Cursors)

| 引擎 | SCROLL | NO SCROLL | 默认行为 | 版本 |
|------|:---:|:---:|------|------|
| PostgreSQL | ✅ | ✅ | NO SCROLL（除非查询本身可逆向） | 7.4+ |
| MySQL | ❌ | ❌ | 仅 NEXT（不支持 SCROLL） | — |
| MariaDB | ❌ | ❌ | 仅 NEXT（不支持 SCROLL） | — |
| Oracle | ✅ (通过 JDBC/OCI) | — | 服务端仅前向；客户端可滚动 | 8i+ |
| SQL Server | ✅ | ❌ | FORWARD_ONLY（默认） | 6.0+ |
| DB2 | ✅ | ✅ | NO SCROLL | 7.0+ |
| Snowflake | ❌ | ❌ | 仅 NEXT | — |
| Redshift | ✅ | ✅ | NO SCROLL | 2019+ |
| Teradata | ✅ | ✅ | NO SCROLL | V14+ |
| Greenplum | ✅ | ✅ | NO SCROLL | 继承 PG |
| CockroachDB | ❌ | ✅ | NO SCROLL（仅前向） | 23.1+ |
| TiDB | ❌ | ❌ | 仅 NEXT | — |
| OceanBase | ❌ | ❌ | 仅 NEXT | — |
| YugabyteDB | ✅ | ✅ | NO SCROLL | 继承 PG |
| SingleStore | ❌ | ❌ | 仅 NEXT | — |
| TimescaleDB | ✅ | ✅ | NO SCROLL | 继承 PG |
| Exasol | ❌ | ❌ | 仅 NEXT | — |
| SAP HANA | ❌ | ❌ | 仅 NEXT | — |
| Informix | ✅ | ❌ | SCROLL 需显式声明 | 7.0+ |
| Firebird | ✅ | ❌ | 仅 NEXT（SCROLL 需 3.0+） | 3.0+ |
| Azure Synapse | ✅ | ❌ | FORWARD_ONLY | GA |
| Materialize | ✅ | ✅ | NO SCROLL | 继承 PG 协议 |
| Yellowbrick | ✅ | ✅ | NO SCROLL | 继承 PG |

### 游标灵敏度 (Cursor Sensitivity)

灵敏度决定游标是否可见底层表数据在游标打开后发生的修改。

| 引擎 | SENSITIVE | INSENSITIVE | ASENSITIVE | 默认 | 说明 |
|------|:---:|:---:|:---:|------|------|
| PostgreSQL | ❌ | ✅ (隐含) | ❌ | INSENSITIVE | 游标使用 MVCC 快照，不可见后续修改 |
| MySQL | ❌ | ❌ | ✅ (隐含) | ASENSITIVE | 实现依赖，部分修改可见 |
| MariaDB | ❌ | ❌ | ✅ (隐含) | ASENSITIVE | 同 MySQL |
| Oracle | ✅ (隐含) | ❌ | ❌ | SENSITIVE | 读一致性模型，自身 DML 可见 |
| SQL Server | ✅ (KEYSET/DYNAMIC) | ✅ (STATIC) | ❌ | 取决于游标类型 | 四种游标类型对应不同灵敏度 |
| DB2 | ✅ | ✅ | ✅ | ASENSITIVE | 完全实现 SQL 标准三种模式 |
| Teradata | ❌ | ❌ | ✅ (隐含) | ASENSITIVE | — |
| Informix | ❌ | ❌ | ✅ (隐含) | ASENSITIVE | SCROLL 游标为 INSENSITIVE |
| Firebird | ❌ | ❌ | ✅ (隐含) | ASENSITIVE | PSQL 游标实现依赖 |
| SAP HANA | ❌ | ❌ | ✅ (隐含) | ASENSITIVE | — |
| Azure Synapse | ✅ (DYNAMIC) | ✅ (STATIC) | ❌ | 取决于类型 | 同 SQL Server |
| Redshift | ❌ | ✅ (隐含) | ❌ | INSENSITIVE | MVCC 快照 |
| Greenplum | ❌ | ✅ (隐含) | ❌ | INSENSITIVE | 继承 PG MVCC |
| YugabyteDB | ❌ | ✅ (隐含) | ❌ | INSENSITIVE | 继承 PG |
| TimescaleDB | ❌ | ✅ (隐含) | ❌ | INSENSITIVE | 继承 PG |
| CockroachDB | ❌ | ✅ (隐含) | ❌ | INSENSITIVE | MVCC 快照 |

### WITH HOLD (跨事务保持)

WITH HOLD 允许游标在事务提交后继续存在。这对长时间批处理和客户端分页场景至关重要。

| 引擎 | WITH HOLD | WITHOUT HOLD | 默认行为 | 说明 |
|------|:---:|:---:|------|------|
| PostgreSQL | ✅ | ✅ | WITHOUT HOLD | 提交时物化剩余结果 |
| MySQL | ❌ | ❌ | 不适用 | 存储过程内游标，无跨事务需求 |
| MariaDB | ❌ | ❌ | 不适用 | 同 MySQL |
| Oracle | ✅ (隐含) | ❌ | 默认跨事务保持 | 游标默认在 COMMIT 后存活（除非 CLOSE_CURSORS_ON_COMMIT=TRUE） |
| SQL Server | ❌ | ❌ | 事务提交自动关闭 | 使用 CURSOR_CLOSE_ON_COMMIT 选项控制 |
| DB2 | ✅ | ✅ | WITHOUT HOLD | SQL 标准兼容 |
| Redshift | ✅ | ✅ | WITHOUT HOLD | 继承 PG 语义 |
| Teradata | ✅ | ✅ | WITHOUT HOLD | — |
| Greenplum | ✅ | ✅ | WITHOUT HOLD | 继承 PG |
| CockroachDB | ❌ | ✅ | WITHOUT HOLD | 不支持 WITH HOLD |
| YugabyteDB | ✅ | ✅ | WITHOUT HOLD | 继承 PG |
| Informix | ✅ | ✅ | WITHOUT HOLD | — |
| Firebird | ❌ | ❌ | 事务结束自动关闭 | — |
| TimescaleDB | ✅ | ✅ | WITHOUT HOLD | 继承 PG |
| SAP HANA | ✅ | ✅ | WITHOUT HOLD | — |
| Materialize | ✅ | ✅ | WITHOUT HOLD | 继承 PG 协议 |
| Yellowbrick | ✅ | ✅ | WITHOUT HOLD | 继承 PG |
| Azure Synapse | ❌ | ❌ | 事务提交自动关闭 | 继承 SQL Server 行为 |

### FETCH 方向支持

| 引擎 | NEXT | PRIOR | FIRST | LAST | ABSOLUTE n | RELATIVE n |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| MySQL | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| MariaDB | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Oracle | ✅ | ❌ (服务端) | ❌ (服务端) | ❌ (服务端) | ❌ (服务端) | ❌ (服务端) |
| SQL Server | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| DB2 | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Redshift | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Teradata | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Greenplum | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| CockroachDB | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TiDB | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| OceanBase | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| YugabyteDB | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| SingleStore | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Informix | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Firebird | ✅ | ✅ (SCROLL, 3.0+) | ✅ (SCROLL, 3.0+) | ✅ (SCROLL, 3.0+) | ✅ (SCROLL, 3.0+) | ✅ (SCROLL, 3.0+) |
| SAP HANA | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Exasol | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| TimescaleDB | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Azure Synapse | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Materialize | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Yellowbrick | ✅ | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) | ✅ (SCROLL) |
| Snowflake | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 可更新游标 (FOR UPDATE / WHERE CURRENT OF)

| 引擎 | FOR UPDATE | FOR READ ONLY | WHERE CURRENT OF | 说明 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ✅ | 完整支持定位 UPDATE/DELETE |
| MySQL | ❌ | ✅ (隐含) | ❌ | 存储过程游标只读 |
| MariaDB | ❌ | ✅ (隐含) | ❌ | 同 MySQL |
| Oracle | ✅ | ❌ | ✅ | FOR UPDATE 锁定行，支持 FOR UPDATE OF col |
| SQL Server | ✅ | ✅ | ✅ | 默认 READ ONLY（优化器可升级） |
| DB2 | ✅ | ✅ | ✅ | 完整支持，可指定 OF column_list |
| Redshift | ❌ | ✅ (隐含) | ❌ | 不支持可更新游标 |
| Teradata | ✅ | ✅ | ✅ | — |
| Greenplum | ✅ | ✅ | ✅ | 继承 PG |
| CockroachDB | ❌ | ✅ (隐含) | ❌ | 不支持可更新游标 |
| YugabyteDB | ✅ | ✅ | ✅ | 继承 PG |
| Informix | ✅ | ✅ | ✅ | — |
| Firebird | ✅ | ❌ | ✅ | PSQL 中使用 AS CURSOR 语法 |
| SAP HANA | ✅ | ✅ | ✅ | — |
| TimescaleDB | ✅ | ✅ | ✅ | 继承 PG |
| TiDB | ❌ | ✅ (隐含) | ❌ | 游标只读 |
| OceanBase | ✅ (Oracle 模式) | ✅ | ✅ (Oracle 模式) | MySQL 模式不支持 |
| SingleStore | ❌ | ✅ (隐含) | ❌ | 游标只读 |
| Exasol | ❌ | ✅ (隐含) | ❌ | — |
| Snowflake | ❌ | ✅ (隐含) | ❌ | 游标只读 |
| Azure Synapse | ✅ | ✅ | ✅ | 继承 SQL Server |
| Materialize | ❌ | ✅ (隐含) | ❌ | 只读系统 |
| Yellowbrick | ✅ | ✅ | ✅ | 继承 PG |

### REF CURSOR / SYS_REFCURSOR (动态游标)

REF CURSOR 是 Oracle 引入的概念，允许将游标作为变量传递、作为参数或返回值使用。

| 引擎 | REF CURSOR | SYS_REFCURSOR | 游标类型变量 | 游标作为 OUT 参数 | 版本 |
|------|:---:|:---:|:---:|:---:|------|
| Oracle | ✅ | ✅ | ✅ | ✅ | 7.2+ |
| PostgreSQL | ✅ (refcursor 类型) | ❌ | ✅ | ✅ | 7.2+ |
| DB2 | ✅ | ✅ | ✅ | ✅ (WITH RETURN) | 9.7+ |
| SQL Server | ❌ | ❌ | ✅ (CURSOR 变量) | ✅ (OUTPUT) | 2000+ |
| MySQL | ❌ | ❌ | ❌ | ❌ | — |
| MariaDB | ❌ | ❌ | ❌ | ❌ | — |
| OceanBase | ✅ (Oracle 模式) | ✅ (Oracle 模式) | ✅ (Oracle 模式) | ✅ (Oracle 模式) | 3.0+ |
| Informix | ❌ | ❌ | ❌ | ❌ | — |
| Firebird | ❌ | ❌ | ❌ | ❌ | — |
| SAP HANA | ✅ | ✅ | ✅ | ✅ | 1.0+ |
| Greenplum | ✅ (refcursor) | ❌ | ✅ | ✅ | 继承 PG |
| YugabyteDB | ✅ (refcursor) | ❌ | ✅ | ✅ | 继承 PG |
| TimescaleDB | ✅ (refcursor) | ❌ | ✅ | ✅ | 继承 PG |
| Teradata | ❌ | ❌ | ❌ | ✅ (WITH RETURN) | V14+ |
| Redshift | ✅ (refcursor) | ❌ | ✅ | ✅ | 继承 PG |
| CockroachDB | ✅ (refcursor) | ❌ | ✅ | ✅ | 23.1+ |
| Yellowbrick | ✅ (refcursor) | ❌ | ✅ | ✅ | 继承 PG |
| Exasol | ❌ | ❌ | ❌ | ❌ | — |
| Snowflake | ❌ | ❌ | ✅ (RESULTSET) | ❌ | — |

### 隐式游标 (Implicit Cursors)

隐式游标由引擎自动管理，开发者无需显式声明。典型用途包括 FOR...IN 循环和单行 SELECT INTO。

| 引擎 | FOR...IN 循环 | SELECT INTO (单行) | 隐式属性 | 说明 |
|------|:---:|:---:|:---:|------|
| Oracle | ✅ `FOR rec IN (SELECT...)` | ✅ | ✅ SQL%FOUND/NOTFOUND/ROWCOUNT/ISOPEN | 最完整的隐式游标模型 |
| PostgreSQL | ✅ `FOR rec IN query` | ✅ | ✅ FOUND 变量 | PL/pgSQL |
| SQL Server | ❌ | ✅ | ✅ @@FETCH_STATUS / @@CURSOR_ROWS | T-SQL 无 FOR...IN 游标 |
| DB2 | ✅ `FOR rec AS cur CURSOR FOR` | ✅ | ✅ SQLCODE/SQLSTATE | SQL PL |
| MySQL | ❌ | ✅ | ✅ FOUND_ROWS() / ROW_COUNT() | 无 FOR 游标循环 |
| MariaDB | ❌ | ✅ | ✅ FOUND_ROWS() / ROW_COUNT() | 无 FOR 游标循环 |
| Snowflake | ✅ `FOR rec IN cur` | ✅ | ✅ SQLROWCOUNT | Snowflake Scripting |
| Redshift | ✅ `FOR rec IN query` | ✅ | ✅ FOUND | 继承 PG |
| Greenplum | ✅ `FOR rec IN query` | ✅ | ✅ FOUND | 继承 PG |
| OceanBase | ✅ (Oracle 模式) | ✅ | ✅ (Oracle 模式) | Oracle 模式完整支持 |
| Teradata | ✅ `FOR rec AS cur CURSOR FOR` | ✅ | ✅ ACTIVITY_COUNT | SPL |
| SAP HANA | ✅ `FOR rec AS SELECT...` | ✅ | ✅ ::ROWCOUNT | SQLScript |
| Informix | ✅ `FOREACH...END FOREACH` | ✅ | ✅ SQLCODE/SQLSTATE | SPL |
| Firebird | ✅ `FOR SELECT...INTO...DO` | ✅ | ✅ ROW_COUNT | PSQL |
| Exasol | ✅ `FOR rec IN (SELECT...)` | ✅ | ❌ | Lua 脚本 |
| YugabyteDB | ✅ `FOR rec IN query` | ✅ | ✅ FOUND | 继承 PG |
| TimescaleDB | ✅ `FOR rec IN query` | ✅ | ✅ FOUND | 继承 PG |
| CockroachDB | ✅ `FOR rec IN query` (v23.2+) | ✅ | ✅ FOUND | PL/pgSQL 兼容 |
| TiDB | ❌ | ✅ | ✅ FOUND_ROWS() | 继承 MySQL |
| SingleStore | ❌ | ✅ | ✅ ROW_COUNT() | 继承 MySQL |
| Azure Synapse | ❌ | ✅ | ✅ @@FETCH_STATUS | 继承 SQL Server |
| Yellowbrick | ✅ `FOR rec IN query` | ✅ | ✅ FOUND | 继承 PG |

### 服务端 vs 客户端游标

| 引擎 | 服务端游标 | 客户端游标 | 默认模式 | 说明 |
|------|:---:|:---:|------|------|
| PostgreSQL | ✅ | ✅ (libpq/JDBC) | 客户端 | DECLARE 为服务端；默认查询结果为客户端一次性获取 |
| MySQL | ✅ (mysql_stmt_store_result) | ✅ | 客户端 | 服务端游标通过 prepared statement 的 CURSOR_TYPE_READ_ONLY |
| MariaDB | ✅ | ✅ | 客户端 | 同 MySQL |
| Oracle | ✅ | ✅ (OCI) | 服务端 | 所有游标在服务端管理，客户端通过 prefetch 控制批量获取 |
| SQL Server | ✅ (API cursors) | ✅ (ADO/ODBC) | 客户端 | 服务端游标通过 sp_cursoropen 或 API cursor |
| DB2 | ✅ | ✅ (CLI) | 依赖接口 | CLI/JDBC 客户端游标；嵌入式 SQL 服务端游标 |
| Snowflake | ✅ | ✅ (JDBC) | 客户端 | Scripting 游标为服务端 |
| Redshift | ✅ | ✅ | 客户端 | DECLARE 为服务端 |
| SQL Server | ✅ | ✅ | 客户端 | T-SQL 游标为服务端 |
| Teradata | ✅ | ✅ (ODBC/JDBC) | 客户端 | — |
| Informix | ✅ | ✅ (ESQL/C) | 服务端 | — |
| Firebird | ✅ | ✅ | 服务端 | 所有查询结果通过服务端游标返回 |
| SAP HANA | ✅ | ✅ (JDBC/ODBC) | 客户端 | — |
| Azure Synapse | ✅ | ✅ | 客户端 | 继承 SQL Server |

### 游标变量 (Cursor Variables)

| 引擎 | 游标变量声明 | 动态绑定查询 | 作为参数传递 | 说明 |
|------|:---:|:---:|:---:|------|
| Oracle | ✅ `TYPE ref_cur IS REF CURSOR` | ✅ `OPEN cur FOR sql_string` | ✅ IN/OUT | 最灵活的游标变量模型 |
| PostgreSQL | ✅ `refcursor` 类型 | ✅ `OPEN cur FOR EXECUTE` | ✅ | PL/pgSQL |
| SQL Server | ✅ `DECLARE @cur CURSOR` | ✅ `SET @cur = CURSOR FOR` | ✅ OUTPUT | T-SQL |
| DB2 | ✅ | ✅ `ASSOCIATE LOCATORS` | ✅ | SQL PL |
| MySQL | ❌ | ❌ | ❌ | 游标必须静态声明 |
| MariaDB | ❌ | ❌ | ❌ | 同 MySQL |
| Snowflake | ✅ `RESULTSET` | ✅ `OPEN cur FOR sql` | ❌ | Scripting |
| SAP HANA | ✅ | ✅ `OPEN cur FOR sql` | ✅ | SQLScript |
| Greenplum | ✅ `refcursor` | ✅ | ✅ | 继承 PG |
| YugabyteDB | ✅ `refcursor` | ✅ | ✅ | 继承 PG |
| TimescaleDB | ✅ `refcursor` | ✅ | ✅ | 继承 PG |
| Redshift | ✅ `refcursor` | ✅ | ✅ | PG 兼容 |
| CockroachDB | ✅ `refcursor` | ✅ (v23.2+) | ✅ | PG 兼容 |
| Firebird | ❌ | ❌ | ❌ | 游标名必须静态 |
| Informix | ❌ | ✅ `PREPARE + DECLARE` | ❌ | 通过动态 SQL |
| OceanBase | ✅ (Oracle 模式) | ✅ (Oracle 模式) | ✅ (Oracle 模式) | — |
| Teradata | ❌ | ❌ | ❌ | 游标名静态 |
| Exasol | ❌ | ❌ | ❌ | — |
| Yellowbrick | ✅ `refcursor` | ✅ | ✅ | 继承 PG |

## 各引擎详细语法

### PostgreSQL

PostgreSQL 在 SQL 层面和 PL/pgSQL 层面均支持游标。SQL 层面的游标主要用于客户端分批获取大结果集。

```sql
-- SQL 层面：声明和使用游标（在事务内）
BEGIN;
DECLARE emp_cur SCROLL CURSOR WITH HOLD FOR
    SELECT id, name, salary FROM employees WHERE dept = 'ENG';

-- 逐行获取
FETCH NEXT FROM emp_cur;
FETCH PRIOR FROM emp_cur;
FETCH ABSOLUTE 5 FROM emp_cur;

-- 批量获取
FETCH 100 FROM emp_cur;             -- 前向获取 100 行
FETCH BACKWARD 10 FROM emp_cur;     -- 反向获取 10 行（需 SCROLL）
MOVE FORWARD 50 IN emp_cur;         -- 跳过 50 行，不返回数据
CLOSE emp_cur;
COMMIT;
```

```sql
-- PL/pgSQL：存储过程/函数中的游标
CREATE OR REPLACE FUNCTION process_orders()
RETURNS void AS $$
DECLARE
    -- 绑定游标（声明时绑定查询）
    order_cur CURSOR FOR
        SELECT order_id, amount FROM orders WHERE status = 'pending';
    -- 未绑定游标（参数化）
    cust_cur CURSOR (p_region TEXT) FOR
        SELECT cust_id, name FROM customers WHERE region = p_region;
    -- 游标变量（动态绑定）
    dyn_cur refcursor;
    rec RECORD;
BEGIN
    -- 绑定游标使用
    OPEN order_cur;
    LOOP
        FETCH order_cur INTO rec;
        EXIT WHEN NOT FOUND;
        UPDATE orders SET status = 'processing'
            WHERE CURRENT OF order_cur;
    END LOOP;
    CLOSE order_cur;

    -- 参数化游标
    OPEN cust_cur('APAC');
    FETCH cust_cur INTO rec;
    CLOSE cust_cur;

    -- 动态游标
    OPEN dyn_cur FOR EXECUTE
        'SELECT * FROM ' || quote_ident('audit_log')
        || ' WHERE created_at > $1'
        USING now() - interval '1 day';
    FETCH ALL FROM dyn_cur INTO rec;  -- 注意：ALL 获取所有行
    CLOSE dyn_cur;

    -- FOR 隐式游标（推荐方式）
    FOR rec IN SELECT id, name FROM employees LOOP
        RAISE NOTICE 'Employee: %, %', rec.id, rec.name;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

```sql
-- 返回 refcursor（多结果集模式）
CREATE OR REPLACE FUNCTION get_report(
    OUT cur1 refcursor,
    OUT cur2 refcursor
) AS $$
BEGIN
    OPEN cur1 FOR SELECT * FROM summary_data;
    OPEN cur2 FOR SELECT * FROM detail_data;
END;
$$ LANGUAGE plpgsql;

-- 调用端
BEGIN;
SELECT * FROM get_report();  -- 返回两个游标名称
FETCH ALL FROM "<cursor_name_1>";
FETCH ALL FROM "<cursor_name_2>";
COMMIT;
```

### MySQL / MariaDB

MySQL 和 MariaDB 的游标功能有限，仅在存储过程/函数中可用，只支持前向、只读游标。

```sql
-- MySQL 存储过程中的游标
DELIMITER //
CREATE PROCEDURE calculate_bonuses()
BEGIN
    DECLARE v_emp_id INT;
    DECLARE v_salary DECIMAL(10,2);
    DECLARE v_done INT DEFAULT 0;

    -- 声明游标
    DECLARE emp_cursor CURSOR FOR
        SELECT emp_id, salary FROM employees WHERE dept_id = 10;

    -- 声明 NOT FOUND 处理器（必须在 CURSOR 声明之后）
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN emp_cursor;

    read_loop: LOOP
        FETCH emp_cursor INTO v_emp_id, v_salary;
        IF v_done THEN
            LEAVE read_loop;
        END IF;

        -- 业务逻辑
        INSERT INTO bonuses (emp_id, bonus_amount)
        VALUES (v_emp_id, v_salary * 0.1);
    END LOOP;

    CLOSE emp_cursor;
END //
DELIMITER ;
```

MariaDB 从 10.3 开始扩展了游标能力（Oracle 兼容模式）：

```sql
-- MariaDB 10.3+ (SQL_MODE=ORACLE)
CREATE OR REPLACE PROCEDURE process_data AS
    CURSOR dept_cur IS
        SELECT dept_id, dept_name FROM departments;
    rec dept_cur%ROWTYPE;
BEGIN
    OPEN dept_cur;
    LOOP
        FETCH dept_cur INTO rec;
        EXIT WHEN dept_cur%NOTFOUND;
        -- 使用 rec.dept_id, rec.dept_name
    END LOOP;
    CLOSE dept_cur;
END;
/
```

### Oracle

Oracle PL/SQL 提供了最全面的游标支持，包括显式游标、隐式游标、REF CURSOR、游标属性和 BULK COLLECT。

```sql
-- 显式游标（基本用法）
DECLARE
    CURSOR emp_cur (p_dept NUMBER) IS
        SELECT employee_id, last_name, salary
        FROM employees
        WHERE department_id = p_dept
        FOR UPDATE OF salary;
    v_rec emp_cur%ROWTYPE;
BEGIN
    OPEN emp_cur(50);
    LOOP
        FETCH emp_cur INTO v_rec;
        EXIT WHEN emp_cur%NOTFOUND;

        IF v_rec.salary < 5000 THEN
            UPDATE employees SET salary = salary * 1.1
            WHERE CURRENT OF emp_cur;
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('处理行数: ' || emp_cur%ROWCOUNT);
    CLOSE emp_cur;
END;
/
```

```sql
-- 隐式游标与 FOR 循环（推荐方式）
BEGIN
    FOR rec IN (
        SELECT employee_id, last_name
        FROM employees
        WHERE department_id = 30
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(rec.last_name);
    END LOOP;

    -- 隐式游标属性
    UPDATE employees SET salary = salary * 1.05
    WHERE department_id = 40;
    DBMS_OUTPUT.PUT_LINE('更新行数: ' || SQL%ROWCOUNT);

    IF SQL%NOTFOUND THEN
        DBMS_OUTPUT.PUT_LINE('未找到匹配行');
    END IF;
END;
/
```

```sql
-- REF CURSOR（动态游标 / 游标变量）
CREATE OR REPLACE PACKAGE types_pkg AS
    TYPE ref_cursor_type IS REF CURSOR;
END;
/

CREATE OR REPLACE FUNCTION get_data(
    p_table_name VARCHAR2
) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
BEGIN
    OPEN v_cur FOR
        'SELECT * FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(p_table_name)
        || ' WHERE ROWNUM <= 100';
    RETURN v_cur;
END;
/

-- 调用端
DECLARE
    v_cursor SYS_REFCURSOR;
    v_id NUMBER;
    v_name VARCHAR2(100);
BEGIN
    v_cursor := get_data('EMPLOYEES');
    LOOP
        FETCH v_cursor INTO v_id, v_name;
        EXIT WHEN v_cursor%NOTFOUND;
    END LOOP;
    CLOSE v_cursor;
END;
/
```

```sql
-- BULK COLLECT（批量获取，高性能替代逐行 FETCH）
DECLARE
    CURSOR large_cur IS
        SELECT employee_id, salary FROM employees;
    TYPE emp_tab_type IS TABLE OF large_cur%ROWTYPE;
    v_batch emp_tab_type;
BEGIN
    OPEN large_cur;
    LOOP
        FETCH large_cur BULK COLLECT INTO v_batch LIMIT 1000;
        EXIT WHEN v_batch.COUNT = 0;

        FORALL i IN v_batch.FIRST .. v_batch.LAST
            UPDATE emp_audit SET processed = 'Y'
            WHERE emp_id = v_batch(i).employee_id;

        COMMIT;
    END LOOP;
    CLOSE large_cur;
END;
/
```

### SQL Server

SQL Server 提供四种游标类型，每种有不同的灵敏度和性能特征。

```sql
-- 基本游标
DECLARE @emp_id INT, @emp_name NVARCHAR(100), @salary DECIMAL(10,2);

DECLARE emp_cursor CURSOR
    LOCAL                    -- 局部游标（默认；GLOBAL 为全局）
    FORWARD_ONLY             -- 仅前向（也可用 SCROLL）
    STATIC                   -- 静态快照（也可用 KEYSET/DYNAMIC/FAST_FORWARD）
    READ_ONLY                -- 只读（也可用 SCROLL_LOCKS/OPTIMISTIC）
FOR
    SELECT emp_id, emp_name, salary
    FROM employees
    WHERE department = 'Engineering';

OPEN emp_cursor;

FETCH NEXT FROM emp_cursor INTO @emp_id, @emp_name, @salary;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT('Employee: ', @emp_name, ', Salary: ', @salary);

    FETCH NEXT FROM emp_cursor INTO @emp_id, @emp_name, @salary;
END;

CLOSE emp_cursor;
DEALLOCATE emp_cursor;     -- SQL Server 要求 DEALLOCATE 释放资源
```

SQL Server 四种游标类型对比：

```
类型           灵敏度        行集             性能          适用场景
───────────   ──────────   ───────────────  ──────────   ──────────────
STATIC        INSENSITIVE  物化到 tempdb    中等(大集合)   报表/只读
KEYSET        半敏感        键值集物化       中等          需检测删除/修改
DYNAMIC       SENSITIVE    无物化，实时读取  较慢          需看到所有变化
FAST_FORWARD  同 STATIC    前向只读优化      最快          简单遍历(推荐)
```

```sql
-- 可滚动、可更新的 KEYSET 游标
DECLARE update_cursor CURSOR
    SCROLL
    KEYSET
    SCROLL_LOCKS           -- 获取更新锁
FOR
    SELECT emp_id, salary FROM employees
    WHERE dept_id = 10
    FOR UPDATE OF salary;

OPEN update_cursor;

-- 滚动到指定位置
FETCH ABSOLUTE 5 FROM update_cursor INTO @emp_id, @salary;

-- 定位更新
UPDATE employees SET salary = @salary * 1.1
WHERE CURRENT OF update_cursor;

-- 定位删除
FETCH NEXT FROM update_cursor INTO @emp_id, @salary;
DELETE FROM employees WHERE CURRENT OF update_cursor;

CLOSE update_cursor;
DEALLOCATE update_cursor;
```

```sql
-- 游标变量
DECLARE @cur_var CURSOR;

SET @cur_var = CURSOR FORWARD_ONLY STATIC FOR
    SELECT name FROM sys.databases;

OPEN @cur_var;
-- ...使用游标...
CLOSE @cur_var;
DEALLOCATE @cur_var;
```

```sql
-- FAST_FORWARD 游标（性能最优的前向只读游标）
DECLARE fast_cur CURSOR
    LOCAL FAST_FORWARD
FOR
    SELECT order_id, total FROM orders WHERE status = 'new';

OPEN fast_cur;
FETCH NEXT FROM fast_cur INTO @order_id, @total;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- 处理逻辑
    FETCH NEXT FROM fast_cur INTO @order_id, @total;
END;
CLOSE fast_cur;
DEALLOCATE fast_cur;
```

### DB2

DB2 对 SQL 标准游标的支持最为完整，包括所有灵敏度模式和 WITH RETURN 语义。

```sql
-- SQL PL 存储过程中的游标
CREATE OR REPLACE PROCEDURE process_employees(IN p_dept INT)
LANGUAGE SQL
BEGIN
    DECLARE v_id INT;
    DECLARE v_name VARCHAR(100);
    DECLARE v_salary DECIMAL(10,2);
    DECLARE v_done INT DEFAULT 0;

    -- 声明可滚动、不敏感、WITH HOLD 游标
    DECLARE emp_cur INSENSITIVE SCROLL CURSOR WITH HOLD FOR
        SELECT emp_id, emp_name, salary
        FROM employees
        WHERE dept_id = p_dept
        FOR UPDATE OF salary;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN emp_cur;

    fetch_loop: LOOP
        FETCH NEXT FROM emp_cur INTO v_id, v_name, v_salary;
        IF v_done = 1 THEN
            LEAVE fetch_loop;
        END IF;

        IF v_salary < 50000 THEN
            UPDATE employees SET salary = salary * 1.1
                WHERE CURRENT OF emp_cur;
        END IF;
    END LOOP fetch_loop;

    CLOSE emp_cur;
END;
```

```sql
-- 使用 WITH RETURN 将游标结果返回给调用者
CREATE OR REPLACE PROCEDURE get_dept_employees(IN p_dept INT)
LANGUAGE SQL
DYNAMIC RESULT SETS 2
BEGIN
    DECLARE cur1 CURSOR WITH RETURN TO CALLER FOR
        SELECT emp_id, emp_name FROM employees WHERE dept_id = p_dept;
    DECLARE cur2 CURSOR WITH RETURN TO CLIENT FOR
        SELECT dept_name, location FROM departments WHERE dept_id = p_dept;

    OPEN cur1;
    OPEN cur2;
    -- 不关闭游标，结果集自动返回给调用者/客户端
END;
```

```sql
-- FOR 循环游标（隐式）
CREATE OR REPLACE PROCEDURE audit_salaries()
LANGUAGE SQL
BEGIN
    FOR rec AS emp_cur CURSOR FOR
        SELECT emp_id, salary FROM employees WHERE salary > 100000
    DO
        INSERT INTO salary_audit (emp_id, salary, audit_date)
        VALUES (rec.emp_id, rec.salary, CURRENT_DATE);
    END FOR;
END;
```

### Snowflake

Snowflake 在 Snowflake Scripting（2022 GA）中引入了游标支持，但功能较传统数据库有限。

```sql
-- Snowflake Scripting 游标
CREATE OR REPLACE PROCEDURE process_regions()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    region_name VARCHAR;
    region_count INT;
    -- 声明游标
    region_cur CURSOR FOR
        SELECT region, COUNT(*) AS cnt
        FROM customers
        GROUP BY region;
BEGIN
    OPEN region_cur;

    LOOP
        FETCH region_cur INTO region_name, region_count;
        IF (region_count IS NULL) THEN
            -- Snowflake 使用 NULL 检测判断无更多行
            LEAVE;
        END IF;
        -- 业务逻辑
        INSERT INTO region_summary VALUES (:region_name, :region_count);
    END LOOP;

    CLOSE region_cur;
    RETURN 'Done';
END;
$$;
```

```sql
-- RESULTSET（Snowflake 的动态游标替代方案）
CREATE OR REPLACE PROCEDURE dynamic_query(table_name VARCHAR)
RETURNS TABLE()
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
    query VARCHAR;
BEGIN
    query := 'SELECT * FROM ' || :table_name || ' LIMIT 100';
    res := (EXECUTE IMMEDIATE :query);
    RETURN TABLE(res);
END;
$$;
```

```sql
-- FOR 循环游标
CREATE OR REPLACE PROCEDURE summarize_sales()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    sales_cur CURSOR FOR SELECT product_id, SUM(amount) AS total FROM sales GROUP BY product_id;
BEGIN
    FOR rec IN sales_cur DO
        INSERT INTO sales_summary VALUES (rec.product_id, rec.total);
    END FOR;
    RETURN 'Complete';
END;
$$;
```

### Teradata

```sql
-- Teradata SPL 游标
REPLACE PROCEDURE process_orders(IN p_status VARCHAR(20))
BEGIN
    DECLARE v_order_id INTEGER;
    DECLARE v_amount DECIMAL(12,2);
    DECLARE v_sqlcode INTEGER DEFAULT 0;

    DECLARE order_cur SCROLL CURSOR WITH HOLD FOR
        SELECT order_id, amount
        FROM orders
        WHERE status = p_status
        FOR UPDATE OF status;

    DECLARE CONTINUE HANDLER FOR SQLSTATE '02000'
        SET v_sqlcode = 1;

    OPEN order_cur;

    label1: LOOP
        FETCH NEXT FROM order_cur INTO v_order_id, v_amount;
        IF v_sqlcode = 1 THEN
            LEAVE label1;
        END IF;

        UPDATE orders SET status = 'PROCESSED'
            WHERE CURRENT OF order_cur;
    END LOOP label1;

    CLOSE order_cur;
END;
```

### SAP HANA

```sql
-- SAP HANA SQLScript 游标
CREATE OR REPLACE PROCEDURE process_customers()
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE CURSOR cust_cur FOR
        SELECT customer_id, name, credit_limit
        FROM customers
        WHERE status = 'active';

    FOR rec AS cust_cur DO
        IF rec.credit_limit > 100000 THEN
            UPDATE customers SET tier = 'platinum'
                WHERE CURRENT OF cust_cur;
        END IF;
    END FOR;
END;
```

```sql
-- SAP HANA 动态游标
CREATE OR REPLACE PROCEDURE dynamic_report(IN p_table NVARCHAR(128))
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE CURSOR dyn_cur FOR
        EXEC 'SELECT * FROM ' || :p_table;

    OPEN dyn_cur;
    -- FETCH 循环处理...
    CLOSE dyn_cur;
END;
```

### Informix

```sql
-- Informix SPL 游标
CREATE PROCEDURE archive_old_orders()

    DEFINE v_order_id INTEGER;
    DEFINE v_order_date DATE;
    DEFINE v_amount DECIMAL(12,2);

    -- FOREACH 是 Informix 的隐式游标循环
    FOREACH order_cur WITH HOLD FOR
        SELECT order_id, order_date, amount
        INTO v_order_id, v_order_date, v_amount
        FROM orders
        WHERE order_date < TODAY - 365
        FOR UPDATE

        INSERT INTO orders_archive
        VALUES (v_order_id, v_order_date, v_amount);

        DELETE FROM orders WHERE CURRENT OF order_cur;

    END FOREACH;

END PROCEDURE;
```

```sql
-- 显式 SCROLL 游标
CREATE PROCEDURE scroll_demo()

    DEFINE v_name CHAR(50);

    DECLARE scroll_cur SCROLL CURSOR FOR
        SELECT name FROM customers ORDER BY name;

    OPEN scroll_cur;

    FETCH FIRST scroll_cur INTO v_name;
    FETCH LAST scroll_cur INTO v_name;
    FETCH ABSOLUTE 10 scroll_cur INTO v_name;
    FETCH RELATIVE -3 scroll_cur INTO v_name;

    CLOSE scroll_cur;

END PROCEDURE;
```

### Firebird

```sql
-- Firebird PSQL 游标
CREATE OR ALTER PROCEDURE process_inventory
RETURNS (processed_count INTEGER)
AS
    DECLARE VARIABLE v_item_id INTEGER;
    DECLARE VARIABLE v_quantity INTEGER;
    DECLARE cur_items CURSOR FOR (
        SELECT item_id, quantity FROM inventory WHERE quantity < 10
    );
BEGIN
    processed_count = 0;

    OPEN cur_items;
    WHILE (1 = 1) DO
    BEGIN
        FETCH cur_items INTO v_item_id, v_quantity;
        IF (ROW_COUNT = 0) THEN LEAVE;

        UPDATE inventory SET reorder_flag = 1
            WHERE CURRENT OF cur_items;
        processed_count = processed_count + 1;
    END
    CLOSE cur_items;

    SUSPEND;   -- 返回输出参数
END;
```

```sql
-- Firebird FOR SELECT ... AS CURSOR（隐式+命名游标）
CREATE OR ALTER PROCEDURE update_prices
AS
BEGIN
    FOR SELECT item_id, price FROM products
        WHERE category = 'electronics'
        AS CURSOR price_cur   -- 命名隐式游标，支持 WHERE CURRENT OF
    DO
    BEGIN
        UPDATE products SET price = price * 1.05
            WHERE CURRENT OF price_cur;
    END
END;
```

```sql
-- Firebird 3.0+ SCROLL 游标
CREATE OR ALTER PROCEDURE scroll_example
AS
    DECLARE v_id INTEGER;
    DECLARE cur SCROLL CURSOR FOR (
        SELECT id FROM test_table ORDER BY id
    );
BEGIN
    OPEN cur;
    FETCH FIRST FROM cur INTO v_id;
    FETCH LAST FROM cur INTO v_id;
    FETCH ABSOLUTE 5 FROM cur INTO v_id;
    FETCH RELATIVE -2 FROM cur INTO v_id;
    FETCH PRIOR FROM cur INTO v_id;
    CLOSE cur;
END;
```

### Exasol

```sql
-- Exasol 脚本中的游标
CREATE OR REPLACE SCRIPT process_data() AS
    -- Exasol 使用 Lua 风格的脚本
    local cur = query([[
        SELECT id, name, value
        FROM measurements
        WHERE status = 'pending'
    ]])

    for i = 1, #cur do
        -- cur[i].ID, cur[i].NAME, cur[i].VALUE
        query([[
            UPDATE measurements SET status = 'done'
            WHERE id = :id
        ]], {id = cur[i].ID})
    end
/

-- Exasol SQL 脚本游标 (7.0+)
CREATE OR REPLACE SCRIPT cursor_demo() AS
    FOR rec IN (SELECT dept_id, dept_name FROM departments) DO
        output(rec.DEPT_ID .. ': ' .. rec.DEPT_NAME)
    END FOR;
/
```

### Azure Synapse

Azure Synapse Analytics（专用 SQL 池）继承 SQL Server 的 T-SQL 游标语法。

```sql
-- Azure Synapse 游标（与 SQL Server 语法一致）
DECLARE @product_id INT;
DECLARE @product_name NVARCHAR(200);

DECLARE product_cursor CURSOR
    FORWARD_ONLY
    STATIC
    READ_ONLY
FOR
    SELECT product_id, product_name
    FROM dim_product
    WHERE category = 'Electronics';

OPEN product_cursor;
FETCH NEXT FROM product_cursor INTO @product_id, @product_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- 注意：Synapse 中游标性能较差，应尽量避免
    EXEC process_product @product_id, @product_name;
    FETCH NEXT FROM product_cursor INTO @product_id, @product_name;
END;

CLOSE product_cursor;
DEALLOCATE product_cursor;
```

> Synapse 专用 SQL 池支持 STATIC 和 FAST_FORWARD 游标，但不支持 DYNAMIC 和 KEYSET 类型。无服务器 SQL 池不支持游标。

### CockroachDB

CockroachDB 从 v23.1 开始引入 PL/pgSQL 游标支持。

```sql
-- CockroachDB PL/pgSQL 游标 (v23.1+)
CREATE OR REPLACE FUNCTION process_accounts()
RETURNS void AS $$
DECLARE
    acc_cur CURSOR FOR
        SELECT id, balance FROM accounts WHERE status = 'active';
    rec RECORD;
BEGIN
    OPEN acc_cur;
    LOOP
        FETCH acc_cur INTO rec;
        EXIT WHEN NOT FOUND;
        -- 处理逻辑
        RAISE NOTICE 'Account: %, Balance: %', rec.id, rec.balance;
    END LOOP;
    CLOSE acc_cur;
END;
$$ LANGUAGE plpgsql;
```

> CockroachDB 的游标仅支持 FETCH NEXT（前向），不支持 SCROLL、WITH HOLD 或 WHERE CURRENT OF。

### Materialize

Materialize 作为流式数据库，支持 PostgreSQL 协议级别的游标（DECLARE/FETCH/CLOSE），但不支持存储过程中的游标。

```sql
-- Materialize SQL 层面游标（用于增量消费变更）
BEGIN;
DECLARE changes CURSOR FOR
    SUBSCRIBE TO mv_orders WITH (PROGRESS);

-- 获取变更事件
FETCH ALL FROM changes;  -- 获取所有当前可用的变更

-- 持续获取（通常在应用循环中）
FETCH ALL FROM changes WITH (timeout = '10s');

CLOSE changes;
COMMIT;
```

> Materialize 的 SUBSCRIBE (原 TAIL) 与游标结合，提供了一种独特的流式消费模式。

## OLAP / 分布式引擎中游标缺失的原因

以下引擎不支持游标：BigQuery、DuckDB、ClickHouse、Trino、Presto、Spark SQL、Hive、Flink SQL、Databricks、Impala、StarRocks、Doris、MonetDB、CrateDB、QuestDB、Amazon Athena、Google Spanner、RisingWave、InfluxDB、DatabendDB、Firebolt、Vertica、H2、HSQLDB、Derby。

不支持游标的根本原因涉及架构和设计哲学两个层面：

```
原因分析:

1. 架构冲突
   ├─ MPP/分布式执行: 数据分布在多个节点，逐行定位成本极高
   ├─ 列式存储: 按列压缩存储，逐行读取违反存储优化方向
   ├─ 向量化执行: 批量处理是性能关键，游标的逐行模式与之冲突
   └─ 无状态查询: 多数分析引擎的工作节点无状态，无法保持游标上下文

2. 设计取舍
   ├─ 分析工作负载: 以全表扫描/聚合为主，极少需要逐行处理
   ├─ 集合操作完备: Window 函数、CTE、LATERAL 等已覆盖多数场景
   ├─ 客户端分页: 通过 LIMIT/OFFSET 或 keyset pagination 替代
   └─ 流式处理引擎: 如 Flink/RisingWave，本身就是流式的，无需游标

3. 嵌入式/轻量级引擎
   ├─ SQLite: 无存储过程，游标在应用层通过 sqlite3_step() API 实现
   ├─ DuckDB: 面向分析，通过 API 层的 result streaming 替代
   ├─ H2/HSQLDB/Derby: Java 嵌入式数据库，通过 JDBC ResultSet 提供等价功能
   └─ 这些引擎的"游标"存在于 API/驱动层而非 SQL 层
```

值得注意的几个特殊情况：

- **Vertica**：虽然是分析型数据库，但支持存储过程，却不支持 SQL 层游标。逐行处理通过其他编程接口完成。
- **Google Spanner**：虽是分布式关系型数据库，但设计上专注于全球分布式事务，不提供过程化 SQL 能力。
- **H2/HSQLDB/Derby**：作为 Java 嵌入式数据库，游标功能完全依赖 JDBC `ResultSet` 接口。在 JDBC 层面，这些引擎都支持可滚动和可更新游标（通过 `ResultSet.TYPE_SCROLL_INSENSITIVE` 和 `ResultSet.CONCUR_UPDATABLE`），但没有 SQL 层面的 DECLARE CURSOR 语法。

## 游标替代方案

对于不支持游标的引擎或追求性能优化的场景，常见替代方案如下：

| 场景 | 游标方式 | 替代方案 | 适用引擎 |
|------|---------|---------|---------|
| 逐行处理 | FETCH NEXT 循环 | Window 函数 + CTE | 所有引擎 |
| 条件更新 | WHERE CURRENT OF | UPDATE ... WHERE + 子查询 | 所有引擎 |
| 分页 | SCROLL + ABSOLUTE | LIMIT/OFFSET 或 Keyset Pagination | 所有引擎 |
| 多结果集 | REF CURSOR | 多次查询 / UNION ALL | 大多数引擎 |
| 批量处理 | FETCH + 逐行 DML | BULK COLLECT + FORALL (Oracle) / MERGE | Oracle, DB2 |
| 累计计算 | 游标变量累加 | SUM() OVER (ORDER BY ...) | 所有引擎 |
| 行间比较 | FETCH + 前一行变量 | LAG() / LEAD() 窗口函数 | 所有引擎 |

## 游标性能注意事项

各引擎对游标性能的处理有显著差异：

| 引擎 | 性能影响 | 最佳实践 |
|------|---------|---------|
| PostgreSQL | WITH HOLD 游标在 COMMIT 时物化全部结果 | 使用 FOR 循环；避免大结果集 WITH HOLD |
| Oracle | 游标在 PGA 中管理，大量打开游标消耗内存 | 使用 BULK COLLECT LIMIT；关注 OPEN_CURSORS 参数 |
| SQL Server | DYNAMIC 游标每次 FETCH 重新评估查询 | 优先使用 FAST_FORWARD；避免 DYNAMIC |
| MySQL | 游标结果在服务端临时表中物化 | 限制结果集大小；考虑应用层游标 |
| DB2 | INSENSITIVE SCROLL 游标在临时表空间中物化 | 使用 ASENSITIVE 避免不必要的物化 |
| SQL Server | KEYSET 游标在 tempdb 中存储键值 | tempdb 性能直接影响游标性能 |

Oracle 的 OPEN_CURSORS 参数限制了每个会话可同时打开的游标数量（默认 50-300），这是 Oracle 连接池和游标管理中最常见的调优参数之一。超出限制将触发 ORA-01000 错误。

## 关键发现

1. **传统 RDBMS 是游标的主要支持者**：PostgreSQL、Oracle、SQL Server、DB2、Informix、Firebird 等传统关系型数据库提供了最完整的游标支持，这与它们对过程化 SQL 的深度投入一致。

2. **MySQL/MariaDB 的游标功能有限**：仅支持前向只读游标，无 SCROLL、无 FOR UPDATE、无 WHERE CURRENT OF。MariaDB 通过 Oracle 兼容模式部分弥补了这一差距。

3. **PostgreSQL 系引擎继承完整游标能力**：YugabyteDB、Greenplum、TimescaleDB、Redshift、Yellowbrick 等基于 PostgreSQL 的引擎均继承了完整的游标支持，包括 SCROLL、WITH HOLD 和 refcursor 类型。CockroachDB 虽兼容 PostgreSQL 协议，但游标支持仍有限制（无 SCROLL、无 WITH HOLD）。

4. **SQL Server 的四种游标类型是独特设计**：STATIC/KEYSET/DYNAMIC/FAST_FORWARD 四种类型在其他引擎中没有直接对应。这种分类将灵敏度和性能特征绑定到游标类型上，提供了更细粒度的控制。

5. **DB2 的标准合规性最高**：DB2 完整实现了 SQL 标准的 SENSITIVE/INSENSITIVE/ASENSITIVE 三种灵敏度模式、WITH HOLD、WITH RETURN TO CALLER/CLIENT 语义，是标准兼容度最高的实现。

6. **Oracle 的 REF CURSOR 和 BULK COLLECT 是游标进化的方向**：REF CURSOR 允许游标作为一等公民在过程间传递，BULK COLLECT 通过批量操作解决了逐行 FETCH 的性能问题。PostgreSQL 的 refcursor 类型提供了类似能力。

7. **OLAP/分布式引擎全面缺席**：约 26 个引擎（超过一半）不支持 SQL 层面的游标。这些引擎的架构（MPP、列式存储、向量化执行）与游标的逐行处理模式存在根本冲突。

8. **游标的退出替代方案已成熟**：Window 函数（LAG/LEAD/SUM OVER）、CTE、MERGE 语句等集合操作已覆盖了原本需要游标的大多数场景。对于新系统，应优先考虑集合操作。

9. **嵌入式数据库通过 API 层提供等价功能**：SQLite (sqlite3_step)、H2/HSQLDB/Derby (JDBC ResultSet) 虽然不支持 SQL DECLARE CURSOR，但在 API 层提供了完整的逐行读取和可滚动访问能力。

10. **服务端游标的资源管理是关键挑战**：Oracle 的 OPEN_CURSORS、SQL Server 的 tempdb 占用、PostgreSQL 的 WITH HOLD 物化——各引擎都面临游标状态保持带来的内存和存储开销。生产环境中游标泄漏（未关闭）是常见的运维问题。

11. **Snowflake 代表了云数仓的折中方案**：虽然作为分析型引擎，但通过 Snowflake Scripting 提供了基本的前向只读游标，满足了 ETL 存储过程迁移的需求。RESULTSET 类型作为 REF CURSOR 的替代设计，体现了云原生的简化思路。

12. **Materialize 的游标用途独特**：将 PostgreSQL 协议游标与 SUBSCRIBE 结合，用于流式消费物化视图变更，而非传统的行级处理——这是游标语义在流处理语境下的创新应用。
