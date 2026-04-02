# 触发器 (Triggers)

触发器是数据库中自动响应数据变更或 DDL 事件而执行的过程化代码。作为声明式的事件驱动机制，触发器在数据完整性约束、审计日志、级联更新、业务规则强制执行等场景中扮演着不可替代的角色。然而在分布式 OLAP 和云数仓时代，触发器的支持度急剧分化——传统 OLTP 数据库几乎都有完整支持，而大多数分析引擎则完全不提供触发器能力。理解各引擎的差异是 SQL 引擎开发者的必备知识。

## SQL 标准中的触发器定义

SQL:1999（SQL3）标准首次引入触发器定义（ISO/IEC 9075-2, Section 11.39），SQL:2003 做了进一步细化。标准定义的核心语法如下：

```sql
CREATE TRIGGER <trigger_name>
    { BEFORE | AFTER } { INSERT | DELETE | UPDATE [ OF <column_list> ] }
    ON <table_name>
    [ REFERENCING
        { OLD [ ROW ] [ AS ] <old_name> }
        { NEW [ ROW ] [ AS ] <new_name> }
        { OLD TABLE [ AS ] <old_table_name> }
        { NEW TABLE [ AS ] <new_table_name> }
    ]
    [ FOR EACH { ROW | STATEMENT } ]
    [ WHEN ( <search_condition> ) ]
    <triggered_SQL_statement>
```

标准的关键语义：

1. **时机（Timing）**：`BEFORE` 在操作执行前触发，可修改 NEW 值或拒绝操作；`AFTER` 在操作完成后触发
2. **事件（Event）**：`INSERT`、`UPDATE`（可限定列）、`DELETE`
3. **粒度（Granularity）**：`FOR EACH ROW` 对每行触发；`FOR EACH STATEMENT` 对整个语句触发一次（默认）
4. **过渡变量（Transition Variables）**：`OLD ROW` / `NEW ROW` 引用变更前后的行；`OLD TABLE` / `NEW TABLE` 引用受影响行的集合
5. **条件子句（WHEN）**：仅当条件为真时才执行触发器体
6. **INSTEAD OF** 触发器：SQL:1999 标准未定义，但 SQL:2011 在可更新视图上下文中涉及，多数引擎作为扩展实现

> 注：SQL 标准中 `INSTEAD OF` 触发器不属于 SQL:1999 核心触发器规范的一部分，而是作为各数据库的扩展实现广泛存在。

## 支持矩阵

### 触发器时机（Timing）

| 引擎 | BEFORE | AFTER | INSTEAD OF | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ✅ (视图, 9.1+) | 7.0+ |
| MySQL | ✅ | ✅ | ❌ | 5.0.2+ |
| MariaDB | ✅ | ✅ | ❌ | 5.0+ |
| SQLite | ✅ | ✅ | ✅ (视图) | 3.0+ |
| Oracle | ✅ | ✅ | ✅ (视图) | 7.0+ |
| SQL Server | ❌ | ✅ | ✅ (视图) | 2000+ |
| DB2 | ✅ | ✅ | ✅ (视图, 9.7+) | 7.0+ |
| Snowflake | ❌ | ❌ | ❌ | -- |
| BigQuery | ❌ | ❌ | ❌ | -- |
| Redshift | ❌ | ❌ | ❌ | -- |
| DuckDB | ❌ | ❌ | ❌ | -- |
| ClickHouse | ❌ | ❌ | ❌ | -- |
| Trino | ❌ | ❌ | ❌ | -- |
| Presto | ❌ | ❌ | ❌ | -- |
| Spark SQL | ❌ | ❌ | ❌ | -- |
| Hive | ❌ | ❌ | ❌ | -- |
| Flink SQL | ❌ | ❌ | ❌ | -- |
| Databricks | ❌ | ❌ | ❌ | -- |
| Teradata | ✅ | ✅ | ❌ | V2R5+ |
| Greenplum | ✅ | ✅ | ✅ (视图) | 4.0+ |
| CockroachDB | ✅ | ✅ | ❌ | 22.2+ |
| TiDB | ❌ | ❌ | ❌ | -- |
| OceanBase | ✅ (Oracle 模式) | ✅ | ✅ (Oracle 模式) | 3.0+ |
| YugabyteDB | ✅ | ✅ | ✅ (视图) | 2.0+ |
| SingleStore | ❌ | ❌ | ❌ | -- |
| Vertica | ❌ | ❌ | ❌ | -- |
| Impala | ❌ | ❌ | ❌ | -- |
| StarRocks | ❌ | ❌ | ❌ | -- |
| Doris | ❌ | ❌ | ❌ | -- |
| MonetDB | ❌ | ❌ | ❌ | -- |
| CrateDB | ❌ | ❌ | ❌ | -- |
| TimescaleDB | ✅ | ✅ | ✅ (视图) | 继承 PG |
| QuestDB | ❌ | ❌ | ❌ | -- |
| Exasol | ❌ | ❌ | ❌ | -- |
| SAP HANA | ✅ | ✅ | ✅ (视图, 2.0+) | 1.0+ |
| Informix | ✅ | ✅ | ❌ | 7.3+ |
| Firebird | ✅ | ✅ | ❌ | 1.0+ |
| H2 | ✅ | ✅ | ✅ | 1.0+ |
| HSQLDB | ✅ | ✅ | ✅ | 2.0+ |
| Derby | ✅ | ✅ | ❌ | 10.1+ |
| Amazon Athena | ❌ | ❌ | ❌ | -- |
| Azure Synapse | ❌ | ❌ | ❌ | -- |
| Google Spanner | ❌ | ❌ | ❌ | -- |
| Materialize | ❌ | ❌ | ❌ | -- |
| RisingWave | ❌ | ❌ | ❌ | -- |
| InfluxDB | ❌ | ❌ | ❌ | -- |
| DatabendDB | ❌ | ❌ | ❌ | -- |
| Yellowbrick | ❌ | ❌ | ❌ | -- |
| Firebolt | ❌ | ❌ | ❌ | -- |

> 统计：约 19 个引擎支持某种形式的触发器，约 30 个引擎完全不支持。SQL Server 是唯一不支持 BEFORE 触发器的主流 OLTP 数据库，但通过 INSTEAD OF 触发器可实现类似效果。

### 触发事件（Event）

| 引擎 | INSERT | UPDATE | DELETE | UPDATE OF col | 多事件合并 | TRUNCATE | 版本 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ✅ | ✅ | ✅ `INSERT OR UPDATE` | ✅ (9.0+) | 7.0+ |
| MySQL | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | 5.0.2+ |
| MariaDB | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | 5.0+ |
| SQLite | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 3.0+ |
| Oracle | ✅ | ✅ | ✅ | ✅ | ✅ `INSERT OR UPDATE` | ❌ | 7.0+ |
| SQL Server | ✅ | ✅ | ✅ | ✅ (via UPDATE()) | ✅ `INSERT, UPDATE` | ❌ | 2000+ |
| DB2 | ✅ | ✅ | ✅ | ✅ | ✅ `INSERT OR UPDATE` | ❌ | 7.0+ |
| Teradata | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | V2R5+ |
| Greenplum | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 4.0+ |
| CockroachDB | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | 22.2+ |
| OceanBase | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | 3.0+ |
| YugabyteDB | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 2.0+ |
| TimescaleDB | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 继承 PG |
| SAP HANA | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | 1.0+ |
| Informix | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 7.3+ |
| Firebird | ✅ | ✅ | ✅ | ❌ | ✅ `INSERT OR UPDATE` | ❌ | 1.0+ |
| H2 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | 1.0+ |
| HSQLDB | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 2.0+ |
| Derby | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 10.1+ |

