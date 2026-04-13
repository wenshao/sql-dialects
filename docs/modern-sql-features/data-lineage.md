# 数据血缘与查询溯源 (Data Lineage and Query Provenance)

当一份关键报表数字出错，工程师需要在十分钟内回答："这个字段是从哪些表、哪些列、经过哪些 SQL 算出来的？"——这就是数据血缘 (Data Lineage)。它是数据治理 (Data Governance)、合规审计 (GDPR / HIPAA / SOX)、影响分析 (Impact Analysis)、敏感字段追踪 (PII Tracking) 与故障定位的底层基础设施。在云数仓时代，它已经从"可选的元数据工具"演变为"内置的引擎能力"。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准）至今没有定义数据血缘相关的语法或视图。`INFORMATION_SCHEMA` 仅描述对象 (table / column / view) 的结构，并不描述对象之间的"派生关系"。因此当前所有数据血缘能力都是供应商私有扩展，并且呈现两种主流形态：

1. **引擎内置血缘视图**：典型如 Snowflake `ACCESS_HISTORY`、Databricks Unity Catalog Lineage、BigQuery Data Lineage (Dataplex)、SQL Server `sys.dm_sql_referenced_entities`、Oracle `DBMS_UTILITY.EXPAND_SQL_TEXT`。
2. **外部血缘平台与协议**：典型如 OpenLineage（LF AI & Data, 2020+）、Apache Atlas（Hortonworks 2015+）、Marquez (OpenLineage 参考实现)、DataHub (LinkedIn)、Amundsen (Lyft)、sqllineage (Python 库) 等。

这是一个仍在快速演进的新兴领域，云数仓领先，传统 RDBMS 落后。

## 支持矩阵（综合）

下表按"是否在引擎内提供血缘能力"为视角，统一比较 49 个数据库 / 引擎。"--"表示不支持或需依赖外部工具。

### 1. 列级血缘 (Column-level Lineage) 与表级血缘 (Table-level Lineage)

| 引擎 | 内置列级血缘 | 内置表级血缘 | 提供方式 | GA 时间 |
|------|------------|------------|---------|---------|
| PostgreSQL | -- | 部分 (pg_depend) | 系统目录 (对象依赖) | -- |
| MySQL | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- |
| Oracle | -- | 是 | `DBA_DEPENDENCIES` / `DBMS_UTILITY.EXPAND_SQL_TEXT` | 早期 |
| SQL Server | 部分 | 是 | `sys.dm_sql_referenced_entities` / `sys.sql_expression_dependencies` | 2008+ |
| DB2 | -- | 是 | `SYSCAT.TABDEP` / `SYSCAT.VIEWDEP` | 早期 |
| Snowflake | 是 | 是 | `ACCESS_HISTORY` (BASE_OBJECTS_ACCESSED / OBJECTS_MODIFIED) | 列级 2022 |
| BigQuery | 是 | 是 | Dataplex Data Lineage API + `INFORMATION_SCHEMA.JOBS` | 2023 |
| Redshift | -- | 部分 | `STL_QUERY` + `STL_DDLTEXT` (需自行解析) | -- |
| DuckDB | -- | -- | `json_serialize_sql` (parse tree) 自行解析 | -- |
| ClickHouse | -- | 部分 | `system.query_log` + `databases / tables` | -- |
| Trino | -- | 部分 | Query Analyzer / Event Listener | -- |
| Presto | -- | 部分 | Event Listener SPI | -- |
| Spark SQL | -- | 部分 | LogicalPlan + OpenLineage Spark Listener | OL 集成 2021 |
| Hive | -- | 部分 | Hive Hook + Apache Atlas | Atlas 2015 |
| Flink SQL | -- | 部分 | Job Graph + OpenLineage Flink Listener | OL 集成 2023 |
| Databricks | 是 | 是 | Unity Catalog Lineage (列级) | 2023 |
| Teradata | -- | 部分 | `DBC.Tables` 依赖 + Viewpoint | -- |
| Greenplum | -- | 部分 | 继承 PostgreSQL `pg_depend` | -- |
| CockroachDB | -- | -- | -- | -- |
| TiDB | -- | -- | -- | -- |
| OceanBase | -- | -- | -- | -- |
| YugabyteDB | -- | 部分 | 继承 PostgreSQL `pg_depend` | -- |
| SingleStore | -- | -- | -- | -- |
| Vertica | -- | 部分 | `V_CATALOG.VIEW_TABLES` | -- |
| Impala | -- | 部分 | Hive Metastore + Atlas | -- |
| StarRocks | -- | -- | -- | -- |
| Doris | -- | -- | -- | -- |
| MonetDB | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | -- | 部分 | 继承 PostgreSQL `pg_depend` | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- |
| SAP HANA | -- | 部分 | `SYS.OBJECT_DEPENDENCIES` | 早期 |
| Informix | -- | 部分 | `sysdepend` | 早期 |
| Firebird | -- | 部分 | `RDB$DEPENDENCIES` | 早期 |
| H2 | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- |
| Derby | -- | -- | `SYS.SYSDEPENDS` (限定) | -- |
| Amazon Athena | -- | 部分 | AWS Glue Data Catalog | -- |
| Azure Synapse | -- | 部分 | Microsoft Purview 集成 | -- |
| Google Spanner | -- | -- | -- | -- |
| Materialize | -- | 部分 | `mz_catalog.mz_object_dependencies` | -- |
| RisingWave | -- | 部分 | `rw_catalog.rw_relation_dependencies` | -- |
| InfluxDB (SQL) | -- | -- | -- | -- |
| Databend | -- | -- | -- | -- |
| Yellowbrick | -- | 部分 | 继承 PostgreSQL `pg_depend` | -- |
| Firebolt | -- | -- | -- | -- |

> 统计：仅 3 个引擎（Snowflake、Databricks、BigQuery）在引擎内原生支持完整的"列级"血缘；约 18 个引擎可以查询"表 / 视图级"对象依赖关系；其余引擎完全依赖外部工具。

### 2. 血缘图查询 / 语句级溯源

