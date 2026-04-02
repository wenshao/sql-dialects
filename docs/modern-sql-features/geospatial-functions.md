# 地理空间函数 (Geospatial Functions)

地理空间查询是现代 SQL 引擎中增长最快的能力之一。从外卖配送范围计算、车辆轨迹分析，到气候网格数据聚合、地块权属判定——空间 SQL 已从传统 GIS 专业工具进入主流数据平台。OGC Simple Features 标准和 SQL/MM Part 3 为空间 SQL 奠定了基础，但各引擎在实现深度上差异巨大：有的提供数百个空间函数（PostGIS），有的仅支持基本的距离计算，有的完全不支持。本文系统梳理 45+ SQL 方言的地理空间能力。

## 标准与规范

地理空间 SQL 涉及三个核心标准体系：

```
OGC Simple Features (SFA):
  Open Geospatial Consortium 定义的几何模型标准
  ISO 19125-1 (架构) + ISO 19125-2 (SQL 选项)
  定义了 GEOMETRY, POINT, LINESTRING, POLYGON 等类型层次
  定义了 ST_ 前缀的空间函数命名规范

SQL/MM Part 3 (Spatial):
  ISO/IEC 13249-3, SQL 多媒体标准的空间部分
  在 OGC SFA 基础上扩展，定义了更丰富的空间类型和函数
  是 SQL 标准的正式组成部分
  引入了 ST_Geometry 类型层次和方法式调用语法

关键几何类型层次:
  Geometry (抽象基类)
  ├── Point                    -- 点
  ├── Curve (抽象)
  │   └── LineString           -- 线串
  │       └── Line / LinearRing
  ├── Surface (抽象)
  │   └── Polygon              -- 多边形
  ├── GeometryCollection       -- 几何集合
  │   ├── MultiPoint           -- 多点
  │   ├── MultiCurve (抽象)
  │   │   └── MultiLineString  -- 多线串
  │   └── MultiSurface (抽象)
  │       └── MultiPolygon     -- 多多边形
  └── CircularString, CompoundCurve, CurvePolygon  -- SQL/MM 扩展

GEOMETRY vs GEOGRAPHY:
  GEOMETRY  -- 平面坐标系 (笛卡尔)，单位为坐标单位，计算快
  GEOGRAPHY -- 大地坐标系 (球面/椭球面)，单位为米/度，结果精确
  大多数引擎仅支持 GEOMETRY；PostGIS、SQL Server 同时支持两者；BigQuery 仅支持 GEOGRAPHY
```

## 空间能力总览

| 引擎 | 空间支持 | 实现方式 | 函数数量 | GEOGRAPHY 类型 | 空间索引 |
|------|---------|---------|---------|---------------|---------|
| PostgreSQL + PostGIS | 极强 | 扩展 (PostGIS) | 300+ | 是 | GiST, SP-GiST |
| MySQL | 中等 | 原生 (8.0+) | ~60 | 否 | R-Tree (InnoDB) |
| MariaDB | 中等 | 原生 | ~60 | 否 | R-Tree |
| SQLite + SpatiaLite | 强 | 扩展 (SpatiaLite) | 200+ | 否 | R-Tree |
| Oracle Spatial | 极强 | 原生/选件 | 200+ | 通过 SRID 区分 | R-Tree, Quadtree |
| SQL Server | 强 | 原生 | ~80 | 是 | 空间网格索引 |
| DB2 | 强 | Spatial Extender | ~70 | 是 | 网格索引 |
| Snowflake | 中等 | 原生 | ~50 | 是 | 无显式索引 |
| BigQuery | 强 | 原生 | ~50 | 是 (默认) | 自动 |
| Redshift | 弱 | 原生 (有限) | ~20 | 否 | 无 |
| DuckDB | 中等 | 扩展 (spatial) | ~50 | 否 | 无 |
| ClickHouse | 中等 | 原生 | ~30 | 否 | 无 |
| Trino | 中等 | 原生 | ~40 | 否 | 无 |
| Presto | 中等 | 原生 | ~40 | 否 | 无 |
| Spark SQL | 弱 | 有限/UDF | ~10 | 否 | 无 |
| Hive | 弱 | UDF (ESRI) | 外部 | 否 | 无 |
| Flink SQL | 弱 | 无原生 | 外部 | 否 | 无 |
| Databricks | 弱 | 内建函数 (有限) | ~15 | 否 | 无 |
| Teradata | 中等 | Geospatial 选件 | ~40 | 否 | 主索引 |
| Greenplum | 强 | PostGIS 扩展 | 300+ | 是 | GiST |
| CockroachDB | 中等 | 原生 (兼容 PostGIS 子集) | ~40 | 是 | 倒排索引 |
| TiDB | 弱 | 原生 (兼容 MySQL 子集) | ~20 | 否 | 无 |
| OceanBase | 弱 | 原生 (MySQL 模式) | ~20 | 否 | R-Tree |
| YugabyteDB | 中等 | PostGIS 扩展 | 继承 PostGIS | 是 | GiST |
| SingleStore | 中等 | 原生 | ~30 | 是 | 无显式空间索引 |
| Vertica | 中等 | 原生 (STV_) | ~30 | 否 | 无 |
| Impala | 弱 | 无原生 | 0 | 否 | 无 |
| StarRocks | 弱 | 原生 (有限) | ~15 | 否 | 无 |
| Doris | 弱 | 原生 (有限) | ~15 | 否 | 无 |
| MonetDB | 弱 | GIS 模块 | ~10 | 否 | 无 |
| CrateDB | 中等 | 原生 (GeoJSON) | ~15 | 否 | GeoHash |
| TimescaleDB | 极强 | PostGIS 扩展 | 300+ | 是 | GiST |
| QuestDB | 弱 | 原生 (有限) | ~5 | 否 | 无 |
| Exasol | 弱 | 原生 (有限) | ~15 | 否 | 无 |
| SAP HANA | 中等 | 原生 | ~50 | 是 | 无显式空间索引 |
| Informix | 中等 | Spatial DataBlade | ~40 | 否 | R-Tree |
| Firebird | 无 | 无 | 0 | 否 | 无 |
| H2 | 弱 | 原生 (有限) | ~15 | 否 | 无 |
| HSQLDB | 无 | 无 | 0 | 否 | 无 |
| Derby | 无 | 无 | 0 | 否 | 无 |
| Amazon Athena | 中等 | 继承 Trino | ~40 | 否 | 无 |
| Azure Synapse | 弱 | 原生 (有限子集) | ~15 | 有限 | 无 |
| Google Spanner | 无 | 无 | 0 | 否 | 无 |
| Materialize | 无 | 无 | 0 | 否 | 无 |
| RisingWave | 无 | 无 | 0 | 否 | 无 |
| InfluxDB | 无 | 无 | 0 | 否 | 无 |
| DatabendDB | 弱 | 原生 (有限) | ~10 | 否 | 无 |
| Yellowbrick | 弱 | 原生 (有限) | ~10 | 否 | 无 |
| Firebolt | 无 | 无 | 0 | 否 | 无 |

> 注：PostGIS 是 PostgreSQL 的扩展，不属于 PostgreSQL 核心。Greenplum、TimescaleDB、YugabyteDB 等基于 PostgreSQL 的引擎通常可安装 PostGIS 扩展获得完整空间能力。CockroachDB 原生实现了 PostGIS 兼容的空间函数子集，并非直接使用 PostGIS 扩展。

## 空间数据类型支持

