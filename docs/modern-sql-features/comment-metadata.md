# COMMENT 与描述元数据 (COMMENT and Description Metadata)

数据库的注释（COMMENT）是最被低估的元数据能力——它不影响查询结果，却支撑着数据治理、血缘追踪、自动化文档、Schema 浏览器、dbt/SQLAlchemy 等几乎所有工具链。一张有完整 COMMENT 的表，等于自带说明书；一张没有 COMMENT 的表，对接手者就是黑箱。本文系统对比 49 个数据库引擎在表/列/Schema/索引/视图/函数等对象上的注释能力。

## 为什么 COMMENT 如此重要却又被忽视

在大部分团队中，COMMENT 的命运是这样的：建表脚本里写了几行 `COMMENT '订单金额'`，迁移到生产环境后再无人维护，新增列时谁也不补，最终所有人靠口口相传猜字段含义。但在数据平台成熟的团队里，COMMENT 是一等公民：

1. **数据治理与合规**：GDPR / PCI 要求标记敏感字段（PII、PCI），COMMENT 是最轻量的标签载体
2. **血缘与文档**：dbt、DataHub、Amundsen、OpenMetadata 都从 COMMENT 抽取字段描述，构建血缘图谱
3. **工具链集成**：DBeaver、DataGrip、TablePlus 等 IDE 在浏览表结构时直接显示 COMMENT
4. **AI / Text-to-SQL**：LLM 生成 SQL 严重依赖 COMMENT 理解列语义，有 COMMENT 的 schema 准确率可提升 30%+
5. **ORM / 代码生成**：SQLAlchemy `Column.doc`、Hibernate 反向工程都会读取 COMMENT
6. **数据契约（Data Contract）**：COMMENT 中嵌入 JSON/YAML 是新兴的轻量契约存储方式

被忽视的根本原因有两个：一是 SQL 标准化程度低（各家语法差异巨大），二是没有强制约束（缺失 COMMENT 不会报错）。本文的目标就是把 49 个引擎的差异讲清楚。

## SQL 标准定义

SQL:2003 标准（ISO/IEC 9075-11 Information Schema）正式收录了 `COMMENT ON` 语句，但它的历史远比 2003 久。事实上 IBM SQL/DS 在 1980 年代就引入了 `COMMENT ON`，Oracle 在 v7（1992）跟进，PostgreSQL 在 7.3（2002）实现，最终被 SQL:2003 追认为标准。

```sql
<comment_statement> ::=
      COMMENT ON TABLE  <table_name>  IS <character_string_literal>
    | COMMENT ON COLUMN <column_name> IS <character_string_literal>
```

标准只规定了表和列两种对象，其他对象（Schema、索引、视图、函数、类型、约束、序列、触发器…）都属于扩展。读取注释的标准方式是 `INFORMATION_SCHEMA`：

```sql
-- 标准方式：INFORMATION_SCHEMA
SELECT table_schema, table_name, '' AS column_name,
       /* 注：标准本身没有 comment 列，是各厂商扩展 */
       NULL AS comment
FROM information_schema.tables;
```

讽刺的是：SQL 标准的 `INFORMATION_SCHEMA.TABLES` / `COLUMNS` 视图本身**并没有** `COMMENT` 字段（标准在 SQL:2008 才间接定义），导致每个厂商各自扩展，读取方式至今不统一。

## 支持矩阵（综合）

### COMMENT ON TABLE / COLUMN（核心能力）

| 引擎 | COMMENT ON TABLE | COMMENT ON COLUMN | 内联 COMMENT | MySQL 表选项 COMMENT= | 起始版本 |
|------|------------------|-------------------|-------------|---------------------|---------|
| PostgreSQL | 是 | 是 | -- | -- | 7.3 (2002) |
| MySQL | -- | -- | 是 | 是 | 4.1 |
| MariaDB | -- | -- | 是 | 是 | 全部 |
| SQLite | -- | -- | -- | -- | 不支持 |
| Oracle | 是 | 是 | -- | -- | v7 (1992) |
| SQL Server | -- | -- | -- | -- | 仅 sp_addextendedproperty |
| DB2 | 是 | 是 (LABEL ON 也可) | -- | -- | v1 |
| Snowflake | 是 | 是 | 是 (COMMENT='') | 是 | GA |
| BigQuery | -- (用 OPTIONS) | -- (用 OPTIONS) | OPTIONS(description=) | -- | GA |
| Redshift | 是 | 是 | -- | -- | 继承 PG |
| DuckDB | 是 | 是 | -- | -- | 0.8+ |
| ClickHouse | 是 (ALTER MODIFY) | 是 (COMMENT COLUMN) | 是 | 是 (引擎选项) | 18.x+ |
| Trino | 是 | 是 | -- | -- | 309+ |
| Presto | 是 | 是 | -- | -- | 0.193+ |
| Spark SQL | 是 | 是 (ALTER) | 是 | 是 (TBLPROPERTIES) | 2.0+ |
| Hive | 是 | 是 (ALTER CHANGE) | 是 | 是 (TBLPROPERTIES) | 全部 |
| Flink SQL | 是 | 是 | 是 | 是 (WITH) | 1.11+ |
| Databricks | 是 | 是 | 是 | 是 | GA |
| Teradata | 是 (COMMENT ON) | 是 | -- | -- | 全部 |
| Greenplum | 是 | 是 | -- | -- | 继承 PG |
| CockroachDB | 是 | 是 | -- | -- | 1.1+ |
| TiDB | -- (兼容 MySQL) | -- (兼容 MySQL) | 是 | 是 | 全部 |
| OceanBase | 是 (Oracle 模式) | 是 | 是 (MySQL 模式) | 是 | 全部 |
| YugabyteDB | 是 | 是 | -- | -- | 继承 PG |
| SingleStore | -- | -- | 是 (兼容 MySQL) | 是 | 全部 |
| Vertica | 是 | 是 | -- | -- | 全部 |
| Impala | 是 (ALTER) | 是 (ALTER) | 是 | 是 (TBLPROPERTIES) | 全部 |
| StarRocks | -- | -- | 是 | 是 (PROPERTIES) | 2.0+ |
| Doris | -- | -- | 是 | 是 (PROPERTIES) | 1.0+ |
| MonetDB | 是 | 是 | -- | -- | 全部 |
| CrateDB | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | 是 | -- | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | 是 (COMMENT IS) | 是 | -- | -- | 全部 |
| SAP HANA | 是 | 是 | 是 (COMMENT '') | -- | 全部 |
| Informix | -- (无 COMMENT 语句) | -- | -- | -- | 部分（系统目录） |
| Firebird | 是 (COMMENT ON 自 2.0) | 是 | -- | -- | 2.0+ (2007) |
| H2 | 是 | 是 | 是 | -- | 全部 |
| HSQLDB | -- (有限支持) | -- | -- | -- | 部分 |
| Derby | -- | -- | -- | -- | 不支持 |
| Amazon Athena | 是 | 是 | 是 | 是 (TBLPROPERTIES) | 继承 Hive/Trino |
| Azure Synapse | -- | -- | -- | -- | 仅 sp_addextendedproperty |
| Google Spanner | -- | -- | -- | -- | 不支持 |
| Materialize | 是 | 是 | -- | -- | GA |
| RisingWave | 是 | 是 | -- | -- | GA |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| DatabendDB | 是 | 是 | 是 | 是 | GA |
| Yellowbrick | 是 | 是 | -- | -- | 继承 PG |
| Firebolt | -- | -- | -- | -- | 不支持 |