| 引擎 | 血缘图查询 (Graph Query) | 语句级溯源 (Per-Statement Provenance) | 接口 |
|------|------------------------|-------------------------------------|------|
| PostgreSQL | `pg_depend` 递归 CTE | `pg_stat_statements` (无对象解析) | -- |
| MySQL | -- | `performance_schema.events_statements_history` | -- |
| MariaDB | -- | `performance_schema` | -- |
| Oracle | `DBA_DEPENDENCIES` 递归 | `V$SQL` + `DBMS_XPLAN` | -- |
| SQL Server | `sys.dm_sql_referenced_entities` (单跳) | Query Store + Extended Events | XEL |
| DB2 | `SYSCAT.TABDEP` 递归 | `MON_GET_PKG_CACHE_STMT` | -- |
| Snowflake | `ACCESS_HISTORY` JOIN | `QUERY_HISTORY` + `ACCESS_HISTORY` | INFORMATION_SCHEMA |
| BigQuery | Dataplex Lineage API | `INFORMATION_SCHEMA.JOBS_BY_PROJECT` | REST API |
| Redshift | -- | `STL_QUERY` / `SVL_QUERY_REPORT` | -- |
| Databricks | Unity Catalog Lineage Graph | `system.access.audit` | REST API |
| Trino | Event Listener Plugin | Event Listener | -- |
| Presto | Event Listener SPI | Event Listener | -- |
| Spark SQL | OpenLineage Listener | OpenLineage Run Event | OL JSON |
| Flink SQL | OpenLineage Listener | OpenLineage Run Event | OL JSON |
| Hive | Hook + Atlas | Hive Hook | Atlas REST |
| Vertica | `V_CATALOG.VIEW_TABLES` 递归 | `QUERY_REQUESTS` | -- |
| SAP HANA | `OBJECT_DEPENDENCIES` 递归 | `M_SQL_PLAN_CACHE` | -- |
| Materialize | `mz_object_dependencies` 递归 | -- | -- |
| RisingWave | `rw_relation_dependencies` 递归 | -- | -- |

### 3. 解析树导出 (Parse Tree Export) 与 SQL 重写审计

| 引擎 | 解析树导出 | 函数 / 命令 | SQL 重写审计 |
|------|----------|------------|------------|
| PostgreSQL | -- (需 `pg_query` C 库) | -- | -- |
| MySQL | -- | -- | -- |
| Oracle | `DBMS_UTILITY.EXPAND_SQL_TEXT` | 视图展开 | 是 (`V$SQL_SHARED_CURSOR`) |
| SQL Server | `sys.dm_exec_query_plan` (XML) | -- | -- |
| DB2 | `EXPLAIN` JSON | -- | -- |
| Snowflake | `GET_OBJECT_REFERENCES` | UDF | -- |
| BigQuery | `EXPLAIN` 阶段树 | -- | -- |
| Spark SQL | `EXPLAIN EXTENDED` (Logical Plan tree) | `df.queryExecution.logical` | 是 |
| DuckDB | `json_serialize_sql('SELECT ...')` | 标量函数 | -- |
| Trino | `EXPLAIN (TYPE LOGICAL, FORMAT JSON)` | -- | -- |
| Presto | `EXPLAIN (TYPE LOGICAL)` | -- | -- |
| ClickHouse | `EXPLAIN AST` | -- | -- |
| CockroachDB | `EXPLAIN (OPT, VERBOSE)` | -- | -- |
| TiDB | `EXPLAIN ANALYZE` JSON | -- | -- |
| Materialize | `EXPLAIN RAW PLAN` | -- | 是 |
| RisingWave | `EXPLAIN (TYPE LOGICAL)` | -- | -- |

> 仅 DuckDB 直接以 SQL 标量函数返回 JSON 格式的 AST (`json_serialize_sql`)，这是其用于教学和血缘工具构建的独特优势。

### 4. GRANT / 审计事件追踪

GRANT、REVOKE、登录、对象访问等事件是血缘的"底层证据链"。详细对比请参见 [audit-logging.md](./audit-logging.md)。本文仅列出与血缘最相关的能力：

| 引擎 | GRANT 审计 | 行级访问审计 | 列级访问审计 |
|------|-----------|------------|------------|
| PostgreSQL | `pgaudit` 扩展 | `pgaudit` ROW | -- |
| MySQL | Audit Plugin | -- | -- |
| Oracle | Unified Audit (FGA) | FGA `DBMS_FGA` | FGA |
| SQL Server | SQL Audit | SQL Audit | -- |
| DB2 | Audit Facility | 是 | -- |
| Snowflake | `ACCESS_HISTORY` | `ACCESS_HISTORY` | `ACCESS_HISTORY` (列级) |
| BigQuery | Cloud Audit Logs | Data Access Logs | `INFORMATION_SCHEMA.JOBS` 列引用 |
| Redshift | `STL_USERLOG` / Audit Logs | `SVL_STATEMENTTEXT` | -- |
| Databricks | `system.access.audit` | Unity Catalog | UC Lineage 列级 |
| Trino | Event Listener | Event Listener | -- |
| Spark SQL | Hook | -- | -- |
| Hive | Hook + Ranger | Ranger | Ranger 列脱敏 |

### 5. OpenLineage / Apache Atlas / 数据目录集成