> 注：MySQL/MariaDB 每个表的每种 timing + event 组合只能定义一个触发器（MySQL 5.7.2 之前），MySQL 5.7.2+ 和 MariaDB 10.2.3+ 取消了此限制。PostgreSQL 的 TRUNCATE 触发器仅支持语句级 (FOR EACH STATEMENT)。

### 行级 vs 语句级触发器

| 引擎 | FOR EACH ROW | FOR EACH STATEMENT | 默认 | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | STATEMENT | 7.0+ |
| MySQL | ✅ | ❌ | ROW（唯一选项） | 5.0.2+ |
| MariaDB | ✅ | ❌ | ROW（唯一选项） | 5.0+ |
| SQLite | ✅ | ❌ | ROW（唯一选项） | 3.0+ |
| Oracle | ✅ | ✅ | STATEMENT | 7.0+ |
| SQL Server | ❌ (通过 INSERTED/DELETED 表间接实现) | ✅ | STATEMENT（唯一选项） | 2000+ |
| DB2 | ✅ | ✅ | STATEMENT | 7.0+ |
| Teradata | ✅ | ✅ | ROW | V2R5+ |
| Greenplum | ✅ | ✅ | STATEMENT | 4.0+ |
| CockroachDB | ✅ | ✅ | STATEMENT | 22.2+ |
| OceanBase | ✅ | ✅ | STATEMENT | 3.0+ |
| YugabyteDB | ✅ | ✅ | STATEMENT | 2.0+ |
| TimescaleDB | ✅ | ✅ | STATEMENT | 继承 PG |
| SAP HANA | ✅ | ✅ | ROW | 1.0+ |
| Informix | ✅ | ✅ | STATEMENT | 7.3+ |
| Firebird | ❌ | ❌ (隐式逐行) | ROW（隐式） | 1.0+ |
| H2 | ✅ | ❌ | ROW | 1.0+ |
| HSQLDB | ✅ | ✅ | STATEMENT | 2.0+ |
| Derby | ✅ | ✅ | STATEMENT | 10.1+ |

> 注：SQL Server 的触发器始终是语句级的，但通过特殊的 `INSERTED` 和 `DELETED` 伪表可访问所有受影响的行集合，这使得它实际上能处理行级逻辑。Firebird 触发器没有显式的 FOR EACH ROW/STATEMENT 语法，其触发器体总是对每一行执行。

### DDL 触发器

| 引擎 | DDL 触发器 | 支持的事件 | 版本 |
|------|:---:|------|------|
| PostgreSQL | ✅ (事件触发器) | `ddl_command_start`, `ddl_command_end`, `table_rewrite`, `sql_drop` | 9.3+ |
| MySQL | ❌ | -- | -- |
| MariaDB | ❌ | -- | -- |
| SQLite | ❌ | -- | -- |
| Oracle | ✅ | `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `GRANT`, `REVOKE`, `LOGON`, `LOGOFF`, `STARTUP`, `SHUTDOWN` 等 | 8i+ |
| SQL Server | ✅ | `CREATE_TABLE`, `ALTER_TABLE`, `DROP_TABLE`, `CREATE_INDEX` 等，支持数据库级和服务器级 | 2005+ |
| DB2 | ❌ | -- | -- |
| Teradata | ❌ | -- | -- |
| SAP HANA | ❌ | -- | -- |
| Informix | ❌ | -- | -- |
| Firebird | ❌ | -- | -- |
| CockroachDB | ❌ | -- | -- |
| YugabyteDB | ✅ (事件触发器) | 继承 PostgreSQL 事件触发器 | 2.0+ |
| TimescaleDB | ✅ (事件触发器) | 继承 PostgreSQL 事件触发器 | 继承 PG |
| Greenplum | ✅ (事件触发器) | 继承 PostgreSQL 事件触发器 | 6.0+ |
| OceanBase | ✅ (Oracle 模式) | `CREATE`, `ALTER`, `DROP` 等 | 3.0+ |
| HSQLDB | ❌ | -- | -- |
| H2 | ❌ | -- | -- |
| Derby | ❌ | -- | -- |

> 注：PostgreSQL 使用独立的 `CREATE EVENT TRIGGER` 语法而非 `CREATE TRIGGER`。Oracle 的 DDL 触发器可以定义在 `DATABASE` 或 `SCHEMA` 级别。SQL Server 的 DDL 触发器最为丰富，可以在数据库级或服务器级创建，还支持 LOGON 触发器。

### WHEN 条件子句

| 引擎 | WHEN 子句 | 语法 | 版本 |
|------|:---:|------|------|
| PostgreSQL | ✅ | `WHEN (NEW.status = 'active')` | 9.0+ |
| MySQL | ❌ | 在触发器体内用 IF 模拟 | -- |
| MariaDB | ❌ | 在触发器体内用 IF 模拟 | -- |
| SQLite | ✅ | `WHEN NEW.amount > 1000` | 3.0+ |
| Oracle | ✅ | `WHEN (NEW.salary > 100000)` — 不带冒号前缀 | 7.0+ |
| SQL Server | ❌ | 在触发器体内用 IF 模拟 | -- |
| DB2 | ✅ | `WHEN (N.status = 'X')` | 9.7+ |
| Teradata | ✅ | `WHEN (NEW.col > value)` | V2R5+ |
| Greenplum | ✅ | 继承 PostgreSQL | 4.0+ |
| CockroachDB | ✅ | 继承 PostgreSQL | 22.2+ |
| OceanBase | ✅ | `WHEN (NEW.col > value)` | 3.0+ |
| YugabyteDB | ✅ | 继承 PostgreSQL | 2.0+ |
| TimescaleDB | ✅ | 继承 PostgreSQL | 继承 PG |
| SAP HANA | ❌ | 在触发器体内用 IF 模拟 | -- |
| Informix | ✅ | `WHEN (NEW.col > value)` | 11.50+ |
| Firebird | ❌ | 在触发器体内用 IF 模拟 | -- |
| H2 | ❌ | 在触发器体内用 IF 模拟 | -- |
| HSQLDB | ✅ | `WHEN (NEW.col > value)` | 2.3+ |
| Derby | ❌ | 在触发器体内用 IF 模拟 | -- |

### NEW / OLD 伪记录引用方式

| 引擎 | 行级引用语法 | 语句级/集合引用 | 自定义别名 | 版本 |
|------|------|------|:---:|------|
| PostgreSQL | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` (10+) | ✅ `REFERENCING` | 7.0+ |
| MySQL | `NEW.col` / `OLD.col` | -- | ❌ | 5.0.2+ |
| MariaDB | `NEW.col` / `OLD.col` | -- | ❌ | 5.0+ |
| SQLite | `NEW.col` / `OLD.col` | -- | ❌ | 3.0+ |
| Oracle | `:NEW.col` / `:OLD.col` | -- | ✅ `REFERENCING NEW AS n OLD AS o` | 7.0+ |
| SQL Server | -- | `INSERTED` / `DELETED` 伪表 | ❌ (固定名称) | 2000+ |
| DB2 | `N.col` / `O.col` (自定义) | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | 7.0+ |
| Teradata | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | V2R5+ |
| Greenplum | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | 4.0+ |
| CockroachDB | `NEW.col` / `OLD.col` | -- | ❌ | 22.2+ |
| OceanBase | `:NEW.col` / `:OLD.col` | -- | ✅ `REFERENCING` | 3.0+ |
| YugabyteDB | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | 2.0+ |
| TimescaleDB | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | 继承 PG |
| SAP HANA | `:NEW.col` / `:OLD.col` | `NEW TABLE ntt` / `OLD TABLE ott` | ✅ | 1.0+ |
| Informix | `NEW.col` / `OLD.col` | -- | ✅ `REFERENCING` | 7.3+ |
| Firebird | `NEW.col` / `OLD.col` | -- | ❌ | 1.0+ |
| H2 | `NEW.col` / `OLD.col` | -- | ❌ | 1.0+ |
| HSQLDB | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | 2.0+ |
| Derby | `NEW.col` / `OLD.col` | `NEW TABLE AS nt` / `OLD TABLE AS ot` | ✅ `REFERENCING` | 10.1+ |

