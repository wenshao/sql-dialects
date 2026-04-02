# 约束语法 (Constraint Syntax)

约束（Constraint）是关系模型的核心保障机制，用于在数据库层面强制数据完整性规则。然而，各 SQL 引擎对约束的支持差异极大：传统 OLTP 引擎（PostgreSQL、Oracle、SQL Server）提供完整的约束体系——包括外键、CHECK、可延迟约束、约束启用/禁用等；分布式 NewSQL 引擎（CockroachDB、TiDB、YugabyteDB）在兼容传统语法的同时需要处理分布式事务带来的额外复杂度；而 OLAP / 数据湖引擎（BigQuery、Redshift、Snowflake、ClickHouse）则普遍采用"信息性约束"（Informational Constraint）模式——接受约束声明语法但不强制执行，仅供查询优化器使用。理解这些差异对于跨引擎迁移和多引擎架构设计至关重要。

## SQL 标准中的约束

### SQL:1992 定义的约束类型

SQL:1992 标准（ISO/IEC 9075:1992）定义了以下约束类型：

- **NOT NULL** — 列级约束，禁止 NULL 值
- **UNIQUE** — 保证列或列组合的唯一性（允许 NULL）
- **PRIMARY KEY** — UNIQUE + NOT NULL，每表最多一个
- **FOREIGN KEY ... REFERENCES** — 引用完整性，支持 `ON DELETE` / `ON UPDATE` 动作
- **CHECK (condition)** — 行级条件检查

引用完整性动作在 SQL:1992 中定义了五种：

```
ON DELETE { CASCADE | SET NULL | SET DEFAULT | RESTRICT | NO ACTION }
ON UPDATE { CASCADE | SET NULL | SET DEFAULT | RESTRICT | NO ACTION }
```

- `NO ACTION`（默认）：语句结束时检查，若违反则回滚
- `RESTRICT`：立即检查，若违反则拒绝操作
- `CASCADE`：级联删除/更新
- `SET NULL`：将外键列设为 NULL
- `SET DEFAULT`：将外键列设为默认值

### SQL:2003 扩展

SQL:2003 增加了约束的可延迟特性：

```sql
CONSTRAINT fk_order_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id)
    DEFERRABLE INITIALLY DEFERRED
```

- `NOT DEFERRABLE`（默认）：每条语句后立即检查
- `DEFERRABLE INITIALLY IMMEDIATE`：默认立即检查，但可在事务中设为延迟
- `DEFERRABLE INITIALLY DEFERRED`：默认延迟到事务提交时检查

## PRIMARY KEY 支持矩阵

| 引擎 | 单列 PK | 复合 PK | 命名 PK | 版本 |
|------|---------|---------|---------|------|
| PostgreSQL | 支持 | 支持 | 支持 | 全版本 |
| MySQL | 支持 | 支持 | 不支持(忽略名称) | 全版本 |
| MariaDB | 支持 | 支持 | 不支持(忽略名称) | 全版本 |
| SQLite | 支持 | 支持 | 支持 | 全版本 |
| Oracle | 支持 | 支持 | 支持 | 全版本 |
| SQL Server | 支持 | 支持 | 支持 | 全版本 |
| DB2 | 支持 | 支持 | 支持 | 全版本 |
| Snowflake | 支持 | 支持 | 支持 | 全版本(不强制) |
| BigQuery | 支持 | 支持 | 不支持 | 2022+(不强制) |
| Redshift | 支持 | 支持 | 支持 | 全版本(不强制) |
| DuckDB | 支持 | 支持 | 支持 | 全版本 |
| ClickHouse | 支持(仅排序键) | 支持(仅排序键) | 不支持 | 全版本(仅 ORDER BY) |
| Trino | 不支持 | 不支持 | 不支持 | - |
| Presto | 不支持 | 不支持 | 不支持 | - |
| Spark SQL | 不支持 | 不支持 | 不支持 | - |
| Hive | 支持 | 支持 | 支持 | 3.0+(不强制) |
| Flink SQL | 支持 | 支持 | 支持 | 1.13+ |
| Databricks | 支持 | 支持 | 支持 | Unity Catalog(不强制) |
| Teradata | 支持 | 支持 | 支持 | 全版本 |
| Greenplum | 支持 | 支持 | 支持 | 全版本(分布键限制) |
| CockroachDB | 支持 | 支持 | 支持 | 全版本 |
| TiDB | 支持 | 支持 | 不支持(忽略名称) | 全版本 |
| OceanBase | 支持 | 支持 | 支持 | 全版本 |
| YugabyteDB | 支持 | 支持 | 支持 | 全版本 |
| SingleStore | 支持 | 支持 | 不支持(忽略名称) | 全版本 |
| Vertica | 支持 | 支持 | 支持 | 全版本(不强制) |
| Impala | 支持 | 支持 | 不支持 | 3.0+(不强制) |
| StarRocks | 支持 | 支持 | 不支持 | 全版本(排序键) |
| Doris | 支持 | 支持 | 不支持 | 全版本(排序键) |
| MonetDB | 支持 | 支持 | 支持 | 全版本 |
| CrateDB | 支持 | 支持 | 不支持 | 全版本 |
| TimescaleDB | 支持 | 支持 | 支持 | 全版本(继承 PG) |
| QuestDB | 不支持 | 不支持 | 不支持 | - |
| Exasol | 支持 | 支持 | 支持 | 全版本 |
| SAP HANA | 支持 | 支持 | 支持 | 全版本 |
| Informix | 支持 | 支持 | 支持 | 全版本 |
| Firebird | 支持 | 支持 | 支持 | 全版本 |
| H2 | 支持 | 支持 | 支持 | 全版本 |
| HSQLDB | 支持 | 支持 | 支持 | 全版本 |
| Derby | 支持 | 支持 | 支持 | 全版本 |
| Amazon Athena | 不支持 | 不支持 | 不支持 | - |
| Azure Synapse | 支持 | 支持 | 支持 | 全版本(不强制) |
| Google Spanner | 支持 | 支持 | 不支持 | 全版本 |
| Materialize | 支持 | 不支持 | 不支持 | 0.27+ |
| RisingWave | 支持 | 支持 | 不支持 | 全版本 |
| InfluxDB | 不支持 | 不支持 | 不支持 | 时序引擎，无传统约束 |
| DatabendDB | 不支持 | 不支持 | 不支持 | - |
| Yellowbrick | 支持 | 支持 | 支持 | 全版本 |
| Firebolt | 支持 | 支持 | 不支持 | 全版本(不强制) |

