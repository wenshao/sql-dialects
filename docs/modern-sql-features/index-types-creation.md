# 索引类型与创建语法：各 SQL 方言实现全对比

> 参考资料:
> - [MySQL 8.0 - CREATE INDEX](https://dev.mysql.com/doc/refman/8.0/en/create-index.html)
> - [PostgreSQL - Indexes](https://www.postgresql.org/docs/current/indexes.html)
> - [Oracle - Managing Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-indexes.html)
> - [SQL Server - Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/)
> - [ClickHouse - Data Skipping Indexes](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-data_skipping-indexes)
> - [Snowflake - Search Optimization](https://docs.snowflake.com/en/user-guide/search-optimization-service)

索引是数据库引擎中最核心的查询加速机制。一个设计良好的索引可以将查询从全表扫描 O(n) 降为 O(log n) 甚至 O(1)。但不同引擎对索引类型的支持差异极大——从最基础的 B-tree 到 PostgreSQL 的 GIN/GiST/BRIN 家族，从传统的 Hash 索引到 ClickHouse 独特的列式跳数索引，选择合适的索引类型是引擎开发者和使用者共同面对的核心问题。

本文从 45+ 种 SQL 方言出发，全面对比各引擎的索引类型支持、创建语法差异、高级特性（部分索引、表达式索引、覆盖索引等），为引擎开发者提供系统性的参考。

## 索引类型支持矩阵

```
引擎              B-tree  Hash  GIN  GiST  BRIN  Bitmap  倒排  全文  空间  列式跳数
────────────────  ──────  ────  ───  ────  ────  ──────  ────  ────  ────  ────────
MySQL              ✅     ✅(1)  ❌    ❌    ❌     ❌     ✅(2) ✅    ✅     ❌
PostgreSQL         ✅     ✅     ✅    ✅    ✅     ❌(3)   ❌    ✅(4) ✅     ❌
Oracle             ✅     ✅(5)  ❌    ❌    ❌     ✅     ✅(6) ✅    ✅     ❌
SQL Server         ✅     ✅(7)  ❌    ❌    ❌     ❌     ✅(8) ✅    ✅     ✅(9)
SQLite             ✅     ❌     ❌    ❌    ❌     ❌     ❌    ✅(10)❌     ❌
BigQuery           ❌(11) ❌     ❌    ❌    ❌     ❌     ✅    ✅    ✅     ❌
Snowflake          ❌(12) ❌     ❌    ❌    ❌     ❌     ❌    ❌    ✅(13) ❌
ClickHouse         ❌(14) ❌     ❌    ❌    ❌     ❌     ✅    ✅(15)❌     ✅
Hive               ❌     ❌     ❌    ❌    ❌     ✅(16) ❌    ❌    ❌     ❌
Spark SQL          ❌     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
Trino/Presto       ❌     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
DuckDB             ✅(17) ❌     ❌    ❌    ❌     ❌     ❌    ✅(18)❌     ❌
TiDB               ✅     ❌     ❌    ❌    ❌     ❌     ❌    ✅(19)❌     ❌
OceanBase          ✅     ✅     ❌    ❌    ❌     ❌     ✅    ✅    ✅     ❌
CockroachDB        ✅     ✅     ✅    ✅    ❌     ❌     ✅    ✅    ✅     ❌
StarRocks          ❌(20) ❌     ❌    ❌    ❌     ✅     ❌    ❌    ❌     ❌
Doris              ❌(20) ❌     ❌    ❌    ❌     ✅     ✅    ❌    ❌     ❌
MaxCompute         ❌     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
Greenplum          ✅     ✅     ✅    ✅    ❌     ✅     ❌    ✅    ✅     ❌
Redshift           ❌(21) ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
Teradata           ✅(22) ✅     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
DB2                ✅     ✅     ❌    ❌    ❌     ❌     ❌    ✅    ✅     ❌
Informix           ✅     ✅     ❌    ❌    ❌     ❌     ❌    ✅    ✅     ❌
MariaDB            ✅     ✅(1)  ❌    ❌    ❌     ❌     ❌    ✅    ✅     ❌
Percona Server     ✅     ✅(1)  ❌    ❌    ❌     ❌     ❌    ✅    ✅     ❌
Aurora MySQL       ✅     ✅(1)  ❌    ❌    ❌     ❌     ❌    ✅    ✅     ❌
Aurora PostgreSQL  ✅     ✅     ✅    ✅    ✅     ❌     ❌    ✅    ✅     ❌
AlloyDB            ✅     ✅     ✅    ✅    ✅     ❌     ❌    ✅    ✅     ❌
CrateDB            ✅     ❌     ❌    ❌    ❌     ❌     ✅    ✅    ✅     ❌
TimescaleDB        ✅     ✅     ✅    ✅    ✅     ❌     ❌    ✅    ✅     ❌
YugabyteDB         ✅     ✅     ✅    ✅    ❌     ❌     ❌    ✅    ✅     ❌
SingleStore(MemSQL)✅     ✅     ❌    ❌    ❌     ❌     ❌    ✅    ✅     ✅
Citus              ✅     ✅     ✅    ✅    ✅     ❌     ❌    ✅    ✅     ❌
Vertica            ✅(22) ❌     ❌    ❌    ❌     ❌     ❌    ✅    ❌     ✅
MonetDB            ✅     ✅     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
QuestDB            ❌     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
InfluxDB(SQL)      ❌     ❌     ❌    ❌    ❌     ❌     ✅    ❌    ❌     ❌
Databricks SQL     ❌     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
Firebolt           ❌     ❌     ❌    ❌    ❌     ❌     ❌    ✅    ❌     ✅
Yellowbrick        ✅     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ✅
EXASOL             ❌(11) ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
Voltdb             ✅     ✅     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
NuoDB              ✅     ✅     ❌    ❌    ❌     ❌     ❌    ✅    ❌     ❌
H2                 ✅     ✅     ❌    ❌    ❌     ❌     ❌    ✅    ✅     ❌
HSQLDB             ✅     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌
Derby              ✅     ❌     ❌    ❌    ❌     ❌     ❌    ❌    ❌     ❌

(1)  MySQL/MariaDB: Hash 仅 MEMORY/NDB 引擎支持, InnoDB 使用自适应 Hash (内部自动)
(2)  MySQL: InnoDB 倒排索引通过 FULLTEXT INDEX 实现
(3)  PostgreSQL: 无原生 Bitmap 索引, 但查询执行时有 Bitmap Index Scan (动态构建)
(4)  PostgreSQL: 全文索引通过 GIN on tsvector 实现
(5)  Oracle: Hash 索引已不推荐, 实际使用 Hash Cluster
(6)  Oracle: 倒排索引通过 Oracle Text (CTXSYS) 实现
(7)  SQL Server: 2014+ 通过 In-Memory OLTP 支持 Hash 索引
(8)  SQL Server: 倒排索引通过 Full-Text Index 实现
(9)  SQL Server: 列存储索引 (Columnstore Index), 非跳数索引
(10) SQLite: FTS5 虚拟表实现全文搜索
(11) BigQuery/EXASOL: 列存引擎, 无传统索引, 依赖自动优化
(12) Snowflake: 无用户可创建索引, 依赖 Search Optimization Service
(13) Snowflake: 空间类型支持查询但无专用索引
(14) ClickHouse: 主键排序代替 B-tree, MergeTree ORDER BY 即排序键
(15) ClickHouse: 全文通过 tokenbf_v1/ngrambf_v1 跳数索引实现
(16) Hive: ORC 格式内置 Bitmap 索引
(17) DuckDB: ART (Adaptive Radix Tree) 作为默认索引结构
(18) DuckDB: 通过 FTS 扩展支持
(19) TiDB: 全文索引功能有限, 仅语法兼容
(20) StarRocks/Doris: 基于排序键的稀疏索引, 非传统 B-tree
(21) Redshift: 无用户索引, 依赖 Sort Key + Zone Maps
(22) Teradata/Vertica: 使用 Primary Index (PI) 或投影 (Projection) 机制
```

## 索引类型详解

### B-tree 索引 (最通用的默认索引)

B-tree (Balanced Tree) 是绝大多数关系型数据库的默认索引结构。它支持等值查询、范围查询和排序操作，是最通用的索引类型。

```sql
-- MySQL: B-tree 是 InnoDB 默认索引类型
CREATE INDEX idx_name ON users (name);
-- 等价于
CREATE INDEX idx_name ON users (name) USING BTREE;

-- PostgreSQL: B-tree 也是默认
CREATE INDEX idx_name ON users (name);
-- 显式指定
CREATE INDEX idx_name ON users USING btree (name);

-- Oracle: 默认就是 B-tree (不需要显式指定)
CREATE INDEX idx_name ON users (name);

-- SQL Server: 默认创建非聚集 B-tree 索引
CREATE NONCLUSTERED INDEX idx_name ON users (name);

-- SQLite: B-tree 是唯一的索引结构
CREATE INDEX idx_name ON users (name);

-- DuckDB: 使用 ART (Adaptive Radix Tree) 代替传统 B-tree
-- 创建语法相同, 但底层结构不同
CREATE INDEX idx_name ON users (name);
```

### Hash 索引

Hash 索引仅支持等值查询 (=, IN)，不支持范围查询和排序。查找复杂度为 O(1)，但功能受限。

```sql
-- PostgreSQL: 原生 Hash 索引 (10+ 后 WAL 安全)
CREATE INDEX idx_email ON users USING hash (email);
-- 注意: PostgreSQL 10 之前的 Hash 索引不记录 WAL, 崩溃后不安全

-- MySQL: 仅 MEMORY/NDB 引擎支持显式 Hash 索引
CREATE TABLE sessions (
    id    VARCHAR(64) NOT NULL,
    data  TEXT,
    INDEX idx_id (id) USING HASH
) ENGINE = MEMORY;
-- InnoDB 的自适应 Hash 索引是内部机制, 无法手动创建

-- SQL Server: In-Memory OLTP 表的 Hash 索引
CREATE TABLE sessions (
    id   NVARCHAR(64) NOT NULL PRIMARY KEY NONCLUSTERED
         HASH WITH (BUCKET_COUNT = 131072),
    data NVARCHAR(MAX)
) WITH (MEMORY_OPTIMIZED = ON);

-- CockroachDB: 通过 STORING 的 Hash Sharded Index
CREATE INDEX idx_ts ON events (ts) USING HASH WITH (bucket_count = 8);
```

### GIN (Generalized Inverted Index) — PostgreSQL 家族

GIN 是 PostgreSQL 的通用倒排索引，适用于包含多个元素的值（数组、JSON、全文搜索等）。

```sql
-- PostgreSQL: 数组搜索
CREATE INDEX idx_tags ON articles USING gin (tags);
-- 查询: SELECT * FROM articles WHERE tags @> ARRAY['sql', 'index'];

-- PostgreSQL: JSONB 搜索
CREATE INDEX idx_meta ON products USING gin (metadata jsonb_path_ops);
-- 查询: SELECT * FROM products WHERE metadata @> '{"color": "red"}';

-- PostgreSQL: 全文搜索
CREATE INDEX idx_fts ON documents USING gin (to_tsvector('english', content));
-- 查询: SELECT * FROM documents WHERE to_tsvector('english', content) @@ to_tsquery('database & index');

-- CockroachDB: 兼容 PostgreSQL GIN 语法
CREATE INVERTED INDEX idx_tags ON articles (tags);
-- 或
CREATE INDEX idx_tags ON articles USING gin (tags);

-- Greenplum: 继承 PostgreSQL GIN
CREATE INDEX idx_tags ON articles USING gin (tags);
```

### GiST (Generalized Search Tree) — PostgreSQL 家族

GiST 是一个通用搜索树框架，支持自定义数据类型的索引。最常用于空间数据 (PostGIS) 和范围类型。

```sql
-- PostgreSQL: 空间索引 (PostGIS)
CREATE INDEX idx_location ON places USING gist (geom);
-- 查询: SELECT * FROM places WHERE ST_DWithin(geom, ST_MakePoint(116.4, 39.9), 1000);

-- PostgreSQL: 范围类型索引
CREATE INDEX idx_period ON reservations USING gist (period);
-- 查询: SELECT * FROM reservations WHERE period && daterange('2025-01-01', '2025-12-31');

-- PostgreSQL: 排他约束 (利用 GiST)
ALTER TABLE reservations ADD CONSTRAINT no_overlap
    EXCLUDE USING gist (room_id WITH =, period WITH &&);

-- CockroachDB: 空间索引使用 GiST
CREATE INDEX idx_geo ON locations USING gist (geom);
```

### BRIN (Block Range INdex) — PostgreSQL 特有

BRIN 是一种极小的索引，存储每个数据块范围的摘要信息。适用于数据物理排列与索引列有强相关性的场景（如时间序列）。

```sql
-- PostgreSQL: 时间序列数据 (数据按 created_at 自然排序)
CREATE INDEX idx_ts ON events USING brin (created_at);
-- BRIN 索引大小通常只有 B-tree 的 1/100

-- 指定 pages_per_range (每多少页存储一个摘要)
CREATE INDEX idx_ts ON events USING brin (created_at)
    WITH (pages_per_range = 32);
-- pages_per_range 越小精度越高, 但索引越大
-- 默认 128 页, 时间序列场景建议 32~64 页

-- TimescaleDB: BRIN 特别适合 hypertable 的时间列
CREATE INDEX idx_ts ON metrics USING brin (time)
    WITH (pages_per_range = 32);

-- Aurora PostgreSQL / AlloyDB / Citus: 完全继承 PostgreSQL BRIN
```

### Bitmap 索引

Bitmap 索引用位图表示每个值的行集合，适用于低基数列 (distinct 值少的列)。

```sql
-- Oracle: 原生 Bitmap 索引
CREATE BITMAP INDEX idx_status ON orders (status);
-- status 只有 'pending', 'shipped', 'delivered' 等少数几个值
-- 注意: Bitmap 索引不适合高并发 DML, 主要用于 OLAP/数据仓库

-- Greenplum: 支持 Bitmap 索引
CREATE INDEX idx_status ON orders USING bitmap (status);

-- StarRocks: Bitmap 索引
ALTER TABLE orders ADD INDEX idx_status (status) USING BITMAP;

-- Doris: Bitmap 索引
ALTER TABLE orders ADD INDEX idx_status (status) USING BITMAP;

-- Hive: ORC 文件格式内置 Bitmap 索引 (不需要显式创建)
-- 通过 ORC 的 bloom filter 和行组索引实现类似功能
CREATE TABLE orders (
    id     BIGINT,
    status STRING
) STORED AS ORC
TBLPROPERTIES ("orc.bloom.filter.columns" = "status");
```

### 全文索引

全文索引用于自然语言文本搜索，支持分词、词干提取、相关度排序等功能。

```sql
-- MySQL: FULLTEXT 索引 (InnoDB 5.6+)
CREATE FULLTEXT INDEX idx_content ON articles (title, content);
-- 查询 (自然语言模式)
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database index' IN NATURAL LANGUAGE MODE);
-- 查询 (布尔模式)
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql' IN BOOLEAN MODE);

-- PostgreSQL: 基于 GIN + tsvector
CREATE INDEX idx_fts ON articles USING gin (
    to_tsvector('english', title || ' ' || content)
);
SELECT * FROM articles
WHERE to_tsvector('english', title || ' ' || content) @@ plainto_tsquery('english', 'database index');

-- Oracle: Oracle Text (CTXSYS)
CREATE INDEX idx_content ON articles (content)
    INDEXTYPE IS CTXSYS.CONTEXT;
SELECT * FROM articles WHERE CONTAINS(content, 'database AND index') > 0;

-- SQL Server: Full-Text Index
CREATE FULLTEXT CATALOG ft_catalog;
CREATE FULLTEXT INDEX ON articles (title, content)
    KEY INDEX pk_articles ON ft_catalog;
SELECT * FROM articles WHERE CONTAINS((title, content), 'database AND index');

-- SQLite: FTS5 虚拟表
CREATE VIRTUAL TABLE articles_fts USING fts5(title, content);
SELECT * FROM articles_fts WHERE articles_fts MATCH 'database index';

-- ClickHouse: tokenbf_v1 / ngrambf_v1 跳数索引
ALTER TABLE articles
    ADD INDEX idx_fts content TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4;
-- 这是布隆过滤器实现, 有假阳性但无假阴性

-- DuckDB: FTS 扩展
INSTALL fts;
LOAD fts;
PRAGMA create_fts_index('articles', 'id', 'title', 'content');
```

### 空间索引

空间索引用于地理和几何数据的高效查询 (R-tree 结构)。

```sql
-- MySQL: SPATIAL 索引 (InnoDB, MyISAM)
CREATE SPATIAL INDEX idx_geo ON places (location);
-- location 列类型为 POINT/GEOMETRY 等
SELECT * FROM places
WHERE MBRContains(ST_GeomFromText('POLYGON(...)'), location);

-- PostgreSQL + PostGIS: GiST 空间索引
CREATE INDEX idx_geo ON places USING gist (geom);
SELECT * FROM places
WHERE ST_DWithin(geom, ST_SetSRID(ST_MakePoint(116.4, 39.9), 4326), 1000);

-- Oracle: Spatial Index (R-tree)
INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES ('PLACES', 'GEOM',
    SDO_DIM_ARRAY(SDO_DIM_ELEMENT('X', -180, 180, 0.005),
                  SDO_DIM_ELEMENT('Y', -90, 90, 0.005)), 4326);
CREATE INDEX idx_geo ON places (geom)
    INDEXTYPE IS MDSYS.SPATIAL_INDEX;

-- SQL Server: 空间索引
CREATE SPATIAL INDEX idx_geo ON places (geom)
    USING GEOGRAPHY_GRID
    WITH (GRIDS = (MEDIUM, MEDIUM, MEDIUM, MEDIUM));

-- BigQuery: 地理函数支持 (无显式索引, 内部优化)
SELECT * FROM places
WHERE ST_DWithin(geom, ST_GeogPoint(116.4, 39.9), 1000);
```

### ClickHouse 列式跳数索引 (Data Skipping Index)

ClickHouse 不使用传统索引，而是基于 MergeTree 引擎的排序键和跳数索引。

```sql
-- 主键排序 (MergeTree ORDER BY)
CREATE TABLE events (
    event_date Date,
    user_id    UInt64,
    event_type String,
    payload    String
) ENGINE = MergeTree()
ORDER BY (event_date, user_id);
-- ORDER BY 定义了数据的物理排列顺序, 类似聚集索引

-- MinMax 跳数索引: 记录每个 granule 的最小值和最大值
ALTER TABLE events
    ADD INDEX idx_user user_id TYPE minmax GRANULARITY 4;

-- Set 跳数索引: 记录每个 granule 中的唯一值集合
ALTER TABLE events
    ADD INDEX idx_type event_type TYPE set(100) GRANULARITY 4;

-- Bloom Filter 跳数索引
ALTER TABLE events
    ADD INDEX idx_payload payload TYPE bloom_filter(0.01) GRANULARITY 4;

-- tokenbf_v1: 分词后的布隆过滤器 (适合文本搜索)
ALTER TABLE events
    ADD INDEX idx_text payload TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4;

-- ngrambf_v1: N-gram 布隆过滤器 (适合模糊搜索)
ALTER TABLE events
    ADD INDEX idx_ngram payload TYPE ngrambf_v1(3, 10240, 3, 0) GRANULARITY 4;
```

## CREATE INDEX 语法差异对比

### 基本语法

```
引擎              基本语法模式
────────────────  ────────────────────────────────────────────────
MySQL             CREATE [UNIQUE|FULLTEXT|SPATIAL] INDEX name ON tbl (cols) [USING type]
PostgreSQL        CREATE [UNIQUE] INDEX [CONCURRENTLY] name ON tbl [USING method] (cols)
Oracle            CREATE [UNIQUE|BITMAP] INDEX name ON tbl (cols) [TABLESPACE ts]
SQL Server        CREATE [UNIQUE] [CLUSTERED|NONCLUSTERED] INDEX name ON tbl (cols) [INCLUDE (cols)]
SQLite            CREATE [UNIQUE] INDEX [IF NOT EXISTS] name ON tbl (cols) [WHERE expr]
BigQuery          CREATE SEARCH INDEX name ON tbl (cols)
ClickHouse        ALTER TABLE tbl ADD INDEX name expr TYPE type GRANULARITY n
DuckDB            CREATE [UNIQUE] INDEX name ON tbl (cols)
TiDB              CREATE [UNIQUE] INDEX name ON tbl (cols)
OceanBase         CREATE [UNIQUE] INDEX name ON tbl (cols) [LOCAL|GLOBAL]
CockroachDB       CREATE [UNIQUE|INVERTED] INDEX name ON tbl (cols) [STORING (cols)]
StarRocks         CREATE INDEX name ON tbl (col) [USING BITMAP]
Doris             CREATE INDEX name ON tbl (col) [USING BITMAP|INVERTED]
Greenplum         CREATE [UNIQUE] INDEX name ON tbl [USING method] (cols)
DB2               CREATE [UNIQUE] INDEX name ON tbl (cols) [INCLUDE (cols)]
Teradata          CREATE [UNIQUE] INDEX name (cols) ON tbl
H2                CREATE [UNIQUE|HASH] INDEX name ON tbl (cols)
```

### IF NOT EXISTS 支持

```
引擎              IF NOT EXISTS   说明
────────────────  ─────────────   ──────────────────────────
MySQL              ❌             不支持, 需要用存储过程绕过
PostgreSQL         ✅             CREATE INDEX IF NOT EXISTS (9.5+)
Oracle             ❌             不支持, 需要 PL/SQL 异常处理
SQL Server         ❌             不支持, 需要先查询系统视图
SQLite             ✅             CREATE INDEX IF NOT EXISTS
BigQuery           ✅             CREATE SEARCH INDEX IF NOT EXISTS
ClickHouse         ✅             ALTER TABLE ... ADD INDEX IF NOT EXISTS
DuckDB             ✅             CREATE INDEX IF NOT EXISTS (非标准但支持)
TiDB               ❌             不支持 (与 MySQL 兼容)
OceanBase          ❌             不支持 (与 MySQL 兼容)
CockroachDB        ✅             CREATE INDEX IF NOT EXISTS
StarRocks          ❌             不支持
Doris              ❌             不支持
MariaDB            ✅             CREATE INDEX IF NOT EXISTS (10.1.4+)
H2                 ✅             CREATE INDEX IF NOT EXISTS
Greenplum          ✅             继承 PostgreSQL
DB2                ❌             不支持
Teradata           ❌             不支持
```

### 在线/非阻塞索引创建

在线索引创建是生产环境的关键需求——在不阻塞 DML 操作的前提下完成索引构建。

```sql
-- PostgreSQL: CONCURRENTLY (不阻塞读写, 但耗时更长)
CREATE INDEX CONCURRENTLY idx_name ON users (name);
-- 注意: CONCURRENTLY 不能在事务块内使用
-- 注意: 如果失败会留下 INVALID 索引, 需要 DROP 后重建

-- MySQL: ALGORITHM=INPLACE / LOCK=NONE (5.6+, InnoDB Online DDL)
CREATE INDEX idx_name ON users (name) ALGORITHM=INPLACE, LOCK=NONE;
-- ALGORITHM 选项: DEFAULT, INPLACE, COPY, INSTANT (8.0+)
-- LOCK 选项: DEFAULT, NONE, SHARED, EXCLUSIVE

-- Oracle: ONLINE 关键字
CREATE INDEX idx_name ON users (name) ONLINE;
-- Oracle 还支持并行创建
CREATE INDEX idx_name ON users (name) ONLINE PARALLEL 8;

-- SQL Server: ONLINE = ON (Enterprise Edition)
CREATE INDEX idx_name ON users (name) WITH (ONLINE = ON);
-- 可指定等待策略
CREATE INDEX idx_name ON users (name)
    WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 60);
-- RESUMABLE: SQL Server 2019+, 支持中断后恢复

-- TiDB: 默认在线 (分布式 DDL)
CREATE INDEX idx_name ON users (name);
-- TiDB 所有 DDL 都是在线的, 通过内部状态机实现

-- OceanBase: 默认在线
CREATE INDEX idx_name ON users (name);

-- CockroachDB: 默认在线
CREATE INDEX idx_name ON users (name);
-- 所有 schema change 都是在线非阻塞的

-- MariaDB: ALGORITHM/LOCK 选项 (与 MySQL 类似)
CREATE INDEX idx_name ON users (name) ALGORITHM=INPLACE, LOCK=NONE;

-- Greenplum: 不支持 CONCURRENTLY (与 PostgreSQL 不同)
CREATE INDEX idx_name ON users (name); -- 会阻塞写
```

```
在线创建索引支持矩阵:

引擎              在线创建     关键字/机制                    可恢复中断
────────────────  ──────────   ─────────────────────────────  ──────────
MySQL              ✅          ALGORITHM=INPLACE, LOCK=NONE   ❌
PostgreSQL         ✅          CONCURRENTLY                   ❌ (失败需重建)
Oracle             ✅          ONLINE [PARALLEL n]            ✅ (RESUMABLE)
SQL Server         ✅(Ent.)    WITH (ONLINE=ON)               ✅ (RESUMABLE, 2019+)
SQLite             ❌          单线程, 无需                    N/A
BigQuery           N/A         搜索索引异步创建               N/A
ClickHouse         N/A         ADD INDEX 仅修改元数据         N/A
DuckDB             ❌          嵌入式, 无需                    N/A
TiDB               ✅          默认在线 (状态机)              ✅ (内部实现)
OceanBase          ✅          默认在线                       ✅
CockroachDB        ✅          默认在线                       ✅
StarRocks          N/A         索引在数据写入时构建           N/A
Doris              N/A         索引在数据写入时构建           N/A
MariaDB            ✅          ALGORITHM=INPLACE              ❌
Greenplum          ❌          不支持 CONCURRENTLY            ❌
DB2                ✅          ALLOW READ/WRITE ACCESS        ❌
Teradata           ❌          需要离线                       ❌
```

## 高级索引特性

### Unique 索引 (唯一索引)

```sql
-- 几乎所有引擎都支持 UNIQUE INDEX
CREATE UNIQUE INDEX idx_email ON users (email);

-- MySQL: UNIQUE 索引允许多个 NULL 值 (InnoDB)
-- PostgreSQL: UNIQUE 索引同样允许多个 NULL (默认)
-- PostgreSQL 15+: NULLS NOT DISTINCT 选项
CREATE UNIQUE INDEX idx_email ON users (email) NULLS NOT DISTINCT;
-- 有了这个选项, NULL 也被视为相同值, 只允许一个 NULL

-- SQL Server: 唯一索引默认只允许一个 NULL
-- 如果需要允许多个 NULL:
CREATE UNIQUE INDEX idx_email ON users (email) WHERE email IS NOT NULL;

-- Oracle: UNIQUE 索引不存储全 NULL 的行
-- 复合唯一索引中, 只有所有列都非 NULL 时才检查唯一性
```

### 复合索引 (Composite Index)

```sql
-- 所有引擎都支持复合索引, 列顺序至关重要
CREATE INDEX idx_composite ON orders (customer_id, order_date);
-- 此索引可以加速:
--   WHERE customer_id = 100                     (使用第一列)
--   WHERE customer_id = 100 AND order_date > ... (使用两列)
-- 不能加速:
--   WHERE order_date > '2025-01-01'             (跳过第一列)

-- MySQL: 最多支持 16 列
-- PostgreSQL: 最多支持 32 列
-- Oracle: 最多支持 32 列
-- SQL Server: 最多支持 16 列 (加 INCLUDE 列不受此限制)

-- PostgreSQL: 复合索引指定不同排序方向
CREATE INDEX idx_multi ON orders (customer_id ASC, order_date DESC NULLS LAST);

-- MySQL 8.0+: 支持 DESC 索引 (之前 DESC 被解析但忽略)
CREATE INDEX idx_multi ON orders (customer_id ASC, order_date DESC);
```

### 覆盖索引 (Covering Index) 与 INCLUDE 子句

覆盖索引将额外的列存储在索引叶子节点中，使查询可以仅通过索引完成（Index-Only Scan），不需要回表。

```sql
-- SQL Server: INCLUDE 子句 (2005+, 最早支持)
CREATE INDEX idx_orders ON orders (customer_id)
    INCLUDE (order_date, amount);
-- customer_id 在索引树中用于搜索
-- order_date, amount 仅存储在叶子节点, 不参与排序

-- PostgreSQL: INCLUDE 子句 (11+)
CREATE INDEX idx_orders ON orders (customer_id)
    INCLUDE (order_date, amount);

-- MySQL: 无 INCLUDE 子句, 但 InnoDB 聚集索引结构天然覆盖
-- 可以通过将额外列加入复合索引来实现覆盖
CREATE INDEX idx_covering ON orders (customer_id, order_date, amount);
-- 虽然能覆盖查询, 但所有列都参与排序, 索引更大更慢

-- CockroachDB: STORING 子句 (功能等同于 INCLUDE)
CREATE INDEX idx_orders ON orders (customer_id)
    STORING (order_date, amount);

-- Oracle: 无 INCLUDE 子句, 通过复合索引实现覆盖
-- 但 Oracle 有 Index-Organized Table (IOT), 整张表就是索引

-- DB2: INCLUDE 子句
CREATE UNIQUE INDEX idx_orders ON orders (customer_id)
    INCLUDE (order_date, amount);
-- DB2 的 INCLUDE 仅支持 UNIQUE INDEX
```

```
INCLUDE 子句支持矩阵:

引擎              INCLUDE   替代名称        版本要求
────────────────  ───────   ────────────    ────────
MySQL              ❌       (复合索引替代)
PostgreSQL         ✅       INCLUDE          11+
Oracle             ❌       (复合索引/IOT)
SQL Server         ✅       INCLUDE          2005+
SQLite             ❌
BigQuery           N/A
ClickHouse         N/A
DuckDB             ❌
TiDB               ❌       (与 MySQL 兼容)
OceanBase          ❌
CockroachDB        ✅       STORING          全版本
StarRocks          N/A
Doris              N/A
MariaDB            ❌
Greenplum          ✅       INCLUDE (继承PG)
DB2                ✅       INCLUDE (仅UNIQUE)
YugabyteDB         ✅       INCLUDE
```

### 部分索引 / 过滤索引 (Partial / Filtered Index)

部分索引只对满足 WHERE 条件的行建立索引，可以显著减少索引大小。

```sql
-- PostgreSQL: WHERE 子句 (最早支持, 最灵活)
CREATE INDEX idx_active ON users (email)
    WHERE is_active = true;
-- 仅对活跃用户建立索引, 如果只有 10% 用户活跃, 索引缩小 90%

-- SQL Server: WHERE 子句 (Filtered Index, 2008+)
CREATE INDEX idx_active ON users (email)
    WHERE is_active = 1;
-- 限制: WHERE 条件不能使用子查询、函数、OR 跨列

-- SQLite: WHERE 子句
CREATE INDEX idx_active ON users (email)
    WHERE is_active = 1;

-- CockroachDB: WHERE 子句 (兼容 PostgreSQL)
CREATE INDEX idx_active ON users (email)
    WHERE is_active = true;

-- Oracle: 利用 NULL 不入索引的特性模拟
-- Oracle B-tree 索引不存储全 NULL 行
CREATE INDEX idx_active ON users (
    CASE WHEN is_active = 1 THEN email END
);
-- 只有 is_active=1 的行会被索引 (其他行表达式为 NULL)

-- MySQL: 不支持部分索引
-- 可以通过 Generated Column + 索引模拟:
ALTER TABLE users ADD COLUMN active_email VARCHAR(255)
    GENERATED ALWAYS AS (CASE WHEN is_active = 1 THEN email END) STORED;
CREATE INDEX idx_active ON users (active_email);
```

```
部分索引支持矩阵:

引擎              支持    语法                 限制
────────────────  ──────  ──────────────────   ────────────────────
PostgreSQL         ✅     WHERE clause          几乎无限制
SQL Server         ✅     WHERE clause          不能跨列 OR, 无函数
SQLite             ✅     WHERE clause          条件受限
CockroachDB        ✅     WHERE clause          与 PostgreSQL 兼容
DuckDB             ✅     WHERE clause          基本支持
MySQL              ❌     需要 Generated Column 变通
Oracle             ❌     需要函数索引模拟
TiDB               ❌     与 MySQL 兼容, 不支持
OceanBase          ❌     不支持
MariaDB            ❌     不支持
BigQuery           N/A
ClickHouse         N/A
Greenplum          ✅     继承 PostgreSQL
YugabyteDB         ✅     继承 PostgreSQL
TimescaleDB        ✅     继承 PostgreSQL
DB2                ❌     不支持
Teradata           ❌     不支持
```

### 函数索引 / 表达式索引 (Function-based / Expression Index)

```sql
-- PostgreSQL: 任意表达式索引
CREATE INDEX idx_lower ON users (lower(email));
-- 查询: SELECT * FROM users WHERE lower(email) = 'alice@example.com';

CREATE INDEX idx_year ON orders (extract(year from order_date));
CREATE INDEX idx_json ON products ((metadata->>'category'));

-- Oracle: 函数索引 (8i+)
CREATE INDEX idx_upper ON users (UPPER(email));
-- 需要 QUERY_REWRITE_ENABLED = TRUE 和 QUERY_REWRITE_INTEGRITY = TRUSTED

-- MySQL 8.0+: 表达式索引 (通过函数式键部分)
CREATE INDEX idx_expr ON users ((CAST(data->>'$.age' AS UNSIGNED)));
-- MySQL 8.0.13+: 内部创建隐藏的 Generated Column

-- SQL Server: 计算列 + 索引 (间接支持)
ALTER TABLE users ADD email_lower AS LOWER(email) PERSISTED;
CREATE INDEX idx_lower ON users (email_lower);
-- 或者直接用 Computed Column Index (需要确定性函数)

-- SQLite: 表达式索引
CREATE INDEX idx_lower ON users (lower(email));

-- CockroachDB: 表达式索引 (兼容 PostgreSQL)
CREATE INDEX idx_lower ON users (lower(email));

-- TiDB: 表达式索引 (5.1+)
CREATE INDEX idx_lower ON users ((lower(email)));
-- 注意: 需要双层括号

-- DuckDB: 不支持表达式索引
```

```
表达式索引支持矩阵:

引擎              支持    语法/方式                      版本
────────────────  ──────  ─────────────────────────────  ─────────
PostgreSQL         ✅     CREATE INDEX ... (expr)         7.4+
Oracle             ✅     CREATE INDEX ... (func(col))    8i+
MySQL              ✅     CREATE INDEX ... ((expr))       8.0.13+
SQL Server         ⚠️     Computed Column + Index         间接支持
SQLite             ✅     CREATE INDEX ... (expr)         3.9.0+
CockroachDB        ✅     CREATE INDEX ... (expr)         全版本
TiDB               ✅     CREATE INDEX ... ((expr))       5.1+
OceanBase          ✅     函数索引                        与 Oracle 模式兼容
MariaDB            ✅     CREATE INDEX ... ((expr))       10.6+
DuckDB             ❌     不支持
BigQuery           N/A    无用户索引
ClickHouse         N/A    通过物化列实现
Greenplum          ✅     继承 PostgreSQL
YugabyteDB         ✅     继承 PostgreSQL
DB2                ✅     表达式索引                      全版本
Teradata           ❌     不支持
```

### 不可见索引 (Invisible Index) 与未使用索引检测

不可见索引允许在不删除索引的前提下测试其对查询计划的影响。

```sql
-- MySQL 8.0+: 不可见索引
CREATE INDEX idx_name ON users (name) INVISIBLE;
-- 或者修改现有索引为不可见
ALTER TABLE users ALTER INDEX idx_name INVISIBLE;
ALTER TABLE users ALTER INDEX idx_name VISIBLE;
-- 优化器默认忽略 INVISIBLE 索引, 但索引仍然维护

-- 使用 optimizer switch 临时启用不可见索引
SET SESSION optimizer_switch = 'use_invisible_indexes=on';

-- Oracle 11g+: 不可见索引
CREATE INDEX idx_name ON users (name) INVISIBLE;
ALTER INDEX idx_name INVISIBLE;
ALTER INDEX idx_name VISIBLE;

-- PostgreSQL: 无原生 INVISIBLE, 但 HypoPG 扩展可以创建假设索引
CREATE EXTENSION hypopg;
SELECT * FROM hypopg_create_index('CREATE INDEX idx_name ON users (name)');
-- 然后用 EXPLAIN 测试查询计划, 完成后:
SELECT hypopg_drop_index(indexrelid) FROM hypopg_list_indexes();

-- SQL Server: 无原生不可见索引, 但可以 DISABLE
ALTER INDEX idx_name ON users DISABLE;
-- DISABLE 后索引不被使用也不被维护, 需要 REBUILD 恢复

-- MariaDB 10.6+: IGNORED 索引
CREATE INDEX idx_name ON users (name) IGNORED;
ALTER TABLE users ALTER INDEX idx_name IGNORED;
ALTER TABLE users ALTER INDEX idx_name NOT IGNORED;

-- TiDB: 不可见索引 (与 MySQL 8.0 兼容)
ALTER TABLE users ALTER INDEX idx_name INVISIBLE;
ALTER TABLE users ALTER INDEX idx_name VISIBLE;

-- CockroachDB: NOT VISIBLE
CREATE INDEX idx_name ON users (name) NOT VISIBLE;
ALTER INDEX users@idx_name NOT VISIBLE;
```

```
未使用索引检测方式:

引擎              检测方式
────────────────  ──────────────────────────────────────────
MySQL             sys.schema_unused_indexes (performance_schema)
PostgreSQL        pg_stat_user_indexes.idx_scan = 0
Oracle            V$OBJECT_USAGE, DBA_INDEX_USAGE (12c+)
SQL Server        sys.dm_db_index_usage_stats
MariaDB           sys.schema_unused_indexes (类似 MySQL)
TiDB              INFORMATION_SCHEMA.TIDB_INDEX_USAGE (7.0+)
CockroachDB       crdb_internal.index_usage_statistics
```

### 索引提示 (Index Hints)

```sql
-- MySQL: USE INDEX / FORCE INDEX / IGNORE INDEX
SELECT * FROM orders USE INDEX (idx_date)
WHERE order_date > '2025-01-01';

SELECT * FROM orders FORCE INDEX (idx_customer)
WHERE customer_id = 100;

SELECT * FROM orders IGNORE INDEX (idx_date)
WHERE order_date > '2025-01-01' AND customer_id = 100;

-- MySQL 8.0+: 优化器提示 (更推荐的方式)
SELECT /*+ INDEX(orders idx_date) */ * FROM orders
WHERE order_date > '2025-01-01';

SELECT /*+ NO_INDEX(orders idx_date) */ * FROM orders
WHERE order_date > '2025-01-01';

-- Oracle: 优化器提示
SELECT /*+ INDEX(orders idx_date) */ * FROM orders
WHERE order_date > '2025-01-01';

SELECT /*+ FULL(orders) */ * FROM orders  -- 强制全表扫描
WHERE order_date > '2025-01-01';

SELECT /*+ INDEX_FFS(orders idx_date) */ * FROM orders;  -- Fast Full Index Scan

-- PostgreSQL: 无原生索引提示, 通过参数间接控制
SET enable_seqscan = off;     -- 禁用顺序扫描 (变相强制使用索引)
SET enable_indexscan = off;   -- 禁用索引扫描
SET enable_bitmapscan = off;  -- 禁用位图扫描
-- pg_hint_plan 扩展提供类似 Oracle 的提示语法

-- SQL Server: 索引提示
SELECT * FROM orders WITH (INDEX(idx_date))
WHERE order_date > '2025-01-01';

SELECT * FROM orders WITH (FORCESEEK)  -- 强制索引查找
WHERE customer_id = 100;

SELECT * FROM orders WITH (FORCESCAN)  -- 强制索引扫描
WHERE order_date > '2025-01-01';

-- TiDB: 兼容 MySQL 提示语法
SELECT /*+ USE_INDEX(orders, idx_date) */ * FROM orders
WHERE order_date > '2025-01-01';

SELECT /*+ IGNORE_INDEX(orders, idx_date) */ * FROM orders
WHERE order_date > '2025-01-01';

-- OceanBase: 兼容 MySQL 提示语法 (MySQL 模式)
SELECT /*+ INDEX(orders idx_date) */ * FROM orders
WHERE order_date > '2025-01-01';

-- CockroachDB: 索引提示
SELECT * FROM orders@idx_date
WHERE order_date > '2025-01-01';
-- @ 语法指定使用特定索引
```

```
索引提示支持矩阵:

引擎              USE/FORCE    Optimizer Hint    表级语法           其他
────────────────  INDEX        /*+ ... */        WITH (INDEX)     ────────
MySQL              ✅           ✅ (8.0+)          ❌               -
PostgreSQL         ❌           ❌ (扩展)           ❌               SET enable_*
Oracle             ❌           ✅                  ❌               -
SQL Server         ❌           ❌                  ✅               FORCESEEK/SCAN
SQLite             ✅ (部分)    ❌                  ❌               INDEXED BY
TiDB               ✅           ✅                  ❌               与 MySQL 兼容
OceanBase          ✅           ✅                  ❌               双模式
CockroachDB        ❌           ❌                  ❌               @index 语法
MariaDB            ✅           ❌                  ❌               与 MySQL 兼容
DB2                ❌           ✅ (Optimization Profile)  ❌       -
```

### 聚集索引 vs 非聚集索引 (Clustered vs Non-Clustered)

聚集索引决定了数据行的物理存储顺序——一张表只能有一个聚集索引。

```sql
-- SQL Server: 显式创建聚集索引
CREATE CLUSTERED INDEX idx_id ON users (id);
-- 非聚集索引
CREATE NONCLUSTERED INDEX idx_name ON users (name);
-- 默认: 有主键时自动创建聚集索引, 可以用 NONCLUSTERED 改变

-- MySQL/InnoDB: 主键自动成为聚集索引 (不可改变)
-- 如果没有主键, InnoDB 选择第一个 NOT NULL UNIQUE 索引
-- 如果没有合适的候选, InnoDB 创建隐藏的聚集键 (GEN_CLUST_INDEX)
CREATE TABLE users (
    id   BIGINT PRIMARY KEY,  -- 自动成为聚集索引
    name VARCHAR(100),
    INDEX idx_name (name)     -- 非聚集索引 (二级索引)
);
-- InnoDB 二级索引的叶子节点存储主键值 (而非行指针)

-- Oracle: Index-Organized Table (IOT) 是聚集表
CREATE TABLE users (
    id   NUMBER PRIMARY KEY,
    name VARCHAR2(100)
) ORGANIZATION INDEX;
-- 普通表 (堆表) 的索引都是非聚集的

-- PostgreSQL: 无原生聚集索引概念, 但可以物理重排
CLUSTER users USING idx_date;
-- CLUSTER 按索引排序重写整张表 (一次性操作, 后续插入不保持)

-- CockroachDB: PRIMARY KEY 决定数据排列 (类似 InnoDB)
CREATE TABLE users (
    id   INT PRIMARY KEY,  -- 数据按此排列
    name STRING
);

-- TiDB: 聚簇表 (5.0+)
CREATE TABLE users (
    id   BIGINT PRIMARY KEY CLUSTERED,  -- 显式聚簇
    name VARCHAR(100)
) ;
-- 也支持非聚簇主键
CREATE TABLE logs (
    id   BIGINT PRIMARY KEY NONCLUSTERED,
    ts   TIMESTAMP
);

-- ClickHouse: ORDER BY 定义数据排列 (类似聚集索引)
CREATE TABLE events (
    ts      DateTime,
    user_id UInt64
) ENGINE = MergeTree()
ORDER BY (ts, user_id);
```

```
聚集索引行为总结:

引擎              聚集索引来源          二级索引叶节点存储    可选择聚集键
────────────────  ────────────────────  ──────────────────    ──────────
MySQL/InnoDB       主键 (自动)           主键值               ❌ (永远是主键)
PostgreSQL         无 (堆表)             行指针 (ctid)        ❌ (CLUSTER 一次性)
Oracle             IOT 时主键            行指针 (ROWID)       ✅ (IOT 时)
SQL Server         可指定任意列          RID 或聚集键         ✅ (CREATE CLUSTERED)
SQLite             主键 (INTEGER PK)     行号 (rowid)         ❌
TiDB               主键 (可选 CLUSTERED) 主键值               ✅ (5.0+)
CockroachDB        主键 (自动)           主键值               ❌
ClickHouse         ORDER BY 列           N/A (列存)           ✅
StarRocks          排序键                N/A (列存)           ✅
Doris              排序键                N/A (列存)           ✅
```

### 主键与隐式索引创建

```sql
-- 几乎所有引擎: PRIMARY KEY 自动创建唯一索引
CREATE TABLE users (
    id   BIGINT PRIMARY KEY,  -- 自动创建索引
    email VARCHAR(255) UNIQUE  -- 自动创建唯一索引
);

-- 各引擎的差异在于:
-- MySQL:    PK = 聚集索引, UNIQUE = 非聚集索引, 外键列自动创建索引
-- PostgreSQL: PK 和 UNIQUE 创建 B-tree 索引, 外键列不自动创建索引
-- Oracle:   PK 和 UNIQUE 创建 B-tree 索引, 外键列不自动创建索引
-- SQL Server: PK 默认创建聚集索引, UNIQUE 创建非聚集索引
-- SQLite:   INTEGER PRIMARY KEY 是 rowid 别名 (不创建额外索引)

-- 外键是否自动创建索引:
--   MySQL/InnoDB: ✅ 自动创建 (如果不存在)
--   PostgreSQL:   ❌ 不自动创建 (需手动, 否则级联删除可能全表扫描)
--   Oracle:       ❌ 不自动创建 (强烈建议手动创建)
--   SQL Server:   ❌ 不自动创建
--   SQLite:       ❌ 不自动创建
```

```
隐式索引创建矩阵:

引擎              PK→索引  UNIQUE→索引  FK→索引  其他自动索引
────────────────  ───────  ──────────   ───────  ─────────────────────────
MySQL              ✅       ✅            ✅       -
PostgreSQL         ✅       ✅            ❌       -
Oracle             ✅       ✅            ❌       -
SQL Server         ✅       ✅            ❌       -
SQLite             ✅(1)    ✅            ❌       -
BigQuery           ❌(2)    N/A          N/A      Search Index 需手动
ClickHouse         ❌(3)    N/A          N/A      ORDER BY 即排序键
DuckDB             ✅       ✅            ❌       -
TiDB               ✅       ✅            ✅       与 MySQL 兼容
OceanBase          ✅       ✅            ✅       与 MySQL 兼容
CockroachDB        ✅       ✅            ❌       UNIQUE 自动创建 STORING 索引
MariaDB            ✅       ✅            ✅       与 MySQL 兼容
StarRocks          ❌(3)    N/A          N/A      排序键
Doris              ❌(3)    N/A          N/A      排序键

(1) SQLite: INTEGER PRIMARY KEY 不创建额外索引, 其他类型 PK 创建
(2) BigQuery: 主键是逻辑约束, 不创建物理索引
(3) ClickHouse/StarRocks/Doris: OLAP 引擎, 无传统索引概念
```

## 各引擎特有索引功能

### PostgreSQL 特有

```sql
-- SP-GiST (Space-Partitioned GiST): 适用于不平衡数据
CREATE INDEX idx_ip ON sessions USING spgist (ip inet_ops);
-- 适合: 电话号码、IP 地址、几何数据等

-- RUM 索引 (扩展): GIN 的增强版, 支持排序
CREATE EXTENSION rum;
CREATE INDEX idx_fts ON documents USING rum (fts_vector rum_tsvector_ops);
-- 与 GIN 的区别: RUM 可以按相关度排序而无需回表

-- 条件唯一索引 (Partial Unique Index)
CREATE UNIQUE INDEX idx_active_email ON users (email)
    WHERE deleted_at IS NULL;
-- 只在未删除的用户中保证 email 唯一
```

### Oracle 特有

```sql
-- Reverse Key Index: 防止索引右侧热点 (序列值)
CREATE INDEX idx_id ON orders (id) REVERSE;
-- 将键值反转存储, 分散相邻值到不同叶子块
-- 缺点: 不支持范围扫描

-- Index-Organized Table (IOT): 整张表存储在索引结构中
CREATE TABLE sessions (
    session_id RAW(16) PRIMARY KEY,
    user_id    NUMBER,
    data       CLOB
) ORGANIZATION INDEX
OVERFLOW TABLESPACE ts_overflow;  -- 大列溢出到单独空间

-- 压缩索引
CREATE INDEX idx_name ON users (last_name, first_name) COMPRESS 1;
-- COMPRESS 1: 压缩前缀的第一列 (适合高重复度前缀)

-- 全局 vs 本地分区索引
CREATE INDEX idx_date ON orders (order_date) LOCAL;   -- 每个分区一个索引
CREATE INDEX idx_cust ON orders (customer_id) GLOBAL; -- 跨分区的全局索引
```

### SQL Server 特有

```sql
-- 列存储索引 (Columnstore Index): OLAP 加速
-- 聚集列存储索引 (整张表转为列存)
CREATE CLUSTERED COLUMNSTORE INDEX idx_cs ON fact_sales;

-- 非聚集列存储索引 (选择部分列)
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_cs ON fact_sales
    (product_id, quantity, amount);

-- 过滤列存储索引 (2016+)
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_cs ON orders
    (status, amount)
    WHERE order_date >= '2024-01-01';

-- 可恢复的索引操作 (2019+)
CREATE INDEX idx_name ON users (name)
    WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 120);
-- 如果超时或手动暂停:
ALTER INDEX idx_name ON users PAUSE;
ALTER INDEX idx_name ON users RESUME;
ALTER INDEX idx_name ON users ABORT;
```

### MySQL/InnoDB 特有

```sql
-- 前缀索引: 对长文本列只索引前 N 个字符
CREATE INDEX idx_name ON users (name(20));
-- 只索引 name 列的前 20 个字符, 节省空间
-- 注意: 前缀索引不能用于 ORDER BY 和 GROUP BY

-- 降序索引 (8.0+)
CREATE INDEX idx_multi ON orders (customer_id ASC, created_at DESC);
-- 8.0 之前 DESC 被解析但忽略

-- 自适应 Hash 索引 (AHI): 完全自动
-- InnoDB 自动检测频繁访问的索引页, 在内存中构建 Hash 索引
-- 通过 innodb_adaptive_hash_index 参数控制

-- 更改索引可见性
ALTER TABLE users ALTER INDEX idx_name INVISIBLE;
ALTER TABLE users ALTER INDEX idx_name VISIBLE;
```

### ClickHouse 特有

```sql
-- 投影 (Projection): 类似物化视图的预聚合索引
ALTER TABLE events ADD PROJECTION proj_by_user (
    SELECT user_id, count(), sum(amount)
    GROUP BY user_id
);
ALTER TABLE events MATERIALIZE PROJECTION proj_by_user;

-- 多种跳数索引类型
-- minmax: 最小值/最大值
ALTER TABLE t ADD INDEX idx col TYPE minmax GRANULARITY 4;
-- set(N): 存储唯一值集合 (最多 N 个)
ALTER TABLE t ADD INDEX idx col TYPE set(1000) GRANULARITY 4;
-- bloom_filter: 布隆过滤器
ALTER TABLE t ADD INDEX idx col TYPE bloom_filter(0.01) GRANULARITY 4;
-- tokenbf_v1: 分词布隆过滤器
ALTER TABLE t ADD INDEX idx col TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4;
-- ngrambf_v1: N-gram 布隆过滤器
ALTER TABLE t ADD INDEX idx col TYPE ngrambf_v1(3, 10240, 3, 0) GRANULARITY 4;

-- 跳数索引的 GRANULARITY 参数:
-- GRANULARITY 4 表示每 4 个 granule (默认每 granule 8192 行) 生成一个索引条目
-- 值越小精度越高但索引越大
```

### CockroachDB 特有

```sql
-- Hash Sharded Index: 防止范围热点
CREATE INDEX idx_ts ON events (ts) USING HASH WITH (bucket_count = 8);
-- 将单调递增的时间戳值分散到 8 个 bucket

-- 多区域索引
CREATE INDEX idx_region ON orders (id)
    PARTITION BY LIST (region) (
        PARTITION us VALUES IN ('us-east1', 'us-west2'),
        PARTITION eu VALUES IN ('europe-west1')
    );

-- 部分 GIN 索引
CREATE INVERTED INDEX idx_tags ON articles (tags)
    WHERE status = 'published';
```

### Doris 特有

```sql
-- 倒排索引 (2.0+): 用于文本搜索和高基数列
ALTER TABLE articles ADD INDEX idx_content (content) USING INVERTED
    PROPERTIES("parser" = "chinese");

-- BloomFilter 索引: 通过表属性设置
ALTER TABLE orders SET ("bloom_filter_columns" = "order_id, user_id");

-- NGram BloomFilter 索引 (2.0+): 模糊匹配加速
ALTER TABLE logs ADD INDEX idx_msg (message) USING INVERTED
    PROPERTIES("parser" = "unicode", "support_phrase" = "true");
```

## 综合对比总结

### 索引高级特性支持矩阵

```
引擎              UNIQUE  复合  覆盖     部分    表达式  不可见  提示     聚集
                  索引    索引  (INCLUDE) 索引    索引    索引    语法     索引
────────────────  ──────  ────  ───────  ──────  ──────  ──────  ──────  ──────
MySQL              ✅     ✅     ❌       ❌      ✅(8.0) ✅(8.0) ✅      ✅(PK)
PostgreSQL         ✅     ✅     ✅(11)   ✅      ✅      ❌(1)   ❌(2)   ❌(3)
Oracle             ✅     ✅     ❌       ❌(4)   ✅      ✅(11g) ✅      ✅(IOT)
SQL Server         ✅     ✅     ✅       ✅      ⚠️(5)   ❌(6)   ✅      ✅
SQLite             ✅     ✅     ❌       ✅      ✅      ❌      ⚠️(7)   ✅(IPK)
ClickHouse         ❌     N/A   N/A      N/A     N/A     ❌      N/A     ✅(OB)
DuckDB             ✅     ✅     ❌       ✅      ❌      ❌      ❌      ❌
TiDB               ✅     ✅     ❌       ❌      ✅(5.1) ✅      ✅      ✅(5.0)
OceanBase          ✅     ✅     ❌       ❌      ✅      ✅      ✅      ✅(PK)
CockroachDB        ✅     ✅     ✅(S)    ✅      ✅      ✅      ✅(@)   ✅(PK)
MariaDB            ✅     ✅     ❌       ❌      ✅(10.6)✅(10.6) ✅     ✅(PK)
Greenplum          ✅     ✅     ✅       ✅      ✅      ❌      ❌      ❌
DB2                ✅     ✅     ✅(U)    ❌      ✅      ❌      ✅      ✅
YugabyteDB         ✅     ✅     ✅       ✅      ✅      ❌      ❌      ✅(PK)

(1)  PostgreSQL: 可用 HypoPG 扩展做假设索引测试
(2)  PostgreSQL: 无原生提示, pg_hint_plan 扩展提供
(3)  PostgreSQL: CLUSTER 命令可一次性按索引排序, 但不持续维护
(4)  Oracle: 可通过函数索引 + NULL 特性模拟
(5)  SQL Server: 通过 Computed Column + Index 间接实现
(6)  SQL Server: 可用 DISABLE 代替, 但语义不同
(7)  SQLite: INDEXED BY 子句指定索引
(S)  CockroachDB: 使用 STORING 替代 INCLUDE
(U)  DB2: INCLUDE 仅限 UNIQUE 索引
(OB) ClickHouse: ORDER BY 决定数据排列
(IPK) SQLite: INTEGER PRIMARY KEY 即 rowid
```

## 对引擎开发者的实现建议

```
1. 索引类型的优先级

   如果你在开发新的 SQL 引擎, 建议按以下优先级实现:
     - P0 (必须): B-tree (或等效有序结构), UNIQUE 约束, 复合索引
     - P1 (强烈建议): 全文索引, 表达式索引, 部分索引
     - P2 (推荐): INCLUDE/覆盖索引, 不可见索引, 在线创建
     - P3 (可选): Hash 索引, 空间索引, Bitmap 索引, GIN/GiST

   OLAP 引擎的优先级不同:
     - P0: 排序键 (ORDER BY / Sort Key), MinMax/Zone Map 过滤
     - P1: 布隆过滤器, 倒排索引 (高基数列)
     - P2: Bitmap 索引 (低基数列), 列存索引
     - P3: 物化视图/投影 (Projection)

2. B-tree 实现要点

   B-tree 是最核心的索引结构, 实现时注意:
     - 页大小: 4KB (SQLite), 8KB (PostgreSQL), 16KB (InnoDB) 都有成功案例
     - 并发控制: B-link tree (Lehman-Yao) 是事实标准, 减少锁争用
     - 前缀压缩: 对复合索引的公共前缀进行压缩 (Oracle COMPRESS)
     - 后缀截断: 非叶子节点只存储用于路由的最短前缀 (PostgreSQL 特性)
     - 页分裂策略: 50-50 分裂 vs 90-10 分裂 (对顺序插入场景很重要)
     - 空页回收: 延迟回收 (InnoDB) vs 即时回收, 需要考虑 MVCC 可见性

3. 在线索引创建的实现

   生产环境必须支持在线创建索引:
     - 方案一 (PostgreSQL CONCURRENTLY):
       * 第一遍: 扫描全表建索引, 不持有排他锁
       * 第二遍: 处理第一遍期间的增量变更
       * 第三遍: 验证索引完整性
       * 优点: 实现相对简单; 缺点: 如果失败需要清理 INVALID 索引
     - 方案二 (InnoDB Online DDL):
       * 创建索引结构 → 扫描全表填充 → 回放期间的 DML log
       * 通过 row_log 记录增量变更
       * 优点: 在事务引擎中更自然; 缺点: row_log 可能很大
     - 方案三 (分布式引擎, TiDB/CockroachDB):
       * 使用状态机: absent → delete-only → write-only → public
       * 每个状态保证向后兼容, 逐步生效
       * 优点: 天然支持滚动更新; 缺点: 实现复杂度高

4. IF NOT EXISTS 的重要性

   看似简单的功能, 但对 DevOps/CI/CD 流程至关重要:
     - 幂等性: 迁移脚本可以重复执行而不失败
     - MySQL 至今不支持 CREATE INDEX IF NOT EXISTS, 这是一个痛点
     - 建议: 新引擎从第一天就支持 IF NOT EXISTS
     - 同样重要的: DROP INDEX IF EXISTS

5. 部分索引和表达式索引

   这两个特性对高级用户极其重要:
     - 部分索引: 索引大小可以减少 50%~99%, 对多租户场景尤其关键
     - 表达式索引: 需要解决的核心问题是表达式的确定性 (deterministic)
       * 只有确定性表达式才能建索引
       * IMMUTABLE (PostgreSQL) / DETERMINISTIC (Oracle) 标记
       * 需要在查询优化器中做表达式匹配 (expression matching)
     - 实现建议: 底层都可以通过隐藏的计算列 (hidden generated column) 实现

6. 索引提示的设计哲学

   两种对立的设计哲学:
     - MySQL/Oracle 路线: 提供丰富的索引提示, 让用户控制执行计划
       * 优点: 用户可以 workaround 优化器的缺陷
       * 缺点: 提示可能与实际数据分布不匹配, 导致性能劣化
     - PostgreSQL 路线: 不提供索引提示, 强制依赖优化器
       * 优点: 避免了过时提示的问题
       * 缺点: 优化器不完美时用户束手无策
     - 建议: 至少提供基于注释的提示 (/*+ ... */) 作为逃生舱
       * 提示应该是建议 (advisory) 而非强制 (mandatory)
       * 记录提示使用频率, 作为优化器改进的方向

7. 不可见索引

   这是一个低成本高回报的特性:
     - 实现: 只需在优化器的索引选择阶段增加一个标志位检查
     - 价值: DBA 可以安全地测试删除索引的影响
     - 扩展: 结合索引使用统计, 可以自动推荐不可见/删除候选

8. 聚集索引的选择

   这是一个影响整个存储引擎架构的决策:
     - 堆表模型 (PostgreSQL, Oracle 默认):
       * 数据按插入顺序存储, 所有索引通过行指针 (ctid/ROWID) 访问
       * 优点: 索引小 (只存指针), UPDATE 不影响其他索引
       * 缺点: 范围扫描效率低, 行指针可能失效 (PostgreSQL HOT 优化)
     - 索引组织表模型 (InnoDB, SQL Server, TiDB):
       * 数据按主键排序存储, 二级索引存储主键值
       * 优点: 主键范围扫描极快, 覆盖扫描天然支持
       * 缺点: 二级索引更大 (存主键值), 主键更新代价高
     - 建议: OLTP 选择索引组织表, OLAP 选择列存, 混合负载考虑堆表

9. 索引元数据管理

   容易被忽视但影响生产的方面:
     - 索引统计信息: auto-analyze 的触发条件和采样率
     - 索引碎片检测: 页填充率 (fill factor) 监控
     - 索引重建: REINDEX (PostgreSQL) vs ALTER INDEX REBUILD (SQL Server)
     - 索引占用空间: 系统视图中需要暴露索引大小信息
     - 索引使用频率: 跟踪每个索引被使用的次数, 帮助发现冗余索引

10. 分布式环境下的索引

    分布式数据库的索引有额外挑战:
      - 全局索引 vs 本地索引:
        * 本地索引: 每个分片独立维护, 分片内查询高效
        * 全局索引: 跨分片的索引, 需要分布式事务维护
        * OceanBase 支持 LOCAL/GLOBAL 显式选择
      - 索引一致性:
        * 强一致: 索引与数据在同一事务中更新 (CockroachDB)
        * 最终一致: 索引异步更新, 读取可能不一致 (某些方案)
      - 分布式 DDL:
        * 在线 schema change 的核心挑战是多节点协调
        * Google F1 论文的状态机方案 (absent → delete-only → write-only → public)
          被 TiDB 和 CockroachDB 广泛采用
```

## 附录: 快速参考

### 常见索引操作语法速查

```sql
-- 创建索引
CREATE INDEX idx ON tbl (col);                        -- 标准 SQL
CREATE INDEX IF NOT EXISTS idx ON tbl (col);          -- PG, SQLite, CockroachDB
CREATE INDEX idx ON tbl (col) ALGORITHM=INPLACE;      -- MySQL
CREATE INDEX CONCURRENTLY idx ON tbl (col);           -- PostgreSQL

-- 删除索引
DROP INDEX idx;                                       -- 标准 SQL
DROP INDEX idx ON tbl;                                -- MySQL, SQL Server
DROP INDEX IF EXISTS idx;                             -- PostgreSQL, SQLite
DROP INDEX CONCURRENTLY idx;                          -- PostgreSQL

-- 重建索引
REINDEX INDEX idx;                                    -- PostgreSQL
ALTER INDEX idx REBUILD;                              -- SQL Server, Oracle
ALTER TABLE tbl ENGINE=InnoDB;                        -- MySQL (重建所有索引)
OPTIMIZE TABLE tbl;                                   -- MySQL

-- 重命名索引
ALTER INDEX idx RENAME TO idx_new;                    -- PostgreSQL, Oracle
ALTER TABLE tbl RENAME INDEX idx TO idx_new;          -- MySQL 5.7+

-- 查看索引
SHOW INDEX FROM tbl;                                  -- MySQL
\di+ tbl                                              -- PostgreSQL (psql)
SELECT * FROM pg_indexes WHERE tablename = 'tbl';    -- PostgreSQL
SELECT * FROM user_indexes WHERE table_name = 'TBL'; -- Oracle
sp_helpindex 'tbl';                                   -- SQL Server
PRAGMA index_list('tbl');                             -- SQLite
```
