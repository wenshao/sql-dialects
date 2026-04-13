# 外部数据源与数据库链接 (Foreign Data Wrappers and Database Links)

当数据散落在 PostgreSQL、Oracle、MongoDB、S3 与 Kafka 的二十种系统里，一条能跨库 JOIN 的 SQL 比一支 ETL 团队还值钱——这就是 SQL/MED 与联邦查询存在的全部理由。

## 为什么联邦查询如此重要

现代企业的数据栈几乎不可能由单一引擎承载：交易系统跑 PostgreSQL/Oracle，分析侧用 Snowflake/BigQuery，日志进 ClickHouse，文档进 MongoDB，对象存储里还有 Parquet。每一次"我能不能在 OLTP 库里直接 JOIN 一下数仓的维表"的需求，都对应着一个工程困境：

1. **数据集成 (Data Integration)**：避免每次都搭 ETL 管道，让 SQL 引擎像访问本地表一样访问远端数据。
2. **数据迁移 (Data Migration)**：从 Oracle 迁到 PostgreSQL、从 MySQL 迁到 TiDB 时，能直接 `INSERT INTO local SELECT * FROM foreign`，而不是先导出再导入。
3. **数据虚拟化 (Data Virtualization)**：构造一个跨多源的统一视图，让 BI 工具只面向一个 endpoint。
4. **冷热分层 (Tiered Storage)**：热数据放本地，冷数据放 S3/远端归档库，通过 FDW 透明访问。
5. **跨云联邦 (Cross-cloud Federation)**：在 BigQuery 中查 Cloud SQL，在 Databricks 中查 Snowflake——这是 Lakehouse 时代的常态。

本文聚焦于跨数据库链接（Foreign Data Wrapper / Database Link / Linked Server / Federated Query），与基于文件的 [external-tables.md](./external-tables.md) 互补：那篇讲对象存储/HDFS/本地文件，本篇讲跨引擎、跨实例的 SQL 数据源。

## SQL 标准：SQL/MED (ISO/IEC 9075-9)

SQL/MED（SQL Management of External Data，"外部数据管理"）是 SQL 标准的第 9 部分，于 2003 年正式发布（ISO/IEC 9075-9:2003），并在 2008、2016 中持续修订。它定义了将"外部数据源"以一等公民的方式纳入 SQL 引擎的完整框架：

```sql
-- 1. 外部数据包装器：实现某种外部数据源的访问驱动
CREATE FOREIGN DATA WRAPPER pgsql_fdw
    HANDLER pgsql_fdw_handler
    VALIDATOR pgsql_fdw_validator;

-- 2. 服务器：基于 wrapper 的具体远程实例描述
CREATE SERVER remote_pg
    FOREIGN DATA WRAPPER pgsql_fdw
    OPTIONS (host 'db.example.com', port '5432', dbname 'sales');

-- 3. 用户映射：本地用户到远端用户的认证桥
CREATE USER MAPPING FOR local_user
    SERVER remote_pg
    OPTIONS (user 'remote_user', password 'secret');

-- 4. 外部表：将远端表的元数据登记到本地 catalog
CREATE FOREIGN TABLE remote_orders (
    id BIGINT,
    customer_id BIGINT,
    amount NUMERIC,
    created_at TIMESTAMPTZ
) SERVER remote_pg
  OPTIONS (schema_name 'public', table_name 'orders');

-- 5. 批量导入远端 schema：自动登记多个表
IMPORT FOREIGN SCHEMA public
    LIMIT TO (orders, customers, products)
    FROM SERVER remote_pg
    INTO local_schema;
```

标准的核心抽象：

1. **Foreign Data Wrapper (FDW)**：访问某一类数据源（如 PostgreSQL、CSV、ODBC）的"驱动"，由 C 函数 handler 实现。
2. **Server**：FDW 的一个实例化，描述具体远端的连接参数。
3. **User Mapping**：解决跨实例的认证与权限隔离问题。
4. **Foreign Table**：在本地 catalog 中以表的形式登记远端对象，使其可被 SQL 自由引用。
5. **IMPORT FOREIGN SCHEMA**（SQL:2008 引入）：批量自动登记，避免逐表声明。

值得指出：SQL/MED 标准并未规定 FDW 必须支持下推（pushdown）——是否将 WHERE/JOIN/聚合下推到远端，由实现自由决定。这就是不同引擎能力差距的根源。

## 支持矩阵

### 联邦能力总览（45+ 引擎）