| 引擎 | OpenLineage | Apache Atlas | Unity Catalog | Snowflake Horizon | BigQuery Data Catalog | AWS Glue | Microsoft Purview |
|------|------------|--------------|---------------|-------------------|----------------------|---------|------------------|
| Snowflake | 第三方 | 第三方 | -- | 原生 | -- | 是 | 是 |
| Databricks | 原生 | 第三方 | 原生 | -- | -- | 是 | 是 |
| BigQuery | 第三方 | 第三方 | -- | -- | 原生 (Dataplex) | -- | 是 |
| Redshift | 第三方 | 第三方 | -- | -- | -- | 原生 | 是 |
| Spark SQL | 原生 (Spark Listener) | 是 (Atlas Hook) | 是 (UC on Spark) | -- | -- | 是 | 是 |
| Flink SQL | 原生 (Flink Listener, 1.17+) | 是 | -- | -- | -- | -- | -- |
| Hive | 第三方 | 原生 (Hive Hook) | -- | -- | -- | 是 | -- |
| Impala | -- | 原生 (Impala Hook) | -- | -- | -- | -- | -- |
| Trino | 第三方 (Plugin) | 第三方 | -- | -- | -- | 是 | 是 |
| Presto | 第三方 | 第三方 | -- | -- | -- | 是 | -- |
| PostgreSQL | 第三方 (sqllineage) | -- | -- | -- | -- | -- | 是 |
| Oracle | 第三方 | -- | -- | -- | -- | -- | 是 |
| SQL Server | 第三方 | -- | -- | -- | -- | -- | 原生 |
| MySQL | 第三方 | -- | -- | -- | -- | 是 | 是 |
| Athena | 第三方 | -- | -- | -- | -- | 原生 | -- |
| Synapse | 第三方 | -- | -- | -- | -- | -- | 原生 |
| dbt (SQL 编排) | 原生 | -- | 是 | 是 | 是 | 是 | 是 |
| Airflow | 原生 | 第三方 | 是 | 是 | 是 | 是 | 是 |

> "原生"指引擎或工具官方维护的连接器；"第三方"指由 OpenLineage 社区或独立项目（如 sqllineage、Marquez、DataHub）维护的解析器。

### 6. 视图 / 物化视图血缘

视图本身就是"血缘节点"——它的定义即输入到输出的派生函数。物化视图更进一步：它存储派生结果，因此一致性、新鲜度、回溯都依赖血缘元数据。

| 引擎 | 视图血缘 | 物化视图血缘 | 列级追踪 | 失效传播 |
|------|--------|-------------|---------|---------|
| PostgreSQL | `pg_rewrite` | `pg_class` (relkind='m') | -- | 手动 REFRESH |
| Oracle | `DBA_DEPENDENCIES` | `DBA_MVIEW_REFRESH_TIMES` | -- | FAST REFRESH 依赖 |
| SQL Server | `sys.sql_expression_dependencies` | Indexed View | 部分 | 自动 |
| DB2 | `SYSCAT.VIEWDEP` | MQT (`SYSCAT.TABLES.PROPERTY`) | -- | 自动 |
| Snowflake | `ACCESS_HISTORY` | `INFORMATION_SCHEMA.MATERIALIZED_VIEWS` | 是 | 自动 |
| BigQuery | Dataplex Lineage | Materialized Views | 是 | 自动 |
| Redshift | -- | `STV_MV_INFO` | -- | 手动 / 自动 |
| Databricks | Unity Catalog | UC + Delta Live Tables | 是 (DLT) | 自动 |
| ClickHouse | `system.tables` | `system.tables` (engine=MaterializedView) | -- | -- |
| Materialize | `mz_object_dependencies` | 原生 (核心模型) | -- | 自动 (增量) |
| RisingWave | `rw_relation_dependencies` | 原生 (核心模型) | -- | 自动 (增量) |
| Hive | Atlas | Materialized Views | -- | -- |
| Spark SQL | LogicalPlan | -- | -- | -- |
| Trino | Event Listener | Materialized Views | -- | -- |
| SAP HANA | `OBJECT_DEPENDENCIES` | -- | -- | -- |
| Vertica | `V_CATALOG.VIEW_TABLES` | Projection (类似) | -- | 自动 |

## 详细引擎对比

### Snowflake：ACCESS_HISTORY 深度剖析

Snowflake 在 2021 年正式 GA `ACCOUNT_USAGE.ACCESS_HISTORY` 视图，2022 年初将其扩展为列级粒度。这是云数仓领域第一个"零配置 + 列级 + 持久化"的内置血缘方案。

```sql
-- 1. 查看最近 7 天对 customer_pii 表的所有访问 (基对象级)
SELECT query_id,
       user_name,
       direct_objects_accessed,
       base_objects_accessed,
       objects_modified
FROM   snowflake.account_usage.access_history
WHERE  query_start_time > DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND  ARRAY_CONTAINS(
         'PROD.CRM.CUSTOMER_PII'::VARIANT,
         BASE_OBJECTS_ACCESSED:objectName
       );
```

字段语义：

- `DIRECT_OBJECTS_ACCESSED`：SQL 文本中"直接"引用的对象（视图本身）。
- `BASE_OBJECTS_ACCESSED`：解析视图后真正被读取的"基表"。这是 Snowflake 血缘的关键创新——它穿透多层视图嵌套。
- `OBJECTS_MODIFIED`：被 INSERT / UPDATE / MERGE / DELETE / CTAS 写入的对象。
- `OBJECTS_MODIFIED.columns.directSources`：列级"输入列 → 输出列"映射。

```sql
-- 2. 列级血缘：找出 fct_revenue.gross_amount 是从哪些列派生而来
SELECT modified.value:objectName::STRING                    AS target_table,
       cols.value:columnName::STRING                         AS target_column,
       src.value:objectName::STRING                          AS source_table,
       src.value:columnName::STRING                          AS source_column,
       query_id, query_start_time
FROM   snowflake.account_usage.access_history,
       LATERAL FLATTEN(input => objects_modified)            modified,
       LATERAL FLATTEN(input => modified.value:columns)      cols,
       LATERAL FLATTEN(input => cols.value:directSources)    src
WHERE  modified.value:objectName::STRING = 'PROD.MART.FCT_REVENUE'
  AND  cols.value:columnName::STRING     = 'GROSS_AMOUNT'
ORDER  BY query_start_time DESC
LIMIT  100;
```

辅助函数 `GET_OBJECT_REFERENCES` 用于"静态分析"一个视图的依赖（无需执行）：

```sql
SELECT * FROM TABLE(
  INFORMATION_SCHEMA.GET_OBJECT_REFERENCES(
    DATABASE_NAME => 'PROD',
    SCHEMA_NAME   => 'MART',
    OBJECT_NAME   => 'V_CUSTOMER_360'
  )
);
```

2023 年起，Snowflake 将上述能力整合进 **Horizon Data Governance**，包括分类标签 (Classification)、Tag-based Policy、Trust Center 与跨账号 Lineage UI。对管理员而言，最实用的是把 `ACCESS_HISTORY` 与 `TAG_REFERENCES` 关联，自动找出"哪些查询访问了 PII 标签的列"。

