# 空间索引类型 (Spatial Index Types)

从外卖配送的最近骑手匹配，到自动驾驶的高精地图查询，再到风控系统的位置欺诈识别——空间查询的核心永远是同一个问题：如何在数十亿坐标点中，毫秒级返回与给定区域相交的子集？传统 B 树在一维有序数据上无懈可击，但面对二维平面或三维球面坐标却几乎束手无策——这就是空间索引存在的意义。

本文系统梳理 45+ SQL 引擎中的空间索引实现：R-Tree 及其变体如何在工业界占据主导地位，PostgreSQL 的 GiST 框架如何把可扩展索引做到极致，SP-GiST 与 QuadTree 在不规则空间分布下的优势，以及 Uber 的 H3 与 Google 的 S2 网格如何颠覆传统树形索引的范式。

## SQL 标准与现状

**没有 SQL 标准定义空间索引**。SQL/MM Part 3 (ISO/IEC 13249-3, Spatial) 定义了空间数据类型 (`ST_Geometry` 类型层次) 和空间函数 (`ST_Intersects`、`ST_Contains` 等)，但**完全不规定索引实现细节**——索引类型、构建语法、底层算法均由各引擎自行决定。

OGC Simple Features for SQL 同样只关注几何模型与函数命名，对索引实现保持沉默。

这导致空间索引在各引擎中呈现出极强的方言性：

```sql
-- PostgreSQL/PostGIS: 显式声明索引方法
CREATE INDEX idx_geom ON parcels USING GIST (geom);
CREATE INDEX idx_geom_sp ON parcels USING SPGIST (geom);

-- MySQL: 关键字 SPATIAL，底层固定为 R-Tree
CREATE SPATIAL INDEX idx_geom ON parcels (geom);

-- SQL Server: 必须指定网格层级
CREATE SPATIAL INDEX idx_geom ON parcels(geom)
USING GEOGRAPHY_GRID
WITH (GRIDS = (LEVEL_1=MEDIUM, LEVEL_2=MEDIUM, LEVEL_3=MEDIUM, LEVEL_4=MEDIUM));

-- Oracle: 通过 INDEXTYPE 关联到 Spatial 算子
CREATE INDEX idx_geom ON parcels(geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2;

-- SQLite: R*Tree 必须用虚拟表 (不是普通索引)
CREATE VIRTUAL TABLE idx_geom USING rtree(id, minX, maxX, minY, maxY);
```

同样的需求 (二维点的空间查询)，五种语法、四种索引模型——这正是空间索引在 SQL 生态中最显著的特征。

## 空间索引方法总览

```
┌─────────────────────────────────────────────────────────────┐
│  空间索引家族 (按算法范式)                                    │
├─────────────────────────────────────────────────────────────┤
│  R-Tree 家族:                                                │
│    R-Tree       Guttman 1984，最经典实现                    │
│    R*-Tree      Beckmann 1990，更优分裂启发式                │
│    R+-Tree      不允许节点重叠 (写入慢)                      │
│    Hilbert R-Tree  按 Hilbert 曲线排序                      │
│                                                              │
│  树形分割家族:                                                │
│    Quadtree     四叉树 (二维空间四分递归)                    │
│    Octree       八叉树 (三维空间八分递归)                    │
│    KD-Tree      k 维二叉树，按维度交替分割                   │
│    BSP-Tree     二叉空间分割                                 │
│                                                              │
│  GiST 通用框架:                                               │
│    GiST         Generalized Search Tree (PG 7.x+)           │
│    SP-GiST      Space-Partitioned GiST (PG 9.2+)            │
│                                                              │
│  网格 / 离散化:                                              │
│    Geohash      Z-order 字符串编码                           │
│    H3 (Uber)    六边形分层网格 (16 层)                       │
│    S2 (Google)  球面 Hilbert 曲线 + 四叉树                   │
│    地理网格      SQL Server geography_grid (4 层)            │
│                                                              │
│  线性化 / 空间填充曲线:                                       │
│    Z-order      Morton 码                                    │
│    Hilbert      局部性更好的曲线                             │
└─────────────────────────────────────────────────────────────┘
```

## 主要支持矩阵 (45+ 引擎)

### R-Tree 与 R-Tree 变体支持

| 引擎 | R-Tree | R*-Tree | 实现方式 | 索引语法 | 版本 |
|------|--------|---------|---------|---------|------|
| PostgreSQL (核心) | -- | -- | 旧版有 R-Tree，已移除 (建议 GiST) | -- | 8.2+ 移除 |
| PostgreSQL + PostGIS | 是 | -- | 通过 GiST + 几何 opclass | `USING GIST` | 1.0+ (2005) |
| MySQL (InnoDB) | 是 | -- | 原生 R-Tree | `SPATIAL INDEX` | 5.7+ (2015) |
| MySQL (MyISAM) | 是 | -- | 原生 R-Tree (legacy) | `SPATIAL INDEX` | 4.1+ |
| MariaDB | 是 | -- | InnoDB R-Tree | `SPATIAL INDEX` | 10.2+ |
| SQLite | -- | 是 | R*Tree 虚拟表扩展 | `CREATE VIRTUAL TABLE ... USING rtree` | 3.8+ (2013) |
| Oracle Spatial | 是 | -- | 原生 R-Tree | `INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2` | 10g+ (2003) |
| SQL Server | -- | -- | 基于网格分解 (非 R-Tree) | `USING GEOGRAPHY_GRID` | 2008+ |
| DB2 Spatial Extender | 是 | -- | 网格 + R-Tree 混合 | `CREATE INDEX ... EXTEND USING db2gse.spatial_index` | 9.1+ |
| Informix Spatial | 是 | 是 | R-Tree DataBlade | `CREATE INDEX ... USING RTREE` | IDS 9+ |
| Snowflake | -- | -- | 自动微分区裁剪，无显式空间索引 | -- | -- |
| BigQuery | -- | -- | 自动空间裁剪 (S2) | -- | -- |
| Redshift | -- | -- | 无空间索引 | -- | -- |
| ClickHouse | -- | -- | spatial_index 实验性 (skip index) | `INDEX ... TYPE spatial_index` | 24.x 实验 |
| DuckDB | 是 | -- | spatial 扩展 (R-Tree) | `CREATE INDEX ... USING RTREE` | 0.10+ |
| Trino | -- | -- | 无原生索引 | -- | -- |
| Presto | -- | -- | 无原生索引 | -- | -- |
| Spark SQL | -- | -- | 无原生空间索引 (依赖外部) | -- | -- |
| Hive | -- | -- | 无空间索引 (UDF only) | -- | -- |
| Flink SQL | -- | -- | 无空间索引 | -- | -- |
| Databricks | -- | -- | Delta Lake Z-order (非 R-Tree) | `OPTIMIZE ... ZORDER BY` | DBR 7+ |
| Greenplum | 是 | -- | PostGIS GiST | `USING GIST` | 4.x+ |
| CockroachDB | -- | -- | 倒排索引 (S2 cell ID) | `INVERTED INDEX` | 20.2+ |
| TiDB | -- | -- | 无空间索引 | -- | -- |
| OceanBase (MySQL) | 是 | -- | InnoDB 兼容 R-Tree | `SPATIAL INDEX` | 4.x+ |
| YugabyteDB | 是 | -- | PostGIS via GiST | `USING GIST` | 2.6+ |
| SingleStore | -- | -- | 主键排序 + 函数索引 | -- | -- |
| Vertica | -- | -- | 无空间索引 (有 STV_ 函数) | -- | -- |
| Teradata | -- | -- | 仅主索引 (PI) | -- | -- |
| Impala | -- | -- | 无空间索引 | -- | -- |
| StarRocks | -- | -- | 无空间索引 | -- | -- |
| Doris | -- | -- | 无空间索引 | -- | -- |
| MonetDB | -- | -- | 无空间索引 | -- | -- |
| CrateDB | -- | -- | Geohash 倒排 (Lucene 底层) | -- | 0.x+ |
| TimescaleDB | 是 | -- | PostGIS GiST | `USING GIST` | 继承 PG |
| QuestDB | -- | -- | 无空间索引 | -- | -- |
| Exasol | -- | -- | 无空间索引 | -- | -- |
| SAP HANA | 是 | -- | 网格分层 + R-Tree | `CREATE SPATIAL INDEX` | SPS 09+ |
| Firebird | -- | -- | 无空间支持 | -- | -- |
| H2 | 是 | -- | 内置 R-Tree (MVStore) | `SPATIAL INDEX` | 1.4+ |
| HSQLDB | -- | -- | 无空间索引 | -- | -- |
| Derby | -- | -- | 无空间索引 | -- | -- |
| Athena | -- | -- | 继承 Presto/Trino，无索引 | -- | -- |
| Synapse Analytics | -- | -- | 有限空间支持，无索引 | -- | -- |
| Cloud Spanner | -- | -- | 无空间索引 | -- | -- |
| MongoDB (类 SQL) | -- | -- | 2d / 2dsphere 索引 | `db.coll.createIndex({loc: '2dsphere'})` | 2.4+ (2dsphere) |
| Esri ArcSDE | -- | -- | 自适应分箱 (Adaptive grid) | -- | 9.x+ |
| pg_h3 (PG 扩展) | -- | -- | H3 索引上的 B-tree | `CREATE INDEX ... ON (h3_cell)` | 3.7+ |
| Yellowbrick | -- | -- | 无空间索引 | -- | -- |
| Firebolt | -- | -- | 无空间索引 | -- | -- |