| 引擎 | SQL/MED FDW | DATABASE LINK | 3-part 命名 | Linked Server | 远程 EXTERNAL TABLE | 谓词下推 | JOIN 下推 | 聚合下推 | 跨引擎 FDW | IMPORT FOREIGN SCHEMA |
|------|-------------|---------------|------------|---------------|--------------------|----------|-----------|----------|-----------|----------------------|
| PostgreSQL | 是 (9.1+) | -- | -- | -- | -- | 是 | 是 (9.6+) | 是 (10+) | 多种 | 是 (9.5+) |
| MySQL | -- | -- | -- | -- | FEDERATED 引擎 | 是 | -- | -- | 仅 MySQL | -- |
| MariaDB | -- | -- | -- | -- | CONNECT/FEDERATED | 是 | -- | -- | 多种 | -- |
| SQLite | -- | -- | -- | -- | ATTACH DATABASE | 不适用 | -- | -- | -- | -- |
| Oracle | -- | 是 (v7+) | 是 (`@dblink`) | -- | -- | 是 | 是 | 是 | Gateway | -- |
| SQL Server | -- | -- | 是 (4-part) | 是 | OPENROWSET/OPENQUERY | 是 | 是 | 是 | 多种 | -- |
| DB2 | 是 (有限) | -- | 三部分昵称 | -- | Federation Server | 是 | 是 | 是 | 多种 (WebSphere) | -- |
| Snowflake | -- | -- | 是 (account.db.schema) | -- | 外部表 (S3/Azure/GCS) | 仅外部表 | -- | -- | 跨账户共享 | -- |
| BigQuery | -- | -- | 是 (project.dataset.table) | -- | EXTERNAL_QUERY | 部分 | -- | -- | Cloud SQL/Spanner | -- |
| Redshift | -- | -- | 是 (跨 db) | -- | Spectrum/联邦查询 | 是 | -- | 部分 | PG/Aurora/RDS | -- |
| DuckDB | -- | -- | 是 (ATTACH) | -- | scanner 扩展 | 是 | 部分 | 部分 | PG/MySQL/SQLite | -- |
| ClickHouse | -- | -- | -- | -- | 表引擎 | 是 | -- | -- | 多种引擎 | -- |
| Trino | -- | -- | 是 (catalog.schema.table) | -- | 不适用 | 是 | 是 | 是 | 60+ 连接器 | -- |
| Presto | -- | -- | 是 | -- | 不适用 | 是 | 是 | 部分 | 多种 | -- |
| Spark SQL | -- | -- | 是 (catalog) | -- | DataSource | 是 | 部分 | 部分 | JDBC/多种 | -- |
| Hive | -- | -- | -- | -- | StorageHandler | 部分 | -- | -- | JDBC StorageHandler | -- |
| Flink SQL | -- | -- | 是 (catalog) | -- | Connector | 部分 | -- | -- | 多种连接器 | -- |
| Databricks | -- | -- | 是 (Unity Catalog) | -- | Lakehouse Federation | 是 | 部分 | 部分 | 多种 (2023+) | -- |
| Teradata | -- | -- | 是 (跨数据库) | -- | QueryGrid | 是 | 是 | 是 | QueryGrid | -- |
| Greenplum | 是 (继承 PG) | -- | -- | -- | gpfdist/PXF | 是 | 是 | 是 | 多种 | 是 |
| CockroachDB | -- | -- | 是 (db.schema.table) | -- | -- | 不适用 | -- | -- | -- | -- |
| TiDB | -- | -- | 是 | -- | -- | -- | -- | -- | -- | -- |
| OceanBase | -- | DBLINK (兼容 Oracle) | 是 | -- | -- | 是 | -- | -- | 仅 OB/Oracle | -- |
| YugabyteDB | 是 (继承 PG) | -- | -- | -- | -- | 是 | 是 | 是 | 同 PG 生态 | 是 |
| SingleStore | -- | -- | -- | -- | Pipelines | 部分 | -- | -- | -- | -- |
| Vertica | -- | -- | -- | -- | 外部表 | 是 | -- | -- | 通过 Connector | -- |
| Impala | -- | -- | -- | -- | 外部表 | 是 | -- | -- | JDBC 表 (4.0+) | -- |
| StarRocks | -- | -- | 是 (Catalog) | -- | 外部 Catalog | 是 | 部分 | 部分 | JDBC/多种 | -- |
| Doris | -- | -- | 是 (Catalog) | -- | 外部 Catalog | 是 | 部分 | 部分 | JDBC/多种 | -- |
| MonetDB | -- | -- | -- | -- | REMOTE TABLE | 是 | -- | -- | 仅 MonetDB | -- |
| CrateDB | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| TimescaleDB | 是 (继承 PG) | -- | -- | -- | -- | 是 | 是 | 是 | 同 PG | 是 |
| QuestDB | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Exasol | -- | -- | 是 | -- | IMPORT/EXPORT | 部分 | -- | -- | JDBC | -- |
| SAP HANA | -- | -- | -- | -- | Smart Data Access | 是 | 是 | 是 | SDA Adapter | -- |
| Informix | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Firebird | -- | -- | -- | -- | EXECUTE STATEMENT ON EXTERNAL | 不适用 | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | LINKED TABLE | -- | -- | -- | JDBC | -- |
| HSQLDB | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Amazon Athena | -- | -- | 是 (data source) | -- | 不适用 (本身即外部) | 是 | -- | -- | Federated Query | -- |
| Azure Synapse | -- | -- | 是 (3-part/4-part) | 是 | PolyBase | 是 | -- | -- | PolyBase | -- |
| Google Spanner | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | Source | 不适用 | -- | -- | PG/MySQL/Kafka | -- |
| RisingWave | -- | -- | -- | -- | Source | 不适用 | -- | -- | PG/MySQL/Kafka | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Databend | -- | -- | -- | -- | 外部 Stage | 部分 | -- | -- | -- | -- |
| Yellowbrick | 是 (继承 PG) | -- | -- | -- | 外部表 | 是 | -- | -- | PG 生态 | 是 |
| Firebolt | -- | -- | -- | -- | 外部表 | 是 | -- | -- | -- | -- |

> 注：表中 "是" 不代表完全等价于 SQL/MED 标准；许多引擎以自有语法（DATABASE LINK/Linked Server/Catalog/Connector）实现等价能力。例如 Trino 没有 SQL/MED CREATE FOREIGN DATA WRAPPER 语法，但它的 catalog/connector 模型在概念上是 SQL/MED 的超集。
>
> 统计：约 18 个引擎实现了某种形式的 FDW 或下推完整的联邦查询；约 12 个仅有简单 JDBC/外部表能力；约 15 个完全不支持跨实例联邦。

### 跨引擎 FDW 生态（PostgreSQL）

| FDW | 远端类型 | 谓词下推 | JOIN 下推 | 聚合下推 | 写入 | 维护方 |
|-----|---------|----------|-----------|---------|------|-------|
| postgres_fdw | PostgreSQL | 是 | 是 | 是 | 是 | core |
| file_fdw | 本地 CSV/text | -- | -- | -- | -- | core |
| mysql_fdw | MySQL/MariaDB | 是 | -- | -- | 是 | EnterpriseDB |
| oracle_fdw | Oracle | 是 | 是 | 部分 | 是 | Laurenz Albe |
| tds_fdw | SQL Server/Sybase | 是 | -- | -- | -- | tds-fdw |
| mongo_fdw | MongoDB | 是 | -- | -- | 是 | EnterpriseDB |
| redis_fdw | Redis | -- | -- | -- | 是 | pg-redis-fdw |
| sqlite_fdw | SQLite | 是 | -- | -- | 是 | pgspider |
| jdbc_fdw | 任何 JDBC | 部分 | -- | -- | -- | pgspider |
| odbc_fdw | 任何 ODBC | 部分 | -- | -- | -- | CARTO |
| parquet_s3_fdw | S3 Parquet | 是 | -- | -- | -- | pgspider |
| kafka_fdw | Kafka | -- | -- | -- | -- | adjust |
| influxdb_fdw | InfluxDB | 部分 | -- | 部分 | 是 | pgspider |
| clickhouse_fdw | ClickHouse | 是 | 部分 | 部分 | 是 | Adjust |
| multicorn | Python wrapper | 取决于实现 | -- | -- | 取决于 | dalibo |

> Multicorn 让任何人都能用纯 Python 实现一个 FDW——是 PostgreSQL 联邦生态最具创造力的入口。

## BERNOULLI vs SYSTEM 之外的另一组关键概念：DBLINK vs FDW vs Linked Server

三种主流跨库访问范式在哲学上有显著差异：

### DATABASE LINK（Oracle 范式）

```sql
-- Oracle: 创建数据库链接
CREATE DATABASE LINK sales_link
    CONNECT TO sales_user IDENTIFIED BY "secret"
    USING 'sales_db.example.com:1521/PROD';

-- 使用 @dblink 后缀引用远端表
SELECT * FROM orders@sales_link WHERE customer_id = 42;

-- 跨库 JOIN
SELECT l.id, l.name, r.total
FROM customers l
JOIN orders@sales_link r ON l.id = r.customer_id;
```

特征：以连接为单位（per-connection），通过 `@linkname` 后缀引用，不在本地登记元数据。元数据按需远端拉取，灵活但容易出现 schema drift。

### FDW（PostgreSQL/SQL/MED 范式）

```sql
-- PostgreSQL: 创建外部表（一次性登记元数据）
CREATE EXTENSION postgres_fdw;
CREATE SERVER sales_srv FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'sales.example.com', dbname 'sales');
CREATE USER MAPPING FOR current_user SERVER sales_srv
    OPTIONS (user 'sales_user', password 'secret');
CREATE FOREIGN TABLE remote_orders (
    id BIGINT, customer_id BIGINT, amount NUMERIC
) SERVER sales_srv OPTIONS (table_name 'orders');

-- 像本地表一样使用
SELECT * FROM remote_orders WHERE customer_id = 42;
```

特征：远端对象在本地 catalog 中以"表"形式登记，与本地表无差别。计划器知道列与类型，可参与代价估算与下推。代价是元数据维护：远端 DDL 变更时需要 `IMPORT FOREIGN SCHEMA` 重新同步。

### Linked Server（SQL Server 范式）