| 引擎 | GEOMETRY | GEOGRAPHY | POINT | LINESTRING | POLYGON | Multi* | 存储格式 |
|------|----------|-----------|-------|------------|---------|--------|---------|
| PostgreSQL + PostGIS | 是 | 是 | 是 | 是 | 是 | 是 | WKB 内部 |
| MySQL (8.0+) | 是 | 否 | 是 | 是 | 是 | 是 | WKB 内部 |
| MariaDB | 是 | 否 | 是 | 是 | 是 | 是 | WKB 内部 |
| SQLite + SpatiaLite | 是 | 否 | 是 | 是 | 是 | 是 | WKB BLOB |
| Oracle | SDO_GEOMETRY | 通过 SRID | 是 | 是 | 是 | 是 | SDO 对象 |
| SQL Server | geometry | geography | 子类型 | 子类型 | 子类型 | 是 | CLR |
| DB2 | ST_Geometry | ST_Geometry | 是 | 是 | 是 | 是 | WKB 内部 |
| Snowflake | GEOMETRY | GEOGRAPHY | 子类型 | 子类型 | 子类型 | 是 | GeoJSON 内部 |
| BigQuery | GEOGRAPHY | 是 (默认) | 子类型 | 子类型 | 子类型 | 是 | S2 内部 |
| Redshift | GEOMETRY | 否 | 子类型 | 子类型 | 子类型 | 是 | WKB 内部 |
| DuckDB | GEOMETRY | 否 | 独立类型 | 独立类型 | 独立类型 | 是 | 内部 |
| ClickHouse | 无统一类型 | 否 | Point | LineString | Polygon | Multi* | Tuple/Array |
| Trino | 无统一类型 | 否 | 无 | 无 | 无 | 无 | varbinary(WKB) |
| Presto | 无统一类型 | 否 | 无 | 无 | 无 | 无 | varbinary(WKB) |
| Spark SQL | 无原生 | 否 | 无 | 无 | 无 | 无 | 字符串/UDF |
| Hive | 无原生 | 否 | 无 | 无 | 无 | 无 | 字符串/UDF |
| Databricks | 无原生 | 否 | 无 | 无 | 无 | 无 | 字符串/内建函数 |
| CockroachDB | GEOMETRY | GEOGRAPHY | 子类型 | 子类型 | 子类型 | 是 | WKB 内部 |
| TiDB | 无独立类型 | 否 | 无 | 无 | 无 | 无 | WKB BLOB |
| SAP HANA | ST_GEOMETRY | ST_GEOMETRY | 是 | 是 | 是 | 是 | 内部 |
| SingleStore | GEOGRAPHYPOINT, GEOGRAPHY | 是 | GEOGRAPHYPOINT | 无 | GEOGRAPHY | 无 | WKB 内部 |
| CrateDB | GEO_POINT | 否 | GEO_POINT | 无 | GEO_SHAPE | 否 | GeoJSON |
| H2 | GEOMETRY | 否 | 子类型 | 子类型 | 子类型 | 是 | WKB 内部 |

## 几何构造函数

| 函数 | PostGIS | MySQL 8.0 | SQL Server | Oracle | BigQuery | Snowflake | DuckDB | ClickHouse | Trino |
|------|---------|-----------|------------|--------|----------|-----------|--------|------------|-------|
| ST_Point(x,y) | 是 | 是 (8.0.12+) | 方法 | 否 | ST_GEOGPOINT | 是 | 是 | 否 | 否 |
| ST_MakePoint(x,y) | 是 | 否 | 否 | 否 | 否 | 是 | 否 | 否 | 否 |
| ST_GeomFromText(WKT) | 是 | 是 | 静态方法 | SDO_GEOMETRY | ST_GEOGFROMTEXT | 是 | 是 | 否 | ST_GeometryFromText |
| ST_GeomFromWKB(WKB) | 是 | 是 | 静态方法 | 否 | ST_GEOGFROMWKB | 是 | 是 | 否 | 否 |
| ST_GeomFromGeoJSON | 是 | 是 (8.0+) | 否 | 否 | ST_GEOGFROMGEOJSON | 是 | 是 | 否 | 否 |
| ST_MakeLine | 是 | 否 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| ST_MakePolygon | 是 | 否 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| ST_MakeEnvelope | 是 | 是 (Envelope) | 否 | 否 | ST_MAKELINE 等 | 否 | 否 | 否 | 否 |

补充说明：

```
Oracle:     使用 SDO_GEOMETRY 构造函数:
            SDO_GEOMETRY(2001, 4326, SDO_POINT_TYPE(lng, lat, NULL), NULL, NULL)

SQL Server: 使用类的静态方法:
            geometry::STGeomFromText('POINT(0 0)', 4326)
            geography::Point(lat, lng, 4326)

ClickHouse: 无 ST_ 构造函数，使用 Tuple 和 Array 表示:
            Point = (x, y)  -- Tuple(Float64, Float64)
            Polygon = [[(x1,y1), (x2,y2), ...]]  -- Array(Array(Tuple))

Trino:      ST_GeometryFromText('POINT (0 0)')
            ST_Point(x, y) 在较新版本中可用

BigQuery:   所有空间函数使用 GEOGRAPHY 类型，ST_GEOGPOINT(lng, lat)

Databricks: ST_Point(x, y), ST_GeomFromWKT('...') (3.4+, 内建函数)
```

## 测量函数

| 函数 | 功能 | PostGIS | MySQL 8.0 | SQL Server | Oracle | BigQuery | Snowflake | DuckDB | ClickHouse | Trino |
|------|------|---------|-----------|------------|--------|----------|-----------|--------|------------|-------|
| ST_Distance | 两几何距离 | 是 | 是 | STDistance | SDO_GEOM.SDO_DISTANCE | ST_DISTANCE | 是 | 是 | 是 | ST_Distance |
| ST_Area | 面积 | 是 | 是 | STArea | SDO_GEOM.SDO_AREA | ST_AREA | 是 | 是 | 否 | ST_Area |
| ST_Length | 线长度 | 是 | 是 | STLength | SDO_GEOM.SDO_LENGTH | ST_LENGTH | 是 | 是 | 否 | ST_Length |
| ST_Perimeter | 周长 | 是 | 否 | 否 | SDO_GEOM.SDO_LENGTH | ST_PERIMETER | 是 | 是 | 否 | 否 |
| ST_Azimuth | 方位角 | 是 | 否 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| ST_DWithin | 距离内判断 | 是 | 否 | 否 | SDO_WITHIN_DISTANCE | ST_DWITHIN | 是 | 是 | 否 | 否 |
| ST_MaxDistance | 最大距离 | 是 | 否 | 否 | 否 | ST_MAXDISTANCE | 否 | 否 | 否 | 否 |

扩展引擎支持：

| 函数 | CockroachDB | StarRocks | Doris | Exasol | SAP HANA | Redshift | Athena |
|------|-------------|-----------|-------|--------|----------|----------|--------|
| ST_Distance | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_Area | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_Length | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_Perimeter | 是 | 否 | 否 | 否 | 是 | 否 | 否 |

```
测量函数的关键差异:

1. 坐标系影响:
   GEOMETRY 类型: ST_Distance 返回坐标单位（度），无实际地理意义
   GEOGRAPHY 类型: ST_Distance 返回米，考虑地球曲率

2. PostGIS 同时提供两套:
   ST_Distance(geom, geom)      -- 平面距离
   ST_Distance(geog, geog)      -- 大地线距离 (米)
   ST_DistanceSphere(geom,geom) -- 用 GEOMETRY 但按球面计算

3. BigQuery 默认是 GEOGRAPHY:
   ST_DISTANCE(geog1, geog2)    -- 始终返回米

4. MySQL 8.0.14+ 支持 SRID 感知:
   ST_Distance(g1, g2)          -- 若 SRID=4326 返回米
```

## 空间关系测试