> 统计：49 个引擎中，约 32 个支持表/列注释，10 个仅通过内联或 properties 支持，7 个完全不支持或需通过 sp_addextendedproperty 等迂回方式。

### COMMENT ON SCHEMA / DATABASE

| 引擎 | COMMENT ON SCHEMA | COMMENT ON DATABASE | 备注 |
|------|------------------|--------------------|----|
| PostgreSQL | 是 | 是 | 完整支持 |
| MySQL | -- | -- (建库时无 COMMENT) | -- |
| MariaDB | -- | -- | -- |
| Oracle | -- (Schema=User) | -- | 用 COMMENT ON USER 不可，仅 ALL_USERS |
| SQL Server | -- | -- | 仅 sp_addextendedproperty |
| DB2 | 是 (COMMENT ON SCHEMA) | -- | 数据库级无 |
| Snowflake | 是 | 是 | 完整支持 |
| BigQuery | OPTIONS(description=) on dataset | -- (project) | dataset 级 OPTIONS |
| Redshift | 是 | 是 | 继承 PG |
| DuckDB | 是 | 是 | 0.9+ |
| ClickHouse | -- | 是 (DATABASE ENGINE) | -- |
| Trino | 是 (COMMENT ON SCHEMA) | -- | 357+ |
| Spark SQL | 是 (COMMENT ON DATABASE) | 是 | DATABASE/SCHEMA 别名 |
| Hive | 是 (CREATE DATABASE COMMENT) | 是 | -- |
| Flink SQL | -- | -- | -- |
| Databricks | 是 | 是 | -- |
| Teradata | 是 (COMMENT ON DATABASE) | 是 | -- |
| CockroachDB | 是 | 是 | 19.2+ |
| YugabyteDB | 是 | 是 | -- |
| Vertica | 是 (SCHEMA) | -- | -- |
| Impala | 是 | 是 | -- |
| MonetDB | 是 | -- | -- |
| Exasol | 是 | -- | -- |
| SAP HANA | 是 (SCHEMA) | -- | -- |
| Firebird | -- | -- | -- |
| H2 | 是 | -- | -- |
| Materialize | 是 | 是 | -- |
| Greenplum | 是 | 是 | -- |
| TimescaleDB | 是 | 是 | -- |

### COMMENT ON 其他对象（INDEX / VIEW / MV / CONSTRAINT / FUNCTION / TYPE）