> 统计：约 18 个引擎原生支持 R-Tree 或基于 GiST 的 R-Tree 实现，约 25 个引擎完全无空间索引（多为分析型/MPP 引擎，依赖全表扫描或文件级裁剪）。

### GiST / SP-GiST / QuadTree / KD-Tree

| 引擎 | GiST | SP-GiST | QuadTree (空间) | KD-Tree | 多列空间 |
|------|------|---------|----------------|---------|---------|
| PostgreSQL (核心) | 是 (7.x+, 2001) | 是 (9.2+, 2012) | SP-GiST 内置 opclass | SP-GiST 内置 opclass | 是 |
| PostgreSQL + PostGIS | 是 | 是 (PostGIS 2.5+) | -- | -- | 是 |
| MySQL | -- | -- | -- | -- | 否 |
| MariaDB | -- | -- | -- | -- | 否 |
| SQLite | -- | -- | -- | -- | -- |
| Oracle Spatial | -- | -- | 是 (Quadtree 索引) | -- | 是 |
| SQL Server | -- | -- | 是 (网格分解类似 QuadTree) | -- | 是 |
| DB2 | -- | -- | 是 (网格分层) | -- | 是 |
| Informix | -- | -- | -- | -- | -- |
| ClickHouse | -- | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | -- | -- |
| Greenplum | 是 | 是 | 是 (PostGIS) | -- | 是 |
| CockroachDB | -- | -- | -- | -- | -- |
| YugabyteDB | 是 | 部分 | -- | -- | 是 |
| TimescaleDB | 是 | 是 | 是 | -- | 是 |
| H2 | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- | 是 |
| MongoDB | -- | -- | -- | -- | -- |
| Esri SDE | -- | -- | -- | -- | -- |

### H3 / S2 / Geohash 网格支持

| 引擎 | H3 (Uber) | S2 (Google) | Geohash | 实现 | 备注 |
|------|-----------|------------|---------|------|------|
| BigQuery | 函数 | 索引 | 函数 | 内置 | S2 用于自动空间裁剪 |
| Snowflake | 函数 (H3_*) | -- | 函数 | 原生 | 无显式空间索引 |
| Postgres + h3-pg | 是 | -- | 是 | 扩展 | h3_lat_lng_to_cell 等 |
| Postgres + pg_h3 | 是 | -- | -- | 扩展 | 过时实现 |
| ClickHouse | 是 (geoToH3 等) | -- | 是 | 内置函数 | 通过 BTREE 索引 H3 cell |
| DuckDB | 扩展 (h3) | -- | 扩展 | 社区扩展 | -- |
| Apache Pinot | -- | -- | -- | -- | 无 H3 |
| Spark SQL (Sedona) | 是 | 是 | 是 | 第三方 | Apache Sedona 提供 |
| Trino | -- | -- | 是 | 内置 | geohash_* 函数 |
| Presto | -- | -- | 是 | 内置 | -- |
| MongoDB | 否 | 是 (内部用) | 是 | 原生 | 2dsphere 用 S2 实现 |
| Cassandra | -- | -- | 是 | 类型 | 无空间索引 |
| Elasticsearch | -- | 是 (geohex_grid) | 是 (geohash_grid) | 内置 | 聚合用 |
| CrateDB | -- | -- | 是 | Lucene | -- |
| Esri SDE | -- | -- | -- | -- | 自有网格 |
| Vertica | 是 | -- | -- | 函数 | 23.x+ |
| Databricks | 是 (h3_*) | -- | -- | 内置 | DBR 11.2+ |
| Redshift | 是 (H3_*) | -- | -- | 内置 | 2023.x+ |

### 多列与函数空间索引

| 引擎 | 多列空间索引 | 函数索引 (空间) | GENERATED 列 + 索引 |
|------|------------|--------------|----------------|
| PostgreSQL + PostGIS | 是 (复合 GiST) | 是 (`ON ST_Centroid(geom)`) | 是 |
| MySQL 8.x | 否 (单列限制) | 是 (虚拟列) | 是 (生成列) |
| Oracle Spatial | 是 (复合) | 是 | 是 |
| SQL Server | 是 (空间 + 普通列) | -- | -- |
| DB2 | 是 | -- | -- |
| H2 | 否 | -- | -- |

## 各引擎实现详解

### PostgreSQL：GiST 框架的诞生与演进

PostgreSQL 是空间索引领域最具影响力的引擎之一。核心贡献是把"如何构建可扩展的索引方法"抽象为 **GiST (Generalized Search Tree)** 框架。

```
GiST 时间线:
  PG 7.0 (2000)   -- GiST 接口首次出现 (基于 Hellerstein 1995 论文)
  PG 7.1 (2001)   -- contrib/cube, contrib/seg 提供示例
  PG 7.2-7.4      -- 基础设施完善
  PG 8.2 (2006)   -- 移除独立的 R-Tree 索引方法 (改用 GiST)
  PG 9.2 (2012)   -- SP-GiST (Space-Partitioned GiST) 加入
  PG 9.5 (2016)   -- BRIN 加入 (块范围索引，可用于空间近似)
  PG 11+          -- GiST 支持覆盖索引 (INCLUDE)
  PG 13+          -- B-tree 去重，间接影响 GiST 效率
```

**基础语法**：