延迟：`ACCOUNT_USAGE` 视图为最终一致，典型延迟 45 分钟到 3 小时。需要实时血缘的场景应使用 `INFORMATION_SCHEMA.QUERY_HISTORY`（仅 14 天，数据库级）或事件订阅。

### Databricks Unity Catalog 列级血缘

Databricks 在 2023 年将 Unity Catalog Lineage 推到 GA，并同时支持表级和列级。它是"workspace × cluster × notebook × SQL Warehouse"四个维度统一的血缘方案。

```python
# Spark / Python：通过 SDK 查询血缘
from databricks.sdk import WorkspaceClient
w = WorkspaceClient()

# 表级血缘（上游 + 下游）
lineage = w.table_lineage.get(
    table_name="prod.mart.fct_revenue",
    include_entity_lineage=True,
)
for upstream in lineage.upstreams:
    print(upstream.tableinfo.name)
```

```sql
-- SQL：通过 system.access 表查询访问与血缘事件
SELECT event_time,
       source_table_full_name,
       source_column_name,
       target_table_full_name,
       target_column_name,
       entity_type
FROM   system.access.column_lineage
WHERE  target_table_full_name = 'prod.mart.fct_revenue'
  AND  target_column_name     = 'gross_amount'
  AND  event_time > current_timestamp() - INTERVAL 7 DAYS;
```

UC Lineage 的几个关键设计：

1. **零侵入**：只要在 Unity Catalog 启用的工作区运行 SQL / DataFrame / dbt / Delta Live Tables，列级血缘自动捕获，无需启用 hook。
2. **跨语言**：Python `df.select(...)`、Scala、SQL、R 都能解析为相同的列血缘节点。
3. **30 天保留**：`system.access.column_lineage` 默认保留 30 天，需更长期保留可订阅到 Delta 表。
4. **集成 dbt**：dbt manifest 自动作为额外节点写入血缘图，支持模型 → 物理表的双向跳转。

### BigQuery Data Lineage (Dataplex)

BigQuery 在 2023 年通过 Dataplex Universal Catalog GA 了 Data Lineage。它与传统的 BigQuery `INFORMATION_SCHEMA.JOBS` 联合使用：前者提供血缘图，后者提供原始查询和列引用。

```sql
-- 通过 INFORMATION_SCHEMA.JOBS_BY_PROJECT 找到引用某列的所有查询
SELECT job_id,
       user_email,
       query,
       referenced_tables
FROM   `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
                         AND CURRENT_TIMESTAMP()
  AND  EXISTS (
         SELECT 1 FROM UNNEST(referenced_tables) t
         WHERE  t.project_id = 'prod'
           AND  t.dataset_id = 'crm'
           AND  t.table_id   = 'customer_pii'
       );
```

```bash
# Dataplex Lineage API：查询某表的上游
gcloud data-catalog lineage links search \
    --location=us \
    --target=projects/prod/datasets/mart/tables/fct_revenue
```

Dataplex Lineage 自动覆盖：BigQuery SQL、Dataflow、Cloud Composer (Airflow) 与 Cloud Data Fusion。对外部 Spark / Glue 任务则需要手动通过 `LineageEvent` API 上报。

### SQL Server：sys.dm_sql_referenced_entities

SQL Server 自 2008 起提供"对象级"的依赖分析视图，是传统 RDBMS 中血缘能力最完善的。

```sql
-- 找出 sales.vw_customer_360 引用的所有底层对象
SELECT referenced_schema_name,
       referenced_entity_name,
       referenced_minor_name,            -- 列名
       referenced_class_desc,
       is_selected, is_updated
FROM   sys.dm_sql_referenced_entities(
         'sales.vw_customer_360',
         'OBJECT'
       );

-- 反向：找出引用 dbo.customer_pii.email 列的所有对象
SELECT referencing_schema_name,
       referencing_entity_name
FROM   sys.dm_sql_referencing_entities(
         'dbo.customer_pii',
         'OBJECT'
       );
```

`sys.sql_expression_dependencies` 提供持久化的依赖目录，但只覆盖"按名称引用"的对象（运行时动态 SQL 不计入）。

### Oracle：DBMS_METADATA 与 EXPAND_SQL_TEXT

Oracle 的对象依赖通过 `DBA_DEPENDENCIES` 长期存在；血缘关键还在于"展开视图嵌套"的能力：

```sql
-- 1. 展开嵌套视图，得到等价的"无视图" SQL
DECLARE
  v_sql CLOB;
BEGIN
  DBMS_UTILITY.EXPAND_SQL_TEXT(
    input_sql_text  => 'SELECT * FROM sales.v_customer_360 WHERE region = :1',
    output_sql_text => v_sql
  );
  DBMS_OUTPUT.PUT_LINE(v_sql);
END;
/

-- 2. 递归依赖图
SELECT LPAD(' ', 2*LEVEL) || referenced_owner || '.' || referenced_name AS dep
FROM   dba_dependencies
START  WITH owner = 'SALES' AND name = 'V_CUSTOMER_360'
CONNECT BY PRIOR referenced_owner = owner
       AND PRIOR referenced_name  = name;
```

Oracle 的列级血缘需要付费组件 Oracle Enterprise Manager Data Masking / Oracle Data Integrator (ODI)，并不在 Database 内核中。

### PostgreSQL：pg_depend + pg_rewrite

PostgreSQL 拥有强大的对象依赖系统目录 `pg_depend`（用于 `DROP CASCADE` 等操作），但**没有列级血缘**——`pg_depend` 只跟踪对象到对象的关系，不跟踪表达式 / 派生。

```sql
-- 找出 schema.view_name 的直接依赖对象
SELECT DISTINCT
       refobj.relname AS referenced_table,
       refobj.relnamespace::regnamespace AS schema
FROM   pg_depend d
JOIN   pg_rewrite r  ON r.oid = d.objid
JOIN   pg_class c    ON c.oid = r.ev_class
JOIN   pg_class refobj ON refobj.oid = d.refobjid
WHERE  c.relname  = 'v_customer_360'
  AND  d.deptype  = 'n'
  AND  d.classid  = 'pg_rewrite'::regclass
  AND  d.refclassid = 'pg_class'::regclass;