| 引擎 | INDEX | VIEW | MATERIALIZED VIEW | CONSTRAINT | FUNCTION/PROCEDURE | TYPE/DOMAIN |
|------|-------|------|-------------------|-----------|-------------------|-------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Oracle | 是 (10g+) | 是 | 是 | -- | -- (Edition Comment) | -- |
| DB2 | 是 | 是 | -- | -- | 是 | -- |
| MySQL | 是 (CREATE INDEX COMMENT) | 内联 | -- | -- | 是 (CREATE PROC COMMENT) | -- |
| SQL Server | sp_addextendedproperty | sp_addextendedproperty | -- | sp_addextendedproperty | sp_addextendedproperty | sp_addextendedproperty |
| Snowflake | -- | 是 | 是 (DYNAMIC TABLE) | -- | 是 | 是 (FILE FORMAT) |
| Redshift | -- | 是 | -- | 是 | 是 | -- |
| DuckDB | -- | 是 | -- | -- | 是 (1.0+) | -- |
| ClickHouse | 是 (索引 COMMENT) | 是 | 是 | -- | -- | -- |
| Trino | -- | 是 | 是 (412+) | -- | -- | -- |
| Spark SQL | -- | 是 | -- | -- | 是 (CREATE FUNC COMMENT) | -- |
| Hive | -- | 是 | 是 | -- | -- | -- |
| Databricks | -- | 是 | 是 | -- | 是 | -- |
| CockroachDB | 是 | 是 | -- | 是 (22.1+) | -- | 是 |
| Vertica | -- | 是 | -- | 是 | 是 | -- |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TimescaleDB | 是 | 是 | 是 (continuous aggregate) | 是 | 是 | 是 |
| Materialize | 是 | 是 | 是 (sources/sinks) | -- | -- | 是 |
| Firebird | -- | 是 | -- | -- | 是 | 是 (DOMAIN) |
| H2 | -- | 是 | -- | 是 | -- | 是 |
| MonetDB | -- | 是 | -- | -- | 是 | -- |
| Exasol | -- | 是 | -- | -- | 是 | -- |
| SAP HANA | 是 | 是 | -- | -- | 是 | -- |
| Teradata | 是 | 是 | -- | -- | 是 (MACRO/PROC) | -- |

> 注：未列出的引擎一般不支持除 TABLE/COLUMN 之外的 COMMENT。

### 读取注释的途径

| 引擎 | INFORMATION_SCHEMA | 原生系统目录 | 函数 |
|------|-------------------|-------------|------|
| PostgreSQL | -- (无 comment 列) | `pg_description`, `pg_shdescription` | `obj_description()`, `col_description()`, `shobj_description()` |
| Oracle | -- | `ALL_TAB_COMMENTS`, `USER_TAB_COMMENTS`, `ALL_COL_COMMENTS` | -- |
| MySQL | `INFORMATION_SCHEMA.TABLES.TABLE_COMMENT`, `COLUMNS.COLUMN_COMMENT` | -- | -- |
| MariaDB | 同 MySQL | -- | -- |
| SQL Server | -- | `sys.extended_properties` | `fn_listextendedproperty()` |
| DB2 | `SYSCAT.TABLES.REMARKS`, `SYSCAT.COLUMNS.REMARKS` | -- | -- |
| Snowflake | `INFORMATION_SCHEMA.TABLES.COMMENT`, `COLUMNS.COMMENT` | `SHOW TABLES` 列 `comment` | -- |
| BigQuery | `INFORMATION_SCHEMA.TABLES`, `COLUMN_FIELD_PATHS.description` | `__TABLES__` (有限) | -- |
| Redshift | `PG_DESCRIPTION` (PG 兼容) | 同 PG | `obj_description()` |
| DuckDB | `duckdb_tables.comment`, `duckdb_columns.comment` | `pragma_show_tables` | -- |
| ClickHouse | -- | `system.tables.comment`, `system.columns.comment` | -- |
| Trino | `INFORMATION_SCHEMA.TABLES.COMMENT` | `SHOW CREATE TABLE` | -- |
| Spark SQL | -- | `DESCRIBE TABLE EXTENDED`, `DESCRIBE FORMATTED` | -- |
| Hive | -- | `DESCRIBE FORMATTED tbl` | -- |
| Flink SQL | -- | `DESCRIBE`, `SHOW CREATE TABLE` | -- |
| Databricks | `INFORMATION_SCHEMA.TABLES.COMMENT` (Unity Catalog) | `DESCRIBE EXTENDED` | -- |
| Teradata | -- | `DBC.TablesV.CommentString`, `ColumnsV.CommentString` | -- |
| CockroachDB | -- | `pg_description`, `crdb_internal.create_statements` | `obj_description()` |
| TiDB | 兼容 MySQL | -- | -- |
| OceanBase | 双模式各兼容 | `oceanbase.__all_table.comment` | -- |
| YugabyteDB | -- | `pg_description` | `obj_description()` |
| Vertica | `v_catalog.comments` | -- | -- |
| Impala | -- | `DESCRIBE FORMATTED` | -- |
| MonetDB | `sys.comments` | -- | -- |
| Exasol | `EXA_ALL_OBJECTS.OBJECT_COMMENT`, `EXA_ALL_COLUMNS.COLUMN_COMMENT` | -- | -- |
| SAP HANA | -- | `TABLES.COMMENTS`, `TABLE_COLUMNS.COMMENTS` | -- |
| Firebird | -- | `RDB$RELATIONS.RDB$DESCRIPTION`, `RDB$RELATION_FIELDS.RDB$DESCRIPTION` | -- |
| H2 | `INFORMATION_SCHEMA.TABLES.REMARKS`, `COLUMNS.REMARKS` | -- | -- |
| StarRocks | `INFORMATION_SCHEMA.TABLES.TABLE_COMMENT` | -- | -- |
| Doris | 同上（兼容 MySQL） | -- | -- |
| Materialize | `mz_internal.mz_comments` | -- | -- |
| RisingWave | `pg_description` (PG 兼容) | -- | `obj_description()` |
| Greenplum | -- | `pg_description` | `obj_description()` |
| TimescaleDB | -- | `pg_description` | `obj_description()` |

> 关键观察：标准 `INFORMATION_SCHEMA` 完全没有定义 `COMMENT` 列，所有支持的厂商都是自己加的非标准列（MySQL 叫 `TABLE_COMMENT`，Snowflake 叫 `COMMENT`，DB2 叫 `REMARKS`，H2 叫 `REMARKS`），互不兼容。

## 各引擎语法详解

### PostgreSQL（最完整、最优雅的实现）