```sql
-- SQL Server: 创建链接服务器
EXEC sp_addlinkedserver
    @server = 'SALES_SRV',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = 'sales.example.com';

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = 'SALES_SRV',
    @useself = 'FALSE',
    @rmtuser = 'sales_user',
    @rmtpassword = 'secret';

-- 4 段命名引用
SELECT * FROM SALES_SRV.sales_db.dbo.orders WHERE customer_id = 42;

-- 或 OPENQUERY（下推任意 SQL 给远端执行）
SELECT *
FROM OPENQUERY(SALES_SRV,
    'SELECT customer_id, SUM(amount) FROM orders GROUP BY customer_id');
```

特征：四段命名 `server.database.schema.object`；OPENQUERY 允许"原文下推"——绕过本地解析直接把 SQL 字符串发给远端执行。

### 三种范式对比

| 维度 | DATABASE LINK | FDW (SQL/MED) | Linked Server |
|------|---------------|---------------|---------------|
| 标准化 | 否（Oracle 私有） | ISO/IEC 9075-9 | 否（微软私有） |
| 元数据登记 | 按需 | 显式 (CREATE FOREIGN TABLE) | 按需 |
| 命名方式 | `table@link` | `local_name`（透明） | `server.db.schema.object` |
| 计划器可见性 | 部分 | 高（参与代价估算） | 中 |
| 下推能力 | 取决于 Gateway | 取决于 FDW 实现 | 高 + OPENQUERY 原文下推 |
| 异构源支持 | 通过 Gateway | 通过不同 FDW | 通过 OLE DB Provider |
| 写入支持 | 是 | 取决于 FDW | 是 |

## 各引擎详解

### PostgreSQL（SQL/MED 标准最完整实现）

PostgreSQL 9.1（2011 年发布）首次实现 SQL/MED 框架，9.3 引入 postgres_fdw，9.6 加入 join 下推，10 加入聚合下推与 partition-wise join 下推，12 之后持续优化批量插入。

```sql
-- 1. 安装扩展
CREATE EXTENSION postgres_fdw;

-- 2. 定义远端服务器
CREATE SERVER warehouse_srv
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (
        host 'warehouse.internal',
        port '5432',
        dbname 'analytics',
        fetch_size '10000',           -- 批量拉取大小
        use_remote_estimate 'true',   -- 让计划器调用远端 EXPLAIN
        async_capable 'true'          -- 14+ 异步并行查询
    );

-- 3. 用户映射
CREATE USER MAPPING FOR app_user
    SERVER warehouse_srv
    OPTIONS (user 'analytics_ro', password 'xxx');

-- 4. 批量导入 schema
IMPORT FOREIGN SCHEMA public
    LIMIT TO (fact_orders, dim_customers, dim_products)
    FROM SERVER warehouse_srv
    INTO ext;

-- 5. 像本地表一样查询，自动下推
EXPLAIN (VERBOSE, COSTS OFF)
SELECT c.region, SUM(o.amount)
FROM ext.dim_customers c
JOIN ext.fact_orders o ON c.id = o.customer_id
WHERE o.order_date >= '2026-01-01'
GROUP BY c.region;

-- 输出会显示:
-- Foreign Scan
--   Relations: (ext.dim_customers c) INNER JOIN (ext.fact_orders o)
--   Remote SQL: SELECT c.region, sum(o.amount)
--               FROM dim_customers c JOIN fact_orders o ON ...
--               WHERE o.order_date >= '2026-01-01' GROUP BY c.region
```

PostgreSQL postgres_fdw 的下推能力清单：

- **谓词下推**：WHERE 条件中可以下推的算子（操作符必须是稳定的，类型必须可序列化）。
- **JOIN 下推**（9.6+）：同一远端服务器上的两表 JOIN 整体下推。
- **聚合下推**（10+）：GROUP BY、COUNT、SUM、AVG、MIN、MAX。
- **ORDER BY / LIMIT 下推**。
- **UPDATE/DELETE 直接下推**（9.5+ 直接修改远端而不先 SELECT 回本地）。
- **分区表与外部表混合**（partition-wise join，11+）。
- **异步执行**（14+ 异步 append）。

### Oracle（DATABASE LINK 与 Heterogeneous Services）

Oracle 自 v7（1992 年）就支持 DATABASE LINK。同构 Oracle 之间通过 SQL\*Net 协议直接连接；访问非 Oracle 数据源则通过 Heterogeneous Services + Transparent Gateway。

```sql
-- 同构（Oracle to Oracle）
CREATE PUBLIC DATABASE LINK sales_link
    CONNECT TO sales_user IDENTIFIED BY "passwd"
    USING 'sales';   -- tnsnames.ora 别名

-- 跨库查询
SELECT * FROM orders@sales_link WHERE order_date > SYSDATE - 7;

-- 跨库 JOIN（Oracle 优化器有"分布式查询优化"专门处理）
SELECT c.name, SUM(o.amount)
FROM customers c
JOIN orders@sales_link o ON c.id = o.customer_id
GROUP BY c.name;

-- 异构访问（通过 Database Gateway）
-- 安装 Oracle Database Gateway for SQL Server，配置 init<sid>.ora
CREATE PUBLIC DATABASE LINK sqlserver_link
    CONNECT TO "sa" IDENTIFIED BY "x"
    USING 'dg4msql';

SELECT * FROM "Northwind"."dbo"."Customers"@sqlserver_link;

-- DBMS_HS_PASSTHROUGH：原生原文下推
DECLARE
    c INTEGER;
    nr INTEGER;
BEGIN
    c := DBMS_HS_PASSTHROUGH.OPEN_CURSOR@sqlserver_link;
    DBMS_HS_PASSTHROUGH.PARSE@sqlserver_link(c,
        'EXEC sp_who2');
    nr := DBMS_HS_PASSTHROUGH.EXECUTE_NON_QUERY@sqlserver_link(c);
    DBMS_HS_PASSTHROUGH.CLOSE_CURSOR@sqlserver_link(c);
END;
```

Oracle 的优化器对 DBLINK 查询会做"位置透明"重写：尽量把 WHERE/JOIN/聚合下推到远端，只有当远端代价过高或返回行数极少时才把数据拉回本地处理。Oracle 称之为 "distributed query optimization"。

注意：DBLINK 上的事务受限于 2PC 协议（COMMIT 走 two-phase commit），分布式事务的失败处理远比本地复杂。

### SQL Server（Linked Server / OPENROWSET / OPENQUERY）

```sql
-- 添加 Linked Server
EXEC sp_addlinkedserver
    @server = 'PG_SALES',
    @srvproduct = 'PostgreSQL',
    @provider = 'MSDASQL',
    @datasrc = 'PG_SALES_DSN';   -- ODBC DSN

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = 'PG_SALES',
    @useself = 'FALSE',
    @rmtuser = 'sales_ro',
    @rmtpassword = 'xxx';

-- 4 段命名（注意 PostgreSQL ODBC 下区分大小写）
SELECT * FROM PG_SALES.sales.public.orders WHERE id = 42;

-- OPENQUERY：原文下推（绕过 SQL Server 的解析与重写）
SELECT *
FROM OPENQUERY(PG_SALES,
    'SELECT customer_id, COUNT(*) AS cnt
     FROM orders
     WHERE order_date >= ''2026-01-01''
     GROUP BY customer_id
     HAVING COUNT(*) > 10');

-- OPENROWSET：临时连接（无需预先 sp_addlinkedserver）
SELECT * FROM OPENROWSET(
    'MSDASQL',
    'DRIVER={PostgreSQL Unicode};SERVER=...;DATABASE=sales;UID=ro;PWD=xxx',
    'SELECT * FROM orders WHERE id = 42');

-- 删除 Linked Server
EXEC sp_dropserver 'PG_SALES', 'droplogins';
```