```

要在 PostgreSQL 中实现列级血缘，常用方案是：
1. 通过 `pg_query` C 库或 [libpg_query](https://github.com/pganalyze/libpg_query) 解析 AST。
2. 安装 [sqllineage](https://github.com/reata/sqllineage) Python 库或 [DataHub](https://datahubproject.io/) 数据目录。
3. 启用 `pgaudit` 抓取语句文本，离线解析。

### Trino / Presto：Event Listener Plugin

Trino 与 Presto 通过 **Event Listener SPI** 将每个查询的元信息推送给外部系统。事件中包括完整的输入表、输出表与查询统计：

```java
// Trino EventListener 接收的 QueryCompletedEvent (节选)
event.getIoMetadata().getInputs();   // 输入对象 List<TableInfo>
event.getIoMetadata().getOutput();   // 输出对象 (CTAS / INSERT)
event.getMetadata().getQuery();      // 完整 SQL 文本
event.getMetadata().getColumns();    // 列引用列表 (含 schema.table.column)
```

OpenLineage 提供了官方的 Trino Plugin，将 `QueryCompletedEvent` 转换为 OpenLineage `RunEvent` JSON 上报。

### Redshift：STL_QUERY + STL_DDLTEXT

Redshift 没有内置血缘 API，但提供极其完整的查询审计视图，配合外部解析器即可重建血缘：

```sql
SELECT q.query, q.userid, q.starttime, q.endtime,
       LISTAGG(s.text, '') WITHIN GROUP (ORDER BY s.sequence) AS sql_text
FROM   stl_query q
JOIN   stl_querytext s USING (query)
WHERE  q.starttime > GETDATE() - INTERVAL '7 days'
GROUP  BY q.query, q.userid, q.starttime, q.endtime;
```

`STL_DDLTEXT` 进一步保存了所有 DDL 文本，便于分析视图血缘。Redshift 的"完整"血缘通常通过 AWS Glue Data Catalog + Spectrum + sqllineage 完成。

### Spark SQL：LogicalPlan 与 OpenLineage

Spark SQL 的 `LogicalPlan` 树是其血缘解析的核心。OpenLineage 的 [Spark integration](https://openlineage.io/docs/integrations/spark/) 通过 `QueryExecutionListener` 在每次 Action 完成时遍历 LogicalPlan，提取列级 `InputField → OutputField` 映射：

```scala
spark.conf.set(
  "spark.extraListeners",
  "io.openlineage.spark.agent.OpenLineageSparkListener"
)
spark.conf.set("spark.openlineage.transport.type", "http")
spark.conf.set("spark.openlineage.transport.url",  "http://marquez:5000")
```

```scala
// 直接打印 LogicalPlan，可用于教学和血缘调试
val df = spark.sql("SELECT a.id, b.name FROM a JOIN b ON a.id = b.id")
println(df.queryExecution.analyzed.treeString)
```

### DuckDB：json_serialize_sql

DuckDB 是少数将"解析树"作为 SQL 标量函数暴露的引擎，这让构建血缘工具变得极其简单：

```sql
SELECT json_serialize_sql(
  'SELECT customer_id, SUM(amount) AS total
   FROM orders WHERE region = ''US'' GROUP BY customer_id'
);
-- 返回完整 JSON AST
```

```sql
-- 反向：把 JSON AST 重新序列化为 SQL
SELECT json_deserialize_sql('{...}');
```

由于 DuckDB 通常嵌入到 Python 进程中，sqllineage / OpenLineage 可以直接复用上述 JSON。

### 外部血缘工具

- **OpenLineage** (LF AI & Data, 2020+)：与引擎无关的血缘事件协议（`RunEvent`、`InputDataset`、`OutputDataset`、`columnLineage` facet）。已被 Marquez、DataHub、Atlan、Manta、Astronomer 等产品支持。
- **Marquez**：OpenLineage 的参考实现，开源元数据存储与血缘 UI。
- **Apache Atlas** (Hortonworks, ~2015 起)：Hadoop 生态的元数据治理平台，原生集成 Hive / HBase / Kafka / Storm / Sqoop。
- **DataHub** (LinkedIn, 2019)：开源元数据平台，支持 200+ 数据源和列级血缘。
- **sqllineage** (开源 Python 库)：纯解析式工具，零依赖，支持 Trino / Snowflake / SparkSQL / BigQuery / PostgreSQL / MySQL 等方言。
- **dbt**：将 SQL 项目作为 DAG 编译，`manifest.json` + `catalog.json` 是事实标准的血缘元数据来源。
- **Manta、Collibra、Alation**：商业血缘 / 数据目录平台。

### ClickHouse：query_log + 系统目录

ClickHouse 没有专门的血缘视图，但 `system.query_log` 提供了非常完整的查询审计字段，可作为血缘重建的源头：

```sql
SELECT event_time,
       user,
       query,
       databases,
       tables,
       columns,
       projections,
       views,
       written_rows,
       written_bytes
FROM   system.query_log
WHERE  event_time > now() - INTERVAL 7 DAY
  AND  type = 'QueryFinish'
  AND  has(tables, 'analytics.events');