PostgreSQL 是 COMMENT ON 的"金标准"。它支持几乎所有数据库对象的注释，注释统一存储在 `pg_description`（或共享对象的 `pg_shdescription`）系统表中。

```sql
-- 表
COMMENT ON TABLE orders IS '订单主表，每行代表一笔订单';

-- 列
COMMENT ON COLUMN orders.amount IS '订单金额，单位：分';
COMMENT ON COLUMN orders.status IS '订单状态：PENDING/PAID/SHIPPED/CANCELLED';

-- Schema
COMMENT ON SCHEMA finance IS '财务相关表';

-- 数据库
COMMENT ON DATABASE prod IS '生产环境主库';

-- 索引
COMMENT ON INDEX idx_orders_user_id IS '按用户 ID 查询的覆盖索引';

-- 视图 / 物化视图
COMMENT ON VIEW v_active_users IS '过去 30 天活跃用户';
COMMENT ON MATERIALIZED VIEW mv_daily_sales IS '每日销售汇总，每小时刷新';

-- 约束
COMMENT ON CONSTRAINT chk_amount_positive ON orders IS '金额必须为正';

-- 函数
COMMENT ON FUNCTION calculate_discount(numeric) IS '计算折扣，参数为原价';

-- 类型 / 域
COMMENT ON TYPE order_status IS '订单状态枚举';
COMMENT ON DOMAIN positive_money IS '正数金额域';

-- 触发器、序列、外部表、操作符...
COMMENT ON TRIGGER trg_audit ON orders IS '审计触发器';
COMMENT ON SEQUENCE order_id_seq IS '订单 ID 序列';

-- 删除注释（设为 NULL）
COMMENT ON TABLE orders IS NULL;
```

### Oracle（古老但只覆盖 TABLE / COLUMN / MV / INDEXTYPE）

Oracle 是最早支持 COMMENT ON 的商业库（v7, 1992），但范围出乎意料地窄——仅支持 TABLE、COLUMN、MATERIALIZED VIEW、INDEXTYPE、EDITION、OPERATOR、MINING MODEL。**没有** COMMENT ON SCHEMA / FUNCTION / CONSTRAINT。

```sql
-- 表
COMMENT ON TABLE hr.employees IS '员工主表';

-- 列
COMMENT ON COLUMN hr.employees.salary IS '基本月薪，币种 USD';
COMMENT ON COLUMN hr.employees.hire_date IS '入职日期';

-- 物化视图
COMMENT ON MATERIALIZED VIEW mv_dept_salary IS '部门薪资汇总';

-- 读取
SELECT * FROM ALL_TAB_COMMENTS WHERE TABLE_NAME = 'EMPLOYEES';
SELECT * FROM ALL_COL_COMMENTS WHERE TABLE_NAME = 'EMPLOYEES';
SELECT * FROM USER_TAB_COMMENTS;  -- 当前用户拥有的对象
```

### MySQL / MariaDB（仅内联 + 表选项，无 COMMENT ON 语句）

MySQL 完全没有 `COMMENT ON` 语句。它走的是另一条路：在 CREATE TABLE 内联和表选项上写 COMMENT。

```sql
CREATE TABLE orders (
    id           BIGINT       PRIMARY KEY COMMENT '订单主键',
    user_id      BIGINT       NOT NULL    COMMENT '下单用户 ID',
    amount       DECIMAL(10,2) NOT NULL   COMMENT '订单金额（元）',
    status       VARCHAR(16)  NOT NULL    COMMENT '订单状态',
    created_at   DATETIME     NOT NULL    COMMENT '创建时间',
    INDEX idx_user (user_id) COMMENT '用户索引'
) ENGINE=InnoDB COMMENT='订单主表';

-- 修改注释（必须重写整个列定义）
ALTER TABLE orders MODIFY COLUMN amount DECIMAL(10,2) NOT NULL COMMENT '订单金额（分）';

-- 修改表注释
ALTER TABLE orders COMMENT='订单主表（v2）';

-- 读取
SELECT TABLE_COMMENT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'shop' AND TABLE_NAME = 'orders';

SELECT COLUMN_NAME, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'shop' AND TABLE_NAME = 'orders';
```

> 痛点：MySQL 的 `ALTER TABLE MODIFY COLUMN` 必须重复整个列定义才能改 COMMENT，是所有 ORM 迁移工具的噩梦。

### SQL Server（最尴尬的方案：扩展属性）

SQL Server 至今没有 `COMMENT ON` 语法，也没有内联 `COMMENT`。它的"注释"通过通用扩展属性机制（Extended Properties）实现，约定 `name='MS_Description'` 表示描述。这是所有主流数据库中最冗长、最反直觉的方案。

```sql
-- 给表加注释
EXEC sp_addextendedproperty
    @name        = N'MS_Description',
    @value       = N'订单主表',
    @level0type  = N'SCHEMA', @level0name = N'dbo',
    @level1type  = N'TABLE',  @level1name = N'Orders';

-- 给列加注释
EXEC sp_addextendedproperty
    @name        = N'MS_Description',
    @value       = N'订单金额（分）',
    @level0type  = N'SCHEMA', @level0name = N'dbo',
    @level1type  = N'TABLE',  @level1name = N'Orders',
    @level2type  = N'COLUMN', @level2name = N'Amount';

-- 修改：sp_updateextendedproperty
EXEC sp_updateextendedproperty
    @name = N'MS_Description', @value = N'订单金额（人民币分）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'Orders',
    @level2type = N'COLUMN', @level2name = N'Amount';

-- 删除：sp_dropextendedproperty
-- 读取
SELECT
    o.name        AS table_name,
    c.name        AS column_name,
    ep.value      AS description
FROM sys.tables o
LEFT JOIN sys.columns c           ON c.object_id  = o.object_id
LEFT JOIN sys.extended_properties ep
       ON ep.major_id   = o.object_id
      AND ep.minor_id   = c.column_id
      AND ep.name       = 'MS_Description'
      AND ep.class      = 1
WHERE o.name = 'Orders';

-- 或者：
SELECT * FROM fn_listextendedproperty(
    'MS_Description', 'SCHEMA', 'dbo', 'TABLE', 'Orders', 'COLUMN', DEFAULT);
```