> 注：Oracle 在 WHEN 子句中使用 `NEW.col`（不带冒号），在触发器体内使用 `:NEW.col`（带冒号），这是一个常见的混淆点。SQL Server 没有行级 NEW/OLD 概念，完全依赖集合式的 INSERTED/DELETED 伪表。DB2 要求通过 REFERENCING 子句显式定义别名（如 `REFERENCING NEW AS N OLD AS O`），不能直接使用 NEW/OLD。

### 多触发器排序

| 引擎 | 同事件多触发器 | 排序机制 | 版本 |
|------|:---:|------|------|
| PostgreSQL | ✅ | 按名称字母序执行 | 7.0+ |
| MySQL | ✅ (5.7.2+) | `FOLLOWS` / `PRECEDES` 关键字 | 5.7.2+ |
| MariaDB | ✅ (10.2.3+) | `FOLLOWS` / `PRECEDES` 关键字 | 10.2.3+ |
| SQLite | ✅ | 按创建顺序执行 | 3.0+ |
| Oracle | ✅ | `FOLLOWS` / `PRECEDES` 关键字 (11g+) | 11g+ |
| SQL Server | ✅ | `sp_settriggerorder` 指定 FIRST / LAST | 2000+ |
| DB2 | ✅ | 按创建顺序执行 | 7.0+ |
| Teradata | ✅ | `ORDER n` 子句指定顺序号 | V2R5+ |
| Greenplum | ✅ | 按名称字母序执行 | 4.0+ |
| CockroachDB | ✅ | 按名称字母序执行 | 22.2+ |
| OceanBase | ✅ | `FOLLOWS` / `PRECEDES` | 3.0+ |
| YugabyteDB | ✅ | 按名称字母序执行 | 2.0+ |
| TimescaleDB | ✅ | 按名称字母序执行 | 继承 PG |
| SAP HANA | ✅ | 按创建顺序执行 | 1.0+ |
| Informix | ✅ | 按创建顺序执行 | 7.3+ |
| Firebird | ✅ | `POSITION n` 子句 (0-32767) | 1.0+ |
| H2 | ✅ | 按创建顺序执行 | 1.0+ |
| HSQLDB | ✅ | 按创建顺序执行 | 2.0+ |
| Derby | ✅ | 按创建顺序执行 | 10.1+ |

### 递归 / 嵌套触发器

| 引擎 | 嵌套触发器 | 递归触发器 | 最大嵌套深度 | 控制方式 |
|------|:---:|:---:|------|------|
| PostgreSQL | ✅ | ✅ | 无固定限制（栈深度限制） | -- |
| MySQL | ✅ | ❌ (同一触发器不递归) | 依赖 `thread_stack` | -- |
| MariaDB | ✅ | ❌ (同一触发器不递归) | 依赖 `thread_stack` | -- |
| SQLite | ✅ | ✅ | `SQLITE_MAX_TRIGGER_DEPTH` (默认 1000) | 编译期常量 |
| Oracle | ✅ | ✅ (需避免 ORA-04091 变异表错误) | 32 | -- |
| SQL Server | ✅ | ✅ (可选) | 32 | `RECURSIVE_TRIGGERS` 数据库选项 |
| DB2 | ✅ | ✅ | 16 | -- |
| Teradata | ✅ | ✅ | 16 | -- |
| SAP HANA | ✅ | ✅ | 64 | -- |
| Informix | ✅ | ✅ | 63 | -- |
| Firebird | ✅ | ✅ | 32 | -- |
| CockroachDB | ✅ | ❌ | -- | -- |
| YugabyteDB | ✅ | ✅ | 继承 PostgreSQL | -- |
| Greenplum | ✅ | ✅ | 继承 PostgreSQL | -- |
| TimescaleDB | ✅ | ✅ | 继承 PostgreSQL | -- |

> 注：Oracle 的变异表（mutating table）限制是行级触发器不能查询或修改自身触发表，这在实践中经常导致 ORA-04091 错误。常见解决方案是使用复合触发器（COMPOUND TRIGGER, 11g+）或将逻辑转移到语句级触发器。

### ENABLE / DISABLE 触发器

| 引擎 | 支持 | 语法 | 版本 |
|------|:---:|------|------|
| PostgreSQL | ✅ | `ALTER TABLE t ENABLE/DISABLE TRIGGER name/ALL/USER` | 8.1+ |
| MySQL | ❌ | -- | -- |
| MariaDB | ❌ | -- | -- |
| SQLite | ❌ | -- | -- |
| Oracle | ✅ | `ALTER TRIGGER name ENABLE/DISABLE` 或 `ALTER TABLE t ENABLE/DISABLE ALL TRIGGERS` | 8i+ |
| SQL Server | ✅ | `ENABLE/DISABLE TRIGGER name ON table` 或 `ENABLE/DISABLE TRIGGER ALL ON table` | 2005+ |
| DB2 | ✅ | `ALTER TRIGGER name SECURED/NOT SECURED`; 通过 `SET INTEGRITY` 间接控制 | 10.1+ |
| Teradata | ✅ | `ALTER TRIGGER name ENABLED/DISABLED` | V2R5+ |
| Greenplum | ✅ | 继承 PostgreSQL | 4.0+ |
| CockroachDB | ✅ | 继承 PostgreSQL | 22.2+ |
| OceanBase | ✅ | `ALTER TRIGGER name ENABLE/DISABLE` | 3.0+ |
| YugabyteDB | ✅ | 继承 PostgreSQL | 2.0+ |
| TimescaleDB | ✅ | 继承 PostgreSQL | 继承 PG |
| SAP HANA | ✅ | `ALTER TRIGGER name ENABLE/DISABLE` | 1.0+ |
| Informix | ✅ | `SET TRIGGERS name ENABLED/DISABLED` | 11.10+ |
| Firebird | ✅ | `ALTER TRIGGER name ACTIVE/INACTIVE` | 1.5+ |
| H2 | ❌ | -- | -- |
| HSQLDB | ❌ | -- | -- |
| Derby | ✅ | `ALTER TABLE t NO TRIGGERS / ALL TRIGGERS` (非标准) | -- |

### CREATE OR REPLACE TRIGGER

| 引擎 | 支持 | 版本 |
|------|:---:|------|
| PostgreSQL | ✅ | 14+ |
| MySQL | ❌ (需 DROP + CREATE) | -- |
| MariaDB | ✅ | 10.1.4+ |
| SQLite | ❌ (需 DROP + CREATE) | -- |
| Oracle | ✅ | 7.0+ |
| SQL Server | ✅ `CREATE OR ALTER` | 2016 SP1+ |
| DB2 | ✅ | 11.1+ |
| Teradata | ✅ `REPLACE TRIGGER` | V2R5+ |
| Greenplum | ✅ | 继承 PG 14+ |
| CockroachDB | ❌ | -- |
| OceanBase | ✅ | 3.0+ |
| YugabyteDB | ✅ | 继承 PG |
| TimescaleDB | ✅ | 继承 PG 14+ |
| SAP HANA | ✅ | 1.0+ |
| Informix | ❌ (需 DROP + CREATE) | -- |
| Firebird | ✅ | 2.1+ |
| H2 | ❌ | -- |
| HSQLDB | ❌ | -- |
| Derby | ❌ | -- |

## 综合支持概览

下表总结了所有 49 个引擎的触发器支持等级：