| 函数 | PostGIS | MySQL 8.0 | SQL Server | Oracle | BigQuery | Snowflake | DuckDB | ClickHouse | Trino |
|------|---------|-----------|------------|--------|----------|-----------|--------|------------|-------|
| ST_Contains | 是 | 是 | STContains | SDO_CONTAINS | ST_CONTAINS | 是 | 是 | 否 | ST_Contains |
| ST_Within | 是 | 是 | STWithin | SDO_INSIDE | ST_WITHIN | 是 | 是 | 是 (pointInPolygon) | ST_Within |
| ST_Intersects | 是 | 是 | STIntersects | SDO_ANYINTERACT | ST_INTERSECTS | 是 | 是 | 否 | ST_Intersects |
| ST_Overlaps | 是 | 是 | STOverlaps | SDO_OVERLAPS | 否 | 是 | 是 | 否 | ST_Overlaps |
| ST_Touches | 是 | 是 | STTouches | SDO_TOUCH | ST_TOUCHES | 是 | 是 | 否 | ST_Touches |
| ST_Crosses | 是 | 是 | STCrosses | SDO_OVERLAPBDYDISJOINT | 否 | 是 | 是 | 否 | ST_Crosses |
| ST_Disjoint | 是 | 是 | STDisjoint | SDO_DISJOINT(间接) | ST_DISJOINT | 是 | 是 | 否 | ST_Disjoint |
| ST_Equals | 是 | 是 | STEquals | SDO_EQUAL | ST_EQUALS | 是 | 是 | 是 (polygonsEquals) | ST_Equals |
| ST_Covers | 是 | 否 | 否 | SDO_COVERS(间接) | ST_COVERS | 是 | 否 | 否 | 否 |
| ST_CoveredBy | 是 | 否 | 否 | 否 | ST_COVEREDBY | 是 | 否 | 否 | 否 |
| ST_Relate (DE-9IM) | 是 | 否 | STRelate | SDO_RELATE | 否 | 否 | 否 | 否 | ST_Relate |

扩展引擎支持：

| 函数 | CockroachDB | StarRocks | Doris | SAP HANA | Redshift | Athena | H2 |
|------|-------------|-----------|-------|----------|----------|--------|----|
| ST_Contains | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_Within | 是 | 否 | 否 | 是 | 是 | 是 | 是 |
| ST_Intersects | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_Overlaps | 是 | 否 | 否 | 是 | 否 | 是 | 否 |
| ST_Touches | 是 | 否 | 否 | 是 | 否 | 是 | 否 |
| ST_Crosses | 是 | 否 | 否 | 是 | 否 | 是 | 否 |
| ST_Disjoint | 是 | 否 | 否 | 是 | 是 | 是 | 否 |

```
Oracle 特殊语法:
  Oracle 不使用 ST_ 前缀的布尔函数，而是使用 SDO_RELATE 操作符:
  SELECT * FROM table_a a, table_b b
  WHERE SDO_RELATE(a.geom, b.geom, 'mask=ANYINTERACT') = 'TRUE';

  或使用 SDO 操作符语法:
  WHERE SDO_CONTAINS(a.geom, b.geom) = 'TRUE'
  WHERE SDO_INSIDE(a.geom, b.geom) = 'TRUE'

ClickHouse 特殊语法:
  不使用 ST_ 前缀，使用专用函数:
  pointInPolygon((x, y), [(x1,y1), ...])
  pointInEllipses(x, y, cx, cy, a, b)
  polygonsIntersection(poly1, poly2)
  polygonsWithin(poly1, poly2)
  polygonsEquals(poly1, poly2)
```

## 空间操作函数

| 函数 | PostGIS | MySQL 8.0 | SQL Server | Oracle | BigQuery | Snowflake | DuckDB | Trino |
|------|---------|-----------|------------|--------|----------|-----------|--------|-------|
| ST_Union | 是 | 是 | STUnion | SDO_GEOM.SDO_UNION | ST_UNION | 是 (GEOGRAPHY) | 是 | 否 |
| ST_Intersection | 是 | 是 | STIntersection | SDO_GEOM.SDO_INTERSECTION | ST_INTERSECTION | 是 (GEOGRAPHY) | 是 | ST_Intersection |
| ST_Difference | 是 | 是 | STDifference | SDO_GEOM.SDO_DIFFERENCE | ST_DIFFERENCE | 是 (GEOGRAPHY) | 是 | ST_Difference |
| ST_SymDifference | 是 | 是 | STSymDifference | SDO_GEOM.SDO_XOR | ST_SYMDIFFERENCE(间接) | 否 | 是 | ST_SymDifference |
| ST_Buffer | 是 | 是 | STBuffer | SDO_GEOM.SDO_BUFFER | ST_BUFFER | 是 (GEOGRAPHY) | 是 | ST_Buffer |
| ST_Centroid | 是 | 是 | STCentroid | SDO_GEOM.SDO_CENTROID | ST_CENTROID | 是 | 是 | ST_Centroid |
| ST_Envelope | 是 | 是 | STEnvelope | SDO_GEOM.SDO_MBR | ST_BOUNDINGBOX | 是 | 是 | ST_Envelope |
| ST_ConvexHull | 是 | 是 | STConvexHull | SDO_GEOM.SDO_CONVEXHULL | ST_CONVEXHULL | 否 | 是 | ST_ConvexHull |
| ST_Simplify | 是 | 是 (8.0) | Reduce | SDO_UTIL.SIMPLIFY | ST_SIMPLIFY | 否 | 否 | 否 |
| ST_Snap(ToGrid) | 是 | 否 | 否 | 否 | ST_SNAPTOGRID | 否 | 否 | 否 |
| ST_UnaryUnion | 是 | 否 | 否 | 否 | ST_UNION_AGG | 否 | 否 | 否 |

扩展引擎支持：

| 函数 | CockroachDB | StarRocks | Doris | SAP HANA | Redshift | Athena | Exasol |
|------|-------------|-----------|-------|----------|----------|--------|--------|
| ST_Union | 是 | 否 | 否 | 是 | 否 | 否 | 否 |
| ST_Intersection | 是 | 否 | 否 | 是 | 否 | 是 | 否 |
| ST_Buffer | 是 | 否 | 否 | 是 | 否 | 是 | 否 |
| ST_Centroid | 是 | 否 | 否 | 是 | 否 | 是 | 否 |
| ST_Envelope | 是 | 否 | 否 | 是 | 是 | 是 | 是 |
| ST_ConvexHull | 是 | 否 | 否 | 是 | 否 | 是 | 否 |

## 坐标访问与序列化

| 函数 | PostGIS | MySQL 8.0 | SQL Server | Oracle | BigQuery | Snowflake | DuckDB | ClickHouse | Trino |
|------|---------|-----------|------------|--------|----------|-----------|--------|------------|-------|
| ST_X | 是 | 是 | STX (属性) | t.geom.SDO_POINT.X | ST_X | 是 | 是 | 否 | ST_X |
| ST_Y | 是 | 是 | STY (属性) | t.geom.SDO_POINT.Y | ST_Y | 是 | 是 | 否 | ST_Y |
| ST_SRID | 是 | 是 | STSrid | t.geom.SDO_SRID | 不适用 (默认 4326) | 是 | 是 | 否 | 否 |
| ST_SetSRID | 是 | ST_SRID(g,srid) | 否 | 否 | 不适用 | 是 | 是 | 否 | 否 |
| ST_AsText (WKT) | 是 | 是 | STAsText | SDO_UTIL.TO_WKTGEOMETRY | ST_ASTEXT | 是 | 是 | 否 | ST_AsText |
| ST_AsBinary (WKB) | 是 | 是 | STAsBinary | SDO_UTIL.TO_WKBGEOMETRY | ST_ASBINARY | 是 | 是 | 否 | 否 |
| ST_AsGeoJSON | 是 | 是 (8.0+) | 是 (2016+) | SDO_UTIL.TO_GEOJSON | ST_ASGEOJSON | 是 | 是 | 否 | ST_AsText (无) |
| ST_AsKML | 是 | 否 | AsGml(类似) | SDO_UTIL.TO_KMLGEOMETRY | 否 | 否 | 否 | 否 | 否 |
| ST_GeometryType | 是 | 是 | STGeometryType | 方法 | ST_GEOMETRYTYPE | 是 | 是 | 否 | ST_GeometryType |
| ST_NumPoints | 是 | 是 | STNumPoints | SDO_UTIL.GETNUMVERTICES | ST_NUMPOINTS | 否 | 否 | 否 | 否 |