> Azure Synapse Dedicated SQL Pool 同样使用 `sp_addextendedproperty`。Serverless SQL Pool 对扩展属性支持有限。

### DB2（COMMENT ON + LABEL ON 双轨制）

DB2 是 COMMENT ON 的发源地，它甚至有第二个独立机制 `LABEL ON`（更短的标签，常用于报表标题）。

```sql
COMMENT ON TABLE   inventory.parts          IS '零件主表';
COMMENT ON COLUMN  inventory.parts.qty      IS '当前库存数量';
COMMENT ON SCHEMA  inventory                IS '库存模块';
COMMENT ON INDEX   parts_pk                 IS '零件主键索引';
COMMENT ON FUNCTION compute_eoq(INT)        IS '经济订货量计算';

-- LABEL ON：短标签（最长 30 字符）
LABEL ON TABLE inventory.parts IS 'PARTS';
LABEL ON COLUMN inventory.parts.qty IS 'QTY';

-- 读取
SELECT TABNAME, REMARKS FROM SYSCAT.TABLES WHERE TABSCHEMA='INVENTORY';
SELECT COLNAME, REMARKS FROM SYSCAT.COLUMNS WHERE TABNAME='PARTS';
```

> DB2 把 COMMENT 称为 `REMARKS`，这一命名也被 H2、HSQLDB 沿用。

### Snowflake（COMMENT 是一等公民）

Snowflake 在元数据治理上做得非常彻底。它既支持 SQL 标准的 `COMMENT ON`，也支持 CREATE 时内联 `COMMENT='...'`，并且每种对象（包括 Warehouse、Stage、File Format、Pipe、Stream、Task）都能加注释。

```sql
-- CREATE 时内联
CREATE TABLE orders (
    id         NUMBER       COMMENT '订单主键',
    amount     NUMBER(10,2) COMMENT '金额',
    status     VARCHAR      COMMENT '状态'
)
COMMENT = '订单主表';

-- COMMENT ON 语法
COMMENT ON TABLE orders IS '订单主表（v2）';
COMMENT ON COLUMN orders.amount IS '金额（USD）';

-- ALTER 修改
ALTER TABLE orders SET COMMENT = '订单主表（v3）';
ALTER TABLE orders MODIFY COLUMN amount COMMENT '金额（cents）';

-- 读取
SELECT TABLE_NAME, COMMENT FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='SHOP';
SELECT COLUMN_NAME, COMMENT FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='ORDERS';

-- SHOW 命令也带注释
SHOW TABLES LIKE 'orders';  -- 结果中有 comment 列
```

### BigQuery（OPTIONS 是唯一选择）

BigQuery 完全不支持 `COMMENT ON` 语句，唯一的描述机制是 `OPTIONS(description=...)`。

```sql
-- 创建表时
CREATE OR REPLACE TABLE shop.orders (
    id        INT64   OPTIONS(description='订单主键'),
    amount    NUMERIC OPTIONS(description='金额（USD）'),
    status    STRING  OPTIONS(description='订单状态')
)
OPTIONS(
    description='订单主表',
    labels=[('owner','data-team'), ('pii','false')]
);

-- 修改表描述
ALTER TABLE shop.orders SET OPTIONS(description='订单主表 v2');

-- 修改列描述
ALTER TABLE shop.orders ALTER COLUMN amount SET OPTIONS(description='金额（cents）');

-- 数据集（≈Schema）级
ALTER SCHEMA shop SET OPTIONS(description='电商业务库');

-- 读取
SELECT table_name, option_value AS description
FROM `project.shop.INFORMATION_SCHEMA.TABLE_OPTIONS`
WHERE option_name = 'description';

SELECT field_path, description
FROM `project.shop.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
WHERE table_name = 'orders';
```

### ClickHouse（后期补齐，列/表/MV 都可）

ClickHouse 早期版本（<18）完全不支持 COMMENT，后续陆续补齐：18.x 加入列 COMMENT，19.x 加入表 COMMENT，20.x 后逐步覆盖到 MV、索引。

```sql
-- 创建时内联
CREATE TABLE orders (
    id         UInt64        COMMENT '订单主键',
    amount     Decimal(10,2) COMMENT '金额（分）',
    status     String        COMMENT '订单状态',
    created_at DateTime      COMMENT '创建时间'
) ENGINE = MergeTree
ORDER BY id
COMMENT '订单主表';

-- 修改列 COMMENT
ALTER TABLE orders COMMENT COLUMN amount '订单金额（cents）';

-- 修改表 COMMENT
ALTER TABLE orders MODIFY COMMENT '订单主表 v2';