OPENQUERY 是 SQL Server 联邦能力的精髓——它承认了一个事实：异构源的最佳计划器是远端自己。SQL Server 不强行解析 OPENQUERY 字符串，直接转发给远端，避免了"伪下推"陷阱。代价是失去类型检查与计划器可见性。

### MySQL（FEDERATED 引擎，已弱化）

```sql
-- 启用 FEDERATED 存储引擎（默认未编译）
-- my.cnf: federated = ON

-- 创建 FEDERATED 表（指向远端 MySQL）
CREATE TABLE federated_orders (
    id INT NOT NULL,
    customer_id INT,
    amount DECIMAL(10, 2),
    PRIMARY KEY (id)
) ENGINE=FEDERATED
  DEFAULT CHARSET=utf8mb4
  CONNECTION='mysql://sales_ro:xxx@sales.example.com:3306/sales/orders';

SELECT * FROM federated_orders WHERE id = 42;
```

历史与现状：

- MySQL 5.0 引入 FEDERATED；5.5 起标记为"已知 bug 多，不推荐生产使用"。
- MySQL 8.0 文档明确写明 FEDERATED 默认不启用，且不建议在新项目中采用。
- 没有 JOIN/聚合下推；只有简单 WHERE 谓词下推。
- 一次只能连一个远端，不支持事务、不支持外部异构源（仅 MySQL）。
- Oracle 官方建议改用 ProxySQL 或应用层多源 ORM。

### MariaDB（CONNECT 存储引擎）

MariaDB 没有放弃跨源访问，而是引入了功能远比 FEDERATED 强大的 CONNECT 存储引擎（10.0+）：

```sql
-- 启用 CONNECT 引擎
INSTALL SONAME 'ha_connect';

-- CSV 文件作为表
CREATE TABLE csv_orders (
    id INT, customer_id INT, amount DECIMAL(10,2)
) ENGINE=CONNECT TABLE_TYPE=CSV
  FILE_NAME='/data/orders.csv'
  HEADER=1 SEP_CHAR=',';

-- ODBC 连接异构数据库
CREATE TABLE odbc_pg_orders (
    id INT, customer_id INT, amount DECIMAL(10,2)
) ENGINE=CONNECT TABLE_TYPE=ODBC
  TABNAME='public.orders'
  CONNECTION='DSN=PG_SALES;UID=ro;PWD=xxx';

-- JSON 文件
CREATE TABLE json_logs (
    ts DATETIME, level VARCHAR(10), msg TEXT
) ENGINE=CONNECT TABLE_TYPE=JSON
  FILE_NAME='/data/logs.json';

-- XML 文件
CREATE TABLE xml_books (
    title VARCHAR(100), author VARCHAR(100), year INT
) ENGINE=CONNECT TABLE_TYPE=XML
  FILE_NAME='/data/books.xml'
  TABNAME='catalog' OPTION_LIST='rownode=book';

-- REST/HTTP 数据源（CONNECT v1.07+）
CREATE TABLE rest_users (
    id INT, name VARCHAR(100)
) ENGINE=CONNECT TABLE_TYPE=JSON
  HTTP='https://api.example.com/users';
```

CONNECT 同时也保留了 FEDERATED 的兼容能力，并提供改进版 `FEDERATEDX`。MariaDB 的 CONNECT 是中小型数据库里最务实、最丰富的"联邦层"实现之一。

### DB2（Federation Server / WebSphere Federation）

IBM 在企业联邦领域有最长的积累。DB2 LUW（Linux/Unix/Windows）的 Federation Server 与 WebSphere Federation Server（后并入 InfoSphere）支持的源包括：DB2、Oracle、SQL Server、Sybase、Informix、MySQL、Teradata、Excel、ODBC/JDBC、Web Services、XML 等。

```sql
-- DB2 联邦：注册 wrapper
CREATE WRAPPER drda;
CREATE WRAPPER net8 LIBRARY 'libdb2net8.so';   -- Oracle

-- 注册远程服务器
CREATE SERVER orcl_sales
    TYPE ORACLE VERSION '19'
    WRAPPER net8
    AUTHORIZATION "sysuser" PASSWORD "x"
    OPTIONS (NODE 'orcl_node', DBNAME 'PROD');

-- 用户映射
CREATE USER MAPPING FOR app_user
    SERVER orcl_sales
    OPTIONS (REMOTE_AUTHID 'sales_ro', REMOTE_PASSWORD 'xxx');

-- 创建昵称（nickname）— 等价于 FOREIGN TABLE
CREATE NICKNAME orcl_orders
    FOR orcl_sales.SALES.ORDERS;

-- 透明使用
SELECT * FROM orcl_orders WHERE order_date > CURRENT_DATE - 7 DAYS;
```

DB2 的优化器支持完整的"分布式查询优化"，包括：跨源 JOIN 下推、谓词下推、聚合下推、UDF 下推。DB2 联邦在金融、电信等遗留多库整合场景仍有大量部署。

### Snowflake（外部函数与跨账户共享，没有传统 FDW）

Snowflake 的设计哲学是 "把一切搬进来"，所以没有提供 PostgreSQL 风格的 FDW。它的联邦能力主要表现为：

```sql
-- 1. 外部表（指向 S3/Azure Blob/GCS 上的文件）
CREATE EXTERNAL TABLE ext_orders (
    id INT AS (VALUE:c1::INT),
    amount FLOAT AS (VALUE:c2::FLOAT)
)
LOCATION = @my_s3_stage/orders/
FILE_FORMAT = (TYPE = CSV);

-- 2. 跨账户数据共享（Secure Data Sharing）— 不复制数据
-- Provider 端
CREATE SHARE sales_share;
GRANT USAGE ON DATABASE sales TO SHARE sales_share;
GRANT SELECT ON ALL TABLES IN SCHEMA sales.public TO SHARE sales_share;
ALTER SHARE sales_share ADD ACCOUNTS = ('CONSUMER_ACCT');

-- Consumer 端
CREATE DATABASE sales_from_provider FROM SHARE provider_acct.sales_share;
SELECT * FROM sales_from_provider.public.orders;

-- 3. External Functions（远程 HTTP 调用，AWS Lambda/Azure Function）
CREATE EXTERNAL FUNCTION enrich_address(addr STRING)
    RETURNS VARIANT
    API_INTEGRATION = my_api_integration
    AS 'https://api.example.com/enrich';
```

Snowflake 的"联邦"是通过数据共享和外部函数来实现，而不是 FDW。这是 SaaS 数仓的典型路径：避免运行时与他方系统耦合。

### BigQuery（External Tables + EXTERNAL_QUERY）