## FOREIGN KEY 支持矩阵

| 引擎 | FK 声明 | CASCADE | SET NULL | SET DEFAULT | RESTRICT | NO ACTION | 强制执行 |
|------|---------|---------|----------|-------------|----------|-----------|---------|
| PostgreSQL | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| MySQL (InnoDB) | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 | 强制 |
| MariaDB (InnoDB) | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 | 强制 |
| SQLite | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 需 `PRAGMA foreign_keys=ON` |
| Oracle | 支持 | 支持 | 支持 | 不支持 | 不支持(用 NO ACTION) | 支持 | 强制 |
| SQL Server | 支持 | 支持 | 支持 | 支持 | 不支持(用 NO ACTION) | 支持 | 强制 |
| DB2 | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 | 强制 |
| Snowflake | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| BigQuery | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| Redshift | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| DuckDB | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制(0.8+) |
| ClickHouse | 不支持 | - | - | - | - | - | - |
| Trino | 不支持 | - | - | - | - | - | - |
| Presto | 不支持 | - | - | - | - | - | - |
| Spark SQL | 不支持 | - | - | - | - | - | - |
| Hive | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制(3.0+) |
| Flink SQL | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| Databricks | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| Teradata | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 | 强制 |
| Greenplum | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制(7.0+) |
| CockroachDB | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| TiDB | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制(解析但不执行) |
| OceanBase | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 | 强制(MySQL 模式) |
| YugabyteDB | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| SingleStore | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制(解析但不执行) |
| Vertica | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| Impala | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制(3.0+) |
| StarRocks | 不支持 | - | - | - | - | - | - |
| Doris | 不支持 | - | - | - | - | - | - |
| MonetDB | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| CrateDB | 不支持 | - | - | - | - | - | - |
| TimescaleDB | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制(继承 PG) |
| QuestDB | 不支持 | - | - | - | - | - | - |
| Exasol | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| SAP HANA | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| Informix | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 | 强制 |
| Firebird | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| H2 | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| HSQLDB | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| Derby | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | 强制 |
| Amazon Athena | 不支持 | - | - | - | - | - | - |
| Azure Synapse | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| Google Spanner | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 支持 | 强制 |
| Materialize | 不支持 | - | - | - | - | - | - |
| RisingWave | 不支持 | - | - | - | - | - | - |
| InfluxDB | 不支持 | - | - | - | - | - | - |
| DatabendDB | 不支持 | - | - | - | - | - | - |
| Yellowbrick | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不强制 |
| Firebolt | 不支持 | - | - | - | - | - | - |

## UNIQUE 约束支持矩阵

| 引擎 | 单列 UNIQUE | 复合 UNIQUE | 部分 UNIQUE (Partial/Filtered) | NULL 处理 |
|------|------------|------------|-------------------------------|----------|
| PostgreSQL | 支持 | 支持 | 支持 (`WHERE` 子句) | 多个 NULL 允许(15+ 可配置 `NULLS NOT DISTINCT`) |
| MySQL | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| MariaDB | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| SQLite | 支持 | 支持 | 支持 (`WHERE` 子句) | 多个 NULL 允许 |
| Oracle | 支持 | 支持 | 不支持(可用函数索引模拟) | 多个 NULL 允许 |
| SQL Server | 支持 | 支持 | 支持 (`WHERE` 过滤索引) | 单个 NULL(默认)，可用过滤索引绕过 |
| DB2 | 支持 | 支持 | 不支持 | 视配置而定 |
| Snowflake | 支持 | 支持 | 不支持 | 不强制，无实际意义 |
| BigQuery | 不支持 | 不支持 | 不支持 | - |
| Redshift | 支持 | 支持 | 不支持 | 不强制 |
| DuckDB | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| ClickHouse | 不支持 | 不支持 | 不支持 | - |
| Trino | 不支持 | 不支持 | 不支持 | - |
| Hive | 支持 | 支持 | 不支持 | 不强制(3.0+) |
| Flink SQL | 支持 | 支持 | 不支持 | - |
| Databricks | 不支持 | 不支持 | 不支持 | - |
| Teradata | 支持 | 支持 | 不支持 | 单个 NULL |
| Greenplum | 支持 | 支持 | 支持(继承 PG) | 多个 NULL 允许 |
| CockroachDB | 支持 | 支持 | 支持 (`WHERE` 子句) | 多个 NULL 允许 |
| TiDB | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| OceanBase | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| YugabyteDB | 支持 | 支持 | 支持 (`WHERE` 子句) | 多个 NULL 允许 |
| SingleStore | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| Vertica | 支持 | 支持 | 不支持 | 不强制 |
| MonetDB | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| CrateDB | 不支持 | 不支持 | 不支持 | - |
| TimescaleDB | 支持 | 支持 | 支持(继承 PG) | 多个 NULL 允许 |
| Exasol | 支持 | 支持 | 不支持 | 不强制 |
| SAP HANA | 支持 | 支持 | 不支持 | 单个 NULL |
| Informix | 支持 | 支持 | 不支持 | 单个 NULL(默认) |
| Firebird | 支持 | 支持 | 支持(部分索引, 3.0+) | 多个 NULL 允许(3.0+) |
| H2 | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| HSQLDB | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| Derby | 支持 | 支持 | 不支持 | 单个 NULL |
| Google Spanner | 支持 | 支持 | 不支持 | 多个 NULL 允许 |
| Yellowbrick | 支持 | 支持 | 不支持 | 不强制 |
| Firebolt | 不支持 | 不支持 | 不支持 | - |

## CHECK 约束支持矩阵