-- 读取
SELECT name, comment FROM system.tables WHERE database='shop' AND name='orders';
SELECT name, comment FROM system.columns WHERE table='orders';
```

### Trino / Presto（语法标准，覆盖逐步扩大）

```sql
COMMENT ON TABLE  hive.shop.orders IS '订单主表';
COMMENT ON COLUMN hive.shop.orders.amount IS '金额';
COMMENT ON SCHEMA hive.shop IS '电商业务库';            -- Trino 357+
COMMENT ON VIEW   hive.shop.v_active_orders IS '活跃订单';
COMMENT ON MATERIALIZED VIEW hive.shop.mv_daily IS '日聚合';  -- Trino 412+

SELECT table_schema, table_name, comment
FROM information_schema.tables
WHERE table_schema='shop';
```

### Spark SQL / Databricks / Hive

```sql
-- 内联 + COMMENT ON 都支持
CREATE TABLE shop.orders (
    id       BIGINT  COMMENT '订单主键',
    amount   DECIMAL(10,2) COMMENT '金额',
    status   STRING  COMMENT '订单状态'
)
USING DELTA
COMMENT '订单主表'
TBLPROPERTIES ('owner'='data-team');

-- ALTER 修改
ALTER TABLE shop.orders ALTER COLUMN amount COMMENT '金额（cents）';
ALTER TABLE shop.orders SET TBLPROPERTIES ('comment'='订单主表 v2');

-- COMMENT ON（Spark 3.x+）
COMMENT ON TABLE shop.orders IS '订单主表 v3';
COMMENT ON COLUMN shop.orders.amount IS '金额（cents）';

-- 读取
DESCRIBE TABLE EXTENDED shop.orders;       -- 末尾有 Comment 行
DESCRIBE FORMATTED shop.orders;             -- Hive 样式
SHOW CREATE TABLE shop.orders;
```

### DuckDB（与 PG 完全一致）

```sql
COMMENT ON TABLE  orders IS '订单主表';
COMMENT ON COLUMN orders.amount IS '金额';
COMMENT ON VIEW   v_active IS '活跃订单';
COMMENT ON SCHEMA shop IS '电商业务库';

SELECT table_name, comment FROM duckdb_tables();
SELECT column_name, comment FROM duckdb_columns() WHERE table_name='orders';
```

### CockroachDB / YugabyteDB（PG 兼容）

均沿用 PostgreSQL 的 `COMMENT ON` 语法和 `pg_description` 系统表，几乎可无缝迁移。CockroachDB 22.1+ 还增加了 COMMENT ON CONSTRAINT。

### TiDB / OceanBase（MySQL 兼容 + Oracle 兼容）

TiDB 完全兼容 MySQL 内联 COMMENT 与 `INFORMATION_SCHEMA.TABLES.TABLE_COMMENT`。OceanBase 双模式（MySQL 模式走 MySQL 语法，Oracle 模式同时支持 `COMMENT ON TABLE/COLUMN`）。

### SQLite（完全没有）

SQLite 是少数完全没有 COMMENT 概念的主流数据库。社区惯用做法是把注释写在 `CREATE TABLE` 的 `--` 单行注释里，因为 `sqlite_master.sql` 列保存原始 DDL 文本。

```sql
CREATE TABLE orders (
    id     INTEGER PRIMARY KEY,  -- 订单主键
    amount REAL                  -- 金额
);

-- 读取（间接方式）
SELECT sql FROM sqlite_master WHERE name='orders';
-- 自己解析 SQL 文本中的 -- 注释
```

### 其他引擎要点

- **Redshift / Greenplum / TimescaleDB**：完全继承 PostgreSQL 语法和 `pg_description`。
- **Vertica**：`COMMENT ON TABLE/COLUMN/SCHEMA/VIEW/PROJECTION/...`，读取走 `v_catalog.comments`。
- **Impala**：用 `ALTER TABLE ... SET TBLPROPERTIES('comment'='...')` 或 `CHANGE COLUMN ... COMMENT`，DESCRIBE FORMATTED 查看。
- **StarRocks / Doris**：仅 MySQL 风格内联 + PROPERTIES。
- **Materialize / RisingWave**：流式数据库，二者都支持 `COMMENT ON`，把注释存入各自的内部目录。
- **Firebird**：从 2.0 开始支持 `COMMENT ON`，存储在 `RDB$DESCRIPTION` BLOB 列。
- **H2 / HSQLDB**：H2 较完整，HSQLDB 仅有限支持。读取时列名是 `REMARKS`（沿用 DB2 命名）。
- **Exasol**：`COMMENT IS` 语法略有不同，`COMMENT ON COLUMN t.c IS 'xx'` 或在 CREATE 时 `c VARCHAR(10) COMMENT IS 'xx'`。
- **SAP HANA**：标准 COMMENT ON + 内联 `c INT COMMENT 'xx'`。
- **Teradata**：`COMMENT ON TABLE db.t IS 'xx'`，`DBC.TablesV.CommentString`。
- **Google Spanner**：完全不支持。需要靠应用层或 Data Catalog 维护。
- **Firebolt / QuestDB / CrateDB / InfluxDB**：均不支持。
- **DatabendDB**：完整支持 COMMENT ON 与内联 COMMENT。

## PostgreSQL `pg_description` 深入

PostgreSQL 把所有非共享对象的注释都塞进一张表 `pg_description`，结构非常优雅：

```sql
\d pg_description
       Column    |  Type   |
   --------------+---------+
    objoid       | oid     | -- 对象 OID
    classoid     | oid     | -- 对象所属 catalog 表的 OID（如 pg_class）
    objsubid     | integer | -- 子对象编号（列编号；0 表示对象本身）
    description  | text    |