```

`tables` 与 `columns` 字段是 ClickHouse 在 21.x 后内置的"被引用对象"列表，由查询解析器写入。结合 `system.tables` 中的 `dependencies_database` / `dependencies_table` 即可重建物化视图链路。

### Materialize / RisingWave：增量血缘

流式数仓的核心是物化视图，因此血缘是**第一类内核数据结构**。Materialize 提供 `mz_catalog.mz_object_dependencies`：

```sql
WITH RECURSIVE deps(object_id, depth) AS (
  SELECT object_id, 0
  FROM   mz_catalog.mz_object_dependencies
  WHERE  referenced_object_id =
         (SELECT id FROM mz_catalog.mz_objects WHERE name = 'src_orders')
  UNION  ALL
  SELECT d.object_id, deps.depth + 1
  FROM   mz_catalog.mz_object_dependencies d
  JOIN   deps ON d.referenced_object_id = deps.object_id
)
SELECT o.name, deps.depth
FROM   deps JOIN mz_catalog.mz_objects o USING (object_id)
ORDER  BY deps.depth;
```

RisingWave 提供等价的 `rw_catalog.rw_relation_dependencies`。两者都不提供列级血缘，但因为视图本身就是"长期常驻的算子图"，UI 工具可以直接将 LogicalPlan 渲染为列级 DAG。

### Apache Hive：Atlas Hook 与 LineageLogger

Hive 是较早内置血缘 Hook 的引擎。`hive.exec.post.hooks=org.apache.hadoop.hive.ql.hooks.LineageLogger` 启用后，每条查询执行完毕都会写出列级输入输出 JSON：

```bash
SET hive.exec.post.hooks=org.apache.hadoop.hive.ql.hooks.LineageLogger;
INSERT OVERWRITE TABLE mart.fct_revenue
SELECT customer_id, SUM(amount) FROM orders GROUP BY customer_id;
```

LineageLogger 输出示例：

```json
{
  "version": "1.0",
  "user": "etl",
  "timestamp": 1712956800,
  "duration": 14523,
  "jobIds": ["job_..."],
  "engine": "tez",
  "database": "mart",
  "hash": "...",
  "queryText": "INSERT OVERWRITE ...",
  "edges": [
    {"sources": [0], "targets": [2], "edgeType": "PROJECTION"},
    {"sources": [1], "targets": [3], "edgeType": "PROJECTION", "expression": "SUM(orders.amount)"}
  ],
  "vertices": [
    {"id": 0, "vertexType": "COLUMN", "vertexId": "default.orders.customer_id"},
    {"id": 1, "vertexType": "COLUMN", "vertexId": "default.orders.amount"},
    {"id": 2, "vertexType": "COLUMN", "vertexId": "mart.fct_revenue.customer_id"},
    {"id": 3, "vertexType": "COLUMN", "vertexId": "mart.fct_revenue.gross"}
  ]
}
```

Apache Atlas 通过 `org.apache.atlas.hive.hook.HiveHook` 把同样的事件写入 Atlas 元数据仓库，提供完整的血缘 UI。Impala 通过 `org.apache.impala.hooks.QueryEventHook` 复用 Atlas 的血缘 schema。

### Flink SQL：OpenLineage 1.x 集成

Flink 在 1.17 后官方提供 `flink-openlineage` 集成，把每个 Job 的 source / sink / 列依赖以 OpenLineage RunEvent 上报。SQL Gateway 模式下尤其方便：

```yaml
# flink-conf.yaml
execution.attached: true
pipeline.classpaths: file:///opt/flink/lib/openlineage-flink.jar
openlineage.transport.type: http
openlineage.transport.url:  http://marquez:5000
openlineage.namespace:      flink_prod
```

Flink 的血缘有一个特殊问题：**流是无界的**。OpenLineage 通过 `eventType=START` / `RUNNING` / `COMPLETE` / `FAIL` 模型支持持续运行的作业，每次 checkpoint 可发一次 RUNNING。

### dbt：开发期血缘

虽然 dbt 不是数据库引擎，但它在现代数据栈中是事实上的"血缘源头"。每次 `dbt compile` 都会输出 `target/manifest.json`，其中包含每个 model 的 `depends_on.nodes`、`refs`、`sources`。dbt 1.5+ 支持列级血缘 (`dbt-core --select +column:`), dbt Cloud 提供 Column-level Lineage UI。

```bash
dbt compile
jq '.nodes["model.shop.fct_revenue"].depends_on' target/manifest.json
```

dbt manifest 与运行期血缘 (Snowflake ACCESS_HISTORY / UC Lineage) 相结合，可以提供"代码血缘 + 运行血缘"的全景。

## ACCESS_HISTORY 与 Unity Catalog 的设计差异

| 维度 | Snowflake ACCESS_HISTORY | Databricks Unity Catalog Lineage |
|------|-------------------------|----------------------------------|
| GA 时间 | 2021 (列级 2022) | 2023 (列级随之 GA) |
| 数据形态 | 单一 ACCOUNT_USAGE 视图 | `system.access.*` 表 + REST API + UI |
| 解析层 | SQL Compiler 内部 | Spark Analyzer + UC Catalog |
| 跨语言 | 仅 SQL | SQL / Python / Scala / R |
| 视图穿透 | 是 (BASE vs DIRECT) | 是 (Logical Plan) |
| 物化视图 | 是 | 是 (含 DLT) |
| 跨账号 / 工作区 | Share / Reader Account | UC Federation (跨 workspace) |
| 延迟 | ACCOUNT_USAGE 45 min - 3 h | system tables 数分钟 |
| 列级映射 | `directSources` / `baseSources` | `column_lineage` 表 |
| 标签集成 | TAG_REFERENCES / Horizon | UC Tags + Lakehouse Monitoring |
| 计费 | 包含在仓库使用费 | 包含在 UC（按计算计费） |

## OpenLineage 数据模型详解

OpenLineage 是 LF AI & Data 项目，2020 年由 Marquez 团队捐赠。它定义了一个**与引擎无关**的事件模型：

```json
{
  "eventTime": "2026-04-13T10:00:00Z",
  "eventType": "COMPLETE",
  "run": { "runId": "uuid..." },
  "job": {
    "namespace": "snowflake://prod",
    "name": "mart.fct_revenue.daily_etl"
  },
  "inputs": [
    {
      "namespace": "snowflake://prod",
      "name": "raw.orders",
      "facets": {
        "schema": { "fields": [
          {"name": "order_id",  "type": "BIGINT"},
          {"name": "amount",    "type": "DECIMAL"}
        ]}
      }
    }
  ],
  "outputs": [
    {
      "namespace": "snowflake://prod",
      "name": "mart.fct_revenue",
      "facets": {
        "columnLineage": {
          "fields": {
            "gross_amount": {
              "inputFields": [
                {"namespace": "snowflake://prod",
                 "name": "raw.orders",
                 "field": "amount",
                 "transformations": [
                   {"type": "AGGREGATION", "subtype": "SUM"}
                 ]}
              ]
            }
          }
        }
      }
    }
  ],
  "producer": "https://github.com/OpenLineage/OpenLineage/tree/1.20.0/integration/spark"
}
```

核心概念：

- **Run / Job / Dataset**：三类一等公民。Run 是 Job 的一次执行；Dataset 由 `(namespace, name)` 唯一标识。
- **Facet**：可扩展的元数据片段，例如 `schema`、`columnLineage`、`dataQuality`、`sourceCode`、`ownership`。
- **Producer**：发送事件的集成的版本号，便于追踪 schema 演进。

引擎厂商可以原生发送 (Spark / Flink / Airflow / dbt 都已支持)，也可由 Marquez / DataHub / Astronomer Astro 接收。

## 自建血缘工具链：libpg_query + sqllineage

对于 PostgreSQL / MySQL / 通用方言用户，"自建"通常是比商用更现实的方案。最小可行架构：

```
+----------------+    +---------------+    +-------------+    +----------+
| pgaudit / general_log | -> | sqllineage    | -> | Marquez DB  | -> | UI / Tag |
+----------------+    +---------------+    +-------------+    +----------+
                         ^
                         |
                  libpg_query (AST)