| 引擎 | CHECK 约束 | 表达式支持 | 命名 CHECK | 强制执行 | 版本 |
|------|-----------|-----------|-----------|---------|------|
| PostgreSQL | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| MySQL | 支持 | 完整表达式 | 支持 | 强制 | 8.0.16+(之前仅解析不执行) |
| MariaDB | 支持 | 完整表达式 | 支持 | 强制 | 10.2.1+ |
| SQLite | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Oracle | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| SQL Server | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| DB2 | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Snowflake | 不支持 | - | - | - | - |
| BigQuery | 不支持 | - | - | - | - |
| Redshift | 不支持 | - | - | - | - |
| DuckDB | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| ClickHouse | 支持 | 完整表达式 | 支持 | 强制 | 22.6+ |
| Trino | 不支持 | - | - | - | - |
| Hive | 支持 | 有限表达式 | 不支持 | 不强制 | 3.0+ |
| Spark SQL | 支持(Delta Lake) | SQL 表达式 | 不支持 | 强制 | Delta Lake 1.0+ |
| Flink SQL | 不支持 | - | - | - | - |
| Databricks | 支持 | SQL 表达式 | 不支持 | 强制 | Delta Lake |
| Teradata | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Greenplum | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| CockroachDB | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| TiDB | 支持 | 完整表达式 | 支持 | 强制 | 8.0+ |
| OceanBase | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| YugabyteDB | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| SingleStore | 不支持 | - | - | - | - |
| Vertica | 不支持 | - | - | - | - |
| MonetDB | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| CrateDB | 支持 | 完整表达式 | 不支持 | 强制 | 4.0+ |
| TimescaleDB | 支持 | 完整表达式 | 支持 | 强制 | 全版本(继承 PG) |
| QuestDB | 不支持 | - | - | - | - |
| Exasol | 支持 | 完整表达式 | 支持 | 不强制 | 全版本 |
| SAP HANA | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Informix | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Firebird | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| H2 | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| HSQLDB | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Derby | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Amazon Athena | 不支持 | - | - | - | - |
| Azure Synapse | 支持 | 完整表达式 | 支持 | 不强制 | 全版本 |
| Google Spanner | 支持 | 完整表达式 | 支持 | 强制 | 全版本 |
| Materialize | 不支持 | - | - | - | - |
| RisingWave | 不支持 | - | - | - | - |
| InfluxDB | 不支持 | - | - | - | - |
| DatabendDB | 不支持 | - | - | - | - |
| Yellowbrick | 不支持 | - | - | - | - |
| Firebolt | 不支持 | - | - | - | - |

## NOT NULL 与 DEFAULT 支持矩阵

| 引擎 | NOT NULL | DEFAULT 常量 | DEFAULT 表达式 | DEFAULT 序列/函数 |
|------|----------|-------------|---------------|------------------|
| PostgreSQL | 支持 | 支持 | 支持(含函数调用) | 支持 `nextval()` |
| MySQL | 支持 | 支持 | 支持(8.0.13+ 表达式) | 不支持(用 AUTO_INCREMENT) |
| MariaDB | 支持 | 支持 | 支持(10.2+ 表达式) | 支持 `nextval()` (10.3+) |
| SQLite | 支持 | 支持 | 支持(常量表达式) | 不支持 |
| Oracle | 支持 | 支持 | 支持(含序列, 12c+) | 支持 `seq.NEXTVAL` (12c+) |
| SQL Server | 支持 | 支持 | 支持(含函数) | 不支持(用 IDENTITY) |
| DB2 | 支持 | 支持 | 支持(有限) | 支持 |
| Snowflake | 支持 | 支持 | 支持(有限) | 支持 `seq.NEXTVAL` |
| BigQuery | 支持 | 支持 | 支持(有限) | 不支持 |
| Redshift | 支持 | 支持 | 支持(有限) | 不支持(用 IDENTITY) |
| DuckDB | 支持 | 支持 | 支持 | 支持 `nextval()` |
| ClickHouse | 支持(Nullable 类型体系) | 支持 | 支持 | 不支持 |
| Trino | 不支持 | 不支持 | 不支持 | 不支持 |
| Hive | 支持(3.0+) | 支持 | 不支持 | 不支持 |
| Spark SQL | 支持 | 支持 | 不支持 | 不支持 |
| Flink SQL | 支持 | 支持 | 支持(含函数) | 不支持 |
| Databricks | 支持 | 支持 | 支持(Delta Lake) | 不支持 |
| Teradata | 支持 | 支持 | 不支持 | 不支持(用 IDENTITY) |
| Greenplum | 支持 | 支持 | 支持(继承 PG) | 支持 |
| CockroachDB | 支持 | 支持 | 支持(含函数) | 支持 `nextval()` |
| TiDB | 支持 | 支持 | 支持(8.0+) | 不支持(用 AUTO_INCREMENT) |
| OceanBase | 支持 | 支持 | 支持 | 不支持(用 AUTO_INCREMENT) |
| YugabyteDB | 支持 | 支持 | 支持(含函数) | 支持 `nextval()` |
| SingleStore | 支持 | 支持 | 不支持 | 不支持(用 AUTO_INCREMENT) |
| Vertica | 支持 | 支持 | 支持(有限) | 支持 |
| MonetDB | 支持 | 支持 | 支持 | 支持 |
| CrateDB | 支持 | 支持 | 不支持 | 不支持 |
| TimescaleDB | 支持 | 支持 | 支持(继承 PG) | 支持 |
| QuestDB | 支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 支持 | 支持 | 支持(有限) | 不支持(用 IDENTITY) |
| SAP HANA | 支持 | 支持 | 支持 | 支持 |
| Informix | 支持 | 支持 | 支持(有限) | 支持 |
| Firebird | 支持 | 支持 | 支持 | 支持 `gen_id()` |
| H2 | 支持 | 支持 | 支持 | 支持 |
| HSQLDB | 支持 | 支持 | 支持 | 支持 |
| Derby | 支持 | 支持 | 不支持 | 不支持(用 IDENTITY) |
| Google Spanner | 支持 | 支持 | 支持(含函数) | 支持 |
| Materialize | 支持 | 支持 | 不支持 | 不支持 |
| RisingWave | 支持 | 支持 | 不支持 | 不支持 |
| DatabendDB | 支持 | 支持 | 不支持 | 不支持 |
| Yellowbrick | 支持 | 支持 | 支持(有限) | 不支持 |
| Firebolt | 支持 | 支持 | 不支持 | 不支持 |

## 高级约束特性矩阵