扩展引擎支持：

| 函数 | CockroachDB | SAP HANA | Redshift | Athena | H2 | Exasol |
|------|-------------|----------|----------|--------|----|--------|
| ST_X | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_Y | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_SRID | 是 | 是 | 是 | 否 | 否 | 否 |
| ST_AsText | 是 | 是 | 是 | 是 | 是 | 是 |
| ST_AsBinary | 是 | 是 | 是 | 否 | 否 | 否 |
| ST_AsGeoJSON | 是 | 是 | 是 | 否 | 否 | 否 |

## 空间索引

| 引擎 | 索引类型 | 创建语法 | 自动使用 | 备注 |
|------|---------|---------|---------|------|
| PostgreSQL + PostGIS | GiST, SP-GiST | `CREATE INDEX idx ON t USING GIST(geom)` | 是 | GiST 是默认选择 |
| MySQL (InnoDB) | R-Tree | `CREATE SPATIAL INDEX idx ON t(geom)` | 是 | 需要 NOT NULL + SRID |
| MariaDB | R-Tree | `CREATE SPATIAL INDEX idx ON t(geom)` | 是 | InnoDB 和 MyISAM 均支持 |
| SQLite + SpatiaLite | R-Tree (虚拟表) | `SELECT CreateSpatialIndex('t','geom')` | 需手动 JOIN | 需手动与 R-Tree 表关联 |
| Oracle | R-Tree, Quadtree | `CREATE INDEX idx ON t(geom) INDEXTYPE IS MDSYS.SPATIAL_INDEX` | 是 | 需先插入元数据 |
| SQL Server | 空间网格 | `CREATE SPATIAL INDEX idx ON t(geom) USING GEOMETRY_GRID` | 是 | 4 层网格 |
| DB2 | 网格索引 | `CREATE INDEX idx ON t(geom) EXTEND USING db2gse.spatial_index` | 是 | 需要空间扩展 |
| Snowflake | 无显式索引 | 自动优化 | 自动 | 微分区剪裁 |
| BigQuery | 自动 | 无需创建 | 自动 | S2 索引内部使用 |
| CockroachDB | 倒排索引 | `CREATE INVERTED INDEX idx ON t(geom)` | 是 | S2 cell 分解 |
| OceanBase | R-Tree | `CREATE SPATIAL INDEX idx ON t(geom)` | 是 | MySQL 模式 |
| CrateDB | GeoHash | 自动 | 自动 | GEO_SHAPE 列自动索引 |
| Greenplum | GiST | 同 PostGIS | 是 | 继承 PostGIS |
| TimescaleDB | GiST | 同 PostGIS | 是 | 继承 PostGIS |
| YugabyteDB | GiST | 同 PostGIS | 是 | 继承 PostGIS |
| SAP HANA | 内部 | 自动 | 自动 | 空间列自动优化 |
| Informix | R-Tree | `CREATE INDEX idx ON t(geom) USING RTREE` | 是 | Spatial DataBlade |

## SRID 与坐标参考系

| 引擎 | 默认 SRID | SRID 强制 | 常用 CRS | SRID 转换 |
|------|----------|----------|---------|----------|
| PostgreSQL + PostGIS | 0 (未定义) | 否 (可配置) | 4326 (WGS84) | ST_Transform |
| MySQL 8.0 | 0 | 是 (8.0+, SRID 属性) | 4326 | ST_Transform (8.0.13+) |
| SQL Server | 4326 (geography) | 类型级别 | 4326 | 无原生转换 |
| Oracle | NULL | 否 | 4326, 8307 | SDO_CS.TRANSFORM |
| BigQuery | 4326 (固定) | 固定 | 4326 | 不支持其他 |
| Snowflake | 4326 | 否 | 4326 | ST_TRANSFORM (有限) |
| DuckDB | 0 | 否 | 4326 | ST_Transform (需 proj) |
| CockroachDB | 0 | 否 | 4326 | ST_Transform |
| SAP HANA | 0 | 否 | 4326 | ST_Transform |
| Redshift | 0 | 否 | 4326 | 无 |

```
SRID 关键说明:
  SRID 4326 = WGS 84，GPS 坐标系，经纬度 (度)
  SRID 3857 = Web Mercator，Web 地图投影 (米)
  SRID 0    = 未定义坐标系 (平面笛卡尔)

  BigQuery 强制使用 4326:
    所有 GEOGRAPHY 值默认 WGS 84，无法使用其他坐标系

  MySQL 8.0 SRID 属性:
    CREATE TABLE t (geom GEOMETRY SRID 4326);
    -- 插入不匹配 SRID 的值会报错

  PostGIS ST_Transform:
    SELECT ST_Transform(geom, 3857) FROM t WHERE ST_SRID(geom) = 4326;
    -- 需要 PROJ 库支持
```

## H3 / S2 单元格函数 (现代空间索引)

H3 (Uber) 和 S2 (Google) 是现代空间索引系统，将地球表面离散化为层次化单元格，适合聚合分析和高效空间连接。

| 函数类别 | BigQuery | ClickHouse | DuckDB | Snowflake | Databricks | Trino | Athena | Presto |
|---------|----------|------------|--------|-----------|------------|-------|--------|--------|
| H3 索引 | 是 | 是 (原生) | 扩展 (h3) | 是 (H3 UDF) | 是 (H3) | 否 | 否 | 否 |
| S2 单元格 | 是 (S2_) | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| H3 点→索引 | H3_LATLNG_TO_CELL | h3ToGeo | h3_latlng_to_cell | H3_LATLNG_TO_CELL | h3_latlng_to_cell | 否 | 否 | 否 |
| H3 索引→多边形 | H3_CELL_TO_BOUNDARY | h3ToGeoBoundary | h3_cell_to_boundary | H3_CELL_TO_BOUNDARY | h3_cell_to_boundary | 否 | 否 | 否 |
| H3 分辨率 | H3_GET_RESOLUTION | h3GetResolution | h3_get_resolution | H3_GET_RESOLUTION | h3_get_resolution | 否 | 否 | 否 |
| H3 邻居 | H3_GRID_DISK | h3kRing | h3_grid_disk | H3_GRID_DISK | h3_grid_disk | 否 | 否 | 否 |
| S2 点→ID | S2_CELLIDFROMPOINT | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| S2 ID→令牌 | S2_CELLID_TO_TOKEN(间接) | 否 | 否 | 否 | 否 | 否 | 否 | 否 |