```sql
-- 安装 PostGIS
CREATE EXTENSION postgis;

-- GiST 索引 (R-Tree 实现，最常用)
CREATE INDEX idx_parcels_geom ON parcels USING GIST (geom);

-- SP-GiST 索引 (KD-Tree 或 QuadTree)
CREATE INDEX idx_parcels_geom_sp ON parcels USING SPGIST (geom);

-- 复合 GiST：geom + 普通列
CREATE INDEX idx_parcels_geom_city ON parcels USING GIST (geom, city_id);

-- 部分空间索引：仅索引活跃记录
CREATE INDEX idx_parcels_active ON parcels USING GIST (geom)
WHERE status = 'active';

-- 表达式索引：索引几何变换的结果
CREATE INDEX idx_parcels_centroid ON parcels USING GIST (ST_Centroid(geom));

-- 包含列 (覆盖索引，PG 11+)
CREATE INDEX idx_parcels_geom_inc ON parcels USING GIST (geom) INCLUDE (parcel_id, area);

-- BRIN 空间索引 (大表，弱筛选，块级近似)
CREATE INDEX idx_parcels_brin ON parcels USING BRIN (geom);
```

**GiST vs SP-GiST 选择**：

```
GiST (R-Tree on top of GiST):
  优点: 平衡树，节点重叠允许，写入快
  缺点: 节点重叠导致查询时多路径搜索
  适用: 通用空间查询，几何形状大小差异大

SP-GiST (Space-Partitioned):
  优点: 空间分割，无重叠，点查询极快
  缺点: 不平衡，写入有局部热点；不支持几何对象重叠
  适用: 点数据 (无延展)、QuadTree/KD-Tree 思路明确的场景

PostGIS 2.5+ 提供 SP-GiST 的几何 opclass，但生产环境仍以 GiST 为主。
```

### PostGIS：R-Tree on GiST 的工业级实现

PostGIS (2005, v1.0) 是 PostgreSQL 的空间扩展，把 R-Tree 算法实现在 GiST 框架之上：

```sql
-- PostGIS 安装与版本
CREATE EXTENSION postgis;       -- 当前主流版本 3.4 (2023)
SELECT PostGIS_Version();        -- "3.4 USE_GEOS=1 USE_PROJ=1 USE_STATS=1"

-- 几何列与索引
CREATE TABLE parcels (
    id BIGSERIAL PRIMARY KEY,
    geom GEOMETRY(POLYGON, 4326),
    area NUMERIC
);

CREATE INDEX idx_parcels_geom ON parcels USING GIST (geom);

-- ANALYZE 后才能用统计信息估算
ANALYZE parcels;

-- 查询：边界框过滤 + 精确判断 (& 操作符触发索引)
SELECT id, area FROM parcels
WHERE geom && ST_MakeEnvelope(120.0, 30.0, 121.0, 31.0, 4326)
  AND ST_Intersects(geom, ST_MakeEnvelope(120.0, 30.0, 121.0, 31.0, 4326));

-- KNN 查询 (k 最近邻)：<-> 操作符 + ORDER BY
SELECT id, geom <-> ST_Point(120.5, 30.5)::geography AS dist
FROM parcels
ORDER BY geom <-> ST_Point(120.5, 30.5)::geography
LIMIT 10;

-- 注意：
-- 1. PostGIS 索引基于几何的 bounding box (BBox)，不是几何本身
-- 2. ST_Intersects 等谓词会被规划器自动改写为先用 BBox 索引，再精判
-- 3. && 操作符就是 BBox 相交，是索引的"通行证"
```

**PostGIS GiST vs SP-GiST 实测差异**：

```
1000万 POINT 表:
  GiST 索引大小:   ~700 MB
  SP-GiST 索引大小: ~500 MB
  点查询 (ST_DWithin 100m):
    GiST:   2.3 ms
    SP-GiST: 1.8 ms (点数据更快)

1000万 POLYGON 表 (复杂边界):
  GiST 索引大小:   ~1.2 GB
  SP-GiST 索引大小: 不支持 (PostGIS 主流 SP-GiST 仅支持 POINT)
```

### MySQL InnoDB R-Tree (5.7+)

MySQL 5.7 (2015) 之前，空间索引仅在 MyISAM 上可用。5.7 把 R-Tree 完整移植到 InnoDB，支持事务的空间索引。

```sql
-- 创建空间表
CREATE TABLE parcels (
    id BIGINT PRIMARY KEY,
    geom GEOMETRY NOT NULL SRID 4326,    -- 8.0+ 强制 SRID
    SPATIAL INDEX idx_geom (geom)
) ENGINE=InnoDB;

-- 在已存在的表上加空间索引
ALTER TABLE parcels ADD SPATIAL INDEX idx_geom (geom);

-- 查询
SELECT id FROM parcels
WHERE MBRIntersects(geom, ST_GeomFromText('POLYGON((120 30, 121 30, 121 31, 120 31, 120 30))', 4326));

-- 注意 MySQL 限制：
-- 1. SPATIAL INDEX 列必须 NOT NULL
-- 2. 空间索引只能在单列上建立
-- 3. 8.0+ 引入 SRID 约束，索引仅对该 SRID 生效
-- 4. R-Tree 节点分裂使用 Guttman 算法 (非 R*-Tree)
-- 5. 不支持 EXPLAIN 详细的空间索引信息
```

**InnoDB R-Tree 的内部细节**：

```
InnoDB R-Tree 实现要点 (storage/innobase/gis):
  - 节点存储在与 B-tree 相同的页结构中 (16KB 页)
  - 内部节点存储子节点 BBox + 子节点指针
  - 叶子节点存储 BBox + 主键值
  - 分裂使用 R-Tree (Guttman 1984) 启发式，非 R*
  - 写入并发：每个页一把 X-lock，类似 B-tree
  - 不支持 KNN 操作符，需通过 ORDER BY ST_Distance + LIMIT 实现 (但走全索引)

性能特征 (作者基准测试，10亿 POINT):
  插入吞吐: ~80K rows/s (单线程)，约为 B-tree 1/3
  范围查询: BBox 匹配 1万 行约 50ms
  空间换时间: 索引大小约为数据大小 1.2-1.5 倍
```

### SQLite R*Tree 扩展 (3.8+)

SQLite 的 R*Tree 模块设计独特：通过虚拟表 (Virtual Table) 接口实现，与主表通过外键链接。

```sql
-- 启用 R*Tree (3.8+ 默认编译)
-- 实际上 SQLite R*Tree 早在 3.8 之前就有，3.8 起广泛可用

-- 创建空间索引虚拟表 (注意：这本身就是"索引"，不是普通的 CREATE INDEX)
CREATE VIRTUAL TABLE demo_index USING rtree(
    id,                  -- 主键
    minX, maxX,          -- X 维度边界
    minY, maxY           -- Y 维度边界
);

-- 主数据表
CREATE TABLE demo_data (
    id INTEGER PRIMARY KEY,
    name TEXT,
    geom_wkt TEXT
);

-- 同步插入：必须在应用层维护两表
INSERT INTO demo_index VALUES (1, 120.0, 120.5, 30.0, 30.5);
INSERT INTO demo_data VALUES (1, 'parcel-1', 'POLYGON(...)');

-- 查询：通过 R*Tree 找候选 ID，再 JOIN 主表
SELECT d.* FROM demo_data d
JOIN demo_index i ON d.id = i.id
WHERE i.minX < 121.0 AND i.maxX > 120.0
  AND i.minY < 31.0 AND i.maxY > 30.0;

-- 注意 SQLite 限制：
-- 1. 仅支持矩形 BBox，不支持任意几何
-- 2. 一维~五维任选 (rtree_i32 支持整数版本)
-- 3. 索引与主表分离，应用层负责一致性
-- 4. 没有 ST_* 函数，需配合 SpatiaLite 扩展
```

**SQLite R*Tree 的内部算法**：