| 引擎 | 触发器支持 | 支持等级 |
|------|:---:|------|
| PostgreSQL | ✅ | 完整（DML + DDL 事件触发器 + 行级/语句级 + WHEN + TRUNCATE） |
| Oracle | ✅ | 完整（DML + DDL + LOGON + 复合触发器 + FOLLOWS/PRECEDES） |
| SQL Server | ✅ | 完整（DML AFTER/INSTEAD OF + DDL + LOGON + 服务器级） |
| DB2 | ✅ | 完整（DML + INSTEAD OF + 行/语句级 + REFERENCING） |
| MySQL | ✅ | 基本（仅 DML 行级 BEFORE/AFTER，5.7.2+ 多触发器） |
| MariaDB | ✅ | 基本（同 MySQL，10.2.3+ 多触发器，支持 OR REPLACE） |
| SQLite | ✅ | 基本（DML + INSTEAD OF + WHEN，仅行级） |
| Teradata | ✅ | 较完整（DML + 行/语句级 + ORDER 排序） |
| SAP HANA | ✅ | 较完整（DML + INSTEAD OF + 行/语句级） |
| Informix | ✅ | 较完整（DML + 行/语句级） |
| Firebird | ✅ | 基本（DML + POSITION 排序，隐式行级） |
| Greenplum | ✅ | 完整（继承 PostgreSQL） |
| CockroachDB | ✅ | 较完整（DML + 行/语句级 + WHEN，22.2+） |
| OceanBase | ✅ | 较完整（Oracle 模式下支持 DML + DDL 触发器） |
| YugabyteDB | ✅ | 完整（继承 PostgreSQL） |
| TimescaleDB | ✅ | 完整（继承 PostgreSQL） |
| H2 | ✅ | 基本（DML + INSTEAD OF） |
| HSQLDB | ✅ | 较完整（DML + INSTEAD OF + 行/语句级 + WHEN） |
| Derby | ✅ | 基本（DML + 行/语句级） |
| Snowflake | ❌ | 不支持 |
| BigQuery | ❌ | 不支持 |
| Redshift | ❌ | 不支持 |
| DuckDB | ❌ | 不支持 |
| ClickHouse | ❌ | 不支持 |
| Trino | ❌ | 不支持 |
| Presto | ❌ | 不支持 |
| Spark SQL | ❌ | 不支持 |
| Hive | ❌ | 不支持 |
| Flink SQL | ❌ | 不支持 |
| Databricks | ❌ | 不支持 |
| SingleStore | ❌ | 不支持 |
| Vertica | ❌ | 不支持 |
| Impala | ❌ | 不支持 |
| StarRocks | ❌ | 不支持 |
| Doris | ❌ | 不支持 |
| MonetDB | ❌ | 不支持 |
| CrateDB | ❌ | 不支持 |
| QuestDB | ❌ | 不支持 |
| Exasol | ❌ | 不支持 |
| TiDB | ❌ | 不支持（MySQL 兼容层未实现触发器） |
| Amazon Athena | ❌ | 不支持 |
| Azure Synapse | ❌ | 不支持 |
| Google Spanner | ❌ | 不支持 |
| Materialize | ❌ | 不支持 |
| RisingWave | ❌ | 不支持 |
| InfluxDB | ❌ | 不支持 |
| DatabendDB | ❌ | 不支持 |
| Yellowbrick | ❌ | 不支持 |
| Firebolt | ❌ | 不支持 |

## 各引擎语法详解

### PostgreSQL（最接近 SQL 标准 + 事件触发器扩展）

PostgreSQL 的触发器实现分为两步：先创建触发器函数（返回 `TRIGGER` 类型），再创建触发器将函数绑定到表。

```sql
-- 步骤 1: 创建触发器函数
CREATE OR REPLACE FUNCTION audit_log_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(table_name, action, new_data, ts)
        VALUES (TG_TABLE_NAME, 'INSERT', row_to_json(NEW), now());
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log(table_name, action, old_data, new_data, ts)
        VALUES (TG_TABLE_NAME, 'UPDATE', row_to_json(OLD), row_to_json(NEW), now());
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log(table_name, action, old_data, ts)
        VALUES (TG_TABLE_NAME, 'DELETE', row_to_json(OLD), now());
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 步骤 2: 创建触发器
CREATE TRIGGER trg_orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_func();

-- BEFORE 触发器：修改数据
CREATE TRIGGER trg_normalize_email
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION normalize_email_func();

-- WHEN 条件子句（9.0+）
CREATE TRIGGER trg_high_value
    AFTER INSERT ON orders
    FOR EACH ROW
    WHEN (NEW.amount > 10000)
    EXECUTE FUNCTION notify_high_value();

-- INSTEAD OF 触发器（仅视图）
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON order_summary_view
    FOR EACH ROW
    EXECUTE FUNCTION handle_view_insert();

-- TRUNCATE 触发器（9.0+，仅语句级）
CREATE TRIGGER trg_truncate_audit
    AFTER TRUNCATE ON orders
    FOR EACH STATEMENT
    EXECUTE FUNCTION log_truncate();

-- 过渡表 (Transition Tables, 10+)
CREATE TRIGGER trg_batch_audit
    AFTER UPDATE ON orders
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION batch_audit_func();

-- ENABLE / DISABLE
ALTER TABLE orders DISABLE TRIGGER trg_orders_audit;
ALTER TABLE orders ENABLE TRIGGER trg_orders_audit;
ALTER TABLE orders DISABLE TRIGGER ALL;  -- 禁用所有触发器
ALTER TABLE orders DISABLE TRIGGER USER; -- 仅禁用用户触发器，保留系统触发器

-- 事件触发器（DDL，9.3+）
CREATE EVENT TRIGGER log_ddl
    ON ddl_command_end
    EXECUTE FUNCTION log_ddl_func();

-- CREATE OR REPLACE TRIGGER（14+）
CREATE OR REPLACE TRIGGER trg_orders_audit
    AFTER INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION audit_log_func();
```

PostgreSQL 触发器特有变量：`TG_OP`（操作类型）、`TG_TABLE_NAME`（表名）、`TG_WHEN`（BEFORE/AFTER/INSTEAD OF）、`TG_LEVEL`（ROW/STATEMENT）、`TG_NARGS` / `TG_ARGV`（触发器参数）。

### MySQL / MariaDB

```sql
-- 基本 BEFORE 触发器
CREATE TRIGGER trg_before_insert_orders
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
    SET NEW.updated_at = NOW();
    IF NEW.amount < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Amount cannot be negative';
    END IF;
END;

-- AFTER 触发器用于审计
CREATE TRIGGER trg_after_update_orders
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO order_audit(order_id, old_status, new_status, changed_at)
    VALUES (OLD.id, OLD.status, NEW.status, NOW());
END;

-- DELETE 触发器
CREATE TRIGGER trg_after_delete_orders
AFTER DELETE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO deleted_orders_log(order_id, amount, deleted_at)
    VALUES (OLD.id, OLD.amount, NOW());
END;

-- MySQL 5.7.2+ / MariaDB 10.2.3+: 同一事件多个触发器
CREATE TRIGGER trg_second_before_insert
BEFORE INSERT ON orders
FOR EACH ROW
FOLLOWS trg_before_insert_orders  -- 在 trg_before_insert_orders 之后执行
BEGIN
    SET NEW.order_number = CONCAT('ORD-', LPAD(NEW.id, 8, '0'));
END;

-- MariaDB: CREATE OR REPLACE (10.1.4+)
CREATE OR REPLACE TRIGGER trg_before_insert_orders
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
END;

-- 限制: MySQL/MariaDB 不支持语句级触发器、INSTEAD OF 触发器、
-- WHEN 条件子句、TRUNCATE 触发器、DDL 触发器
-- 条件逻辑必须在触发器体内用 IF 实现
```