```

通过 `(objoid, classoid, objsubid)` 三元组定位任意对象。共享对象（数据库、tablespace、role）走另一张 `pg_shdescription`。

```sql
-- 表和列的所有注释
SELECT
    n.nspname        AS schema_name,
    c.relname        AS table_name,
    a.attname        AS column_name,
    d.description    AS comment
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attribute  a ON a.attrelid = c.oid AND a.attnum > 0
LEFT JOIN pg_description d
       ON d.objoid    = c.oid
      AND d.classoid  = 'pg_class'::regclass
      AND d.objsubid  = COALESCE(a.attnum, 0)
WHERE n.nspname = 'public'
ORDER BY c.relname, a.attnum;

-- 用便捷函数
SELECT obj_description('orders'::regclass)              AS table_comment;
SELECT col_description('orders'::regclass, 1)           AS column_1_comment;
SELECT shobj_description(d.oid, 'pg_database')           AS db_comment
FROM pg_database d WHERE datname='prod';

-- 一次性导出某 schema 所有注释
SELECT
    'COMMENT ON COLUMN ' || quote_ident(n.nspname) || '.' ||
    quote_ident(c.relname) || '.' || quote_ident(a.attname) ||
    ' IS ' || quote_literal(d.description) || ';'
FROM pg_attribute a
JOIN pg_class c     ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_description d
     ON d.objoid = c.oid AND d.objsubid = a.attnum
WHERE n.nspname = 'public' AND a.attnum > 0;
```

设计的优雅之处：所有对象注释统一存储、统一查询，新增对象类型也无须改 schema。这一思路被 CockroachDB、YugabyteDB、Redshift、Greenplum、TimescaleDB、RisingWave 完全继承。

## SQL Server 扩展属性深入

SQL Server 的 Extended Properties 是把双刃剑：极其灵活（任意 name/value 对都能挂在任意对象上），但极其难用。

### 三层结构

每个属性挂在一个 `(class, level0, level1, level2)` 路径上：

| level | type 取值 | 示例 |
|-------|----------|------|
| 0 | SCHEMA / USER / ASSEMBLY / TYPE | `dbo` |
| 1 | TABLE / VIEW / PROCEDURE / FUNCTION / TYPE / RULE / DEFAULT / SYNONYM | `Orders` |
| 2 | COLUMN / INDEX / CONSTRAINT / TRIGGER / PARAMETER | `Amount` |

### 五个存储过程

```sql
sp_addextendedproperty     -- 新增（已存在则报错）
sp_updateextendedproperty  -- 更新（不存在则报错）
sp_dropextendedproperty    -- 删除
sp_addextendedproperty + sp_updateextendedproperty  -- 必须自己判断是新增还是修改
```

### 一键 upsert 模板

社区流传的 idempotent 模板：

```sql
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties
    WHERE major_id = OBJECT_ID('dbo.Orders')
      AND minor_id = COLUMNPROPERTY(OBJECT_ID('dbo.Orders'), 'Amount', 'ColumnId')
      AND name     = 'MS_Description')
BEGIN
    EXEC sp_addextendedproperty 'MS_Description', N'金额（cents）',
        'SCHEMA', 'dbo', 'TABLE', 'Orders', 'COLUMN', 'Amount';
END
ELSE
BEGIN
    EXEC sp_updateextendedproperty 'MS_Description', N'金额（cents）',
        'SCHEMA', 'dbo', 'TABLE', 'Orders', 'COLUMN', 'Amount';
END
```

正是因为这种笨重，社区涌现出大量 wrapper：Redgate、ApexSQL Doc、SQL Server Data Tools 都把 MS_Description 包装成可视化注释面板。dbt-sqlserver 也专门写了 macro 处理 `sp_addextendedproperty`。

## 真实场景：dbt 如何同步描述

dbt 的核心抽象是把字段描述写在 YAML 里，然后通过 `persist_docs` 配置自动同步到数据库 COMMENT。

```yaml
# models/marts/orders.yml
version: 2
models:
  - name: orders
    description: "订单主表，每行一笔订单"
    config:
      persist_docs:
        relation: true
        columns:  true
    columns:
      - name: id
        description: "订单主键"
      - name: amount
        description: "订单金额（USD）"
      - name: status
        description: "PENDING/PAID/SHIPPED/CANCELLED"