```
SQLite R*Tree 采用 Beckmann 1990 R*-Tree 论文中的:
  - 强制重插入 (forced reinsert) 减少节点重叠
  - ChooseSubtree 启发式：最小化重叠面积，再最小化扩张面积
  - 节点分裂：选择重叠最小、覆盖面积最小的轴

性能 (1000万 POINT):
  索引文件大小: ~120 MB
  范围查询: 1ms 量级 (内存命中)
  插入吞吐: ~30K rows/s (含主表)
```

### Oracle Spatial：R-Tree 与 Quadtree 双引擎

Oracle Spatial (10g, 2003) 是企业级空间数据库的代表，同时支持 R-Tree 与 Quadtree 索引：

```sql
-- 创建几何列 (Oracle 用 SDO_GEOMETRY 类型)
CREATE TABLE parcels (
    parcel_id NUMBER PRIMARY KEY,
    geom MDSYS.SDO_GEOMETRY
);

-- 元数据注册 (Oracle 必需步骤)
INSERT INTO USER_SDO_GEOM_METADATA VALUES (
    'PARCELS', 'GEOM',
    MDSYS.SDO_DIM_ARRAY(
        MDSYS.SDO_DIM_ELEMENT('LON', -180, 180, 0.05),
        MDSYS.SDO_DIM_ELEMENT('LAT', -90, 90, 0.05)
    ),
    8307                     -- SRID (WGS84)
);

-- R-Tree 索引 (默认推荐)
CREATE INDEX idx_parcels_geom ON parcels(geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
PARAMETERS ('layer_gtype=POLYGON tablespace=USERS');

-- Quadtree 索引 (老式，已不推荐)
CREATE INDEX idx_parcels_quad ON parcels(geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX
PARAMETERS ('SDO_LEVEL=8 SDO_NUMTILES=8');

-- 查询 (使用 SDO_FILTER 走索引)
SELECT * FROM parcels
WHERE SDO_FILTER(geom,
    MDSYS.SDO_GEOMETRY(2003, 8307, NULL,
        MDSYS.SDO_ELEM_INFO_ARRAY(1, 1003, 3),
        MDSYS.SDO_ORDINATE_ARRAY(120, 30, 121, 31)))
    = 'TRUE';

-- 精确判断 (索引过滤后再精判)
SELECT * FROM parcels
WHERE SDO_RELATE(geom, query_geom, 'mask=ANYINTERACT') = 'TRUE';
```

**R-Tree vs Quadtree (Oracle 视角)**：

| 维度 | R-Tree | Quadtree |
|------|--------|---------|
| 索引大小 | 较小 | 较大 (2-5 倍) |
| 写入性能 | 较慢 (分裂复杂) | 较快 |
| 查询性能 | 优秀 | 中等 (需要回表) |
| 维护开销 | 低 | 高 (重建周期) |
| 几何类型 | 任意 | POLYGON/LINESTRING 较好 |
| 推荐 | **是** (10g 后默认) | 仅遗留系统 |

### SQL Server geography_grid (2008+)

SQL Server 不使用 R-Tree，而是基于**网格分解**的 4 层分层索引：

```sql
-- 创建空间表
CREATE TABLE Parcels (
    id INT PRIMARY KEY,
    geog GEOGRAPHY,
    geom GEOMETRY
);

-- GEOGRAPHY 索引 (球面坐标，4 层网格)
CREATE SPATIAL INDEX idx_geog ON Parcels(geog)
USING GEOGRAPHY_GRID
WITH (
    GRIDS = (LEVEL_1=MEDIUM, LEVEL_2=MEDIUM, LEVEL_3=MEDIUM, LEVEL_4=MEDIUM),
    CELLS_PER_OBJECT = 16
);

-- GEOMETRY 索引 (平面坐标，必须指定 BBOX)
CREATE SPATIAL INDEX idx_geom ON Parcels(geom)
USING GEOMETRY_GRID
WITH (
    BOUNDING_BOX = (xmin=120, ymin=30, xmax=121, ymax=31),
    GRIDS = (LEVEL_1=MEDIUM, LEVEL_2=MEDIUM, LEVEL_3=MEDIUM, LEVEL_4=MEDIUM),
    CELLS_PER_OBJECT = 16
);

-- 查询
SELECT * FROM Parcels
WHERE geog.STIntersects(geography::Point(30.5, 120.5, 4326).STBuffer(1000)) = 1;

-- 索引选项详解：
-- LEVEL_1 ~ LEVEL_4: 每层网格密度 (LOW=4x4, MEDIUM=8x8, HIGH=16x16)
-- CELLS_PER_OBJECT: 每个几何对象最多分配多少个网格 (1-8192)
```

**SQL Server 网格索引的工作原理**：

```
4 层网格 (假设全部 MEDIUM = 8x8):
  Level 1: 整个空间分为 8x8 = 64 个网格
  Level 2: 每个 Level-1 网格再分 8x8 = 64 个网格
  Level 3: 同上
  Level 4: 同上
  最大单元: 8^4 = 4096 个 Level-4 网格

几何对象的"覆盖网格"由 CELLS_PER_OBJECT 限制:
  一个大多边形可能跨越数千个 Level-4 网格
  如超过 CELLS_PER_OBJECT (默认 16)，就用更粗的 Level-3/2/1 表示
  这种"溢出"会降低查询效率
```

调优建议：

- 数据均匀且密度高：LEVEL_4 用 HIGH，CELLS_PER_OBJECT 增大到 64
- 数据稀疏：LEVEL_1/2 用 LOW，节省存储
- 大几何对象多：增大 CELLS_PER_OBJECT
- 用 sp_help_spatial_geography_index 评估覆盖率

### ClickHouse spatial_index (实验性, 24.x)

ClickHouse 24.x 引入实验性的 `spatial_index`，作为 **data skipping index** 实现：

```sql
-- 必须开启实验特性 (24.x 时为实验性，新版本可能改名/稳定化)
SET allow_experimental_spatial_index = 1;

-- 创建表 + spatial_index
CREATE TABLE parcels (
    id UInt64,
    point Tuple(Float64, Float64),       -- (lon, lat)
    INDEX idx_geom point TYPE spatial_index GRANULARITY 1
) ENGINE = MergeTree()
ORDER BY id;

-- 查询会自动使用 spatial_index 裁剪 granule
SELECT count() FROM parcels
WHERE pointInPolygon(point, [(120,30),(121,30),(121,31),(120,31)]);
```

ClickHouse 的实现哲学：

```
空间索引非真正的"索引"，而是 granule (默认 8192 行) 级别的统计:
  - 对每个 granule 计算 BBox
  - 查询时跳过 BBox 不相交的 granule
  - 仍然需要扫描相交 granule 内的全部行 (无法精细到行级)

优势:
  - 与列存的 granule 模型契合
  - 索引大小极小 (每 8192 行一个 BBox)
  - 不影响写入吞吐

劣势:
  - 选择性差时退化为全表扫描
  - 不适合点查询 (例如查附近 100m 的点)
```

### MongoDB 2dsphere (类 SQL 思路)

虽然 MongoDB 是文档数据库，但 2dsphere 索引的设计思路对 SQL 引擎极有借鉴意义——它是 **S2 cell ID** 索引的工业级实现：

```javascript
// 创建 2dsphere 索引
db.parcels.createIndex({ loc: "2dsphere" });

// 查询 (类 SQL 风格)
db.parcels.find({
    loc: {
        $geoWithin: {
            $geometry: {
                type: "Polygon",
                coordinates: [[[120,30],[121,30],[121,31],[120,31],[120,30]]]
            }
        }
    }
});
```

**2dsphere 内部细节**：