### Oracle（最丰富的触发器类型）

```sql
-- 基本行级触发器
CREATE OR REPLACE TRIGGER trg_orders_audit
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
DECLARE
    v_action VARCHAR2(10);
BEGIN
    IF INSERTING THEN v_action := 'INSERT';
    ELSIF UPDATING THEN v_action := 'UPDATE';
    ELSIF DELETING THEN v_action := 'DELETE';
    END IF;

    INSERT INTO audit_log(table_name, action, old_val, new_val, changed_by, changed_at)
    VALUES ('ORDERS', v_action,
            :OLD.amount, :NEW.amount,
            SYS_CONTEXT('USERENV', 'SESSION_USER'), SYSTIMESTAMP);
END;
/

-- 语句级触发器
CREATE OR REPLACE TRIGGER trg_orders_stmt
BEFORE INSERT ON orders
-- Oracle 语句级：省略 FOR EACH ROW 即为语句级（不使用 FOR EACH STATEMENT 关键字）
BEGIN
    -- 语句级逻辑：例如检查时间窗口
    IF TO_CHAR(SYSDATE, 'HH24') NOT BETWEEN '08' AND '18' THEN
        RAISE_APPLICATION_ERROR(-20001, 'Orders only accepted during business hours');
    END IF;
END;
/

-- WHEN 条件子句（注意：WHEN 中用 NEW 不带冒号，体内用 :NEW 带冒号）
CREATE OR REPLACE TRIGGER trg_high_salary
AFTER UPDATE OF salary ON employees
FOR EACH ROW
WHEN (NEW.salary > 100000)
BEGIN
    INSERT INTO salary_audit VALUES (:OLD.employee_id, :OLD.salary, :NEW.salary, SYSDATE);
END;
/

-- INSTEAD OF 触发器（视图）
CREATE OR REPLACE TRIGGER trg_emp_view
INSTEAD OF INSERT ON employee_department_view
FOR EACH ROW
BEGIN
    INSERT INTO employees(id, name) VALUES (:NEW.emp_id, :NEW.emp_name);
    INSERT INTO departments(id, name) VALUES (:NEW.dept_id, :NEW.dept_name);
END;
/

-- 复合触发器 (COMPOUND TRIGGER, 11g+) — 解决变异表问题
CREATE OR REPLACE TRIGGER trg_compound_orders
FOR INSERT OR UPDATE ON orders
COMPOUND TRIGGER
    TYPE t_order_ids IS TABLE OF orders.id%TYPE;
    v_order_ids t_order_ids := t_order_ids();

    BEFORE STATEMENT IS
    BEGIN
        v_order_ids.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        v_order_ids.EXTEND;
        v_order_ids(v_order_ids.COUNT) := :NEW.id;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        FOR i IN 1..v_order_ids.COUNT LOOP
            -- 在语句级安全地查询触发表
            UPDATE order_summary SET total = (
                SELECT SUM(amount) FROM orders WHERE customer_id = v_order_ids(i)
            );
        END LOOP;
    END AFTER STATEMENT;
END trg_compound_orders;
/

-- 触发器排序 (11g+)
CREATE OR REPLACE TRIGGER trg_second
AFTER INSERT ON orders
FOR EACH ROW
FOLLOWS trg_orders_audit  -- 在 trg_orders_audit 之后执行
BEGIN
    NULL;
END;
/

-- DDL 触发器
CREATE OR REPLACE TRIGGER trg_ddl_audit
AFTER DDL ON SCHEMA
BEGIN
    INSERT INTO ddl_log(event, object_type, object_name, sql_text, username, ts)
    VALUES (ORA_SYSEVENT, ORA_DICT_OBJ_TYPE, ORA_DICT_OBJ_NAME,
            NULL, ORA_LOGIN_USER, SYSTIMESTAMP);
END;
/

-- 数据库级 LOGON 触发器
CREATE OR REPLACE TRIGGER trg_logon_audit
AFTER LOGON ON DATABASE
BEGIN
    INSERT INTO login_log(username, login_time, ip_addr)
    VALUES (SYS_CONTEXT('USERENV','SESSION_USER'), SYSDATE,
            SYS_CONTEXT('USERENV','IP_ADDRESS'));
END;
/

-- ENABLE / DISABLE
ALTER TRIGGER trg_orders_audit DISABLE;
ALTER TRIGGER trg_orders_audit ENABLE;
ALTER TABLE orders DISABLE ALL TRIGGERS;
ALTER TABLE orders ENABLE ALL TRIGGERS;
```

Oracle 特有能力：`INSERTING` / `UPDATING` / `DELETING` 布尔函数、`UPDATING('column_name')` 检测特定列变更、`COMPOUND TRIGGER`（11g+）解决变异表问题、DDL/LOGON/LOGOFF/STARTUP/SHUTDOWN 系统触发器。

### SQL Server（语句级 + INSERTED/DELETED 伪表模型）

```sql
-- AFTER INSERT 触发器（SQL Server 不支持 BEFORE）
CREATE TRIGGER trg_orders_audit
ON orders
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit_log(order_id, action, amount, created_at)
    SELECT id, 'INSERT', amount, GETDATE()
    FROM INSERTED;  -- INSERTED 伪表包含所有新插入的行
END;
GO

-- AFTER UPDATE 触发器
CREATE TRIGGER trg_orders_update
ON orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- INSERTED 包含更新后的行，DELETED 包含更新前的行
    INSERT INTO audit_log(order_id, action, old_amount, new_amount, changed_at)
    SELECT i.id, 'UPDATE', d.amount, i.amount, GETDATE()
    FROM INSERTED i
    INNER JOIN DELETED d ON i.id = d.id;
END;
GO

-- AFTER DELETE 触发器
CREATE TRIGGER trg_orders_delete
ON orders
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO deleted_orders(order_id, amount, deleted_at)
    SELECT id, amount, GETDATE()
    FROM DELETED;  -- DELETED 伪表包含所有被删除的行
END;
GO

-- 多事件触发器
CREATE TRIGGER trg_orders_all
ON orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM INSERTED) AND EXISTS(SELECT 1 FROM DELETED)
        -- UPDATE
        INSERT INTO audit_log(action) VALUES ('UPDATE');
    ELSE IF EXISTS(SELECT 1 FROM INSERTED)
        -- INSERT
        INSERT INTO audit_log(action) VALUES ('INSERT');
    ELSE
        -- DELETE
        INSERT INTO audit_log(action) VALUES ('DELETE');
END;
GO

-- INSTEAD OF 触发器（视图）
CREATE TRIGGER trg_view_insert
ON vw_order_summary
INSTEAD OF INSERT
AS
BEGIN
    INSERT INTO orders(customer_id, amount)
    SELECT customer_id, amount FROM INSERTED;
END;
GO

-- 检测特定列变更
CREATE TRIGGER trg_salary_change
ON employees
AFTER UPDATE
AS
BEGIN
    IF UPDATE(salary)  -- UPDATE() 函数检测列是否在 SET 子句中
    BEGIN
        INSERT INTO salary_audit(emp_id, old_salary, new_salary)
        SELECT i.id, d.salary, i.salary
        FROM INSERTED i JOIN DELETED d ON i.id = d.id
        WHERE i.salary <> d.salary;
    END
END;
GO

-- DDL 触发器（数据库级）
CREATE TRIGGER trg_ddl_audit
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EventData XML = EVENTDATA();
    INSERT INTO ddl_log(event_type, object_name, sql_text, login_name, event_time)
    VALUES (
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(100)'),
        GETDATE()
    );
END;
GO

-- 服务器级 DDL 触发器
CREATE TRIGGER trg_server_ddl
ON ALL SERVER
FOR CREATE_DATABASE, DROP_DATABASE
AS
BEGIN
    -- 记录数据库创建和删除
    PRINT 'Database DDL event detected';
END;
GO

-- LOGON 触发器
CREATE TRIGGER trg_logon_audit
ON ALL SERVER
FOR LOGON
AS
BEGIN
    IF ORIGINAL_LOGIN() = 'suspicious_user'
        ROLLBACK;  -- 阻止登录
END;
GO

-- CREATE OR ALTER（2016 SP1+）
CREATE OR ALTER TRIGGER trg_orders_audit
ON orders
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit_log(order_id) SELECT id FROM INSERTED;
END;
GO

-- 触发器排序
EXEC sp_settriggerorder @triggername = 'trg_orders_audit',
    @order = 'First', @stmttype = 'INSERT';

-- ENABLE / DISABLE
DISABLE TRIGGER trg_orders_audit ON orders;
ENABLE TRIGGER trg_orders_audit ON orders;
DISABLE TRIGGER ALL ON orders;

-- 递归触发器控制
ALTER DATABASE mydb SET RECURSIVE_TRIGGERS ON;
ALTER DATABASE mydb SET RECURSIVE_TRIGGERS OFF;
```