| 引擎 | EXCLUDE 约束 | 可延迟约束 | ENABLE/DISABLE | VALIDATE/NOVALIDATE | 信息性约束 |
|------|-------------|-----------|----------------|---------------------|-----------|
| PostgreSQL | 支持(GiST) | 支持 | 不支持(用 ALTER ... NOT VALID) | 支持(NOT VALID) | 不支持 |
| MySQL | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| MariaDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| SQLite | 不支持 | 支持(有限) | 不支持 | 不支持 | 不支持 |
| Oracle | 不支持 | 支持 | 支持 | 支持 | 支持(RELY) |
| SQL Server | 不支持 | 不支持 | 支持(CHECK/NOCHECK) | 支持(WITH CHECK/NOCHECK) | 支持(NOT FOR REPLICATION) |
| DB2 | 不支持 | 不支持 | 支持 | 支持 | 支持(ENFORCED/NOT ENFORCED) |
| Snowflake | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |
| BigQuery | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |
| Redshift | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |
| DuckDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| ClickHouse | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Teradata | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Greenplum | 支持(继承 PG) | 支持 | 不支持 | 支持(NOT VALID) | 不支持 |
| CockroachDB | 不支持 | 不支持 | 不支持 | 支持(NOT VALID) | 不支持 |
| TiDB | 不支持 | 不支持 | 不支持 | 不支持 | 支持(FK 不强制) |
| OceanBase | 不支持 | 支持(Oracle 模式) | 支持(Oracle 模式) | 支持(Oracle 模式) | 不支持 |
| YugabyteDB | 不支持 | 支持 | 不支持 | 不支持 | 不支持 |
| SingleStore | 不支持 | 不支持 | 不支持 | 不支持 | 支持(FK 不强制) |
| Vertica | 不支持 | 不支持 | 支持 | 不支持 | 支持(全部不强制) |
| MonetDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Exasol | 不支持 | 不支持 | 支持 | 不支持 | 支持(部分不强制) |
| SAP HANA | 不支持 | 不支持 | 支持 | 不支持 | 不支持 |
| Informix | 不支持 | 不支持 | 支持 | 不支持 | 不支持 |
| Firebird | 不支持 | 支持 | 支持(INACTIVE) | 不支持 | 不支持 |
| H2 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| HSQLDB | 不支持 | 支持 | 不支持 | 不支持 | 不支持 |
| Derby | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Azure Synapse | 不支持 | 不支持 | 支持 | 不支持 | 支持(全部不强制) |
| Google Spanner | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Hive | 不支持 | 不支持 | 支持 | 不支持 | 支持(全部不强制) |
| Databricks | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |
| Impala | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |
| Yellowbrick | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |
| Firebolt | 不支持 | 不支持 | 不支持 | 不支持 | 支持(全部不强制) |

## ALTER TABLE ADD/DROP CONSTRAINT

| 引擎 | ADD CONSTRAINT | DROP CONSTRAINT | ADD PK | DROP PK |
|------|---------------|----------------|--------|---------|
| PostgreSQL | 支持 | 支持 | 支持 | 支持 |
| MySQL | 支持(8.0+) | 支持(8.0+) | 支持 | 支持(`DROP PRIMARY KEY`) |
| MariaDB | 支持 | 支持 | 支持 | 支持 |
| SQLite | 不支持(需重建表) | 不支持(需重建表) | 不支持 | 不支持 |
| Oracle | 支持 | 支持 | 支持 | 支持 |
| SQL Server | 支持 | 支持 | 支持 | 支持 |
| DB2 | 支持 | 支持 | 支持 | 支持 |
| Snowflake | 支持(有限) | 支持 | 支持 | 支持 |
| BigQuery | 支持(PK/FK) | 支持 | 支持 | 支持 |
| Redshift | 支持 | 支持 | 支持 | 支持 |
| DuckDB | 支持 | 支持 | 支持 | 支持 |
| ClickHouse | 支持(CHECK, 22.6+) | 支持(CHECK) | 不支持 | 不支持 |
| Teradata | 支持 | 支持 | 支持 | 支持 |
| Greenplum | 支持 | 支持 | 支持 | 支持 |
| CockroachDB | 支持 | 支持 | 支持 | 支持 |
| TiDB | 支持 | 支持 | 支持 | 支持(有限) |
| OceanBase | 支持 | 支持 | 支持 | 支持 |
| YugabyteDB | 支持 | 支持 | 支持 | 支持 |
| SingleStore | 支持(有限) | 支持(有限) | 支持 | 支持 |
| Vertica | 支持 | 支持 | 支持 | 支持 |
| MonetDB | 支持 | 支持 | 支持 | 支持 |
| CrateDB | 不支持 | 不支持 | 不支持 | 不支持 |
| TimescaleDB | 支持 | 支持 | 支持 | 支持 |
| Exasol | 支持 | 支持 | 支持 | 支持 |
| SAP HANA | 支持 | 支持 | 支持 | 支持 |
| Informix | 支持 | 支持 | 支持 | 支持 |
| Firebird | 支持 | 支持 | 支持 | 支持 |
| H2 | 支持 | 支持 | 支持 | 支持 |
| HSQLDB | 支持 | 支持 | 支持 | 支持 |
| Derby | 支持 | 支持 | 支持 | 支持 |
| Google Spanner | 支持 | 支持 | 不支持 | 不支持 |
| Hive | 支持 | 支持 | 支持 | 支持 |
| Databricks | 支持 | 支持 | 支持 | 支持 |

## 各引擎约束语法详解

### PostgreSQL

PostgreSQL 提供最完整的约束实现，包括独有的 EXCLUDE 约束和 NOT VALID 验证机制。

```sql
-- 完整约束声明示例
CREATE TABLE orders (
    id SERIAL,
    customer_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price NUMERIC(10, 2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    
    -- 命名主键
    CONSTRAINT pk_orders PRIMARY KEY (id),
    
    -- 外键 + 引用动作
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    
    CONSTRAINT fk_orders_product 
        FOREIGN KEY (product_id) REFERENCES products(id)
        ON DELETE CASCADE,
    
    -- CHECK 约束
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_price CHECK (price >= 0),
    CONSTRAINT chk_status CHECK (status IN ('pending', 'confirmed', 'shipped', 'cancelled'))
);

-- EXCLUDE 约束 (PostgreSQL 独有) —— 防止时间范围重叠
CREATE TABLE reservations (
    room_id INT NOT NULL,
    during TSTZRANGE NOT NULL,
    
    CONSTRAINT no_overlap EXCLUDE USING GIST (
        room_id WITH =,
        during WITH &&
    )
);

-- 可延迟约束
CREATE TABLE tree_nodes (
    id INT PRIMARY KEY,
    parent_id INT,
    
    CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES tree_nodes(id)
        DEFERRABLE INITIALLY DEFERRED
);

-- 事务中延迟检查
BEGIN;
SET CONSTRAINTS fk_parent DEFERRED;
INSERT INTO tree_nodes VALUES (2, 1);  -- parent_id=1 暂时不存在
INSERT INTO tree_nodes VALUES (1, NULL);  -- 现在插入 parent
COMMIT;  -- 提交时检查约束

-- 部分唯一约束
CREATE UNIQUE INDEX idx_active_email 
    ON users (email) 
    WHERE deleted_at IS NULL;

-- NOT VALID：添加约束但不验证现有数据
ALTER TABLE orders ADD CONSTRAINT chk_positive_total
    CHECK (total > 0) NOT VALID;

-- 之后单独验证
ALTER TABLE orders VALIDATE CONSTRAINT chk_positive_total;

-- PostgreSQL 15+ NULLS NOT DISTINCT
CREATE TABLE tokens (
    token VARCHAR(255),
    CONSTRAINT uq_token UNIQUE NULLS NOT DISTINCT (token)
);
```