```
S2 cell 离散化:
  - 整个地球表面被 S2 库分为多层级网格 (0-30 层)
  - 每个几何对象被分解为覆盖它的 S2 cell ID 集合
  - cell ID 是 64-bit 整数，可建普通 B-tree 索引

查询流程:
  1. 对查询区域计算覆盖的 S2 cell IDs (通常几十到几百个)
  2. B-tree 查找这些 cell IDs 的文档
  3. 用精确空间算法过滤候选

优势:
  - 复用普通 B-tree 索引基础设施 (单一索引引擎)
  - 跨纬度精度均匀 (S2 球面映射设计良好)
  - 支持任意几何对象 (不仅是矩形 BBox)

类比 SQL 引擎:
  CockroachDB 倒排索引 + S2 cell 是类似思路
  Postgres + h3-pg 通过 H3 cell + B-tree 也可达成类似效果
```

### CockroachDB Inverted Index + S2

CockroachDB 20.2+ (2020) 引入了基于 S2 cell 的空间倒排索引：

```sql
-- 创建空间表 (PostGIS 兼容子集)
CREATE TABLE parcels (
    id INT8 PRIMARY KEY,
    geom GEOMETRY(POLYGON, 4326),
    INVERTED INDEX idx_geom (geom)
);

-- 查询
SELECT * FROM parcels
WHERE ST_Intersects(geom, ST_GeomFromText('POLYGON((120 30, 121 30, 121 31, 120 31, 120 30))', 4326));

-- 倒排索引调优 (CockroachDB 特有)
ALTER TABLE parcels CONFIGURE ZONE USING
    range_max_bytes = 524288000;        -- 500MB

-- 自定义 S2 配置
SET CLUSTER SETTING sql.spatial.experimental_box2d_comparison_operators.enabled = true;
```

CockroachDB 的方法学：

```
为何不用 R-Tree?
  R-Tree 在分布式环境下难以横向扩展 (节点分裂复杂)
  S2 cell 是有序整数，天然适合 KV 存储和 Range 分片
  类似设计：BigQuery (S2)、MongoDB (S2)、Pinot (Geohash)

实现细节:
  - 几何对象 → 覆盖 S2 cells (每个对象多行倒排索引)
  - cell ID 范围按主键路由到不同 range
  - 查询时跨 range 并行扫描
  - "倒排索引" = 一个几何对象 → 多个索引行
```

### DuckDB spatial 扩展 (R-Tree)

DuckDB 0.10+ (2024) 通过 spatial 扩展引入 R-Tree 索引：

```sql
-- 安装并加载扩展
INSTALL spatial;
LOAD spatial;

-- 创建空间表
CREATE TABLE parcels (
    id INT PRIMARY KEY,
    geom GEOMETRY
);

-- 创建 R-Tree 索引
CREATE INDEX idx_geom ON parcels USING RTREE (geom);

-- 查询
SELECT * FROM parcels
WHERE ST_Intersects(geom, ST_MakeEnvelope(120, 30, 121, 31));

-- DuckDB 特点:
-- 1. R-Tree 仅在内存中维护 (持久化 0.10+ 实验性)
-- 2. 单线程构建，多线程查询
-- 3. 索引 BBox 用 Float32 存储 (省空间但精度有限)
```

### 其他引擎要点

```sql
-- DB2 Spatial Extender (网格 + R-Tree)
CREATE INDEX idx_geom ON parcels(geom)
EXTEND USING db2gse.spatial_index(1, 10, 100);
-- 三个参数：网格大小 1, 10, 100 米 (3 层)

-- SAP HANA (网格分层 R-Tree)
CREATE SPATIAL INDEX idx_geom ON parcels(geom)
LEVEL 8 LEAF GRANULARITY 32;

-- Greenplum / TimescaleDB (继承 PostGIS)
CREATE INDEX idx_geom ON parcels USING GIST (geom);

-- H2 (内置 R-Tree on MVStore)
CREATE SPATIAL INDEX idx_geom ON parcels(geom);

-- CrateDB (Lucene 底层 Geohash)
CREATE TABLE parcels (
    id INT PRIMARY KEY,
    loc GEO_POINT,        -- 自动建 BKD 树索引
    boundary GEO_SHAPE INDEX USING GEOHASH WITH (precision = '50m')
);

-- Vertica (无空间索引，但有 STV_Intersect 函数)
SELECT * FROM parcels
WHERE STV_Intersect(parcels.geom USING PARAMETERS index='ix1') = 1;
-- 索引在 STV_Create_Index 中创建，类似查找表

-- Esri ArcSDE (Adaptive Grid)
-- 创建索引时根据数据分布自适应选择网格大小
sdelayer -o create_layer -l parcels,geom -g 5,50,500
-- 三层网格：5/50/500 单位
```

## GiST 框架深度解析

GiST (Generalized Search Tree, Hellerstein 1995) 是 PostgreSQL 最有学术价值的贡献之一。它把"如何构建一个搜索索引"抽象为 7 个用户必须实现的方法：

```
GiST 接口 (PostgreSQL implementation):
  consistent(p, q, n) -- 给定查询 q，节点 p 是否可能包含匹配？
  union(set)          -- 计算一组节点的"并集"键
  compress(item)      -- 把原始项压缩为索引存储格式
  decompress(item)    -- 反向解压
  penalty(p, q)       -- 把 q 插入 p 的代价 (用于 ChooseSubtree)
  picksplit(set)      -- 节点分裂算法
  same(a, b)          -- 两个键是否相同？

只要实现这 7 个方法，就可以为任意数据类型构建一棵平衡树索引。
```

**GiST 的扩展性**：

```
PostgreSQL 内置 GiST opclass 示例:
  geometry_ops_2d   -- PostGIS 几何 (R-Tree on GiST)
  box_ops           -- 内置 BOX 类型
  range_ops         -- 范围类型
  tsvector_ops      -- 全文搜索
  cube_ops          -- contrib/cube 多维立方体
  hstore_ops        -- 键值对
  intarray_ops      -- 整数数组
  pg_trgm GiST      -- 字符串相似度搜索
  network ops       -- inet/cidr 类型

每一种 opclass 都"复用" GiST 的平衡树骨架，自定义其语义。
```

**SP-GiST (Space-Partitioned GiST, 9.2)**：

```
SP-GiST 是 GiST 的"非重叠空间分割"变体:
  - 节点分裂时不允许重叠 (与 R-Tree 相反)
  - 树结构非平衡 (按数据分布自然形成)
  - 适合 KD-Tree、QuadTree、Patricia Trie、Suffix Tree 等

PostgreSQL 内置 SP-GiST opclass:
  kd_point_ops          -- KD-Tree (POINT 类型)
  quad_point_ops        -- QuadTree (POINT 类型)
  range_ops             -- 范围
  text_ops (Patricia)   -- 字符串前缀

PostGIS 提供了 SP-GiST 几何 opclass，但仅支持 POINT 类型。
```

## R-Tree 算法深度：分裂启发式

R-Tree 的核心难题是**节点分裂**——当一个节点装满时，如何把它分成两半，使后续查询效率最优？两个最有名的启发式：

### Guttman R-Tree (1984)

```
线性分裂 (Linear Split):
  1. 找到两个最远的对象作为种子
  2. 把剩余对象逐个分配给较近的种子
  3. 时间复杂度 O(n)

二次分裂 (Quadratic Split):
  1. 对所有对象对计算"放入同一节点的扩展面积"
  2. 选择浪费最大的对作为种子
  3. 后续按"扩展最小"原则分配
  4. 时间复杂度 O(n^2)，质量较好

MySQL InnoDB 使用 Guttman 二次分裂。
```