```

dbt 会根据适配器生成对应 SQL：

- PostgreSQL/Redshift/Snowflake：`COMMENT ON TABLE / COMMENT ON COLUMN`
- BigQuery：`ALTER TABLE ... SET OPTIONS(description=...)`
- Databricks：`COMMENT ON / ALTER TABLE ... ALTER COLUMN ... COMMENT`
- SQL Server：`sp_addextendedproperty` + 自检逻辑
- SQLite：跳过（不支持）

这就是为什么 SQL 标准 COMMENT ON 与 BigQuery OPTIONS 模式的差异会直接影响 dbt 模型的可移植性。

## 关键发现

1. **COMMENT 是 SQL 标准里被遗忘的角落**。SQL:2003 只规定了 TABLE 和 COLUMN，连读取方式都没标准化。`INFORMATION_SCHEMA` 标准视图至今没有 `COMMENT` 列，每个厂商都自己加列、自己起名（`TABLE_COMMENT` / `COMMENT` / `REMARKS`），互不兼容。

2. **三大语法流派**：
   - **SQL 标准派**（`COMMENT ON TABLE x IS 'xx'`）：PostgreSQL、Oracle、DB2、Trino、Snowflake、Redshift、DuckDB、CockroachDB、YugabyteDB、Vertica、Materialize、RisingWave、Firebird、Exasol、SAP HANA、Teradata、Greenplum、TimescaleDB、DatabendDB、Yellowbrick、MonetDB、H2 — 共 21+ 个引擎。
   - **MySQL 内联派**（`col TYPE COMMENT 'xx'` + `TABLE … COMMENT='xx'`）：MySQL、MariaDB、TiDB、SingleStore、StarRocks、Doris、ClickHouse、Snowflake、Spark/Hive/Databricks、SAP HANA、H2、DatabendDB —— MySQL 派和标准派**很多引擎同时支持**。
   - **OPTIONS / Extended Properties 派**：BigQuery（`OPTIONS(description=)`）、SQL Server / Azure Synapse（`sp_addextendedproperty MS_Description`）。

3. **PostgreSQL 是对象覆盖最完整的引擎**，几乎所有数据库对象（TABLE/COLUMN/SCHEMA/DATABASE/INDEX/VIEW/MV/CONSTRAINT/FUNCTION/TYPE/DOMAIN/TRIGGER/SEQUENCE/OPERATOR/RULE/AGGREGATE/EXTENSION/ROLE）都能加注释，且统一存于 `pg_description`/`pg_shdescription`。

4. **Oracle 反差**：作为最早商业实现 COMMENT ON 的厂商（v7, 1992），它对对象的覆盖**远不如** PostgreSQL，没有 SCHEMA/FUNCTION/CONSTRAINT 注释。但它在 `ALL_TAB_COMMENTS` / `ALL_COL_COMMENTS` 视图上的工具集成是最早的。

5. **MySQL 的内联模式有严重缺陷**：修改列注释必须重写整个列定义（`ALTER MODIFY COLUMN`），导致 ORM 工具生成的 DDL 极易出错，迁移失败率高。

6. **SQL Server 的扩展属性是"最难用却最强大"**：`sp_addextendedproperty` 一次调用 5-7 个参数；既要 `add` 又要 `update` 还要先 EXISTS 判断；但它不仅能存 `MS_Description`，还能存任意命名空间的属性，作为非侵入式的元数据存储其实非常强大。dbt-sqlserver、SSDT、Redgate 都自己写了 wrapper 来掩盖丑陋。

7. **BigQuery 走的是 OPTIONS 路线**：所有元数据（描述、标签、分区、TTL）都通过 `OPTIONS(...)` 统一处理，是 Google 内部对"元数据即配置"理念的体现。Spanner 则连 OPTIONS 都没有。

8. **SQLite 完全没有 COMMENT 支持**，所有"注释"靠 `sqlite_master.sql` 中保留的 DDL 文本里的 `--` 注释。

9. **云数仓比传统数仓更重视 COMMENT**：Snowflake、Databricks、BigQuery、Redshift 都把 COMMENT 当一等公民暴露在 `INFORMATION_SCHEMA` 中，原因是它们的客户更依赖数据治理和血缘工具。

10. **`REMARKS` vs `COMMENT` vs `description`**：DB2、H2、HSQLDB 沿用 `REMARKS`（IBM 传统）；Snowflake、Trino、ClickHouse、Vertica 用 `COMMENT`；BigQuery、Spanner、SQL Server 用 `description`。JDBC `DatabaseMetaData.getColumns()` 返回的字段叫 `REMARKS`（继承 DB2 命名），是 Java 生态的事实标准。

11. **dbt 是 COMMENT 复兴的最大推手**。`persist_docs` 配置让 YAML 描述自动同步到 DB，极大推动了 COMMENT 的实际使用。如果你的团队还在"COMMENT 写不写都行"的阶段，引入 dbt + `persist_docs` 是最低成本的升级。

12. **AI 时代 COMMENT 的价值在飙升**。Text-to-SQL、自动化数据探索、Copilot 类工具都强依赖 COMMENT 作为字段语义信号源。一个有完整 COMMENT 的 schema，相比裸 schema，LLM 生成 SQL 的准确率可提升 30%+。COMMENT 不再是"可选文档"，而是 LLM 友好型 schema 的必备成分。

13. **流式数据库的反直觉支持**：Materialize、RisingWave 这些新兴流式数据库都支持 COMMENT ON，反而 Flink SQL 的 COMMENT 支持要等到 1.11 才补齐，且只覆盖 CREATE TABLE 的内联用法。

14. **互操作性的痛点**：跨引擎迁移时，COMMENT 几乎是最容易丢失的元数据。PG → SQL Server 必须把 `COMMENT ON` 转成 `sp_addextendedproperty`，PG → BigQuery 必须转成 `OPTIONS(description=)`，PG → SQLite 直接丢弃。Liquibase、Flyway、SchemaSpy 都在不同程度上做这种翻译，但都不完美。

15. **行动建议**：
    - 在所有新建表/列上强制写 COMMENT（用 SQL linter 或 CI 检查）
    - 用 dbt 的 `persist_docs` 同步 YAML 描述到数据库
    - 把敏感字段标签（PII / PCI / GDPR）作为 COMMENT 前缀，便于扫描
    - 在 COMMENT 中嵌入轻量结构化标签（`[owner=data-team][pii=false]`）作为数据契约的雏形
    - 跨引擎迁移时，单独写一个 COMMENT 翻译层，不要依赖通用迁移工具

COMMENT 不是文档的替代品，它是写在 schema 里的"机器可读契约"。一个有 COMMENT 的数据库，对 LLM、对工具、对接手者，都是友好的；一个没有 COMMENT 的数据库，迟早会变成无人敢动的黑盒。