```sql
-- 1. 外部表：指向 GCS/Drive/Sheets/Bigtable
CREATE OR REPLACE EXTERNAL TABLE mydataset.ext_orders
OPTIONS (
    format = 'PARQUET',
    uris = ['gs://my-bucket/orders/*.parquet']
);

-- 2. EXTERNAL_QUERY：联邦到 Cloud SQL / Spanner
SELECT *
FROM EXTERNAL_QUERY(
    'projects/myproj/locations/us/connections/my-cloud-sql',
    'SELECT customer_id, SUM(amount) AS total
     FROM orders
     WHERE order_date >= CURRENT_DATE - INTERVAL ''7 day''
     GROUP BY customer_id'
);

-- 3. 与 BigQuery 表 JOIN
SELECT bq.region, ext.total
FROM mydataset.dim_customers AS bq
JOIN EXTERNAL_QUERY(
    'projects/myproj/locations/us/connections/my-cloud-sql',
    'SELECT customer_id, SUM(amount) AS total FROM orders GROUP BY customer_id'
) AS ext
ON bq.id = ext.customer_id;
```

EXTERNAL_QUERY 与 SQL Server 的 OPENQUERY 哲学一致——把 SQL 字符串原样下推给 Cloud SQL（或 Spanner），由远端自己优化执行。它支持 Cloud SQL for PostgreSQL、Cloud SQL for MySQL，以及 Cloud Spanner（GA 2023）。

### DuckDB（attach 哲学 + scanner 扩展）

DuckDB 在跨库访问方面采取了一种新颖且优雅的方式：通过 `ATTACH` 把外部数据库挂载为一等公民。

```sql
-- 安装 scanner 扩展
INSTALL postgres;
LOAD postgres;

-- 把整个 PostgreSQL 数据库 ATTACH 为本地 catalog
ATTACH 'host=localhost port=5432 dbname=sales user=ro password=x'
    AS pg_sales (TYPE POSTGRES, READ_ONLY);

-- 跨库 JOIN：本地 Parquet + 远端 PG
SELECT p.product_name, SUM(o.amount)
FROM 'orders.parquet' p
JOIN pg_sales.public.orders o ON p.id = o.product_id
GROUP BY p.product_name;

-- 同样支持 MySQL
INSTALL mysql; LOAD mysql;
ATTACH 'host=mysql.host user=ro password=x database=sales'
    AS mysql_sales (TYPE MYSQL);

-- 以及 SQLite
INSTALL sqlite; LOAD sqlite;
ATTACH 'app.db' AS app (TYPE SQLITE);

-- 跨三个引擎的 JOIN
SELECT *
FROM pg_sales.public.customers c
JOIN mysql_sales.orders o ON c.id = o.customer_id
JOIN app.events e ON c.id = e.user_id;
```

DuckDB scanner 已支持基本的谓词下推、列裁剪与部分聚合下推。它把 PostgreSQL/MySQL/SQLite 当作一等存储引擎对待——这对本地开发、ETL 一次性脚本、跨数据源数据探索极其友好。

### Trino（联邦即架构本身）

Trino（前身 Presto）的整个引擎设计就是为了联邦查询：

```sql
-- Trino 的所有数据源都是 catalog（在配置文件中定义，不是 SQL DDL）
-- /etc/trino/catalog/postgres_sales.properties:
--   connector.name=postgresql
--   connection-url=jdbc:postgresql://sales.host/sales
--   connection-user=ro
--   connection-password=xxx

-- /etc/trino/catalog/mongo_logs.properties:
--   connector.name=mongodb
--   mongodb.connection-url=mongodb://logs.host/logs

-- /etc/trino/catalog/hive.properties:
--   connector.name=hive
--   hive.metastore.uri=thrift://hive.host:9083

-- 三段命名：catalog.schema.table
SELECT * FROM postgres_sales.public.orders WHERE id = 42;

-- 跨连接器 JOIN：PostgreSQL + MongoDB + Hive 三源 JOIN
SELECT
    pg.customer_id,
    pg.amount,
    mongo.user_agent,
    hive.region
FROM postgres_sales.public.orders pg
JOIN mongo_logs.app.access_logs mongo
    ON pg.session_id = mongo.session_id
JOIN hive.dim.customers hive
    ON pg.customer_id = hive.id
WHERE pg.order_date >= DATE '2026-01-01';
```

Trino 当前官方提供 60+ 连接器，包括：PostgreSQL、MySQL、Oracle、SQL Server、Cassandra、MongoDB、Elasticsearch、Kafka、Hive、Iceberg、Delta Lake、Druid、Pinot、Phoenix、Redis、Prometheus、Google Sheets、ClickHouse、Snowflake、BigQuery、Redshift、SQL Server、Db2、TPCH/TPCDS（合成数据）……

Trino 的下推能力分为三层：

1. **Predicate / column projection pushdown**：所有连接器都支持。
2. **Aggregate pushdown**：PostgreSQL、MySQL、Oracle、SQL Server 等关系型连接器支持完整的 `COUNT/SUM/MIN/MAX/AVG` 下推。
3. **Join pushdown**（Trino 388+，2022 年）：同一连接器内的两表 JOIN 可下推到远端执行；跨连接器的 JOIN 必然在 Trino 内执行。

### ClickHouse（表引擎即联邦）

ClickHouse 通过"表引擎"实现联邦：MySQL、PostgreSQL、ODBC、JDBC、MongoDB、Redis、HDFS、S3、Kafka 都是表引擎。

```sql
-- 把整个 MySQL 数据库挂载（database engine）
CREATE DATABASE mysql_sales ENGINE = MySQL(
    'mysql.host:3306', 'sales', 'ro', 'xxx');

SELECT * FROM mysql_sales.orders WHERE id = 42;

-- 单表 PostgreSQL 表引擎
CREATE TABLE pg_orders (
    id Int64, customer_id Int64, amount Float64
) ENGINE = PostgreSQL(
    'pg.host:5432', 'sales', 'orders', 'ro', 'xxx');

-- 函数式：远端表函数（一次性查询，不创建对象）
SELECT * FROM mysql(
    'mysql.host:3306', 'sales', 'orders', 'ro', 'xxx')
WHERE customer_id = 42;

SELECT * FROM postgresql(
    'pg.host:5432', 'sales', 'orders', 'ro', 'xxx',
    'public') WHERE id > 1000;

-- 跨引擎 JOIN
SELECT m.product, SUM(p.amount)
FROM mysql_sales.products m
JOIN pg_orders p ON m.id = p.product_id
GROUP BY m.product;
```

ClickHouse 表引擎是最轻量的联邦实现之一——直接在 SQL 层面创建表对象，无需安装 wrapper、无需 user mapping。

### Databricks（Lakehouse Federation 与 Unity Catalog）

Databricks 在 2023 年 GA 了 Lakehouse Federation：通过 Unity Catalog 把外部数据源（Snowflake、Redshift、PostgreSQL、MySQL、SQL Server、BigQuery 等）注册为 Unity Catalog 中的"foreign catalog"，然后在 Databricks SQL 中以三段命名引用。

```sql
-- 在 Unity Catalog 中创建外部连接
CREATE CONNECTION pg_sales_conn TYPE POSTGRESQL
OPTIONS (
    host 'sales.example.com',
    port '5432',
    user secret('scope', 'pg_user'),
    password secret('scope', 'pg_pass')
);

-- 创建外部 Catalog
CREATE FOREIGN CATALOG pg_sales
USING CONNECTION pg_sales_conn
OPTIONS (database 'sales');

-- 透明三段命名查询
SELECT * FROM pg_sales.public.orders WHERE id = 42;

-- 跨源 JOIN：Delta Lake + 外部 PostgreSQL
SELECT
    d.region,
    SUM(p.amount) AS total
FROM main.silver.dim_region d
JOIN pg_sales.public.orders p
    ON d.id = p.region_id
GROUP BY d.region;
```