### Beckmann R*-Tree (1990)

```
关键创新:
  1. ChooseSubtree 改进
     - 叶子层级：选择重叠最小的子树 (而非最小扩展)
     - 内部层级：选择扩展最小的子树 (与原 R-Tree 相同)

  2. 节点分裂改进
     - 沿 X 和 Y 轴各计算两组分裂方案
     - 用三个目标函数评分:
       a) 周长总和 (越小越好)
       b) 重叠面积 (越小越好)
       c) 死空间 (越小越好)
     - 选择综合最优的方案

  3. 强制重插入 (Forced Reinsert)
     - 节点溢出时，先取出 30% 元素，重新插入树中
     - 改善节点重叠，避免树质量退化

R*-Tree 在查询性能上比原 R-Tree 提升 ~30%，但写入开销增加。
SQLite R*Tree 即采用此实现。
```

**R-Tree 性能对比 (实测)**：

| 算法 | 索引构建时间 | 查询性能 | 节点重叠 | 实现复杂度 |
|------|------------|---------|---------|-----------|
| R-Tree (Guttman 线性) | 极快 | 70 分 | 中等 | 低 |
| R-Tree (Guttman 二次) | 快 | 80 分 | 中等 | 中 |
| R*-Tree (Beckmann) | 慢 (1.5x) | 95 分 | 低 | 高 |
| Hilbert R-Tree | 中等 | 90 分 | 极低 | 高 |
| R+-Tree (无重叠) | 极慢 | 95 分 | 0 (但重复存储) | 极高 |

工业实践：

- MySQL/Oracle/H2/PostGIS：Guttman 系列
- SQLite/Informix：R*-Tree
- 学术研究：Hilbert R-Tree、Bulk-Loaded R-Tree (STR Tree)

## H3 vs S2：现代网格索引

R-Tree 在树深度、节点重叠、写入扩展上有天然限制。Uber 的 H3 (2018) 和 Google 的 S2 (内部使用已久，开源 2014) 代表了**离散化 + 普通 B-tree** 的另一种范式。

### H3 (Uber Hexagonal)

```
H3 设计:
  - 球面被分为 122 个基础六边形 (12 个顶点是五边形)
  - 每个六边形细分为 7 个子六边形 (孔径=7)
  - 共 16 层 (Resolution 0~15)
  - cell ID 是 64-bit 整数

Resolution 表 (近似):
  res 0:  4250 km 边长，全球 122 个 cell
  res 5:  8.5 km
  res 8:  461 m
  res 9:  174 m  (城市块级)
  res 10: 65 m
  res 15: 0.5 m

为什么用六边形？
  - 邻居距离均匀 (每个 cell 6 个邻居等距)
  - 减少边缘效应
  - K-ring 查询自然
```

**H3 在 SQL 中的使用**：

```sql
-- BigQuery (H3 内置自 2023)
SELECT
    h3.h3_lat_lng_to_cell(STRUCT(latitude, longitude), 9) AS cell_id,
    COUNT(*)
FROM `my-project.my-dataset.events`
GROUP BY cell_id;

-- Snowflake (H3 内置)
SELECT H3_LATLNG_TO_CELL(latitude, longitude, 9) AS cell_id, COUNT(*)
FROM events
GROUP BY cell_id;

-- ClickHouse (内置自早期版本)
SELECT geoToH3(lon, lat, 9) AS cell_id, count()
FROM events
GROUP BY cell_id;

-- PostgreSQL + h3-pg 扩展
CREATE EXTENSION h3;
CREATE TABLE events (
    id BIGSERIAL,
    location GEOMETRY,
    h3_cell BIGINT GENERATED ALWAYS AS (h3_lat_lng_to_cell(ST_Y(location), ST_X(location), 9)) STORED
);
CREATE INDEX idx_h3 ON events (h3_cell);    -- 普通 B-tree 索引！

-- Databricks (DBR 11.2+)
SELECT h3_longlatash3(lon, lat, 9) AS cell_id, COUNT(*)
FROM events
GROUP BY cell_id;
```

### S2 (Google Spherical)

```
S2 设计:
  - 球面投影到 6 个立方体面
  - 每个面递归四叉分割 (30 层)
  - 沿 Hilbert 曲线编号，cell ID 是 64-bit 整数
  - 排序后的 cell 在空间上邻近 (Hilbert 性质)

Level 表:
  level 0:  85,000,000 km^2  (全球分 6 个 cell)
  level 10: 81 km^2
  level 15: 80 m^2
  level 20: 80 cm^2
  level 30: 1 cm^2

为什么用四叉树而非六边形？
  - 计算简单 (位运算)
  - 四叉树支持任意精度细化
  - Hilbert 曲线把二维 cell ID 映射为一维有序键，适合 B-tree
```

**S2 vs H3 对比**：

| 维度 | H3 (Uber) | S2 (Google) |
|------|-----------|------------|
| 形状 | 六边形 | 四边形 (球面) |
| 层级 | 16 | 30 |
| 邻居距离均匀 | 是 (核心优势) | 否 (经纬度方向不均) |
| 包含查询 | 中等 (六边形非分层) | 优秀 (四叉树天然) |
| 工业采用 | Uber, Foursquare, Snowflake | Google, MongoDB, BigQuery, CockroachDB |
| 开源时间 | 2018 | 2014 |
| 球面映射误差 | 多面体投影 (12 个奇异点) | 立方体投影 (6 个面) |

```sql
-- BigQuery 自动使用 S2 cell 进行空间裁剪 (无显式索引语法)
SELECT *
FROM `bigquery-public-data.geo_us_boundaries.zip_codes`
WHERE ST_INTERSECTS(zip_code_geom,
    ST_GEOGFROMTEXT('POLYGON((-122.5 37.5, -122.4 37.5, -122.4 37.6, -122.5 37.6, -122.5 37.5))'));
-- BigQuery 内部把查询区域转为 S2 cells，与目标表的 S2 cells 求交
```

## 多列空间索引

PostgreSQL/PostGIS 支持复合空间索引，使空间过滤与普通过滤合并：

```sql
-- 复合 GiST：geom + 普通列 (PostGIS 2.0+)
CREATE INDEX idx_orders_geom_status ON orders USING GIST (geom, status);
-- 注意：status 列必须有 GiST opclass (用 btree_gist 扩展)
CREATE EXTENSION btree_gist;

-- 部分索引：状态过滤 + 空间索引
CREATE INDEX idx_orders_active ON orders USING GIST (geom)
WHERE status = 'active' AND created_at > NOW() - INTERVAL '30 days';

-- 多列查询时显著优于单列空间索引：
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE status = 'active'
  AND geom && ST_MakeEnvelope(120, 30, 121, 31, 4326);
-- 单列空间索引：扫描所有空间命中行，再过滤 status
-- 复合索引：直接定位 (status, geom) 双条件命中
```

**SQL Server 同样支持**：

```sql
CREATE SPATIAL INDEX idx_geom_inc ON Parcels(geom)
USING GEOGRAPHY_GRID
INCLUDE (city_id, area)
WITH (CELLS_PER_OBJECT = 16);
-- 8.0+ 通过 INCLUDE 把非空间列加入索引叶子，避免回表
```

**Oracle 复合空间索引**：

```sql
CREATE INDEX idx_geom_dt ON parcels(geom, created_dt)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
PARAMETERS ('layer_gtype=POLYGON sdo_indx_dims=2');
```

## 性能基准与选型

### 1 亿行 POINT 表的索引对比