SQL Server 的独特之处：所有 DML 触发器都是语句级的，通过集合式的 `INSERTED`/`DELETED` 伪表处理行数据。使用 `EVENTDATA()` XML 函数获取 DDL 事件详情。

### SQLite（轻量级但功能完备的行级触发器）

```sql
-- BEFORE INSERT 触发器
CREATE TRIGGER trg_before_insert_orders
BEFORE INSERT ON orders
BEGIN
    SELECT RAISE(ABORT, 'Amount must be positive')
    WHERE NEW.amount <= 0;
END;

-- AFTER INSERT 触发器
CREATE TRIGGER trg_after_insert_orders
AFTER INSERT ON orders
BEGIN
    INSERT INTO audit_log(table_name, action, row_id, ts)
    VALUES ('orders', 'INSERT', NEW.id, datetime('now'));
END;

-- AFTER UPDATE 触发器（指定列）
CREATE TRIGGER trg_update_amount
AFTER UPDATE OF amount, status ON orders
BEGIN
    INSERT INTO order_changes(order_id, old_amount, new_amount, old_status, new_status)
    VALUES (OLD.id, OLD.amount, NEW.amount, OLD.status, NEW.status);
END;

-- WHEN 条件子句
CREATE TRIGGER trg_high_value_orders
AFTER INSERT ON orders
WHEN NEW.amount > 10000
BEGIN
    INSERT INTO high_value_alerts(order_id, amount)
    VALUES (NEW.id, NEW.amount);
END;

-- INSTEAD OF 触发器（仅视图）
CREATE TRIGGER trg_view_update
INSTEAD OF UPDATE ON order_summary_view
BEGIN
    UPDATE orders SET amount = NEW.amount WHERE id = OLD.order_id;
END;

-- 删除触发器
DROP TRIGGER IF EXISTS trg_before_insert_orders;

-- 限制：
-- 1. 仅支持 FOR EACH ROW（不支持语句级）
-- 2. 不支持 ALTER TRIGGER、ENABLE/DISABLE
-- 3. 不支持 CREATE OR REPLACE
-- 4. 触发器体使用 BEGIN...END 包含多条 SQL 语句
-- 5. 使用 RAISE(IGNORE|ABORT|ROLLBACK|FAIL, message) 控制错误处理
```

### DB2（严格的 REFERENCING 语法）

```sql
-- 行级 BEFORE 触发器（需要显式 REFERENCING）
CREATE TRIGGER trg_before_insert_orders
BEFORE INSERT ON orders
REFERENCING NEW AS N
FOR EACH ROW
BEGIN ATOMIC
    SET N.created_at = CURRENT_TIMESTAMP;
    SET N.updated_at = CURRENT_TIMESTAMP;
    IF N.amount < 0 THEN
        SIGNAL SQLSTATE '75000' SET MESSAGE_TEXT = 'Amount must be positive';
    END IF;
END;

-- 行级 AFTER 触发器
CREATE TRIGGER trg_after_update_orders
AFTER UPDATE ON orders
REFERENCING OLD AS O NEW AS N
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO audit_log(order_id, old_amount, new_amount, changed_at)
    VALUES (N.id, O.amount, N.amount, CURRENT_TIMESTAMP);
END;

-- 语句级触发器 + 过渡表
CREATE TRIGGER trg_stmt_after_insert
AFTER INSERT ON orders
REFERENCING NEW TABLE AS new_orders
FOR EACH STATEMENT
BEGIN ATOMIC
    INSERT INTO batch_log(batch_count, batch_time)
    VALUES ((SELECT COUNT(*) FROM new_orders), CURRENT_TIMESTAMP);
END;

-- INSTEAD OF 触发器（9.7+ 视图）
CREATE TRIGGER trg_view_insert
INSTEAD OF INSERT ON order_view
REFERENCING NEW AS N
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO orders(id, amount) VALUES (N.id, N.amount);
END;

-- UPDATE OF 特定列
CREATE TRIGGER trg_salary_change
AFTER UPDATE OF salary ON employees
REFERENCING OLD AS O NEW AS N
FOR EACH ROW
WHEN (N.salary > O.salary * 1.5)
BEGIN ATOMIC
    INSERT INTO salary_alerts VALUES (N.emp_id, O.salary, N.salary);
END;
```

DB2 的特点：强制使用 `REFERENCING` 子句定义行/表别名（不能直接用 NEW/OLD），触发器体用 `BEGIN ATOMIC...END` 包裹。

### Snowflake / BigQuery / Redshift（不支持触发器的云数仓）

```sql
-- Snowflake: 不支持触发器
-- 替代方案 1: 使用 STREAM + TASK 实现类似功能
CREATE STREAM orders_stream ON TABLE orders;

CREATE TASK process_order_changes
    WAREHOUSE = compute_wh
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('orders_stream')
AS
INSERT INTO audit_log(order_id, action, ts)
SELECT
    id,
    CASE METADATA$ACTION
        WHEN 'INSERT' THEN 'INSERT'
        WHEN 'DELETE' THEN 'DELETE'
    END,
    CURRENT_TIMESTAMP()
FROM orders_stream
WHERE METADATA$ISUPDATE = FALSE;

-- BigQuery: 不支持触发器
-- 替代方案: 使用 BigQuery 的 change history（APPENDS / CHANGES）
-- 或者通过 Cloud Functions + Pub/Sub 实现事件驱动

-- Redshift: 不支持触发器
-- 替代方案: 使用 AWS Lambda + Amazon Kinesis Data Firehose
```

### SAP HANA

```sql
-- 行级 AFTER 触发器
CREATE TRIGGER trg_orders_audit
AFTER INSERT ON orders
REFERENCING NEW ROW AS new_row
FOR EACH ROW
BEGIN
    INSERT INTO audit_log(order_id, action, ts)
    VALUES (:new_row.id, 'INSERT', CURRENT_TIMESTAMP);
END;

-- 语句级触发器
CREATE TRIGGER trg_orders_stmt
AFTER UPDATE ON orders
REFERENCING NEW TABLE AS new_tab OLD TABLE AS old_tab
FOR EACH STATEMENT
BEGIN
    INSERT INTO change_log(changed_count, ts)
    VALUES ((SELECT COUNT(*) FROM :new_tab), CURRENT_TIMESTAMP);
END;

-- INSTEAD OF 触发器（2.0+）
CREATE TRIGGER trg_view_insert
INSTEAD OF INSERT ON order_view
REFERENCING NEW ROW AS nrow
FOR EACH ROW
BEGIN
    INSERT INTO orders VALUES (:nrow.id, :nrow.amount, CURRENT_TIMESTAMP);
END;

-- ENABLE / DISABLE
ALTER TRIGGER trg_orders_audit DISABLE;
ALTER TRIGGER trg_orders_audit ENABLE;

-- CREATE OR REPLACE
CREATE OR REPLACE TRIGGER trg_orders_audit
AFTER INSERT ON orders
REFERENCING NEW ROW AS new_row
FOR EACH ROW
BEGIN
    INSERT INTO audit_log VALUES (:new_row.id, 'INSERT', CURRENT_TIMESTAMP);
END;
```