Lakehouse Federation 的核心价值：让 Lakehouse 成为整个企业的 "single pane of glass"，无需对外部数据源做数据搬迁就能 BI 化。它支持基本的谓词下推与列裁剪，部分聚合下推因连接器而异。

### Greenplum / TimescaleDB / YugabyteDB / Yellowbrick（PostgreSQL 后裔）

这一组引擎都基于 PostgreSQL 内核，因此原生继承了 SQL/MED 与 postgres_fdw 全部能力。Greenplum 还额外提供 PXF（Platform Extension Framework）和 gpfdist 用于并行外部数据访问，能将分片读取下推到所有 segment。

YugabyteDB 因复用 PG 优化器，对 postgres_fdw 的支持几乎与上游 PostgreSQL 一致——这是它与 CockroachDB（自有 SQL 层、不支持 FDW）的关键差异。

### SAP HANA（Smart Data Access）

```sql
-- 创建 remote source（SDA）
CREATE REMOTE SOURCE pg_sales
    ADAPTER "odbc"
    CONFIGURATION 'DSN=PG_SALES'
    WITH CREDENTIAL TYPE 'PASSWORD'
    USING 'user=ro;password=xxx';

-- 创建虚拟表（virtual table）
CREATE VIRTUAL TABLE v_orders AT
    "pg_sales"."<NULL>"."public"."orders";

-- 透明使用
SELECT * FROM v_orders WHERE customer_id = 42;
```

SDA 支持丰富的下推能力，包括 JOIN 下推、聚合下推、复杂表达式下推。SAP HANA 在 OLTP+OLAP 混合场景下，常通过 SDA 把冷数据放在外部 PostgreSQL/Hadoop，热数据保留在 HANA 内存中。

## PostgreSQL SQL/MED FDW 深度剖析

PostgreSQL 是 SQL/MED 标准最完整、最值得参考的实现。理解它的内部机制对设计自己的 FDW 或在其它引擎实现联邦层都有借鉴意义。

### 1. FDW Handler 的 7 个核心 callback

```c
typedef struct FdwRoutine {
    NodeTag type;

    /* 扫描相关 */
    GetForeignRelSize_function     GetForeignRelSize;
    GetForeignPaths_function       GetForeignPaths;
    GetForeignPlan_function        GetForeignPlan;
    BeginForeignScan_function      BeginForeignScan;
    IterateForeignScan_function    IterateForeignScan;
    ReScanForeignScan_function     ReScanForeignScan;
    EndForeignScan_function        EndForeignScan;

    /* 修改相关（DML 下推） */
    AddForeignUpdateTargets_function   AddForeignUpdateTargets;
    PlanForeignModify_function         PlanForeignModify;
    BeginForeignModify_function        BeginForeignModify;
    ExecForeignInsert_function         ExecForeignInsert;
    ExecForeignUpdate_function         ExecForeignUpdate;
    ExecForeignDelete_function         ExecForeignDelete;
    EndForeignModify_function          EndForeignModify;

    /* 下推增强 */
    GetForeignJoinPaths_function       GetForeignJoinPaths;       /* 9.6+ */
    GetForeignUpperPaths_function      GetForeignUpperPaths;      /* 10+，聚合下推 */

    /* 异步执行 */
    IsForeignScanParallelSafe_function IsForeignScanParallelSafe;
    ForeignAsyncRequest_function       ForeignAsyncRequest;       /* 14+ */
    ...
} FdwRoutine;
```

实现一个最小可用 FDW 只需 7 个 callback（GetForeignRelSize / GetForeignPaths / GetForeignPlan / Begin / Iterate / ReScan / End）。要支持下推则按需实现 GetForeignJoinPaths、GetForeignUpperPaths、Plan/ExecForeignModify。

### 2. 谓词下推的判定逻辑

postgres_fdw 在 `is_foreign_expr()` 中检查每个表达式是否"安全"地下推。判定标准：

1. **算子必须是 IMMUTABLE 或 STABLE**：VOLATILE 函数（如 `random()`、`now()` 在某些情境）不能下推，否则远端与本地行为可能不一致。
2. **类型必须是已知 OID 共享的内置类型**或显式声明 `extensions` 选项中允许的类型。
3. **collation 必须匹配**：跨实例可能 collation 不一致，会产生不同的排序。
4. **不能引用其它远端服务器**的列（跨多个 server 的表达式无法下推到任一方）。

### 3. JOIN 下推（9.6+）

```c
static void
postgresGetForeignJoinPaths(PlannerInfo *root,
                            RelOptInfo *joinrel,
                            RelOptInfo *outerrel,
                            RelOptInfo *innerrel,
                            JoinType jointype,
                            JoinPathExtraData *extra)
{
    /* 必须是同一 foreign server */
    if (outerrel->serverid != innerrel->serverid) return;

    /* JOIN 类型限制：INNER / LEFT / RIGHT / FULL */
    if (jointype != JOIN_INNER && jointype != JOIN_LEFT &&
        jointype != JOIN_RIGHT && jointype != JOIN_FULL)
        return;

    /* 检查 join 条件能否下推 */
    if (!foreign_join_ok(root, joinrel, jointype, outerrel, innerrel, extra))
        return;

    /* 创建 ForeignPath 表示 join 整体在远端执行 */
    ForeignPath *joinpath = create_foreign_join_path(...);
    add_path(joinrel, (Path *) joinpath);
}
```

### 4. 聚合下推（10+）

聚合下推通过 `GetForeignUpperPaths` 实现，触发条件包括：

- GROUP BY 列、聚合函数本身、HAVING 表达式都必须是"safe to push down"。
- 不允许出现引用本地表的 join 之上的聚合。
- DISTINCT 聚合通常会被禁用，除非 server 选项明确允许。

下推后，PostgreSQL 在远端执行的 SQL 会形如：

```sql
SELECT region, sum(amount), count(*)
FROM remote.orders
WHERE order_date >= '2026-01-01'
GROUP BY region
HAVING sum(amount) > 1000
```

本地节点接收已聚合的小结果集，避免了大量数据穿越网络。

### 5. use_remote_estimate 与代价估算

```sql
ALTER SERVER warehouse_srv OPTIONS (SET use_remote_estimate 'true');
```

启用后，本地计划器在生成 ForeignPath 时会通过执行 `EXPLAIN` 远程查询来获取真实的代价/行数估算。这对涉及 join 顺序选择尤为关键。代价：每次 plan 都要打远端，OLTP 高频场景慎用。

### 6. 异步执行（14+）

PostgreSQL 14 引入 `async_capable`，允许对多个分区/分片的 ForeignScan 并行发起。例如：分区表的不同分区指向不同的 postgres_fdw 远端，扫描时可同时发起，显著降低端到端延迟。

```sql
-- 分区表 + 异步 FDW
CREATE TABLE measurements (
    id BIGINT, ts TIMESTAMPTZ, value DOUBLE PRECISION
) PARTITION BY RANGE (ts);

CREATE FOREIGN TABLE measurements_2024
    PARTITION OF measurements FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')
    SERVER shard_2024 OPTIONS (table_name 'measurements');

CREATE FOREIGN TABLE measurements_2025
    PARTITION OF measurements FOR VALUES FROM ('2025-01-01') TO ('2026-01-01')
    SERVER shard_2025 OPTIONS (table_name 'measurements');

ALTER SERVER shard_2024 OPTIONS (ADD async_capable 'true');
ALTER SERVER shard_2025 OPTIONS (ADD async_capable 'true');

-- 查询会并行打两个分片
SELECT date_trunc('month', ts), avg(value)
FROM measurements
WHERE ts BETWEEN '2024-06-01' AND '2025-06-01'
GROUP BY 1;
```