```
H3 函数示例:

-- ClickHouse: 原生 H3 支持
SELECT geoToH3(lng, lat, 7) AS h3_index
FROM events;

SELECT h3ToGeo(h3_index) AS (lat, lng)
FROM events_h3;

SELECT h3kRing(h3_index, 1) AS neighbors
FROM events_h3;

-- Snowflake: H3 函数
SELECT H3_LATLNG_TO_CELL(lat, lng, 7) AS h3_index
FROM events;

SELECT H3_CELL_TO_BOUNDARY(h3_index) AS boundary_geojson
FROM events_h3;

-- BigQuery: S2 单元格
SELECT S2_CELLIDFROMPOINT(geography, level := 10) AS s2_cell
FROM locations;

SELECT S2_COVERINGCELLIDS(geography, max_level := 12) AS covering_cells
FROM regions;

-- DuckDB: H3 扩展
INSTALL h3;
LOAD h3;
SELECT h3_latlng_to_cell(lat, lng, 7) AS h3_index FROM events;

-- Databricks: H3 内建函数 (DBR 11.2+)
SELECT h3_latlng_to_cell(lat, lng, 7) AS h3_index FROM events;
SELECT h3_cell_to_boundary(h3_index) AS boundary FROM events_h3;
```

## GEOGRAPHY 类型：大地测量计算

支持 GEOGRAPHY 类型（球面/椭球面上的精确计算）的引擎：

| 引擎 | GEOGRAPHY 类型 | 计算模型 | 距离单位 | 面积单位 |
|------|--------------|---------|---------|---------|
| PostgreSQL + PostGIS | geography | 椭球面 (WGS84) | 米 | 平方米 |
| SQL Server | geography | 椭球面 | 米 | 平方米 |
| BigQuery | GEOGRAPHY (唯一类型) | 球面 (S2) | 米 | 平方米 |
| Snowflake | GEOGRAPHY | 球面 | 米 | 平方米 |
| CockroachDB | GEOGRAPHY | 椭球面 (WGS84) | 米 | 平方米 |
| SAP HANA | ST_GEOMETRY (SRID 4326) | 椭球面 | 米 | 平方米 |
| SingleStore | GEOGRAPHY / GEOGRAPHYPOINT | 球面 | 米 | -- |
| DB2 | ST_Geometry (SRID 1003) | 椭球面 | 米 | 平方米 |

```
GEOMETRY vs GEOGRAPHY 性能与精度:

  场景: 上海 (121.47°E, 31.23°N) 到北京 (116.40°E, 39.90°N) 距离

  GEOMETRY (SRID 4326 但按平面计算):
    ST_Distance(GEOMETRY) ≈ 10.04 (度) -- 无实际意义

  GEOGRAPHY (椭球面):
    ST_Distance(GEOGRAPHY) ≈ 1,067,534 (米) ≈ 1067.5 公里 -- 正确

  PostGIS 快捷方式 (GEOMETRY 但球面计算):
    ST_DistanceSphere(GEOMETRY, GEOMETRY) ≈ 1,062,000 (米)  -- 球面近似
    ST_DistanceSpheroid(GEOMETRY, GEOMETRY, spheroid) -- 椭球面

  性能差异:
    GEOMETRY 计算: ~10x 更快 (简单笛卡尔数学)
    GEOGRAPHY 计算: 更慢但精确 (涉及三角函数和椭球面公式)
    小区域 (城市级): GEOMETRY + 投影坐标系 (如 UTM) 通常足够
    大区域 (跨国): 必须使用 GEOGRAPHY 或球面函数
```

## 各引擎语法详解

### PostgreSQL + PostGIS

PostGIS 是最强大的开源空间扩展，提供 300+ 空间函数，是空间 SQL 的事实标准。

```sql
-- 安装 PostGIS
CREATE EXTENSION postgis;

-- 创建表
CREATE TABLE cities (
    id    SERIAL PRIMARY KEY,
    name  TEXT NOT NULL,
    geom  GEOMETRY(Point, 4326)
);

CREATE TABLE districts (
    id    SERIAL PRIMARY KEY,
    name  TEXT NOT NULL,
    geom  GEOMETRY(Polygon, 4326)
);

-- 插入数据
INSERT INTO cities (name, geom) VALUES
('上海', ST_SetSRID(ST_MakePoint(121.47, 31.23), 4326)),
('北京', ST_SetSRID(ST_MakePoint(116.40, 39.90), 4326));

-- 创建空间索引
CREATE INDEX idx_cities_geom ON cities USING GIST(geom);
CREATE INDEX idx_districts_geom ON districts USING GIST(geom);

-- 距离计算 (GEOGRAPHY 类型，返回米)
SELECT a.name, b.name,
       ST_Distance(a.geom::geography, b.geom::geography) AS distance_meters
FROM cities a, cities b
WHERE a.name = '上海' AND b.name = '北京';

-- 空间关系查询: 查找包含某点的区
SELECT d.name
FROM districts d
WHERE ST_Contains(d.geom, ST_SetSRID(ST_MakePoint(121.47, 31.23), 4326));

-- 缓冲区分析: 5公里范围内的 POI
SELECT p.name
FROM pois p, cities c
WHERE c.name = '上海'
  AND ST_DWithin(c.geom::geography, p.geom::geography, 5000);

-- 聚合: 合并多个多边形
SELECT ST_Union(geom) AS merged
FROM districts
WHERE city = '上海';

-- GeoJSON 输出
SELECT name, ST_AsGeoJSON(geom) AS geojson
FROM cities;

-- 坐标系转换
SELECT ST_Transform(geom, 3857) AS web_mercator
FROM cities;

-- GEOGRAPHY 类型直接使用
CREATE TABLE routes (
    id   SERIAL PRIMARY KEY,
    path GEOGRAPHY(LineString, 4326)
);

-- 路线长度 (直接返回米)
SELECT id, ST_Length(path) AS length_meters FROM routes;
```

### MySQL 8.0

MySQL 8.0 大幅改进了空间支持，包括 SRID 感知和 InnoDB 空间索引。

```sql
-- 创建表 (指定 SRID)
CREATE TABLE cities (
    id    INT PRIMARY KEY AUTO_INCREMENT,
    name  VARCHAR(100) NOT NULL,
    geom  POINT NOT NULL SRID 4326,
    SPATIAL INDEX (geom)
);

-- 插入数据
INSERT INTO cities (name, geom) VALUES
('上海', ST_GeomFromText('POINT(121.47 31.23)', 4326)),
('北京', ST_GeomFromText('POINT(116.40 39.90)', 4326));

-- 距离计算 (8.0.14+, SRID 4326 自动按球面计算，返回米)
SELECT a.name, b.name,
       ST_Distance(a.geom, b.geom) AS distance_meters
FROM cities a, cities b
WHERE a.name = '上海' AND b.name = '北京';

-- 空间关系查询
SELECT * FROM pois
WHERE ST_Contains(
    ST_GeomFromText('POLYGON((...定义区域...))', 4326),
    geom
);

-- MBR (最小边界矩形) 关系函数 (更快但不精确)
SELECT * FROM pois
WHERE MBRContains(
    ST_GeomFromText('POLYGON((...))'),
    geom
);

-- 输出格式
SELECT name,
       ST_AsText(geom) AS wkt,
       ST_AsGeoJSON(geom) AS geojson,
       ST_X(geom) AS lng,
       ST_Y(geom) AS lat
FROM cities;

-- 坐标系转换 (8.0.13+)
SELECT ST_Transform(geom, 3857) FROM cities;

-- 注意: MySQL 不支持 GEOGRAPHY 类型
-- 但 SRID 4326 下的 ST_Distance 会按球面计算
-- 不支持 ST_Buffer 在 GEOGRAPHY 上的操作
```

### SQL Server

SQL Server 同时支持 geometry 和 geography 类型，使用方法调用语法。