### MySQL / MariaDB

MySQL 8.0.16+ 开始真正强制执行 CHECK 约束（之前仅解析不执行）。外键仅 InnoDB 引擎支持。

```sql
-- MySQL 约束语法
CREATE TABLE orders (
    id BIGINT NOT NULL AUTO_INCREMENT,
    customer_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    status ENUM('pending', 'confirmed', 'shipped', 'cancelled') 
        NOT NULL DEFAULT 'pending',
    
    PRIMARY KEY (id),  -- MySQL 忽略 PK 命名
    
    -- 外键
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    
    -- CHECK 约束 (8.0.16+)
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_price CHECK (price >= 0),
    
    -- 唯一约束
    UNIQUE KEY uq_order_ref (customer_id, product_id, order_date)
) ENGINE=InnoDB;

-- MySQL 不支持 SET DEFAULT 引用动作
-- 以下会报错:
-- FOREIGN KEY (col) REFERENCES t(col) ON DELETE SET DEFAULT  -- 错误

-- 查看外键状态
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'orders';

-- ALTER TABLE 添加/删除约束
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (quantity * price > 0);
ALTER TABLE orders DROP CONSTRAINT chk_total;  -- MySQL 8.0.19+
-- 旧版本: ALTER TABLE orders DROP CHECK chk_total;

-- MySQL 临时禁用外键检查（DDL 或数据加载时常用）
SET FOREIGN_KEY_CHECKS = 0;
-- ... 批量导入 ...
SET FOREIGN_KEY_CHECKS = 1;
```

MariaDB 额外特性：

```sql
-- MariaDB 10.2+ CHECK 约束
CREATE TABLE products (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    discount DECIMAL(5, 2) DEFAULT 0,
    
    CONSTRAINT chk_discount CHECK (discount >= 0 AND discount <= price)
);

-- MariaDB 10.5+ 支持 ALTER TABLE ... ALTER CONSTRAINT 
-- (MySQL 不支持)
```

### SQLite

SQLite 的约束实现简洁但有特殊行为：外键默认禁用，不支持 ALTER TABLE ADD CONSTRAINT。

```sql
-- SQLite 约束（必须在 CREATE TABLE 时定义）
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,  -- 自动成为 rowid 别名
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0),
    price REAL NOT NULL CHECK(price >= 0),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending', 'confirmed', 'shipped', 'cancelled')),
    
    FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id)
        ON DELETE RESTRICT
);

-- 必须显式启用外键强制执行（每个连接）
PRAGMA foreign_keys = ON;

-- SQLite 不支持 ALTER TABLE ADD/DROP CONSTRAINT
-- 修改约束需要重建表:
-- 1. CREATE TABLE new_table (... 新约束 ...);
-- 2. INSERT INTO new_table SELECT * FROM old_table;
-- 3. DROP TABLE old_table;
-- 4. ALTER TABLE new_table RENAME TO old_table;

-- 部分唯一索引
CREATE UNIQUE INDEX idx_active_user_email
    ON users (email)
    WHERE is_active = 1;
```

### Oracle

Oracle 提供最强大的约束管理能力，包括 ENABLE/DISABLE、VALIDATE/NOVALIDATE、RELY/NORELY 组合。

```sql
-- Oracle 约束声明
CREATE TABLE orders (
    id NUMBER GENERATED ALWAYS AS IDENTITY,
    customer_id NUMBER NOT NULL,
    quantity NUMBER NOT NULL,
    price NUMBER(10, 2) NOT NULL,
    status VARCHAR2(20) DEFAULT 'pending' NOT NULL,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),
    
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE,
    -- Oracle 不支持 ON UPDATE CASCADE
    -- Oracle 不支持 RESTRICT（用 NO ACTION 代替，行为等价）
    
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_status CHECK (status IN ('pending', 'confirmed', 'shipped', 'cancelled'))
);

-- 可延迟约束
ALTER TABLE orders ADD CONSTRAINT fk_orders_product
    FOREIGN KEY (product_id) REFERENCES products(id)
    DEFERRABLE INITIALLY DEFERRED;

-- ENABLE / DISABLE 约束
ALTER TABLE orders DISABLE CONSTRAINT chk_quantity;
ALTER TABLE orders ENABLE CONSTRAINT chk_quantity;

-- VALIDATE / NOVALIDATE：控制是否验证现有数据
ALTER TABLE orders ENABLE NOVALIDATE CONSTRAINT chk_quantity;
-- 启用约束但不检查现有数据

-- 四种组合:
-- ENABLE VALIDATE    (默认) —— 约束生效且现有数据已验证
-- ENABLE NOVALIDATE  —— 约束对新数据生效但不检查旧数据
-- DISABLE VALIDATE   —— 禁止 DML 但保留约束元数据
-- DISABLE NOVALIDATE —— 完全禁用

-- RELY / NORELY：告诉优化器是否可以依赖此约束
ALTER TABLE orders MODIFY CONSTRAINT fk_orders_customer RELY;
-- 优化器可利用此约束进行查询重写（物化视图刷新等）

-- 查看约束状态
SELECT constraint_name, constraint_type, status, validated, rely
FROM user_constraints
WHERE table_name = 'ORDERS';
```

### SQL Server

SQL Server 使用 `WITH CHECK / WITH NOCHECK` 和 `CHECK / NOCHECK` 语法管理约束。