## Trino 作为查询联邦引擎：另一种哲学

PostgreSQL 是"以本地引擎为主，FDW 作为接入点"的思路；Trino 则是"无本地存储，所有数据都在 connector 之后"的极端版本。

### 架构差异

| 维度 | PostgreSQL (FDW) | Trino |
|------|------------------|-------|
| 存储 | 本地 heap + 索引 + WAL | 无（连接器即存储） |
| 元数据 | 本地 catalog + foreign tables | catalog/connector 元数据动态获取 |
| 计划器 | 本地 cost-based optimizer | 联邦优化器，预估远端代价 |
| 执行模型 | 单进程多 worker | MPP，多 worker 并发拉取 |
| 数据移动 | 远端拉到本地 | 远端拉到 worker 内存，跨 worker shuffle |
| 事务 | 完整 ACID（带 2PC 选项） | 只读为主，部分连接器支持 INSERT |
| 适用场景 | OLTP+轻 OLAP+联邦报表 | 大规模 OLAP 联邦分析 |

### Trino 的下推策略

Trino 在 388+ 实现了完整的 JOIN 下推（join pushdown）框架。判定流程：

1. 计划器识别 JOIN 两侧的 RelationHandle 是否来自同一 connector 实例。
2. 调用 connector 的 `applyJoin()` 接口询问能否接受。
3. 连接器返回新的 TableHandle（代表"已合并的虚拟表"），计划器把整个 JOIN 节点替换为 ScanNode。

这一机制让 PostgreSQL/MySQL/Oracle 连接器在两表 JOIN 都来自同一远端时把整个 JOIN 下推。对跨连接器的 JOIN，Trino 退化到经典的 build/probe 模型，在 worker 端构造 hash 表执行。

### 动态过滤（Dynamic Filtering）

Trino 在跨连接器 JOIN 中引入了 dynamic filtering：先扫描小表（build 侧），把 join key 的范围/min-max/Bloom filter 作为动态谓词推送给大表（probe 侧）的扫描。即使无法做完整 JOIN 下推，也能减少远端的数据扫描量。

```sql
-- 假设 dim 是 PostgreSQL 中的小表（1000 行），fact 是 Hive 中的大表（10 亿行）
SELECT f.product, SUM(f.amount)
FROM hive.sales.fact f
JOIN postgres.dim.products p ON f.product_id = p.id
WHERE p.category = 'electronics'   -- 过滤后只剩 50 个 product
GROUP BY f.product;

-- Trino 会先扫 postgres.dim.products，得到 50 个 product_id
-- 然后将 product_id IN (...) 作为动态过滤推到 Hive 扫描
-- 大幅减少 fact 表的扫描量
```

## 深入主题

### 1. 联邦查询的代价模型与陷阱

联邦优化器最难的部分是代价估算：本地表代价基于统计信息，但远端表的统计信息可能不可获取或不可信。PostgreSQL 用 `use_remote_estimate` 调用远端 EXPLAIN，但它本身要付出网络往返代价。Trino 则尽量从 connector 元数据接口获取行数与列基数。

常见陷阱：

- **小表 + 远端大表 JOIN**：如果小表在本地，optimizer 可能倾向于把小表广播到远端做 JOIN（join 下推），但远端可能不接受广播。结果回退到把整个大表拉回本地，性能爆炸。
- **谓词无法下推的隐式类型转换**：`WHERE id = '42'`（字符串与 BIGINT 比较）会导致下推失败，需要写 `WHERE id = 42`。
- **跨时区 timestamp**：远端 timestamp without time zone 与本地 timestamptz 混用时下推会失败，因为表达式语义不一致。
- **远端 view 上的下推**：远端是 view 时，谓词通常下推到 view 之内，但如果 view 包含 window function 或 LATERAL，下推被阻断。

### 2. 安全性与权限模型

跨库链接的安全敏感点：

1. **凭证存储**：SQL/MED 的 USER MAPPING 把密码存在本地系统 catalog（pg_user_mappings）。建议使用 pg_hba 的 cert/SCRAM 而非纯密码。
2. **行级权限不传递**：远端表的 row-level security 可能因为 user mapping 是固定身份而失效。所有本地用户都以同一个远端身份查询，绕开了远端的 RLS。
3. **SQL 注入与函数下推**：FDW 实现需要正确转义所有从本地来的值；postgres_fdw 内部使用参数化协议，但其他实现需要审计。
4. **网络传输加密**：默认情况下 postgres_fdw 走 libpq，需要 `sslmode=verify-full` 防中间人。

### 3. 事务边界与一致性

跨实例事务的一致性问题是联邦查询最深的坑：

- **PostgreSQL postgres_fdw**：在单个本地事务内对多个 FDW 实例的修改通过 2PC 协调（需 `max_prepared_transactions`），但默认不启用。
- **Oracle DBLINK**：原生支持 2PC（distributed transaction），由 RECO 进程清理 in-doubt 事务。
- **SQL Server Linked Server**：通过 MS DTC 协调分布式事务。
- **DuckDB ATTACH**：每个 attached 数据库内部独立事务，跨实例不保证 ACID。
- **Trino**：基本上是只读模型，写入事务弱保证。

工程上常见的折中：把跨库事务限制为"读多写少"，写入仍走单库；或者通过应用层 saga 模式补偿。

### 4. Schema 漂移（Schema Drift）

当远端表结构变更（增加列、修改类型、改名）后，本地 FOREIGN TABLE 不会自动同步——这是 SQL/MED 范式的固有问题。Oracle DBLINK 因为按需获取元数据，没有这个问题，但代价是每次查询都要远端 describe。

实践上有两种应对：

1. **定期重新 IMPORT FOREIGN SCHEMA**：在运维流程中自动化执行。
2. **使用宽 wrapper schema**：对每个 FDW 表只声明 PRIMARY KEY 和需要的列，宽容地忽略远端新增列。

### 5. 推荐选型矩阵

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| OLTP 系统跨库查参考表 | PostgreSQL postgres_fdw | 标准、下推完整、与本地表一致体验 |
| 异构数据库整合 BI | Trino/Presto | 60+ connector，MPP 并发，专为联邦设计 |
| Lakehouse 联邦报表 | Databricks Lakehouse Federation | Unity Catalog 安全、与 Delta 集成 |
| 单脚本跨多源 ETL 探索 | DuckDB ATTACH + scanner | 零配置、单进程、超低延迟 |
| 老 Oracle 系统对接异构源 | Oracle Database Gateway | 唯一支持 Oracle 端发起的方案 |
| 微软栈跨数据库整合 | SQL Server Linked Server + OPENQUERY | 与 SSIS/SSRS 生态无缝 |
| 跨云多 SaaS 数仓查询 | Trino + 各家 connector | 对 Snowflake/BigQuery/Redshift 都有连接器 |
| Snowflake 内跨账户 | Secure Data Sharing | 零拷贝、实时、计费清晰 |
| BigQuery 查 Cloud SQL | EXTERNAL_QUERY | GCP 原生集成，免开外部工具 |
| 内嵌 ETL 脚本 | MariaDB CONNECT 引擎 | 同时支持 CSV/JSON/XML/ODBC/REST |

## 关键发现