```sql
-- 创建表
CREATE TABLE Cities (
    Id   INT PRIMARY KEY IDENTITY,
    Name NVARCHAR(100),
    Geom geometry,
    Geog geography
);

-- 插入数据 (注意: geography 类型经纬度顺序为 lat, lng)
INSERT INTO Cities (Name, Geom, Geog) VALUES
('上海',
 geometry::STGeomFromText('POINT(121.47 31.23)', 4326),
 geography::Point(31.23, 121.47, 4326));

INSERT INTO Cities (Name, Geom, Geog) VALUES
('北京',
 geometry::STGeomFromText('POINT(116.40 39.90)', 4326),
 geography::Point(39.90, 116.40, 4326));

-- 距离 (geography → 米)
SELECT a.Name, b.Name,
       a.Geog.STDistance(b.Geog) AS DistanceMeters
FROM Cities a, Cities b
WHERE a.Name = N'上海' AND b.Name = N'北京';

-- 空间关系
SELECT * FROM Districts d
WHERE d.Geog.STContains(geography::Point(31.23, 121.47, 4326)) = 1;

-- 缓冲区 (geography, 5000米)
DECLARE @center geography = geography::Point(31.23, 121.47, 4326);
SELECT * FROM POIs
WHERE @center.STBuffer(5000).STContains(Geog) = 1;

-- 空间索引
CREATE SPATIAL INDEX idx_cities_geog ON Cities(Geog)
    USING GEOGRAPHY_GRID
    WITH (GRIDS = (MEDIUM, MEDIUM, MEDIUM, MEDIUM));

-- 输出
SELECT Name,
       Geom.STAsText() AS WKT,
       Geog.STAsText() AS WKT_Geog,
       Geog.Lat AS Latitude,
       Geog.Long AS Longitude
FROM Cities;
```

### Oracle Spatial

Oracle 使用 SDO_GEOMETRY 对象类型和 SDO 操作符。

```sql
-- 创建表
CREATE TABLE cities (
    id   NUMBER PRIMARY KEY,
    name VARCHAR2(100),
    geom SDO_GEOMETRY
);

-- 注册空间元数据 (必须)
INSERT INTO USER_SDO_GEOM_METADATA (TABLE_NAME, COLUMN_NAME, DIMINFO, SRID) VALUES (
    'CITIES', 'GEOM',
    SDO_DIM_ARRAY(
        SDO_DIM_ELEMENT('X', -180, 180, 0.005),
        SDO_DIM_ELEMENT('Y', -90, 90, 0.005)
    ),
    4326
);

-- 创建空间索引
CREATE INDEX idx_cities_geom ON cities(geom)
    INDEXTYPE IS MDSYS.SPATIAL_INDEX;

-- 插入数据
INSERT INTO cities VALUES (1, '上海',
    SDO_GEOMETRY(2001, 4326,
        SDO_POINT_TYPE(121.47, 31.23, NULL), NULL, NULL));

-- 距离查询 (SDO_GEOM.SDO_DISTANCE, 返回米)
SELECT SDO_GEOM.SDO_DISTANCE(a.geom, b.geom, 0.005) AS distance_meters
FROM cities a, cities b
WHERE a.name = '上海' AND b.name = '北京';

-- 空间关系 (SDO_RELATE)
SELECT b.name
FROM cities a, districts b
WHERE a.name = '上海'
  AND SDO_RELATE(b.geom, a.geom, 'mask=ANYINTERACT') = 'TRUE';

-- 范围查询 (SDO_WITHIN_DISTANCE)
SELECT p.name
FROM pois p, cities c
WHERE c.name = '上海'
  AND SDO_WITHIN_DISTANCE(p.geom, c.geom, 'distance=5000 unit=meter') = 'TRUE';

-- 输出 WKT
SELECT SDO_UTIL.TO_WKTGEOMETRY(geom) AS wkt FROM cities;

-- 输出 GeoJSON (12c+)
SELECT SDO_UTIL.TO_GEOJSON(geom) AS geojson FROM cities;

-- 坐标系转换
SELECT SDO_CS.TRANSFORM(geom, 3857) FROM cities;
```

### BigQuery

BigQuery 使用纯 GEOGRAPHY 类型（基于 S2 几何库），所有坐标固定为 WGS 84。

```sql
-- 创建表
CREATE TABLE dataset.cities (
    name STRING,
    geog GEOGRAPHY
);

-- 插入数据
INSERT INTO dataset.cities VALUES
('上海', ST_GEOGPOINT(121.47, 31.23)),
('北京', ST_GEOGPOINT(116.40, 39.90));

-- 距离 (始终返回米)
SELECT a.name, b.name,
       ST_DISTANCE(a.geog, b.geog) AS distance_meters
FROM dataset.cities a, dataset.cities b
WHERE a.name = '上海' AND b.name = '北京';

-- 范围查询
SELECT p.name
FROM dataset.pois p, dataset.cities c
WHERE c.name = '上海'
  AND ST_DWITHIN(p.geog, c.geog, 5000);

-- 空间聚合
SELECT city,
       ST_UNION_AGG(geog) AS merged_geography,
       ST_CENTROID_AGG(geog) AS center_point
FROM dataset.districts
GROUP BY city;

-- GeoJSON 输出
SELECT name, ST_ASGEOJSON(geog) AS geojson FROM dataset.cities;

-- WKT 输入
SELECT ST_GEOGFROMTEXT('POLYGON((121 31, 122 31, 122 32, 121 32, 121 31))') AS polygon;

-- S2 单元格
SELECT name,
       S2_CELLIDFROMPOINT(geog, level := 10) AS s2_cell_id
FROM dataset.cities;

-- 注意: BigQuery 不支持 GEOMETRY 类型
-- 不支持非 WGS 84 坐标系
-- 不需要创建空间索引，自动优化空间查询
```

### Snowflake

Snowflake 同时支持 GEOMETRY 和 GEOGRAPHY 类型。

```sql
-- 创建表
CREATE TABLE cities (
    name VARCHAR,
    geom GEOMETRY,
    geog GEOGRAPHY
);

-- 插入数据
INSERT INTO cities VALUES
('上海', ST_MAKEPOINT(121.47, 31.23), ST_GEOGPOINT(121.47, 31.23)),
('北京', ST_MAKEPOINT(116.40, 39.90), ST_GEOGPOINT(116.40, 39.90));

-- 或从 WKT
INSERT INTO cities (name, geog) VALUES
('广州', ST_GEOGRAPHYFROMWKT('POINT(113.26 23.13)'));

-- 距离 (GEOGRAPHY → 米)
SELECT a.name, b.name,
       ST_DISTANCE(a.geog, b.geog) AS distance_meters
FROM cities a, cities b
WHERE a.name = '上海' AND b.name = '北京';

-- 空间关系
SELECT ST_CONTAINS(
    ST_GEOGRAPHYFROMWKT('POLYGON((121 31, 122 31, 122 32, 121 32, 121 31))'),
    geog
) AS is_within
FROM cities;

-- 输出
SELECT name,
       ST_ASTEXT(geog) AS wkt,
       ST_ASGEOJSON(geog) AS geojson,
       ST_X(geog) AS lng,
       ST_Y(geog) AS lat
FROM cities;

-- H3 函数
SELECT name,
       H3_LATLNG_TO_CELL(ST_Y(geog), ST_X(geog), 7) AS h3_index
FROM cities;

-- Snowflake 支持 ST_Intersection, ST_Union, ST_Buffer, ST_Difference 等 GEOGRAPHY 几何运算函数
-- 空间查询自动利用微分区剪裁，无需创建空间索引
```

### DuckDB

DuckDB 通过 spatial 扩展提供空间能力。