```sql
-- SQL Server 约束声明
CREATE TABLE orders (
    id INT IDENTITY(1, 1) NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) NOT NULL 
        CONSTRAINT df_status DEFAULT 'pending',  -- 命名 DEFAULT 约束
    
    CONSTRAINT pk_orders PRIMARY KEY CLUSTERED (id),
    
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    -- SQL Server 支持 SET DEFAULT（需列有 DEFAULT 值）
    
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_price CHECK (price >= 0),
    CONSTRAINT chk_status CHECK (status IN ('pending', 'confirmed', 'shipped', 'cancelled'))
);

-- UNIQUE 过滤索引 —— 仅对非 NULL 值唯一
CREATE UNIQUE INDEX uq_email_active
    ON users (email)
    WHERE email IS NOT NULL;

-- 禁用 / 启用约束
ALTER TABLE orders NOCHECK CONSTRAINT chk_quantity;
ALTER TABLE orders CHECK CONSTRAINT chk_quantity;

-- WITH CHECK 重新验证现有数据
ALTER TABLE orders WITH CHECK CHECK CONSTRAINT chk_quantity;

-- WITH NOCHECK 添加约束但不验证现有数据
ALTER TABLE orders WITH NOCHECK
    ADD CONSTRAINT chk_new_rule CHECK (price > 0);

-- NOT FOR REPLICATION：复制时不检查约束
ALTER TABLE orders ADD CONSTRAINT fk_repl
    FOREIGN KEY (ref_id) REFERENCES ref_table(id)
    NOT FOR REPLICATION;

-- 查看约束是否受信任
SELECT name, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID('orders');
```

### DB2

DB2 支持 `ENFORCED / NOT ENFORCED` 语法，是标准化的信息性约束实现。

```sql
-- DB2 约束声明
CREATE TABLE orders (
    id INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    customer_id INT NOT NULL,
    quantity INT NOT NULL WITH DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),
    
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE,
    
    CONSTRAINT chk_quantity CHECK (quantity > 0) ENFORCED,
    CONSTRAINT chk_info CHECK (price > 0) NOT ENFORCED
    -- NOT ENFORCED: 声明约束但不强制，优化器可使用
);

-- ENABLE / DISABLE（DB2 for z/OS）
ALTER TABLE orders ALTER FOREIGN KEY fk_orders_customer ENFORCED;
ALTER TABLE orders ALTER FOREIGN KEY fk_orders_customer NOT ENFORCED;

-- 查询性约束（Informational Constraint）
ALTER TABLE orders ADD CONSTRAINT chk_hint
    CHECK (status = 'active') NOT ENFORCED ENABLE QUERY OPTIMIZATION;
```

### Google Spanner

Spanner 使用交错表（Interleaved Tables）替代外键，但也支持标准外键语法。

```sql
-- Spanner 主键（必须在建表时指定，不可更改）
CREATE TABLE orders (
    order_id INT64 NOT NULL,
    customer_id INT64 NOT NULL,
    quantity INT64 NOT NULL,
    price NUMERIC NOT NULL,
    status STRING(20) NOT NULL DEFAULT ('pending'),
    
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_price CHECK (price >= 0),
) PRIMARY KEY (order_id);

-- 交错表（Interleaved Table）—— Spanner 特有的父子关系
CREATE TABLE order_items (
    order_id INT64 NOT NULL,
    item_id INT64 NOT NULL,
    product_id INT64 NOT NULL,
    quantity INT64 NOT NULL,
    
    CONSTRAINT chk_item_quantity CHECK (quantity > 0)
) PRIMARY KEY (order_id, item_id),
  INTERLEAVE IN PARENT orders ON DELETE CASCADE;

-- 标准外键（跨表引用）
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
    ON DELETE CASCADE;
-- Spanner FK 仅支持 ON DELETE CASCADE 和 ON DELETE NO ACTION
```

### CockroachDB

CockroachDB 兼容 PostgreSQL 约束语法，但在分布式环境下有特殊考量。

```sql
-- CockroachDB 约束（兼容 PostgreSQL 语法）
CREATE TABLE orders (
    id UUID DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    status STRING NOT NULL DEFAULT 'pending',
    
    CONSTRAINT pk_orders PRIMARY KEY (id),
    
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_status CHECK (status IN ('pending', 'confirmed', 'shipped', 'cancelled'))
);

-- 部分唯一索引
CREATE UNIQUE INDEX idx_active_email 
    ON users (email) 
    WHERE deleted_at IS NULL;

-- NOT VALID：添加外键但不验证现有数据（加速大表迁移）
ALTER TABLE orders ADD CONSTRAINT fk_orders_product
    FOREIGN KEY (product_id) REFERENCES products(id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_product;

-- 注意：CockroachDB 不支持 DEFERRABLE 约束
-- 也不支持 EXCLUDE 约束
```

### TiDB

TiDB 兼容 MySQL 语法，但外键约束在 v6.6 之前不强制执行。

```sql
-- TiDB 约束（MySQL 兼容语法）
CREATE TABLE orders (
    id BIGINT NOT NULL AUTO_INCREMENT,
    customer_id BIGINT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    
    PRIMARY KEY (id),
    
    -- TiDB v6.6+ 支持外键强制执行（需要设置）
    -- SET GLOBAL tidb_enable_foreign_key = ON;
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id),
    
    -- CHECK 约束 (TiDB 8.0+)
    CONSTRAINT chk_quantity CHECK (quantity > 0)
);

-- 注意：TiDB 外键默认不强制执行
-- v6.6 之前：解析外键语法但完全不执行
-- v6.6+：需手动开启 tidb_enable_foreign_key
```

### DuckDB

DuckDB 作为嵌入式 OLAP 引擎，从 0.8 开始强制执行外键约束。

```sql
-- DuckDB 约束
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    status VARCHAR NOT NULL DEFAULT 'pending',
    
    FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    
    CHECK (quantity > 0),
    CHECK (price >= 0),
    UNIQUE (customer_id, order_date)
);

-- DuckDB 支持完整的引用动作
-- CASCADE, SET NULL, SET DEFAULT, RESTRICT, NO ACTION
```

### ClickHouse

ClickHouse 没有传统约束体系，但从 22.6 开始支持 CHECK 约束（ASSUME 模式）。

```sql
-- ClickHouse CHECK 约束
CREATE TABLE orders (
    id UInt64,
    customer_id UInt64,
    quantity UInt32,
    price Decimal(10, 2),
    status String,
    order_date Date
)
ENGINE = MergeTree()
ORDER BY (order_date, id)
SETTINGS check_constraints_on_insert = 1  -- 启用插入时检查
AS
SELECT *
FROM input('id UInt64, customer_id UInt64, ...');

-- 通过 ALTER 添加 CHECK 约束 (22.6+)
ALTER TABLE orders ADD CONSTRAINT chk_quantity CHECK quantity > 0;
ALTER TABLE orders ADD CONSTRAINT chk_price CHECK price >= 0;

-- 删除 CHECK 约束
ALTER TABLE orders DROP CONSTRAINT chk_quantity;

-- 注意：
-- 1. ClickHouse 不支持 PRIMARY KEY / FOREIGN KEY / UNIQUE 约束
-- 2. ORDER BY 中的列扮演类似 "主键" 的角色（用于排序和去重）
-- 3. CHECK 约束通过 check_constraints_on_insert 设置控制
-- 4. ReplacingMergeTree 提供近似去重但非实时唯一性保证
```