```

```python
# sqllineage 用法示例：列级血缘
from sqllineage.runner import LineageRunner

sql = """
INSERT INTO mart.fct_revenue (customer_id, gross_amount)
SELECT o.customer_id, SUM(o.amount)
FROM   raw.orders o
JOIN   raw.refunds r USING (order_id)
GROUP  BY o.customer_id
"""
runner = LineageRunner(sql, dialect="snowflake")
print(runner.source_tables())          # {raw.orders, raw.refunds}
print(runner.target_tables())          # {mart.fct_revenue}
runner.print_column_lineage()
# mart.fct_revenue.customer_id  <- raw.orders.customer_id
# mart.fct_revenue.gross_amount <- raw.orders.amount
```

sqllineage 支持的方言通过 `sqlfluff` 实现，目前覆盖：ansi / bigquery / clickhouse / databricks / db2 / duckdb / exasol / greenplum / hive / mysql / oracle / postgres / redshift / snowflake / soql / sparksql / sqlite / teradata / trino / tsql。

## 实战场景：用血缘解决五类问题

### 场景 1：合规审计 — "谁访问了 PII 列？"

```sql
-- Snowflake：找出过去 30 天访问 customer.ssn 列的所有用户
SELECT DISTINCT user_name, COUNT(*) AS query_count, MIN(query_start_time) AS first_seen
FROM   snowflake.account_usage.access_history,
       LATERAL FLATTEN(input => base_objects_accessed) base,
       LATERAL FLATTEN(input => base.value:columns) cols
WHERE  base.value:objectName::STRING = 'PROD.CRM.CUSTOMER'
  AND  cols.value:columnName::STRING = 'SSN'
  AND  query_start_time > DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY user_name
ORDER  BY query_count DESC;
```

### 场景 2：影响分析 — "如果删除该列，会破坏哪些下游？"

```sql
-- Databricks Unity Catalog
SELECT DISTINCT target_table_full_name, target_column_name
FROM   system.access.column_lineage
WHERE  source_table_full_name = 'prod.raw.events'
  AND  source_column_name     = 'legacy_user_id';
```

```sql
-- SQL Server：通过 sys.dm_sql_referencing_entities
SELECT referencing_schema_name + '.' + referencing_entity_name AS dependent
FROM   sys.dm_sql_referencing_entities('dbo.events', 'OBJECT')
WHERE  referencing_minor_name = 'legacy_user_id';
```

### 场景 3：故障定位 — "下游报表数据错乱，源头是哪个 ETL？"

```sql
-- BigQuery：根据时间窗口找出影响目标表的所有写入
SELECT job_id, user_email, query, start_time, end_time
FROM   `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE  destination_table.dataset_id = 'mart'
  AND  destination_table.table_id   = 'fct_revenue'
  AND  start_time BETWEEN '2026-04-12 00:00:00' AND '2026-04-13 00:00:00'
ORDER  BY start_time DESC;
```

### 场景 4：成本归因 — "哪个下游消费者驱动了 X 表的查询成本？"

将 `ACCESS_HISTORY` 与 `QUERY_HISTORY.credits_used_cloud_services` 聚合，可以按用户 / 团队归集成本：

```sql
SELECT user_name,
       SUM(credits_used_cloud_services) AS credits
FROM   snowflake.account_usage.query_history q
JOIN   snowflake.account_usage.access_history a USING (query_id)
WHERE  ARRAY_CONTAINS('PROD.MART.FCT_REVENUE'::VARIANT,
                      a.base_objects_accessed:objectName)
  AND  q.start_time > DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP  BY user_name
ORDER  BY credits DESC;
```

### 场景 5：模型版本回溯 — "这条记录是哪一版 ETL 写入的？"

将血缘元数据与 Delta Lake / Iceberg / Hudi 的事务历史结合，可以做到"每条数据 → 写入它的查询 → 写入它的 dbt 模型版本"全链路追溯。Databricks Delta Lake 的 `DESCRIBE HISTORY` 与 UC Lineage 联动是当前最完整的方案：

```sql
DESCRIBE HISTORY prod.mart.fct_revenue;

SELECT * FROM system.access.audit
WHERE  request_params.full_name_arg = 'prod.mart.fct_revenue'
  AND  action_name = 'writeFiles';
```

## 关键发现