```sql
-- 加载空间扩展
INSTALL spatial;
LOAD spatial;

-- 创建表
CREATE TABLE cities (
    name VARCHAR,
    geom GEOMETRY
);

-- 插入数据
INSERT INTO cities VALUES
('上海', ST_Point(121.47, 31.23)),
('北京', ST_Point(116.40, 39.90));

-- 从 WKT
INSERT INTO cities VALUES
('广州', ST_GeomFromText('POINT(113.26 23.13)'));

-- 距离 (平面距离，坐标单位)
SELECT a.name, b.name,
       ST_Distance(a.geom, b.geom) AS distance_degrees
FROM cities a, cities b
WHERE a.name = '上海' AND b.name = '北京';

-- 空间关系
SELECT * FROM pois
WHERE ST_Contains(
    ST_GeomFromText('POLYGON((121 31, 122 31, 122 32, 121 32, 121 31))'),
    geom
);

-- 输出
SELECT name,
       ST_AsText(geom) AS wkt,
       ST_AsGeoJSON(geom) AS geojson,
       ST_X(geom) AS x,
       ST_Y(geom) AS y
FROM cities;

-- 读取空间文件
SELECT * FROM ST_Read('path/to/shapefile.shp');
SELECT * FROM ST_Read('path/to/data.geojson');
SELECT * FROM ST_Read('path/to/data.gpkg');

-- H3 扩展 (需单独安装)
INSTALL h3;
LOAD h3;
SELECT h3_latlng_to_cell(31.23, 121.47, 7) AS h3_index;

-- 注意: DuckDB 不支持 GEOGRAPHY 类型
-- 不支持空间索引 (全表扫描)
-- 支持从 Shapefile, GeoJSON, GeoPackage 等格式直接读取
```

### ClickHouse

ClickHouse 使用专有空间函数名称，不完全遵循 ST_ 命名规范。

```sql
-- 空间类型: 使用 Tuple 和 Array
-- Point:   Tuple(Float64, Float64)
-- Ring:    Array(Point)
-- Polygon: Array(Ring)
-- MultiPolygon: Array(Polygon)

-- 创建表
CREATE TABLE cities (
    name String,
    lng  Float64,
    lat  Float64
) ENGINE = MergeTree ORDER BY name;

CREATE TABLE districts (
    name String,
    polygon Array(Array(Tuple(Float64, Float64)))
) ENGINE = MergeTree ORDER BY name;

-- 点在多边形内判断
SELECT name FROM cities
WHERE pointInPolygon((lng, lat), [(x1,y1), (x2,y2), ...]);

-- greatCircleDistance (球面距离, 米)
SELECT greatCircleDistance(121.47, 31.23, 116.40, 39.90) AS distance_meters;

-- geoDistance (椭球面距离, 米, 更精确)
SELECT geoDistance(121.47, 31.23, 116.40, 39.90) AS distance_meters;

-- pointInEllipses (点在椭圆内)
SELECT pointInEllipses(lng, lat, 121.47, 31.23, 5000, 5000) AS within_5km
FROM cities;

-- Polygon 操作
SELECT polygonsIntersection(poly1, poly2) AS intersection;
SELECT polygonsUnion(poly1, poly2) AS union_result;
SELECT polygonsWithin(poly1, poly2) AS is_within;

-- GeoHash
SELECT geohashEncode(121.47, 31.23, 7) AS geohash;
SELECT geohashDecode('wtw3sm0') AS (lng, lat);

-- H3 函数 (原生支持)
SELECT geoToH3(121.47, 31.23, 7) AS h3_index;
SELECT h3ToGeo(h3_index) AS (lat, lng);
SELECT h3ToGeoBoundary(h3_index) AS boundary;
SELECT h3kRing(h3_index, 1) AS neighbors;
SELECT h3GetResolution(h3_index) AS resolution;

-- 注意: 不使用 ST_ 前缀
-- 无 GEOMETRY/GEOGRAPHY 统一类型
-- 空间能力主要面向分析场景 (点在多边形内、距离计算、H3)
```

### Trino / Presto / Amazon Athena

Trino (前身 Presto) 提供了标准化的空间函数集。Amazon Athena 继承 Trino 的空间能力。

```sql
-- 空间类型: 无独立类型，使用 varbinary (WKB 编码)

-- 创建几何
SELECT ST_Point(121.47, 31.23) AS point;
SELECT ST_GeometryFromText('POLYGON((121 31, 122 31, 122 32, 121 32, 121 31))') AS polygon;

-- 距离 (平面坐标单位)
SELECT ST_Distance(
    ST_Point(121.47, 31.23),
    ST_Point(116.40, 39.90)
) AS distance;

-- 球面距离 (Trino 提供 great_circle_distance)
SELECT great_circle_distance(31.23, 121.47, 39.90, 116.40) AS distance_km;

-- 空间关系
SELECT ST_Contains(
    ST_GeometryFromText('POLYGON((121 31, 122 31, 122 32, 121 32, 121 31))'),
    ST_Point(121.47, 31.23)
) AS is_contained;

-- 空间操作
SELECT ST_Intersection(geom1, geom2) AS intersection;
SELECT ST_Buffer(ST_Point(121.47, 31.23), 0.01) AS buffer;
SELECT ST_ConvexHull(ST_GeometryFromText('MULTIPOINT(...)')) AS hull;

-- 输出
SELECT ST_AsText(ST_Point(121.47, 31.23)) AS wkt;

-- Bing Tiles (Trino 特有，用于空间分区)
SELECT bing_tile_at(31.23, 121.47, 15) AS tile;
SELECT bing_tile_polygon(bing_tile_at(31.23, 121.47, 15)) AS tile_polygon;
SELECT bing_tiles_around(31.23, 121.47, 15, 1000) AS nearby_tiles;

-- Athena 与 Trino 语法完全一致
-- Presto 与 Trino 空间函数基本一致 (分叉前的函数)
```

### Spark SQL / Databricks

Spark SQL 原生空间能力有限，Databricks 在 DBR 13+ 引入内建空间函数。

```sql
-- Spark SQL: 无原生空间类型和函数
-- 需要使用第三方库: Apache Sedona (GeoSpark), GeoMesa, Mosaic

-- Apache Sedona 方式:
SELECT ST_Distance(
    ST_GeomFromWKT('POINT(121.47 31.23)'),
    ST_GeomFromWKT('POINT(116.40 39.90)')
) AS distance;

-- Databricks 内建空间函数 (DBR 13.3+):
SELECT ST_Point(121.47, 31.23) AS point;
SELECT ST_GeomFromWKT('POLYGON((121 31, 122 31, 122 32, 121 32, 121 31))') AS poly;

-- H3 函数 (Databricks DBR 11.2+, 原生)
SELECT h3_latlng_to_cell(31.23, 121.47, 7) AS h3_index;
SELECT h3_cell_to_boundary(h3_index) AS boundary;
SELECT h3_grid_disk(h3_index, 1) AS neighbors;

-- Mosaic 库 (Databricks 推荐空间库)
-- 提供更丰富的空间分析能力，包括 ST_ 函数和光栅分析
```

## PostGIS vs 原生实现对比

PostGIS 是空间 SQL 的事实标准，但各引擎越来越多地选择原生实现。以下对比核心差异：

| 维度 | PostGIS | MySQL 8.0 原生 | SQL Server 原生 | BigQuery 原生 | Snowflake 原生 |
|------|---------|---------------|----------------|--------------|---------------|
| 函数数量 | 300+ | ~60 | ~80 | ~50 | ~50 |
| 类型系统 | GEOMETRY + GEOGRAPHY | GEOMETRY | geometry + geography | GEOGRAPHY | GEOMETRY + GEOGRAPHY |
| 空间索引 | GiST, SP-GiST, BRIN | R-Tree (InnoDB) | 4层网格索引 | 自动 (S2) | 自动 (微分区) |
| CRS 转换 | ST_Transform (完整) | ST_Transform (8.0.13+) | 无原生 | 不支持 (仅4326) | ST_TRANSFORM (有限) |
| 拓扑支持 | PostGIS Topology | 无 | 无 | 无 | 无 |
| 光栅支持 | PostGIS Raster | 无 | 无 | 无 | 无 |
| 3D 支持 | 是 (Z, M) | 否 | 是 (Z, M) | 无 | 无 |
| 曲线类型 | 是 (CircularString) | 无 | 是 | 无 | 无 |
| 路由/网络 | pgRouting 扩展 | 无 | 无 | 无 | 无 |
| 标准兼容 | OGC SFA + SQL/MM | OGC SFA (部分) | OGC SFA | 非标准但完整 | OGC SFA (部分) |