### Firebird

Firebird 支持完整的 SQL 标准约束体系，包括可延迟约束和约束活跃/非活跃状态。

```sql
-- Firebird 约束
CREATE TABLE orders (
    id INTEGER GENERATED BY DEFAULT AS IDENTITY,
    customer_id INTEGER NOT NULL,
    quantity INTEGER DEFAULT 1 NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' NOT NULL,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),
    
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_status CHECK (status IN ('pending', 'confirmed', 'shipped', 'cancelled'))
);

-- Firebird 3.0+ 部分索引
CREATE UNIQUE INDEX idx_active_email
    ON users (email)
    WHERE (is_deleted = 0);

-- 约束活跃/非活跃 (ACTIVE/INACTIVE)
ALTER TABLE orders ALTER CONSTRAINT chk_quantity INACTIVE;
ALTER TABLE orders ALTER CONSTRAINT chk_quantity ACTIVE;
```

### H2 / HSQLDB / Derby

Java 嵌入式数据库的约束支持：

```sql
-- H2 约束
CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE,
    
    CONSTRAINT chk_quantity CHECK (quantity > 0)
);

-- HSQLDB 支持可延迟约束
CREATE TABLE tree_nodes (
    id INT PRIMARY KEY,
    parent_id INT,
    
    CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES tree_nodes(id)
        DEFERRABLE INITIALLY DEFERRED
);
SET DATABASE DEFAULT TABLE TYPE CACHED;

-- Derby 约束（不支持可延迟约束和 DEFAULT 表达式）
CREATE TABLE orders (
    id INT GENERATED ALWAYS AS IDENTITY,
    customer_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),
    CONSTRAINT fk_cust FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT chk_qty CHECK (quantity > 0)
);
```

## OLAP 引擎的信息性约束

OLAP 引擎普遍采用"信息性约束"（Informational Constraint）模式——接受约束声明但不强制执行。这种设计背后有明确的工程取舍：

1. **查询优化**：优化器利用 PK/FK/UNIQUE 信息进行 join 消除、去重消除等优化
2. **ETL 兼容性**：大数据加载场景中，约束检查会严重降低写入吞吐
3. **源数据信任**：假设数据在上游 OLTP 系统中已经过约束验证
4. **分布式代价**：跨节点约束检查的代价在分布式架构中不可接受

### Snowflake

```sql
-- Snowflake：所有约束仅为信息性（NOT ENFORCED）
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),           -- 不强制
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id),  -- 不强制
    CONSTRAINT uq_ref UNIQUE (order_ref)             -- 不强制
    -- 不支持 CHECK 约束
);

-- NOT NULL 是唯一被强制执行的约束
-- PK 和 UNIQUE 不阻止重复数据插入
-- FK 不验证引用完整性

-- 查看约束信息
SHOW PRIMARY KEYS IN TABLE orders;
SHOW IMPORTED KEYS IN TABLE orders;
```

### BigQuery

```sql
-- BigQuery：PK 和 FK 为信息性约束 (2022+)
CREATE TABLE dataset.orders (
    id INT64 NOT NULL,
    customer_id INT64 NOT NULL,
    quantity INT64 NOT NULL,
    
    PRIMARY KEY (id) NOT ENFORCED,  -- 必须显式声明 NOT ENFORCED
    FOREIGN KEY (customer_id) REFERENCES dataset.customers(id) NOT ENFORCED
);

-- BigQuery 特殊语法：必须写 NOT ENFORCED
-- 不支持 UNIQUE、CHECK 约束
-- NOT NULL 是唯一被强制执行的约束
```

### Amazon Redshift

```sql
-- Redshift：约束仅用于查询优化
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    
    PRIMARY KEY (id),           -- 不强制唯一性
    FOREIGN KEY (customer_id) REFERENCES customers(id),  -- 不强制引用完整性
    UNIQUE (order_ref)          -- 不强制唯一性
);

-- Redshift 最佳实践：
-- 即使不强制执行，也应声明约束，因为优化器会使用这些信息
-- 例如：join 消除、谓词下推等优化依赖 PK/FK 元数据
```

### Azure Synapse Analytics

```sql
-- Azure Synapse：约束不强制执行（专用 SQL 池）
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL,
    
    CONSTRAINT pk_orders PRIMARY KEY NONCLUSTERED (id) NOT ENFORCED,
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT ENFORCED
);

-- Synapse 特点：
-- 1. PRIMARY KEY 需要 NONCLUSTERED 和 NOT ENFORCED
-- 2. 支持 CHECK 约束语法但不强制执行
-- 3. NOT NULL 强制执行
```

### Hive / Databricks / Impala

```sql
-- Hive 3.0+ 信息性约束
CREATE TABLE orders (
    id BIGINT,
    customer_id BIGINT NOT NULL,
    quantity INT DEFAULT 1,
    
    CONSTRAINT pk_orders PRIMARY KEY (id) DISABLE NOVALIDATE,
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id) DISABLE NOVALIDATE,
    CONSTRAINT uq_ref UNIQUE (order_ref) DISABLE NOVALIDATE,
    CONSTRAINT chk_quantity CHECK (quantity > 0) DISABLE NOVALIDATE
);
-- Hive 要求约束声明带 DISABLE NOVALIDATE，明确表示不执行

-- Databricks (Unity Catalog)
-- PK 和 FK 为信息性约束，CHECK 约束由 Delta Lake 强制执行
CREATE TABLE orders (
    id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    quantity INT NOT NULL,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),    -- 信息性
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id)  -- 信息性
);

-- Delta Lake CHECK 约束（强制执行）
ALTER TABLE orders ADD CONSTRAINT chk_quantity CHECK (quantity > 0);
-- 这个 CHECK 约束在写入时强制执行

-- Impala 3.0+
CREATE TABLE orders (
    id BIGINT,
    customer_id BIGINT,
    
    PRIMARY KEY (id) DISABLE NOVALIDATE,
    FOREIGN KEY (customer_id) REFERENCES customers(id) DISABLE NOVALIDATE
);
```

### Vertica