1. **没有标准**：SQL 标准至今未定义血缘；这是当前 SQL 生态最大的"治理空洞"，每家厂商都在用私有 schema 解决相同的问题。
2. **云数仓三巨头领先**：Snowflake、Databricks、BigQuery 是仅有的提供"零配置 + 列级 + 持久化"的引擎；它们的实现都在 2021-2023 年这个窗口期 GA，恰好与 GDPR / CCPA / 中国《数据安全法》合规需求同步。
3. **传统 RDBMS 停留在对象依赖**：PostgreSQL `pg_depend`、Oracle `DBA_DEPENDENCIES`、SQL Server `sys.dm_sql_referenced_entities`、DB2 `SYSCAT.VIEWDEP` 仅能告诉你"哪些视图依赖哪些表"，无法告诉你"列 A 是从列 B 派生而来"。
4. **OpenLineage 正在成为事实标准**：自 2020 年加入 LF AI & Data 以来，OpenLineage 已被 Spark / Flink / dbt / Airflow / Trino 官方采纳，是跨引擎血缘的"通用语"。Marquez 是其参考实现。
5. **Apache Atlas 仍是 Hadoop 生态首选**：Hive、Impala、HBase、Kafka 通过 Atlas Hook 上报血缘；Cloudera CDP 内置 Atlas。
6. **解析树暴露是少数派**：仅 DuckDB (`json_serialize_sql`)、Spark (`df.queryExecution`)、Oracle (`DBMS_UTILITY.EXPAND_SQL_TEXT`) 把"解析 / 改写"结果作为可查询接口；其他引擎都需要外部解析器。
7. **流处理引擎血缘晚熟**：Flink SQL 直到 2023 年随 OpenLineage 1.x 才有官方集成，Materialize / RisingWave 提供了 `*_dependencies` 系统目录但无列级。
8. **审计与血缘是同一枚硬币的两面**：Snowflake 的设计哲学最有启发——把 GRANT 审计 (`LOGIN_HISTORY` / `GRANTS_TO_USERS`) 和访问血缘 (`ACCESS_HISTORY`) 合并在同一个 `ACCOUNT_USAGE` schema，使"谁，在什么时间，访问了哪些列"成为单条 JOIN 查询。
9. **dbt 改变了血缘的语义边界**：当 SQL 项目以 dbt 模型为单位组织，`manifest.json` 已经是"开发期血缘"的事实标准，与运行期血缘 (ACCESS_HISTORY / UC) 互补。
10. **PostgreSQL 用户的现实路径**：在 PostgreSQL / Greenplum / Yugabyte / TimescaleDB 上实现列级血缘的最实用组合是：`pgaudit` (抓 SQL) → `libpg_query` (解析 AST) → sqllineage / DataHub (建血缘图)。
11. **MySQL / MariaDB / SQLite 几乎空白**：这三家是主流数据库中血缘能力最差的，连"视图引用了哪些表"的查询都需要解析 `INFORMATION_SCHEMA.VIEWS.VIEW_DEFINITION` 字符串。
12. **物化视图自然催生血缘**：Materialize / RisingWave / Snowflake / Databricks (DLT) 等以"增量物化视图"为核心的引擎天然把血缘作为内核数据结构，因为没有血缘就无法做增量维护。
13. **延迟是隐藏成本**：Snowflake `ACCOUNT_USAGE` 视图 45 分钟到 3 小时延迟不适合实时合规审计；Databricks `system.access` 通常分钟级；BigQuery `INFORMATION_SCHEMA.JOBS` 实时但只保留 180 天。
14. **跨账号 / 跨云血缘仍是难题**：当数据从 BigQuery 复制到 Snowflake 再 ETL 到 Databricks，没有任何引擎能自动衔接三段血缘——这是 OpenLineage / Marquez / DataHub 等"中立平台"存在的根本理由。
15. **未来方向**：SQL 标准委员会 WG3 已在讨论 `INFORMATION_SCHEMA.LINEAGE_*` 草案；可以预见 SQL:202x 会出现一个最小公分母的血缘视图标准，但要达到 Snowflake ACCESS_HISTORY 的丰富度仍需多年。

## 附录：术语速查

| 术语 | 中文 | 含义 |
|------|------|------|
| Data Lineage | 数据血缘 | 数据从源到目标的派生路径 |
| Column-level Lineage | 列级血缘 | 输出列到输入列的精确映射 |
| Provenance | 溯源 | 数据"来历 + 处理过程 + 信任链"的统称 |
| Impact Analysis | 影响分析 | 给定上游变更，找出受影响的所有下游 |
| Reverse Lineage | 反向血缘 | 从下游字段回溯到所有上游来源 |
| Field-level Lineage | 字段级血缘 | 等价于列级血缘，常用于半结构化场景 |
| Dataset | 数据集 | OpenLineage 的核心抽象，等价于表 / 视图 / 文件 |
| RunEvent | 运行事件 | OpenLineage 中一次 Job 执行的事件 |
| Facet | 切面 | 可扩展的元数据描述片段 |
| Hook | 钩子 | 引擎执行点上注册的回调，用于上报血缘 |
| Manifest | 清单 | dbt / Airflow 编译产出的元数据 JSON |

## 参考资料

- Snowflake：[ACCESS_HISTORY view](https://docs.snowflake.com/en/sql-reference/account-usage/access_history)、[GET_OBJECT_REFERENCES](https://docs.snowflake.com/en/sql-reference/functions/get_object_references)、[Horizon Data Governance](https://www.snowflake.com/en/data-cloud/horizon/)
- Databricks：[Unity Catalog Data Lineage](https://docs.databricks.com/aws/en/data-governance/unity-catalog/data-lineage)
- Google：[Dataplex Data Lineage](https://cloud.google.com/dataplex/docs/about-data-lineage)、[BigQuery INFORMATION_SCHEMA.JOBS](https://cloud.google.com/bigquery/docs/information-schema-jobs)
- Microsoft：[sys.dm_sql_referenced_entities](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-sql-referenced-entities-transact-sql)
- Oracle：[DBMS_UTILITY.EXPAND_SQL_TEXT](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_UTILITY.html)
- PostgreSQL：[pg_depend / pg_rewrite catalog](https://www.postgresql.org/docs/current/catalog-pg-depend.html)
- Spark：[OpenLineage Spark integration](https://openlineage.io/docs/integrations/spark/)
- DuckDB：[json_serialize_sql](https://duckdb.org/docs/sql/meta/duckdb_table_functions)
- OpenLineage：[Specification & RunEvent](https://openlineage.io/docs/spec/)
- Marquez：[Marquez Project](https://marquezproject.ai/)
- Apache Atlas：[Atlas Architecture](https://atlas.apache.org/)
- sqllineage：[reata/sqllineage GitHub](https://github.com/reata/sqllineage)
- DataHub：[datahubproject.io](https://datahubproject.io/)