### PostGIS 独有能力

```sql
-- 1. 拓扑 (Topology)
CREATE EXTENSION postgis_topology;
SELECT topology.CreateTopology('city_topo', 4326);
SELECT topology.AddTopoGeometryColumn('city_topo', 'public', 'districts', 'topo_geom', 'POLYGON');

-- 2. 光栅 (Raster)
CREATE EXTENSION postgis_raster;
SELECT ST_Value(rast, ST_SetSRID(ST_MakePoint(121.47, 31.23), 4326))
FROM elevation_data
WHERE ST_Intersects(rast, ST_SetSRID(ST_MakePoint(121.47, 31.23), 4326));

-- 3. 3D 操作
SELECT ST_3DDistance(
    ST_GeomFromText('POINT Z(121.47 31.23 100)', 4326),
    ST_GeomFromText('POINT Z(116.40 39.90 50)', 4326)
);

-- 4. 曲线类型
SELECT ST_GeomFromText('CIRCULARSTRING(0 0, 1 1, 2 0)');
SELECT ST_CurveToLine(ST_GeomFromText('CIRCULARSTRING(0 0, 1 1, 2 0)'));

-- 5. pgRouting (最短路径)
SELECT * FROM pgr_dijkstra(
    'SELECT id, source, target, cost FROM road_network',
    1, 100  -- 从节点1到节点100
);

-- 6. 高级空间分析
SELECT ST_VoronoiPolygons(ST_Collect(geom)) FROM cities;  -- Voronoi 图
SELECT ST_DelaunayTriangles(ST_Collect(geom)) FROM cities; -- Delaunay 三角化
SELECT ST_ConcaveHull(ST_Collect(geom), 0.8) FROM pois;    -- 凹包
SELECT ST_ClusterDBSCAN(geom, 0.01, 5) OVER() FROM pois;  -- DBSCAN 聚类
SELECT ST_Subdivide(geom, 256) FROM large_polygons;         -- 几何细分
```

### 各引擎独特能力

```
BigQuery 独有:
  - S2_CELLIDFROMPOINT / S2_COVERINGCELLIDS (S2 单元格)
  - ST_CENTROID_AGG / ST_UNION_AGG (空间聚合函数)
  - 自动空间索引，无需手动创建

SQL Server 独有:
  - geometry/geography 方法调用语法 (OOP 风格)
  - 空间结果可通过 SSMS 直接可视化
  - 4 层分辨率的网格索引

ClickHouse 独有:
  - 原生 H3 函数 (geoToH3, h3ToGeo, h3kRing 等)
  - GeoHash 编解码 (geohashEncode, geohashDecode)
  - 面向高吞吐量分析的点多边形判断

Trino/Athena 独有:
  - Bing Tile 函数 (bing_tile_at, bing_tile_polygon, bing_tiles_around)
  - 空间分区 (使用 Bing Tile 进行数据分区)
  - great_circle_distance (大圆距离)

Oracle Spatial 独有:
  - SDO_RELATE 的丰富 mask 选项
  - SDO_NN (最近邻查询)
  - SDO_SAM (空间分析挖掘)
  - 线性参考系统 (LRS)
  - 网络数据模型 (NDM)
```

## 不支持空间功能的引擎

以下引擎在当前版本中不提供原生空间数据类型或空间函数：

| 引擎 | 状态 | 替代方案 |
|------|------|---------|
| Firebird | 无空间支持 | 应用层计算 |
| HSQLDB | 无空间支持 | 应用层计算 |
| Derby | 无空间支持 | 应用层计算 |
| Google Spanner | 无空间支持 | 应用层计算 |
| Materialize | 无空间支持 | 流处理引擎，不面向 GIS |
| RisingWave | 无空间支持 | 流处理引擎，不面向 GIS |
| InfluxDB | 无空间支持 | 时序引擎，无 GIS 需求 |
| Firebolt | 无空间支持 | 应用层计算 |
| Flink SQL | 无原生支持 | Apache Sedona Flink 连接器 |
| Hive | 无原生支持 | ESRI Hive UDF / Sedona |
| Impala | 无原生支持 | 应用层计算 |

## 关键发现

```
1. PostGIS 仍是最全面的空间 SQL 实现:
   300+ 函数，涵盖拓扑、光栅、3D、路由等高级能力
   Greenplum, TimescaleDB, YugabyteDB 等 PG 系引擎通过安装 PostGIS 获得同等能力
   CockroachDB 原生实现了 PostGIS 兼容子集 (约 40 个核心函数)

2. GEOGRAPHY vs GEOMETRY 是最关键的区分:
   仅 PostGIS, SQL Server, BigQuery, Snowflake, CockroachDB, SAP HANA 支持 GEOGRAPHY 类型
   使用 GEOMETRY + SRID 4326 时，ST_Distance 返回的是"度"而非"米"(MySQL 8.0.14+ 除外)
   BigQuery 仅提供 GEOGRAPHY，不支持 GEOMETRY——这简化了使用但限制了灵活性

3. 云数仓空间能力快速发展:
   BigQuery: 最完善的云端空间能力，S2 原生集成，自动索引
   Snowflake: GEOMETRY + GEOGRAPHY 双类型，H3 原生支持
   Redshift: 仅基础 GEOMETRY 支持，无 GEOGRAPHY
   Azure Synapse: 有限空间子集

4. 现代空间索引 (H3/S2) 成为新趋势:
   ClickHouse: H3 原生支持最成熟
   BigQuery: S2 原生集成
   BigQuery, Snowflake, Databricks, DuckDB: H3 支持
   传统 R-Tree/GiST 仍是 OLTP 场景的主流选择

5. 命名规范差异显著:
   OGC 标准: ST_ 前缀 (ST_Distance, ST_Contains)
   Oracle: SDO_ 前缀 + 包函数 (SDO_GEOM.SDO_DISTANCE)
   SQL Server: 方法语法 (geom.STDistance)
   ClickHouse: 无前缀 (greatCircleDistance, pointInPolygon)
   BigQuery: ST_ 大写 (ST_DISTANCE, ST_CONTAINS)

6. 空间索引实现各异:
   PostGIS: GiST (通用搜索树)，最灵活
   MySQL/MariaDB: R-Tree，需要 NOT NULL 和 SRID 约束
   SQL Server: 多层网格索引
   BigQuery/Snowflake: 自动索引，无需手动创建
   CockroachDB: 倒排索引 + S2 单元格分解
   大多数 OLAP 引擎: 无空间索引，依赖全表扫描

7. 约 12 个引擎完全不提供空间能力:
   Firebird, HSQLDB, Derby, Spanner, Materialize, RisingWave,
   InfluxDB, Firebolt, Flink SQL, Hive, Impala 等
   这些引擎或定位于特定场景 (时序、流处理)，或为嵌入式轻量引擎

8. SRID 4326 (WGS 84) 是事实标准:
   BigQuery 强制使用 4326
   多数引擎默认或推荐 4326
   坐标系转换 (ST_Transform) 支持程度差异大:
   PostGIS > Oracle > MySQL 8.0 > CockroachDB > 其他 (不支持或有限)
```