### Firebird（POSITION 排序 + 隐式行级）

```sql
-- 基本触发器（隐式 FOR EACH ROW）
CREATE TRIGGER trg_orders_bi
FOR orders
ACTIVE BEFORE INSERT
POSITION 0
AS
BEGIN
    IF (NEW.id IS NULL) THEN
        NEW.id = GEN_ID(gen_orders_id, 1);
    NEW.created_at = CURRENT_TIMESTAMP;
END;

-- AFTER UPDATE 触发器
CREATE TRIGGER trg_orders_au
FOR orders
ACTIVE AFTER UPDATE
POSITION 0
AS
BEGIN
    INSERT INTO audit_log(table_name, action, old_val, new_val, ts)
    VALUES ('orders', 'UPDATE', OLD.amount, NEW.amount, CURRENT_TIMESTAMP);
END;

-- 多事件触发器
CREATE TRIGGER trg_orders_multi
FOR orders
ACTIVE AFTER INSERT OR UPDATE OR DELETE
POSITION 10
AS
BEGIN
    IF (INSERTING) THEN
        INSERT INTO log_table VALUES ('INSERT', NEW.id);
    ELSE IF (UPDATING) THEN
        INSERT INTO log_table VALUES ('UPDATE', NEW.id);
    ELSE
        INSERT INTO log_table VALUES ('DELETE', OLD.id);
END;

-- CREATE OR REPLACE (2.1+)
CREATE OR REPLACE TRIGGER trg_orders_bi
FOR orders
ACTIVE BEFORE INSERT
POSITION 0
AS
BEGIN
    NEW.created_at = CURRENT_TIMESTAMP;
END;

-- ENABLE / DISABLE (1.5+)
ALTER TRIGGER trg_orders_bi INACTIVE;
ALTER TRIGGER trg_orders_bi ACTIVE;
```

Firebird 特点：使用 `FOR table_name` 而非 `ON table_name`；`ACTIVE/INACTIVE` 代替 `ENABLE/DISABLE`；`POSITION n` 控制执行顺序（数值越小越先执行）；`INSERTING` / `UPDATING` / `DELETING` 上下文变量。

### H2 / HSQLDB / Derby（Java 嵌入式数据库）

```sql
-- H2: 基本触发器（Java 接口实现）
CREATE TRIGGER trg_orders_audit
AFTER INSERT ON orders
FOR EACH ROW
CALL "com.example.OrderAuditTrigger";
-- H2 还支持内联 SQL 触发器语法 (部分版本)

-- HSQLDB: 标准 SQL 触发器语法
CREATE TRIGGER trg_orders_audit
AFTER INSERT ON orders
REFERENCING NEW ROW AS newrow
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO audit_log(order_id, action)
    VALUES (newrow.id, 'INSERT');
END;

-- HSQLDB: 语句级触发器
CREATE TRIGGER trg_orders_stmt
AFTER INSERT ON orders
REFERENCING NEW TABLE AS new_tab
FOR EACH STATEMENT
BEGIN ATOMIC
    INSERT INTO batch_log(cnt) VALUES ((SELECT COUNT(*) FROM new_tab));
END;

-- HSQLDB: WHEN 条件
CREATE TRIGGER trg_high_value
AFTER INSERT ON orders
REFERENCING NEW ROW AS nrow
FOR EACH ROW
WHEN (nrow.amount > 10000)
BEGIN ATOMIC
    INSERT INTO alerts(order_id) VALUES (nrow.id);
END;

-- Derby: 行级触发器
CREATE TRIGGER trg_orders_audit
AFTER INSERT ON orders
REFERENCING NEW AS new_row
FOR EACH ROW
INSERT INTO audit_log(order_id, action)
VALUES (new_row.id, 'INSERT');

-- Derby: 语句级触发器
CREATE TRIGGER trg_orders_stmt
AFTER DELETE ON orders
REFERENCING OLD TABLE AS deleted_rows
FOR EACH STATEMENT
INSERT INTO delete_log(cnt, ts)
VALUES ((SELECT COUNT(*) FROM deleted_rows), CURRENT_TIMESTAMP);
```

### CockroachDB（22.2+ 触发器支持）

```sql
-- CockroachDB 触发器语法与 PostgreSQL 兼容
-- 步骤 1: 创建触发器函数
CREATE FUNCTION audit_trigger() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(table_name, action, new_data)
        VALUES (TG_TABLE_NAME, 'INSERT', to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log(table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log(table_name, action, old_data)
        VALUES (TG_TABLE_NAME, 'DELETE', to_jsonb(OLD));
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE PLpgSQL;

-- 步骤 2: 创建触发器
CREATE TRIGGER trg_orders_audit
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
EXECUTE FUNCTION audit_trigger();

-- BEFORE 触发器
CREATE TRIGGER trg_set_timestamp
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- WHEN 条件
CREATE TRIGGER trg_status_change
AFTER UPDATE ON orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION log_status_change();

-- ENABLE / DISABLE
ALTER TABLE orders DISABLE TRIGGER trg_orders_audit;
ALTER TABLE orders ENABLE TRIGGER trg_orders_audit;

-- 限制：
-- 1. 不支持 INSTEAD OF 触发器
-- 2. 不支持 DDL 事件触发器
-- 3. 不支持递归触发器
-- 4. 不支持 TRUNCATE 触发器
```

### Teradata

```sql
-- 行级 BEFORE 触发器
CREATE TRIGGER trg_before_insert
BEFORE INSERT ON orders
REFERENCING NEW AS N
FOR EACH ROW
WHEN (N.amount <= 0)
BEGIN ATOMIC
    SIGNAL SQLSTATE '75000' SET MESSAGE_TEXT = 'Invalid amount';
END;

-- 行级 AFTER 触发器
CREATE TRIGGER trg_after_update
AFTER UPDATE OF status ON orders
REFERENCING OLD AS O NEW AS N
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO status_log(order_id, old_status, new_status, ts)
    VALUES (N.id, O.status, N.status, CURRENT_TIMESTAMP);
END;

-- 语句级触发器 + 过渡表
CREATE TRIGGER trg_stmt_after_delete
AFTER DELETE ON orders
REFERENCING OLD TABLE AS deleted_orders
FOR EACH STATEMENT
BEGIN ATOMIC
    INSERT INTO deletion_summary(cnt, ts)
    VALUES ((SELECT COUNT(*) FROM deleted_orders), CURRENT_TIMESTAMP);
END;

-- 多触发器排序（ORDER 子句）
CREATE TRIGGER trg_first
AFTER INSERT ON orders
ORDER 1
REFERENCING NEW AS N
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO log1 VALUES (N.id);
END;

CREATE TRIGGER trg_second
AFTER INSERT ON orders
ORDER 2
REFERENCING NEW AS N
FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO log2 VALUES (N.id);
END;

-- REPLACE TRIGGER
REPLACE TRIGGER trg_before_insert
BEFORE INSERT ON orders
REFERENCING NEW AS N
FOR EACH ROW
WHEN (N.amount <= 0)
BEGIN ATOMIC
    SIGNAL SQLSTATE '75000' SET MESSAGE_TEXT = 'Invalid amount';
END;

-- ENABLE / DISABLE
ALTER TRIGGER trg_before_insert DISABLED;
ALTER TRIGGER trg_before_insert ENABLED;
```