```sql
-- Vertica：约束默认不强制执行
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    
    PRIMARY KEY (id) ENABLED,     -- 语法接受但不保证唯一性
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    UNIQUE (order_ref)
    -- 不支持 CHECK 约束
);

-- 可以显式启用/禁用约束（但启用也不强制执行，仅用于优化器）
ALTER TABLE orders ALTER CONSTRAINT pk_orders ENABLED;
ALTER TABLE orders ALTER CONSTRAINT pk_orders DISABLED;
```

### Exasol

```sql
-- Exasol：PK/FK/UNIQUE 不强制执行
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    
    CONSTRAINT pk_orders PRIMARY KEY (id),           -- 不强制
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(id),  -- 不强制
    CONSTRAINT chk_quantity CHECK (quantity > 0)      -- 不强制
);

-- 启用/禁用约束（控制优化器是否使用）
ALTER TABLE orders MODIFY CONSTRAINT pk_orders ENABLE;
ALTER TABLE orders MODIFY CONSTRAINT pk_orders DISABLE;
```

### Firebolt

```sql
-- Firebolt：PK 为信息性约束
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL,
    
    PRIMARY KEY (id)  -- 不强制唯一性，仅供优化器使用
);

-- Firebolt 不支持 FK、UNIQUE、CHECK 约束
-- PRIMARY KEY 影响数据的物理存储布局和索引
```

### Flink SQL / RisingWave

流处理引擎中的约束有特殊含义：

```sql
-- Flink SQL：PK 定义 changelog 行为
CREATE TABLE orders (
    id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    quantity INT NOT NULL,
    status STRING NOT NULL,
    
    PRIMARY KEY (id) NOT ENFORCED  -- 定义 upsert 语义
) WITH (
    'connector' = 'kafka',
    'format' = 'debezium-json'
);
-- Flink 中 PK 定义 changelog 的 key，不执行唯一性检查
-- 用于确定 INSERT/UPDATE/DELETE 操作的目标行

-- RisingWave：PK 定义物化视图的增量更新粒度
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    quantity INT NOT NULL
);
-- RisingWave 的 PK 影响增量计算和状态管理
```

## 约束命名规范

主流数据库普遍支持约束命名，推荐格式：

| 约束类型 | 命名格式 | 示例 |
|---------|---------|------|
| PRIMARY KEY | `pk_{table}` | `pk_orders` |
| FOREIGN KEY | `fk_{table}_{ref_table}` 或 `fk_{table}_{column}` | `fk_orders_customer` |
| UNIQUE | `uq_{table}_{columns}` | `uq_users_email` |
| CHECK | `chk_{table}_{rule}` | `chk_orders_quantity` |
| DEFAULT | `df_{table}_{column}` | `df_orders_status` |

命名约束的关键好处：
- `ALTER TABLE DROP CONSTRAINT` 需要约束名称
- 错误消息中会显示约束名称，便于调试
- 元数据查询更清晰

注意事项：
- MySQL / MariaDB 忽略 PRIMARY KEY 的命名（始终为 `PRIMARY`）
- TiDB 同样忽略 PK 命名
- BigQuery 不支持约束命名

## 关键发现

### 1. 约束执行的三级分类

根据约束执行方式，可将引擎分为三类：

| 分类 | 引擎 | 特征 |
|------|------|------|
| **完全强制** | PostgreSQL, Oracle, SQL Server, DB2, MySQL(InnoDB), MariaDB, CockroachDB, YugabyteDB, DuckDB, Firebird, H2, HSQLDB, Derby, SAP HANA, Teradata, Greenplum, OceanBase, MonetDB, TimescaleDB, Informix, Google Spanner | 约束在 DML 时实时检查并拒绝违规数据 |
| **信息性约束** | Snowflake, BigQuery, Redshift, Azure Synapse, Vertica, Exasol, Hive, Databricks, Impala, Firebolt, Yellowbrick, Flink SQL | 接受约束语法但不执行，仅供优化器使用 |
| **无约束支持** | ClickHouse(仅CHECK), Trino, Presto, Amazon Athena, QuestDB, InfluxDB, DatabendDB, CrateDB(仅PK) | 不支持或仅支持极少约束类型 |

### 2. 外键是分布式数据库的分水岭

分布式 NewSQL 数据库对外键的态度截然不同：

- **完全支持**：CockroachDB、YugabyteDB、OceanBase（MySQL 模式）、Google Spanner
- **语法兼容但不强制**：TiDB（v6.6 前）、SingleStore
- **不支持**：StarRocks、Doris、CrateDB

### 3. CHECK 约束是 MySQL 生态的历史痛点

MySQL 直到 8.0.16（2019 年）才真正强制执行 CHECK 约束。在此之前长达二十年的时间里，CHECK 子句被解析但完全忽略。MariaDB 在 10.2.1（2017 年）率先修复了这一问题。TiDB 在 8.0 版本才支持 CHECK 强制执行。

### 4. OLAP 引擎中 NOT NULL 的特殊地位

在绝大多数 OLAP / 信息性约束引擎中，NOT NULL 是唯一被真正强制执行的约束。这是因为：
- NULL 处理影响存储格式和编码效率
- 列存引擎的 NULL bitmap 管理是底层存储的核心部分
- NOT NULL 检查是纯本地操作，无需跨节点协调

### 5. PostgreSQL EXCLUDE 约束是独一无二的

EXCLUDE 约束用 GiST 索引实现范围/几何不重叠检查，目前只有 PostgreSQL（及其衍生引擎 Greenplum、TimescaleDB）支持。它解决了传统 UNIQUE 约束无法处理的"范围重叠"问题，在调度系统、预约系统中极为实用。

### 6. 可延迟约束的采用率较低

尽管 SQL:2003 标准定义了 DEFERRABLE 约束，但实际支持的引擎有限：PostgreSQL、Oracle、SQLite（有限）、YugabyteDB、OceanBase（Oracle 模式）、Firebird、HSQLDB、Greenplum。MySQL、SQL Server、DB2（LUW）、CockroachDB 等主流引擎均不支持。可延迟约束最常见的使用场景是循环引用和批量数据加载。

### 7. 流处理引擎中 PRIMARY KEY 的语义变化

在 Flink SQL 和 RisingWave 等流处理引擎中，PRIMARY KEY 不再是唯一性保证，而是 changelog 语义的定义——它决定了 INSERT/UPDATE/DELETE 操作的粒度和 upsert 行为。这是传统关系模型概念在流处理领域的语义重定义。