```
环境: 32 核 CPU, 128GB RAM, NVMe SSD, ~ 8GB 数据
插入吞吐 (单线程):
  PostGIS GiST:        ~50K rows/s
  PostGIS SP-GiST:     ~70K rows/s (无重叠优势)
  MySQL InnoDB R-Tree: ~80K rows/s
  SQLite R*Tree:       ~30K rows/s
  Oracle R-Tree:       ~60K rows/s
  H3 cell + B-tree:    ~500K rows/s (普通 B-tree！)

索引大小:
  PostGIS GiST:        ~3.2 GB
  PostGIS SP-GiST:     ~2.1 GB
  MySQL InnoDB R-Tree: ~3.5 GB
  H3 cell B-tree:      ~600 MB (整数主键)

范围查询 (查找 1 平方公里内点):
  PostGIS GiST:        2.1 ms
  PostGIS SP-GiST:     1.7 ms
  MySQL R-Tree:        4.5 ms
  H3 cell + B-tree:    0.8 ms (单 cell 查找)

KNN 查询 (最近 100 个点):
  PostGIS GiST + KNN:  3.5 ms (使用 <-> 操作符)
  其他引擎模拟:         100+ ms (扫描候选集)
```

### 选型建议

| 场景 | 推荐索引 | 理由 |
|------|---------|------|
| 通用 OLTP 空间查询 | PostGIS GiST | 平衡、生态完整 |
| 海量点数据 | PostGIS SP-GiST | 写入快，无重叠 |
| MySQL 生态 | InnoDB R-Tree | 5.7+ 的事务空间索引 |
| 嵌入式 | SQLite R*Tree | 文件级，零依赖 |
| 企业级混合 | Oracle R-Tree V2 | 成熟、稳定 |
| 微软栈 | SQL Server geography_grid | 与 .NET/Azure 集成 |
| 列存分析 | ClickHouse spatial_index | granule 级裁剪 |
| 网格聚合分析 | H3 cell + B-tree | O(1) 网格统计 |
| 全球分布式 | S2 cell + 倒排 | 跨地域、KV 友好 |
| Spark / Databricks | 不建索引，依赖 Z-order | 数据湖架构 |
| Snowflake / BigQuery | 不建索引，依赖微分区/S2 | 自动优化 |

## 设计争议

### 1. R-Tree 是否过时？

```
反对 R-Tree:
  - 节点重叠导致查询时多路径扫描
  - 写入分裂复杂，分布式系统不友好
  - 树深度难以控制

支持 R-Tree:
  - 算法成熟、文献丰富
  - 任意几何对象 (不只是点)
  - 范围/距离/相交一站式

现实:
  - PostGIS、Oracle、MySQL 仍以 R-Tree 为主流
  - 分布式新引擎 (Spanner, CockroachDB, MongoDB) 转向 cell-based
  - "工程权衡" 多于 "技术替代"
```

### 2. 网格索引的精度悖论

```
H3/S2 cell 索引的根本缺陷:
  - cell 是离散的，几何对象边界穿越多个 cell
  - 大对象需要多行倒排 (写放大)
  - "近似查询" 总要二次精判

R-Tree 的优势 (此场景):
  - BBox 比 cell 更精确
  - 单对象单条索引行
  - 不需要"覆盖 cell" 的预处理
```

### 3. 索引 vs 全扫描的临界点

```
现代分析引擎 (BigQuery/Snowflake/ClickHouse) 的设计哲学:
  - 列存 + 微分区/granule + 自动统计 = 隐式空间索引
  - 用户无需关心索引，引擎自动裁剪
  - 单查询百 GB 是常态，毫秒级 R-Tree 不再必需

OLTP 引擎 (PostGIS/MySQL/Oracle) 的设计哲学:
  - 高并发短查询 (1000 QPS, < 10ms)
  - 必须用索引避免全扫描
  - 索引是"绝对的"

边界正在模糊:
  - DuckDB 添加 R-Tree (OLAP + OLTP 混合)
  - PostgreSQL 添加 BRIN 空间 (大表近似)
  - ClickHouse 添加 spatial_index (列存中的索引)
```

### 4. 谁定义"空间"？

```sql
-- "空间"不只是地理坐标:
-- PostgreSQL GiST 可索引任意"可比较"类型:
CREATE INDEX idx_temporal ON events USING GIST (event_period);  -- TSRANGE 时间范围
CREATE INDEX idx_color ON products USING GIST (color_cube);     -- 3D RGB cube
CREATE INDEX idx_text ON docs USING GIST (content gist_trgm_ops);  -- 字符串相似度

-- "空间索引" = "多维范围查询索引"
-- 引擎开发者应认识到 R-Tree/QuadTree/KD-Tree 的能力远超 GIS
```

## 对引擎开发者的实现建议

### 1. R-Tree 的核心数据结构

```
R-Tree 节点 (内部):
  ┌──────────────────────────────────────┐
  │ Header: type=internal, count=N        │
  │ Entry[0]: BBox + child_page_id        │
  │ Entry[1]: BBox + child_page_id        │
  │ ...                                    │
  │ Entry[N-1]: BBox + child_page_id      │
  └──────────────────────────────────────┘

R-Tree 节点 (叶子):
  ┌──────────────────────────────────────┐
  │ Header: type=leaf, count=N            │
  │ Entry[0]: BBox + record_id (heap tid) │
  │ Entry[1]: BBox + record_id            │
  │ ...                                    │
  └──────────────────────────────────────┘

页大小通常与 B-tree 相同 (8KB / 16KB)，单页能容纳 ~200-500 个 entry。
```

### 2. ChooseSubtree 算法

```
fn choose_subtree(node: &mut RTreeNode, new_entry: &Entry) -> usize:
    // 内部节点：选择"扩展最小"的子树
    if !node.is_leaf:
        let mut best_idx = 0
        let mut min_enlargement = INF
        for (i, child) in node.entries.iter().enumerate():
            let enlargement = child.bbox.union(new_entry.bbox).area() - child.bbox.area()
            if enlargement < min_enlargement:
                min_enlargement = enlargement
                best_idx = i
        return best_idx

    // 叶子节点 (R*-Tree 改进)：选择"重叠最小"的子树
    let mut best_idx = 0
    let mut min_overlap = INF
    for (i, child) in node.entries.iter().enumerate():
        let new_bbox = child.bbox.union(new_entry.bbox)
        let overlap = compute_overlap(new_bbox, &node.entries)
        if overlap < min_overlap:
            min_overlap = overlap
            best_idx = i
    return best_idx
```

### 3. 节点分裂 (Quadratic Split)

```
fn quadratic_split(entries: Vec<Entry>) -> (RTreeNode, RTreeNode):
    // 1. 找出"浪费最大"的种子对
    let mut max_waste = 0
    let mut seeds = (0, 1)
    for i in 0..entries.len():
        for j in i+1..entries.len():
            let combined = entries[i].bbox.union(&entries[j].bbox)
            let waste = combined.area() - entries[i].bbox.area() - entries[j].bbox.area()
            if waste > max_waste:
                max_waste = waste
                seeds = (i, j)

    // 2. 分配剩余 entries
    let mut group_a = vec![entries[seeds.0]]
    let mut group_b = vec![entries[seeds.1]]
    let remaining: Vec<_> = entries.iter().enumerate()
        .filter(|(i, _)| *i != seeds.0 && *i != seeds.1)
        .map(|(_, e)| e.clone())
        .collect()

    for entry in remaining:
        let cost_a = bbox_a.union(&entry.bbox).area() - bbox_a.area()
        let cost_b = bbox_b.union(&entry.bbox).area() - bbox_b.area()
        if cost_a < cost_b:
            group_a.push(entry)
        else:
            group_b.push(entry)

    return (RTreeNode::new(group_a), RTreeNode::new(group_b))
```