### Informix

```sql
-- 行级 BEFORE 触发器
CREATE TRIGGER trg_orders_bi
INSERT ON orders
REFERENCING NEW AS N
BEFORE (
    EXECUTE FUNCTION validate_order(N.id, N.amount)
);

-- 行级 AFTER 触发器
CREATE TRIGGER trg_orders_au
UPDATE OF amount ON orders
REFERENCING OLD AS O NEW AS N
BEFORE (
    EXECUTE FUNCTION check_amount(N.amount)
)
AFTER (
    INSERT INTO audit_log VALUES (N.id, O.amount, N.amount, CURRENT)
);

-- FOR EACH ROW（11.50+）
CREATE TRIGGER trg_orders_audit
INSERT ON orders
REFERENCING NEW AS N
FOR EACH ROW (
    INSERT INTO audit_log(order_id, action)
    VALUES (N.id, 'INSERT')
);

-- ENABLE / DISABLE (11.10+)
SET TRIGGERS trg_orders_bi ENABLED;
SET TRIGGERS trg_orders_bi DISABLED;
```

Informix 的触发器语法较为独特：使用括号而非 BEGIN...END，BEFORE/AFTER 部分可以在同一 CREATE TRIGGER 语句中同时定义。

## 触发器在 OLAP 引擎中的缺失原因

以下引擎完全不支持触发器：Snowflake、BigQuery、Redshift、DuckDB、ClickHouse、Trino、Presto、Spark SQL、Hive、Flink SQL、Databricks、SingleStore（分析模式）、Vertica、Impala、StarRocks、Doris、MonetDB、CrateDB、QuestDB、Exasol、Amazon Athena、Azure Synapse、Google Spanner、Materialize、RisingWave、InfluxDB、DatabendDB、Yellowbrick、Firebolt。

这些引擎不支持触发器的核心原因：

1. **批处理架构冲突**：OLAP 引擎优化的是大批量数据扫描和聚合，行级触发器会在每条记录处理时引入额外开销，与列式存储和向量化执行的设计理念根本矛盾。

2. **分布式执行难题**：在 MPP（大规模并行处理）架构中，数据分布在多个节点上。触发器需要在数据所在节点执行，但可能需要访问其他节点的数据或修改其他表，这会引入分布式事务的复杂性，破坏水平扩展能力。

3. **不可变数据模型**：许多分析引擎（如 ClickHouse、BigQuery）采用追加优先或不可变的存储模型，UPDATE/DELETE 操作本身就受限或语义不同，触发器的前提条件不成立。

4. **确定性和可重放性**：流处理引擎（Flink SQL、Materialize、RisingWave）和数据湖引擎要求计算结果可重放，触发器的副作用（如写入外部系统）破坏了这一保证。

5. **ETL 优先的数据流模型**：OLAP 场景中数据通常通过 ETL/ELT 管道加载，在加载管道中实现业务逻辑（而非在数据库层面）更为普遍和高效。

### 替代方案

| 引擎 | 替代触发器的机制 | 说明 |
|------|------|------|
| Snowflake | STREAM + TASK | STREAM 捕获变更数据，TASK 定期处理 |
| BigQuery | Cloud Functions + Pub/Sub | BigQuery 日志触发 Cloud Functions |
| Redshift | AWS Lambda UDF | 有限的事件响应能力 |
| Databricks | Delta Lake Change Data Feed | 追踪 Delta 表的行级变更 |
| ClickHouse | Materialized Views | MV 在 INSERT 时自动聚合写入目标表 |
| Flink SQL | CDC Connectors | Debezium 等 CDC 工具捕获变更 |
| Spark SQL | Structured Streaming | 流式处理变更数据 |
| Google Spanner | Change Streams | 捕获数据变更并发送到下游 |
| DuckDB | -- | 嵌入式分析引擎，无需触发器 |

> 注：ClickHouse 的 Materialized View 是一种特殊形式的"类触发器"机制。当数据 INSERT 到源表时，MV 会自动将转换后的数据写入目标表。但它不同于真正的触发器：不支持 UPDATE/DELETE 事件，不能执行任意逻辑，且不能阻止原始操作。

## 关键发现

1. **OLTP vs OLAP 的根本分界线**：触发器支持是 OLTP 和 OLAP 引擎之间最鲜明的分界线之一。所有传统 OLTP 数据库（PostgreSQL、MySQL、Oracle、SQL Server、DB2）都支持触发器，而几乎所有 OLAP/分析引擎都不支持。在 49 个被调查的引擎中，仅约 19 个支持触发器。

2. **PostgreSQL 家族的一致性**：PostgreSQL 及其衍生引擎（Greenplum、TimescaleDB、YugabyteDB、CockroachDB）形成了触发器支持最统一的生态系统。所有这些引擎都使用触发器函数 + CREATE TRIGGER 的两步模型，语法高度兼容。

3. **SQL Server 的独特模型**：SQL Server 是唯一不支持 BEFORE 触发器的主流 OLTP 数据库。它用 INSTEAD OF 触发器替代 BEFORE 的功能，并且所有 DML 触发器都是语句级的，通过 INSERTED/DELETED 伪表访问行数据。这种集合式模型在处理批量操作时实际上更高效。

4. **Oracle 的复合触发器是独有创新**：Oracle 11g 引入的 COMPOUND TRIGGER 通过在单个触发器定义中组合 BEFORE STATEMENT / BEFORE EACH ROW / AFTER EACH ROW / AFTER STATEMENT 四个时机点，优雅地解决了变异表（mutating table）问题，这是其他引擎没有的能力。

5. **DDL 触发器差距巨大**：仅 PostgreSQL（事件触发器）、Oracle 和 SQL Server 提供完整的 DDL 触发器支持。Oracle 和 SQL Server 的 DDL 触发器最为成熟，支持几十种 DDL 事件和多级作用域。

6. **NEW/OLD 引用语法碎片化严重**：各引擎对变更前后数据的引用方式差异显著：PostgreSQL/MySQL 用 `NEW.col`/`OLD.col`，Oracle/SAP HANA 用 `:NEW.col`/`:OLD.col`，SQL Server 用 `INSERTED`/`DELETED` 伪表，DB2 要求通过 REFERENCING 自定义别名。这是触发器跨引擎迁移的最大障碍之一。

7. **MySQL/MariaDB 的触发器限制最多**：不支持语句级触发器、INSTEAD OF、WHEN 子句、TRUNCATE 触发器、DDL 触发器。MySQL 5.7.2 之前甚至限制每种 timing + event 组合只能有一个触发器。

8. **触发器排序机制各不相同**：PostgreSQL 按名称字母序，MySQL/Oracle 用 FOLLOWS/PRECEDES，SQL Server 用 sp_settriggerorder，Firebird 用 POSITION，Teradata 用 ORDER。缺乏统一标准使得跨引擎迁移时必须重新设计触发器执行顺序。

9. **TiDB 和 SingleStore 等 NewSQL 不支持触发器**：尽管 TiDB 兼容 MySQL 协议、SingleStore 兼容 MySQL 语法，但这两个分布式数据库都未实现触发器功能。这说明在分布式架构下实现触发器语义的复杂性极高。

10. **CREATE OR REPLACE 支持逐渐普及**：Oracle 最早支持（7.0+），PostgreSQL 在 14 版本才加入，MariaDB 在 10.1.4+，SQL Server 用 CREATE OR ALTER（2016 SP1+）。MySQL 和 SQLite 至今不支持，仍需手动 DROP + CREATE。