1. **SQL/MED 标准化但实现稀少**。SQL/MED（ISO/IEC 9075-9:2003）定义了完整的外部数据接入框架，但完整实现的引擎极少：PostgreSQL 是唯一全功能实现，DB2 部分支持。多数引擎采用自有方案（DBLINK / Linked Server / Catalog / Connector），互相不兼容。

2. **PostgreSQL FDW 是事实标准的参考实现**。从 9.1（2011）引入框架到 14（2021）的异步执行，PostgreSQL 用十年构建了最完整的 SQL/MED FDW 生态：postgres_fdw 支持谓词、JOIN（9.6+）、聚合（10+）下推，第三方 FDW 覆盖 MySQL、Oracle、MongoDB、Kafka、Redis 等几乎所有主流数据源。

3. **三种范式的哲学差异显著**。DATABASE LINK（Oracle）以连接为中心、按需元数据；FDW（PostgreSQL/SQL/MED）以本地表为中心、显式登记；Linked Server（SQL Server）以远端服务器为中心、支持原文下推（OPENQUERY）。三者不是替代关系，反映了不同时代对联邦的理解。

4. **MySQL 在跨库领域全面退守**。FEDERATED 引擎在 8.0 中默认不启用、被官方建议放弃；MySQL 没有等价于 SQL/MED 的方案，跨库查询基本依赖应用层或代理。MariaDB 通过 CONNECT 引擎走出了完全不同的路线，支持 CSV/JSON/XML/ODBC/REST 等丰富类型。

5. **Trino/Presto 重新定义了"联邦"**。Trino 的整个引擎设计就是为了联邦：60+ connector、统一的 catalog.schema.table 三段命名、388+ 实现完整 join 下推、动态过滤跨源加速。它代表了从"扩展现有数据库支持外部源"到"以联邦为第一性原理设计引擎"的范式转变。

6. **Lakehouse 厂商在 2023+ 发力联邦**。Databricks Lakehouse Federation（GA 2023）通过 Unity Catalog 把 Snowflake/Redshift/PostgreSQL/MySQL 等注册为外部 catalog；Snowflake 通过 Secure Data Sharing + External Functions 实现"无搬迁"集成；BigQuery EXTERNAL_QUERY 支持 Cloud SQL/Spanner。云数仓正在把联邦能力作为关键差异化点。

7. **DuckDB 用 ATTACH 重新发明了"轻量级联邦"**。DuckDB 的 postgres/mysql/sqlite scanner 扩展把整个外部数据库挂载为一等 catalog，实现了零配置、单进程、跨多引擎的 SQL 体验。这种模式特别适合本地开发、ETL 脚本、跨源数据探索。

8. **下推能力决定联邦的实用性**。同样支持 FDW，PostgreSQL 与简陋 JDBC 连接器之间在万亿行表上的性能差距可达 100 倍以上。联邦查询的工程价值不在于"能不能查"，而在于"谓词、JOIN、聚合是否能下推到远端"——这是评估任何联邦方案的核心维度。

9. **OPENQUERY 范式仍有不可替代价值**。SQL Server 的 OPENQUERY、BigQuery 的 EXTERNAL_QUERY、Oracle 的 DBMS_HS_PASSTHROUGH 都允许"原文下推"——绕过本地解析直接把 SQL 字符串发给远端。这种"显式信任远端"的范式回避了类型推导、函数兼容、统计估算的所有难题，是处理边缘特性的逃生通道。

10. **跨实例事务依旧是开放问题**。即使 PostgreSQL postgres_fdw 也只在启用 2PC 时支持原子跨库事务；多数生产部署回避跨库写入，通过 saga 或 outbox 模式补偿。任何"跨库 ACID"承诺都需要审视底层是否真的有 2PC，以及网络分区下的恢复策略。

11. **schema drift 是 FDW 的固有税**。SQL/MED 的显式元数据登记带来了计划器可见性，代价是远端 DDL 变更后本地 FOREIGN TABLE 必须手动或定期 IMPORT。Oracle DBLINK 没有这个问题（按需取元数据），但牺牲了计划器优化能力。

12. **基于文件的外部表与跨数据库 FDW 是两个世界**。详细对比见 [external-tables.md](./external-tables.md)：那篇覆盖 S3/HDFS/本地文件的外部表（PolyBase、Snowflake External Tables、Hive 外部表），本篇覆盖跨数据库链接（FDW、DBLINK、Linked Server、Connector）。两者在某些引擎里语法相似（都叫 EXTERNAL TABLE 或 FOREIGN TABLE），但底层机制、下推能力、典型使用场景完全不同。

## 参考资料

- ISO/IEC 9075-9:2016, Information technology — Database languages — SQL — Part 9: Management of External Data (SQL/MED)
- PostgreSQL: [Foreign Data](https://www.postgresql.org/docs/current/ddl-foreign-data.html)
- PostgreSQL: [postgres_fdw](https://www.postgresql.org/docs/current/postgres-fdw.html)
- PostgreSQL: [Writing a Foreign Data Wrapper](https://www.postgresql.org/docs/current/fdwhandler.html)
- PostgreSQL Wiki: [Foreign data wrappers](https://wiki.postgresql.org/wiki/Foreign_data_wrappers)
- Oracle: [Distributed Database Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/ddbac/index.html)
- Oracle: [Database Gateway for ODBC](https://docs.oracle.com/en/database/oracle/oracle-database/19/odbcu/index.html)
- SQL Server: [Linked Servers](https://learn.microsoft.com/en-us/sql/relational-databases/linked-servers/linked-servers-database-engine)
- SQL Server: [OPENQUERY](https://learn.microsoft.com/en-us/sql/t-sql/functions/openquery-transact-sql)
- MySQL: [The FEDERATED Storage Engine](https://dev.mysql.com/doc/refman/8.0/en/federated-storage-engine.html)
- MariaDB: [CONNECT Storage Engine](https://mariadb.com/kb/en/connect/)
- DB2: [Federation Server](https://www.ibm.com/docs/en/db2/11.5?topic=federation)
- Snowflake: [External Functions](https://docs.snowflake.com/en/sql-reference/external-functions)
- Snowflake: [Secure Data Sharing](https://docs.snowflake.com/en/user-guide/data-sharing-intro)
- BigQuery: [EXTERNAL_QUERY](https://cloud.google.com/bigquery/docs/cloud-sql-federated-queries)
- DuckDB: [PostgreSQL Scanner](https://duckdb.org/docs/extensions/postgres)
- DuckDB: [MySQL Scanner](https://duckdb.org/docs/extensions/mysql)
- Trino: [Connectors](https://trino.io/docs/current/connector.html)
- Trino: [Pushdown](https://trino.io/docs/current/optimizer/pushdown.html)
- Trino: [Dynamic Filtering](https://trino.io/docs/current/admin/dynamic-filtering.html)
- ClickHouse: [Table Engines for Integrations](https://clickhouse.com/docs/en/engines/table-engines/integrations)
- Databricks: [Lakehouse Federation](https://docs.databricks.com/en/query-federation/index.html)
- SAP HANA: [Smart Data Access](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/e35d3deb1d8845298b71f0e4faf67d04.html)
- Greenplum: [PXF](https://docs.vmware.com/en/VMware-Greenplum-Platform-Extension-Framework/index.html)
- YugabyteDB: [Foreign data wrappers](https://docs.yugabyte.com/preview/explore/ysql-language-features/advanced-features/foreign-data-wrappers/)