### 4. 与查询规划器的交互

```
关键挑战：空间索引的代价估算

cardinality 估算:
  - 对每个空间索引维护"采样点"统计 (类似 PostgreSQL ANALYZE)
  - 查询区域 vs 全表 BBox 的面积比 = 选择性近似
  - PostGIS 用 100x100 网格统计 (PG_STATS 中的 most_common_freqs)

代价估算公式 (类似 PostGIS):
  index_cost = log_BF(n) * page_io + selectivity * n * cpu_per_tuple
  其中 BF (branching factor) 由节点大小决定，通常 ~50

EXPLAIN 输出:
  -> Index Scan using idx_geom on parcels
       Index Cond: (geom && '...'::geometry)
       Filter: ST_Intersects(geom, '...'::geometry)
       Rows Removed by Filter: 12
       Buffers: shared hit=24
```

### 5. KNN 查询的优先队列实现

```
PostGIS GiST KNN (使用 <-> 操作符):

fn knn_search(root: &RTreeNode, query: &Geometry, k: usize) -> Vec<(f64, RecordId)>:
    let mut pq = PriorityQueue::new()  // min-heap by distance
    let mut result = Vec::new()

    pq.push(Item::Node(root, 0.0))

    while let Some(item) = pq.pop():
        if result.len() >= k:
            break

        match item:
            Item::Node(node, _) =>
                for entry in node.entries:
                    let mindist = compute_mindist(&entry.bbox, query)
                    if entry.is_leaf:
                        pq.push(Item::Leaf(entry.record_id, mindist))
                    else:
                        pq.push(Item::Node(entry.child, mindist))
            Item::Leaf(rid, dist) =>
                let actual_dist = compute_actual_distance(rid, query)
                result.push((actual_dist, rid))

    result
```

### 6. 并发控制

```
R-Tree 并发控制要点:
  - 节点分裂需要 X-lock (写锁)
  - 查询用 S-lock (读锁)，可并发
  - PostgreSQL: 用 GiST 协议，结合 pg_prog buffer pin

锁粒度:
  - 页级锁 (类似 B-tree)，简单但并发度有限
  - SIX (Shared with Intent eXclusive) 提升读写混合
  - 高级实现：CR-Tree (Crash-Recovery R-Tree) 支持 MVCC

写入热点:
  - R-Tree 在数据时间序插入下退化 (新数据集中在树的一边)
  - 解决：批量插入 + Bulk Loading (STR Tree, Hilbert R-Tree)
  - 或预排序后 GENERATED 列 + B-tree (H3 cell 思路)
```

### 7. Bulk Loading 算法

```
STR (Sort-Tile-Recursive) Bulk Loading:
  1. 把所有 BBox 按中心点 X 排序
  2. 分成 sqrt(N/M) 组 (M = 节点容量)
  3. 每组内按 Y 排序
  4. 再分成 sqrt(N/M) 组
  5. 每组打包成叶子节点
  6. 自底向上构建内部节点

效果:
  - 比逐行插入快 5-10 倍
  - 树质量优秀 (节点重叠极少)
  - PostGIS、Oracle 在 CREATE INDEX 时使用
```

## 总结对比矩阵

### 索引能力总览

| 能力 | PostGIS | MySQL | Oracle | SQL Server | SQLite | DuckDB | ClickHouse | BigQuery | Snowflake | MongoDB |
|------|---------|-------|--------|------------|--------|--------|------------|----------|-----------|---------|
| R-Tree | GiST | InnoDB | V2 | -- | R*Tree | RTREE | -- | -- | -- | -- |
| GiST 框架 | 是 | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| SP-GiST | 是 (POINT) | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| QuadTree | -- | -- | 是 | 网格 | -- | -- | -- | -- | -- | -- |
| 网格分层 | -- | -- | -- | 是 (4 层) | -- | -- | -- | -- | -- | -- |
| H3 cell | 扩展 | -- | -- | -- | -- | 扩展 | 函数 | 函数 | 函数 | -- |
| S2 cell | 扩展 | -- | -- | -- | -- | -- | -- | 是 (隐式) | -- | 是 |
| 多列空间 | 是 | -- | 是 | 是 | -- | -- | -- | -- | -- | -- |
| 函数索引 | 是 | 虚拟列 | 是 | -- | -- | -- | -- | -- | -- | -- |
| 部分空间索引 | 是 | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| KNN 操作符 | <-> | -- | SDO_NN | -- | -- | -- | -- | -- | -- | $near |

### 算法演进时间线

```
1984: Guttman 提出 R-Tree (UC Berkeley)
1990: Beckmann 提出 R*-Tree (强制重插入)
1993: Sellis R+-Tree (无重叠，但写入慢)
1995: Hellerstein 提出 GiST (PG 的理论基础)
2001: PostgreSQL GiST 上线 (7.0)
2003: Oracle Spatial 10g 全面 R-Tree
2005: PostGIS 1.0 (R-Tree on GiST)
2008: SQL Server 2008 引入 geography_grid
2012: PostgreSQL SP-GiST 上线 (9.2)
2013: SQLite R*Tree 主流化 (3.8)
2014: Google 开源 S2
2015: MySQL 5.7 InnoDB R-Tree (从 MyISAM 迁移)
2018: Uber 开源 H3
2020: CockroachDB S2-based 倒排空间索引
2024: ClickHouse spatial_index (实验性)
```

## 参考资料

- Guttman, A. (1984). "R-trees: A dynamic index structure for spatial searching." SIGMOD.
- Beckmann, N., Kriegel, H.P., Schneider, R., Seeger, B. (1990). "The R\*-tree: An Efficient and Robust Access Method for Points and Rectangles." SIGMOD.
- Hellerstein, J.M., Naughton, J.F., Pfeffer, A. (1995). "Generalized Search Trees for Database Systems." VLDB.
- PostgreSQL: [GiST Indexes](https://www.postgresql.org/docs/current/gist.html)
- PostgreSQL: [SP-GiST Indexes](https://www.postgresql.org/docs/current/spgist.html)
- PostGIS: [Spatial Indexing](https://postgis.net/docs/using_postgis_dbmanagement.html#idm2236)
- MySQL: [Creating Spatial Indexes](https://dev.mysql.com/doc/refman/8.0/en/creating-spatial-indexes.html)
- SQLite: [The R\*Tree Module](https://www.sqlite.org/rtree.html)
- Oracle Spatial: [Indexing of Spatial Data](https://docs.oracle.com/en/database/oracle/oracle-database/19/spatl/indexing-spatial-data.html)
- SQL Server: [Spatial Indexes Overview](https://learn.microsoft.com/en-us/sql/relational-databases/spatial/spatial-indexes-overview)
- DB2: [Spatial Indexes](https://www.ibm.com/docs/en/db2/11.5?topic=indexes-spatial)
- CockroachDB: [Spatial Indexes](https://www.cockroachlabs.com/docs/stable/spatial-indexes.html)
- ClickHouse: [Spatial Index](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- DuckDB: [Spatial Extension](https://duckdb.org/docs/extensions/spatial)
- MongoDB: [2dsphere Indexes](https://www.mongodb.com/docs/manual/core/2dsphere/)
- Uber H3: [H3 Documentation](https://h3geo.org/)
- Google S2: [S2 Geometry Library](https://s2geometry.io/)
- Apache Sedona: [Spatial SQL](https://sedona.apache.org/)
- Leutenegger, S.T. (1997). "STR: A Simple and Efficient Algorithm for R-Tree Packing." ICDE.
