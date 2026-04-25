# Range 与 Multirange 操作 (Range and Multirange Operations)

用一个值描述一段连续区间，再用一个值描述若干个不连续区间的集合——PostgreSQL 的 range 与 multirange 类型，把"会议室时间冲突""价格有效期""可用窗口的空隙"这些日常需求，从触发器和应用层逻辑，搬到了类型系统与 GiST 索引里。

## 为什么需要 Range 与 Multirange

### 区间是真实世界的常态

绝大多数业务系统都需要表达"一段时间""一段编号""一段价格"这样的连续区间：

- 酒店房间的入住区间 `[check_in, check_out)`
- 员工合同的有效期 `[start_date, end_date)`
- 商品的促销价格区间 `[valid_from, valid_to)`
- IP 段或编号段 `[start_ip, end_ip]`
- 传感器读数的时间窗口 `[t_start, t_end)`

传统 SQL 用两列 `start`/`end` 表示这种区间，但这种"双列模式"在三个层面缺乏表达力：

1. **重叠检测困难**：判断两段时间是否重叠需要 `(a.start < b.end AND a.end > b.start)` 这样易错的复合条件
2. **无重叠约束难以保证**：UNIQUE 约束只能保证完全相等，无法保证"任意两行的时间段不重叠"，传统做法依赖触发器或应用层检查，存在并发竞态
3. **无法表达不连续区间**：员工的多段任职、设备的多次维护窗口、可用时段的并集与差集——双列模式根本无法用单值表示

### Multirange 解决了"集合"问题

Multirange（多范围）是若干个不连续 range 的集合。它解决了 range 类型本身的一个限制：**两个 range 的差集可能不连续**，因此 range 的 `-` 运算符在标准 range 类型上不闭合。例如：

```sql
SELECT '[1,10)'::int4range - '[3,5)'::int4range;
-- 期望结果: {[1,3), [5,10)} —— 这是一个 multirange，不是单个 range
-- 在 PG 14 之前会报错："result of range difference would not be contiguous"
```

PostgreSQL 14 引入 multirange 后，差集运算可以返回 `int4multirange` 值；range_agg 聚合函数可以把行集中的多段 range 合并为一个 multirange；缺口检测（gap detection）变成单个 SQL 表达式。

## SQL:2011 PERIOD vs PostgreSQL Range：两种模型

### SQL:2011 PERIOD：元数据声明

SQL:2011 标准（ISO/IEC 9075-2, Section 4.6.3）引入 `PERIOD FOR` 子句。它在两个标量列上声明"这两列共同构成一个时间段"，然后允许 `WITHOUT OVERLAPS` 约束、`FOR PORTION OF` DML、`OVERLAPS` 谓词等基于 PERIOD 的操作。

```sql
-- SQL:2011 PERIOD 模型：底层仍是两列，PERIOD 是元数据
CREATE TABLE contracts (
    contract_id INT PRIMARY KEY,
    customer_id INT,
    start_date DATE,
    end_date DATE,
    PERIOD FOR validity (start_date, end_date),
    UNIQUE (customer_id, validity WITHOUT OVERLAPS)
);
```

特点：
- 物理存储上仍然是两列
- PERIOD 不是一等数据类型，不能赋值给变量、不能放入数组
- `WITHOUT OVERLAPS` 是约束系统内置的语义，不通过通用运算符表达
- 主要面向时间区间，不是通用的范围类型

实现 SQL:2011 PERIOD 的引擎主要是 Teradata、IBM DB2、MariaDB 部分子集；Oracle 12c 引入了相关概念但官方文档未完全覆盖；SQL Server 的 `PERIOD FOR SYSTEM_TIME` 是另一回事——它用于系统版本化时态表，而非通用的应用时间段。

### PostgreSQL Range：一等类型

PostgreSQL 9.2（2012）引入的 range 类型是一种真正的复合类型：

```sql
-- PG range：一等数据类型，单列存储 [lower, upper, bounds_kind]
CREATE TABLE reservations (
    room_id INT,
    stay daterange,                       -- 一列即一个区间
    EXCLUDE USING gist (room_id WITH =, stay WITH &&)
);
```

特点：
- range 是真正的类型，可以做列、做参数、做返回值、做数组元素
- 内置完整的运算符代数（`&&`, `@>`, `<@`, `+`, `*`, `-`, `-|-`, `<<`, `>>`）
- GiST/SP-GiST 索引原生支持
- EXCLUDE 约束以通用方式声明任意运算符的"不允许同时满足"
- PG 14 起新增 multirange 类型，把差集运算闭合化、聚合化

### 两种模型的对比

| 维度 | SQL:2011 PERIOD | PostgreSQL Range |
|------|-----------------|------------------|
| 类型地位 | 元数据声明（虚拟列） | 真正的一等类型 |
| 物理存储 | 两个标量列 | 单列存储 lower/upper/bounds |
| 重叠检测 | `WITHOUT OVERLAPS` 约束、`OVERLAPS` 谓词 | `&&` 运算符 + EXCLUDE |
| 运算符代数 | 受限（标准定义少） | 完整（包含、交、并、差、相邻） |
| 索引加速 | 普通 B-tree（有限） | GiST/SP-GiST（高效） |
| 不连续区间 | 不支持（多行表示） | Multirange 类型直接支持 |
| 数组/聚合 | 不支持 | range_agg、unnest 等齐全 |
| 上手难度 | 低（看起来像两列） | 中（需要学习运算符） |
| 跨引擎可移植 | 标准定义，但实现少 | PostgreSQL 专属（生态广） |

## 支持矩阵

下面三张表覆盖 50+ 引擎，包括传统关系库、云数仓、HTAP/分布式 NewSQL、嵌入式数据库以及 SQL on stream 引擎。

### 通用支持矩阵：原生 range/multirange/PERIOD

| 引擎 | 原生 Range 类型 | Multirange 类型 | SQL:2011 PERIOD | 版本与备注 |
|------|----------------|-----------------|-----------------|-----------|
| PostgreSQL | 是（int4/int8/num/ts/tstz/date 等） | 是 | -- | 9.2+ range，14+ multirange |
| Greenplum | 是（继承 PG） | 14+ 起 | -- | Greenplum 7 基于 PG 12，仍无 multirange |
| CockroachDB | -- | -- | -- | 无 range 类型，需双列模拟 |
| YugabyteDB | -- | -- | -- | YSQL 兼容 PG 但暂未实现 range |
| Aurora PostgreSQL | 是 | 14+ 起 | -- | 完全继承 PG |
| Aurora DSQL | -- | -- | -- | 当前未提供 range 类型 |
| Cloud SQL for PG | 是 | 是 | -- | 完全继承 PG |
| AlloyDB | 是 | 是 | -- | 完全继承 PG |
| Neon | 是 | 是 | -- | 完全继承 PG |
| Supabase | 是 | 是 | -- | 完全继承 PG |
| Crunchy Bridge | 是 | 是 | -- | 完全继承 PG |
| TimescaleDB | 是（继承 PG） | 是（PG 14+ 起） | -- | 时间窗口场景 |
| Citus | 是（继承 PG） | 是 | -- | 分布式 PG |
| EDB Postgres Advanced | 是 | 是 | -- | PG 兼容栈 |
| OpenGauss | 部分（继承 PG 9.2） | -- | -- | range 已有，multirange 未跟进 |
| KingbaseES | 是 | 部分 | -- | 国产 PG 兼容 |
| GaussDB | 部分 | -- | -- | range 部分支持 |
| Oracle | -- | -- | 部分（12c+，主要时态） | `PERIOD FOR` 实现集中在 Temporal Validity / Flashback |
| IBM DB2 | -- | -- | 是（10.1+） | 应用时间段 + 系统时间段 |
| Teradata | 原生 PERIOD 类型 | -- | 是（SQL:2011 先驱，V13+） | PERIOD(DATE)/PERIOD(TIMESTAMP) |
| SQL Server | -- | -- | 仅 SYSTEM_TIME（无应用 PERIOD） | Temporal Tables 自 2016 起 |
| Azure SQL Database | -- | -- | 仅 SYSTEM_TIME | 同 SQL Server |
| Azure Synapse Dedicated SQL | -- | -- | -- | 不支持 |
| MySQL | -- | -- | -- | 双列 + 触发器 |
| MariaDB | -- | -- | 应用 PERIOD（10.4/10.5+） | 真正的应用 PERIOD + WITHOUT OVERLAPS（10.5）+ SYSTEM_VERSIONING |
| Percona Server | -- | -- | -- | MySQL 派生 |
| TiDB | -- | -- | -- | MySQL 兼容；range 仅指分区 range |
| OceanBase | -- | -- | -- | MySQL/Oracle 兼容模式都不支持应用 PERIOD |
| PolarDB MySQL | -- | -- | -- | 不支持 |
| PolarDB PostgreSQL | 是（继承 PG） | 是 | -- | 完全继承 PG |
| SQLite | -- | -- | -- | 双列模拟 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | 部分（PERIOD/SYSTEM_VERSIONING 关键字解析） | 接近 SQL:2011 |
| Firebird | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Informix | -- | -- | -- | 内置 INTERVAL 但非 range |
| SAP HANA | -- | -- | -- | TEMPORAL TABLE 但无应用 PERIOD |
| SAP IQ | -- | -- | -- | 不支持 |
| Snowflake | -- | -- | -- | 双列；提供 OVERLAPS 谓词 |
| BigQuery | RANGE\<T\>（GA 2024） | -- | -- | RANGE\<DATE\>/RANGE\<DATETIME\>/RANGE\<TIMESTAMP\>，2024 GA |
| Redshift | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | 不支持 |
| Greenplum 7 | 是（继承 PG 12） | -- | -- | range 完整，multirange 缺 |
| ClickHouse | -- | -- | -- | 双列；Tuple 表达近似 |
| Doris | -- | -- | -- | range 仅指分区策略 |
| StarRocks | -- | -- | -- | 同 Doris |
| Trino / Presto | -- | -- | -- | 没有 range 类型 |
| Athena | -- | -- | -- | Trino 派生，同上 |
| DuckDB | -- | -- | -- | 无内置 range 类型，借助 STRUCT 模拟 |
| MonetDB | -- | -- | -- | 无 range 类型 |
| Spark SQL / Databricks | -- | -- | -- | 无内置 range，可用 STRUCT |
| Hive | -- | -- | -- | 无 range；分区 range 仅指 PARTITION BY RANGE |
| Impala | -- | -- | -- | 无 range |
| Flink SQL | -- | -- | -- | 无 range；窗口语义另由 TUMBLE/HOP 提供 |
| Materialize | -- | -- | -- | 兼容 PG 但 range 类型缺失 |
| RisingWave | -- | -- | -- | 兼容 PG 但 range 缺失 |
| Druid | -- | -- | -- | 时间区间用 interval 字符串表达 |
| Pinot | -- | -- | -- | 无 |
| Kylin | -- | -- | -- | 无 |
| InfluxDB（SQL/IOX） | -- | -- | -- | 时间过滤用 BETWEEN |
| QuestDB | -- | -- | -- | 时间过滤用 SAMPLE BY |
| Spanner | -- | -- | -- | 不支持；可用 INTERVAL（不同概念） |
| CrateDB | int range（部分） | -- | -- | 仅 INTEGER 区间字面量，运算受限 |
| Yellowbrick | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | 不支持 |
| Databend | -- | -- | -- | 不支持 |

> 统计：只有 PostgreSQL 系（含完全兼容的云托管/分布式分支）提供完整的 range + multirange 类型；BigQuery 在 2024 年补上 `RANGE<T>` 但暂无 multirange；SQL:2011 PERIOD 阵营主要是 Teradata、DB2、MariaDB；Oracle/SQL Server 的 PERIOD 限定在系统/时态场景。

### Range 运算符与索引支持

| 引擎 | && 重叠 | @> 包含 | <@ 被包含 | + 并集 | - 差集 | * 交集 | -|- 相邻 | GiST | SP-GiST |
|------|---------|---------|-----------|--------|--------|--------|---------|------|---------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是（14+ 返回 multirange） | 是 | 是 | 是 | 是（PG 14+） |
| Greenplum 7 | 是 | 是 | 是 | 是 | 是（不连续报错） | 是 | 是 | 是 | -- |
| Aurora PG / Cloud SQL / AlloyDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| Citus / TimescaleDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| KingbaseES / EDB Adv | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 部分 |
| OpenGauss | 是（运算符未全） | 是 | 是 | 是 | 部分 | 是 | 是 | 是 | -- |
| BigQuery RANGE\<T\> | 是（`RANGE_OVERLAPS`） | 是（`RANGE_CONTAINS`） | -- | 是（`RANGE_UNION`，相邻或重叠才合法） | 是（`RANGE_INTERSECT` 取交集） | 是（`RANGE_INTERSECT`） | -- | -- | -- |
| Teradata PERIOD | `OVERLAPS` | `CONTAINS` | `MEETS`（含相邻） | `P_NORMALIZE` | `P_DIFFERENCE` | `P_INTERSECT` | `MEETS` | -- | -- |
| IBM DB2 PERIOD | `OVERLAPS` | `CONTAINS` | -- | -- | -- | -- | -- | -- | -- |
| MariaDB PERIOD | `WITHOUT OVERLAPS` | -- | -- | -- | `FOR PORTION OF` 拆行 | -- | -- | -- | -- |
| Oracle PERIOD | `OVERLAPS` | -- | -- | -- | -- | -- | -- | -- | -- |
| SQL Server SYSTEM_TIME | -- | -- | -- | -- | -- | -- | -- | -- | -- |

### 高阶能力：multirange、range_agg、EXCLUDE

| 引擎 | multirange 类型 | range_agg | range_intersect_agg | EXCLUDE WITH（无重叠约束） | 范围 GIN/GiST 索引 |
|------|-----------------|-----------|---------------------|---------------------------|--------------------|
| PostgreSQL 14+ | 是 | 是 | 是 | 是 | GiST + SP-GiST |
| PostgreSQL 9.2-13 | -- | -- | -- | 是（基于 range） | GiST |
| Greenplum 7 | -- | -- | -- | 是 | GiST |
| Citus / TimescaleDB | 是（继承 PG 14+） | 是 | 是 | 是 | GiST + SP-GiST |
| Aurora PG / Cloud SQL / AlloyDB / Neon / Supabase | 是 | 是 | 是 | 是 | GiST + SP-GiST |
| EDB Postgres Advanced | 是 | 是 | 是 | 是 | GiST |
| KingbaseES | 部分 | 部分 | -- | 部分 | GiST |
| OpenGauss | -- | -- | -- | 部分 | -- |
| BigQuery | -- | -- | -- | -- | -- |
| Teradata PERIOD | -- | `EXPAND ON` 类似 | -- | 通过自定义约束 | -- |
| MariaDB | -- | -- | -- | `WITHOUT OVERLAPS` | -- |
| Oracle | -- | -- | -- | -- | -- |
| DB2 | -- | -- | -- | -- | -- |

> 关键观察：multirange + range_agg 是 PostgreSQL 14+ 的独占能力；其他引擎要做"合并连续区间"或"找空隙"的查询，要么手写递归 CTE，要么在应用层做。

## 各引擎深入

### PostgreSQL：参考实现

PostgreSQL 9.2（2012）引入 6 种内置 range 类型：

| 内置 range | 元素类型 | 典型用途 |
|------------|----------|----------|
| `int4range` | `integer` | 数字段、ID 区间 |
| `int8range` | `bigint` | 大编号段、字节偏移区间 |
| `numrange` | `numeric` | 浮点/任意精度区间 |
| `daterange` | `date` | 日历日期区间 |
| `tsrange` | `timestamp` | 不带时区的时间戳区间 |
| `tstzrange` | `timestamptz` | 带时区的时间戳区间 |

PostgreSQL 14（2021）配套引入 6 种 multirange 类型：`int4multirange`/`int8multirange`/`nummultirange`/`datemultirange`/`tsmultirange`/`tstzmultirange`。

```sql
-- 创建 range 列
CREATE TABLE bookings (
    booking_id SERIAL PRIMARY KEY,
    room_id INT,
    stay tstzrange
);

-- 字面量与构造函数
INSERT INTO bookings (room_id, stay) VALUES
    (101, '[2026-04-25 14:00, 2026-04-26 11:00)'),
    (102, tstzrange('2026-04-25 14:00+08', '2026-04-27 11:00+08', '[)')),
    (101, tstzrange(NULL, '2026-04-25 11:00+08', '(]'));   -- 无下界

-- 边界规范化（离散类型）
SELECT int4range(1, 10, '[]');     -- → [1,11)
SELECT daterange('2026-01-01', '2026-12-31', '[]');  -- → [2026-01-01,2027-01-01)

-- 端点提取
SELECT lower('[3,9)'::int4range), upper('[3,9)'::int4range);  -- 3 | 9
SELECT lower_inc('[3,9)'::int4range), upper_inc('[3,9)'::int4range);  -- t | f
SELECT isempty('(5,5)'::int4range);  -- t
SELECT isempty('[5,5]'::int4range);  -- f（一个点也是非空）
```

#### 自定义 range 类型

```sql
-- 通过 CREATE TYPE ... AS RANGE 自定义子类型
CREATE TYPE floatrange AS RANGE (
    subtype = float8,
    subtype_diff = float8mi,
    multirange_type_name = floatmultirange     -- PG 14+
);

SELECT floatrange(1.5, 3.7);
```

#### 索引

PostgreSQL 为 range 类型同时支持 GiST 与 SP-GiST：

```sql
-- GiST 索引（PG 9.2+）
CREATE INDEX idx_bookings_stay_gist ON bookings USING gist (stay);

-- SP-GiST 索引（PG 14+ 起对 range 支持更全）
CREATE INDEX idx_bookings_stay_spgist ON bookings USING spgist (stay);

-- 联合索引：room_id + range，需要 btree_gist 扩展
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE INDEX idx_bookings_room_stay ON bookings USING gist (room_id, stay);
```

GiST vs SP-GiST 的取舍：
- GiST 是平衡树，写入更便宜，对偏斜分布友好
- SP-GiST 是空间分区树，对数据分布均匀的 range 查询更快
- 实际项目通常默认 GiST；当 range 集中在某几个区域时用 SP-GiST

#### EXCLUDE 约束

EXCLUDE 是 PostgreSQL 把"无重叠约束"通用化的关键设计：UNIQUE 是 EXCLUDE 的特例（运算符为 `=`），而把 `=` 换成 `&&` 就变成了"任意两行的 range 不重叠"。

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE meeting_rooms (
    room_id INT,
    purpose TEXT,
    period tstzrange,
    EXCLUDE USING gist (
        room_id WITH =,
        period WITH &&
    ) WHERE (NOT isempty(period))     -- WHERE 子句是部分约束
);
```

EXCLUDE 约束是真正的并发安全约束：插入时 GiST 索引在事务内 check & insert 是原子的，无需 SERIALIZABLE 隔离级别，无需触发器。

### PostgreSQL 14+ Multirange 详解

```sql
-- 字面量：花括号包裹一组 range
SELECT '{[1,3),[5,9)}'::int4multirange;

-- 构造函数（注意是 multirange 类型同名函数）
SELECT int4multirange(int4range(1,3), int4range(5,9));

-- multirange 与 range 互转
SELECT '[1,5)'::int4range::int4multirange;     -- → {[1,5)}
SELECT range_merge('{[1,3),[5,9)}'::int4multirange);  -- → [1,9)

-- 集合运算：闭合化
SELECT '[1,10)'::int4range - '[3,5)'::int4range;
-- → {[1,3),[5,10)}    PG 14 起返回 multirange

-- multirange 之间的运算
SELECT '{[1,5),[7,9)}'::int4multirange + '{[4,8),[12,15)}'::int4multirange;
-- → {[1,9),[12,15)}

SELECT '{[1,10)}'::int4multirange - '{[2,4),[6,8)}'::int4multirange;
-- → {[1,2),[4,6),[8,10)}

-- @> / <@ / && 同样适用
SELECT '{[1,5),[8,12)}'::int4multirange @> 9;   -- true
SELECT '[3,4)'::int4range <@ '{[1,5),[8,12)}'::int4multirange;  -- true

-- multirange 的 unnest 拆成多行 range
SELECT * FROM unnest('{[1,3),[5,9)}'::int4multirange) AS r;
--      r
-- ---------
--  [1,3)
--  [5,9)
```

#### range_agg：把行集合并为 multirange

```sql
-- range_agg 把分组中的多个 range 合并为一个 multirange，自动合并相邻/重叠
SELECT room_id, range_agg(stay) AS occupied
FROM bookings
GROUP BY room_id;
--  room_id |              occupied
-- ---------+-------------------------------------
--      101 | {[2026-04-25 14:00, 2026-04-26 11:00)}
--      102 | {[2026-04-25 14:00, 2026-04-27 11:00)}

-- 与 generate_series 搭配，找出某天剩余的可用空闲段
WITH day AS (
    SELECT tstzrange('2026-04-25 00:00+08', '2026-04-26 00:00+08') AS d
),
busy AS (
    SELECT range_agg(stay) AS occupied FROM bookings WHERE room_id = 101
)
SELECT day.d - busy.occupied AS free_windows
FROM day, busy;
-- → {[2026-04-25 00:00, 2026-04-25 14:00),[2026-04-26 11:00, 2026-04-26 00:00)}
-- 注意：上界跨日时仍由 day.d 限制
```

#### range_intersect_agg：求所有 range 的公共交集

```sql
-- 找出所有人都空闲的时间段
SELECT range_intersect_agg(free_window) AS common_free
FROM employee_free_windows;
```

### Greenplum / TimescaleDB / Citus / Aurora PostgreSQL

这些 PostgreSQL 派生引擎和云托管完全继承 range/multirange 能力，差异主要体现在：

- **Greenplum 6**（基于 PG 9.4）支持 range，但**没有** multirange
- **Greenplum 7**（基于 PG 12）支持 range 但仍**未引入** multirange（需要 PG 14 才有）
- **TimescaleDB** 把 range 用作时间窗口聚合的辅助类型，hypertable 自身用的是连续时间列
- **Citus** 在分布式环境支持 EXCLUDE 约束，但**仅在 colocation 列与约束列一致时**有效
- **Aurora PostgreSQL / Cloud SQL / AlloyDB / Neon / Supabase / Crunchy Bridge** 与官方 PG 行为一致

```sql
-- Citus：分布键必须包含在 EXCLUDE 中
SELECT create_distributed_table('reservations', 'room_id');
ALTER TABLE reservations ADD EXCLUDE USING gist (room_id WITH =, stay WITH &&);
-- 因为分布键 room_id 已在约束中，本约束在每个 shard 内独立生效
```

### CockroachDB / YugabyteDB

YSQL（YugabyteDB 的 PG 兼容层）和 CockroachDB SQL 都标榜 PG 兼容，但 range/multirange 类型尚未实现：

```sql
-- CockroachDB / YugabyteDB（截至 2026 年）
CREATE TABLE bookings (room_id INT, stay daterange);
-- ERROR: type "daterange" does not exist
```

替代做法是双列 + CHECK 约束 + 应用层无重叠校验。

### BigQuery RANGE\<T\>（2024 年 GA）

BigQuery 在 2024 年正式 GA 了 `RANGE<T>` 类型，是 PG 之外少数提供原生 range 类型的云数仓：

```sql
-- 类型与字面量
CREATE TABLE my_dataset.events (
    event_id INT64,
    valid RANGE<DATE>
);

INSERT INTO my_dataset.events VALUES
    (1, RANGE<DATE> '[2026-01-01, 2026-12-31)'),
    (2, RANGE(DATE '2026-03-01', DATE '2026-09-01'));

-- 仅支持 DATE / DATETIME / TIMESTAMP 三种元素类型
-- 不支持 INT64 / NUMERIC range；不支持 multirange

-- 端点提取
SELECT RANGE_START(valid), RANGE_END(valid) FROM my_dataset.events;

-- 包含与重叠（函数式语法，无运算符）
SELECT * FROM my_dataset.events
WHERE RANGE_CONTAINS(valid, DATE '2026-06-01');

SELECT a.event_id, b.event_id
FROM my_dataset.events a, my_dataset.events b
WHERE a.event_id < b.event_id
  AND RANGE_OVERLAPS(a.valid, b.valid);

-- 集合运算
SELECT RANGE_INTERSECT(
    RANGE<DATE> '[2026-01-01, 2026-06-01)',
    RANGE<DATE> '[2026-03-01, 2026-09-01)'
);
-- → [2026-03-01, 2026-06-01)

SELECT RANGE_UNION(           -- 并集，仅相邻或重叠时合法
    RANGE<DATE> '[2026-01-01, 2026-04-01)',
    RANGE<DATE> '[2026-04-01, 2026-07-01)'
);
-- → [2026-01-01, 2026-07-01)

-- GENERATE_RANGE_ARRAY 把 range 拆为元素数组
SELECT GENERATE_RANGE_ARRAY(
    RANGE<DATE> '[2026-04-01, 2026-04-05)',
    INTERVAL 1 DAY
);
-- → [2026-04-01, 2026-04-02, 2026-04-03, 2026-04-04]
```

BigQuery 的 RANGE 类型有几个限制：
- 不支持泛型 `RANGE<INT64>` 或 `RANGE<NUMERIC>`
- 没有 multirange，差集运算返回 ARRAY\<RANGE\>
- 没有 EXCLUDE 约束（BigQuery 整体没有传统约束系统）
- 没有专用索引（依赖列存扫描）

### Teradata：SQL:2011 PERIOD 的实践先驱

Teradata V13（2009）就引入了 PERIOD 数据类型，比 SQL:2011 标准更早。

```sql
-- PERIOD 数据类型
CREATE TABLE policy (
    policy_id INTEGER,
    policy_type CHAR(2),
    valid PERIOD(DATE)         -- PERIOD(TIMESTAMP) 也可
);

INSERT INTO policy VALUES (1, 'A1', PERIOD(DATE '2024-01-01', DATE '2025-01-01'));

-- 端点提取
SELECT BEGIN(valid), END(valid), LAST(valid) FROM policy;
-- LAST() 返回闭区间右端点（END - 1 day）

-- 重叠 / 包含 / 相邻
SELECT * FROM policy
WHERE valid OVERLAPS PERIOD(DATE '2024-06-01', DATE '2024-12-31');

SELECT * FROM policy
WHERE valid CONTAINS DATE '2024-09-15';

SELECT * FROM policy a, policy b
WHERE a.policy_id <> b.policy_id
  AND a.valid MEETS b.valid;     -- 严格相邻

-- PERIOD 算术
SELECT P_INTERSECT(
    PERIOD(DATE '2024-01-01', DATE '2024-09-01'),
    PERIOD(DATE '2024-06-01', DATE '2025-03-01')
);
-- → ('2024-06-01', '2024-09-01')

SELECT P_NORMALIZE(             -- 合并相邻/重叠
    PERIOD(DATE '2024-01-01', DATE '2024-06-01'),
    PERIOD(DATE '2024-06-01', DATE '2024-09-01')
);
-- → ('2024-01-01', '2024-09-01')

SELECT P_DIFFERENCE(
    PERIOD(DATE '2024-01-01', DATE '2024-12-31'),
    PERIOD(DATE '2024-06-01', DATE '2024-08-31')
);
-- 返回多个 PERIOD（Teradata 用结果集表示）

-- EXPAND ON：把 PERIOD 拆为多行
SELECT policy_id, BEGIN(p) AS d
FROM policy
EXPAND ON valid AS p BY ANCHOR MONTH_BEGIN;
-- 把 valid 按月拆分成多行
```

Teradata 的 PERIOD 是真类型，但生态里它只跟时间相关——不存在 `PERIOD(INTEGER)` 之类的通用范围类型。

### IBM DB2

DB2 10.1（2012）实现了 SQL:2011 的应用 PERIOD 与系统 PERIOD：

```sql
CREATE TABLE policy_history (
    policy_id INT NOT NULL,
    coverage VARCHAR(20),
    business_start DATE NOT NULL,
    business_end   DATE NOT NULL,
    PERIOD BUSINESS_TIME(business_start, business_end),
    PRIMARY KEY (policy_id, BUSINESS_TIME WITHOUT OVERLAPS)
);

-- 应用时间段查询
SELECT * FROM policy_history
FOR BUSINESS_TIME AS OF DATE '2024-09-15'
WHERE policy_id = 1;

-- FOR BUSINESS_TIME BETWEEN
SELECT * FROM policy_history
FOR BUSINESS_TIME BETWEEN DATE '2024-01-01' AND DATE '2024-12-31';

-- 同时定义 SYSTEM_TIME 和 BUSINESS_TIME → 双时态表
CREATE TABLE bitemporal_policy (
    policy_id INT NOT NULL,
    coverage VARCHAR(20),
    business_start DATE NOT NULL,
    business_end   DATE NOT NULL,
    sys_start  TIMESTAMP(12) GENERATED ALWAYS AS ROW BEGIN NOT NULL,
    sys_end    TIMESTAMP(12) GENERATED ALWAYS AS ROW END NOT NULL,
    trans_id   TIMESTAMP(12) GENERATED ALWAYS AS TRANSACTION START ID,
    PERIOD BUSINESS_TIME(business_start, business_end),
    PERIOD SYSTEM_TIME(sys_start, sys_end),
    PRIMARY KEY (policy_id, BUSINESS_TIME WITHOUT OVERLAPS)
);
```

DB2 的 PERIOD 与 SQL:2011 一致：底层仍是两列，PERIOD 是元数据；`WITHOUT OVERLAPS` 在 PRIMARY KEY/UNIQUE 中可用。

### Oracle：Temporal Validity 与 Flashback

Oracle 12c（2013）引入 Temporal Validity，提供 SQL:2011 风格的 PERIOD：

```sql
CREATE TABLE employees (
    emp_id NUMBER PRIMARY KEY,
    name   VARCHAR2(100),
    valid_start DATE,
    valid_end   DATE,
    PERIOD FOR validity_period (valid_start, valid_end)
);

-- 隐式可见性筛选（会话级别开关）
EXEC DBMS_FLASHBACK_ARCHIVE.ENABLE_AT_VALID_TIME('AS OF', SYSDATE);
SELECT * FROM employees;        -- 自动加 WHERE validity_period CONTAINS SYSDATE

-- PERIOD 谓词
SELECT * FROM employees AS OF PERIOD FOR validity_period DATE '2024-09-15';

SELECT * FROM employees
VERSIONS PERIOD FOR validity_period BETWEEN DATE '2024-01-01' AND DATE '2024-12-31';
```

Oracle 的 Temporal Validity：
- 没有真正的 PERIOD 数据类型，仅元数据
- 没有 `WITHOUT OVERLAPS` 约束
- 没有 `OVERLAPS` 之外的标准 PERIOD 谓词（虽 OVERLAPS 是更早的 SQL 标准已支持）
- 重叠语义需要用户在应用层确保

### SQL Server / Azure SQL：仅 SYSTEM_TIME

SQL Server 2016 引入的 Temporal Tables 只用于"系统版本化"，不是通用的应用 PERIOD：

```sql
CREATE TABLE Employees (
    EmpID INT PRIMARY KEY,
    Name NVARCHAR(100),
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo   DATETIME2 GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.EmployeesHistory));

-- 时态查询
SELECT * FROM Employees FOR SYSTEM_TIME AS OF '2024-09-15';
SELECT * FROM Employees FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-12-31';
SELECT * FROM Employees FOR SYSTEM_TIME ALL;
```

SQL Server 的限制：
- `PERIOD FOR` 只能与 `SYSTEM_TIME` 搭配，不能定义应用 PERIOD
- ValidFrom/ValidTo 的值由数据库自动管理，应用不能直接写
- 不支持 `WITHOUT OVERLAPS` 约束、`FOR PORTION OF` DML

### MariaDB：应用 PERIOD + SYSTEM_VERSIONING 双轨

MariaDB 是 MySQL 系里唯一实现 SQL:2011 应用 PERIOD 的引擎：

```sql
-- 应用时间段（10.4 起 PERIOD FOR / 10.5 起 WITHOUT OVERLAPS）
CREATE TABLE prices (
    product_id INT,
    price DECIMAL(10,2),
    valid_from DATE,
    valid_to   DATE,
    PERIOD FOR valid (valid_from, valid_to),
    PRIMARY KEY (product_id, valid WITHOUT OVERLAPS)
);

INSERT INTO prices VALUES (1, 9.99, '2026-01-01', '2026-06-01');
INSERT INTO prices VALUES (1, 8.99, '2026-04-01', '2026-09-01');
-- ERROR 4025 (23000): CONSTRAINT `PRIMARY` failed for `db`.`prices`

-- FOR PORTION OF：按时间段拆分行
DELETE FROM prices
FOR PORTION OF valid FROM '2026-03-01' TO '2026-04-15'
WHERE product_id = 1;
-- 自动把 [2026-01-01, 2026-06-01) 拆成 [2026-01-01,2026-03-01)+[2026-04-15,2026-06-01)

UPDATE prices
FOR PORTION OF valid FROM '2026-02-01' TO '2026-04-01'
SET price = price * 0.9
WHERE product_id = 1;

-- SYSTEM_VERSIONING：MariaDB 10.3+
CREATE TABLE accounts (
    id INT PRIMARY KEY,
    balance DECIMAL(10,2)
) WITH SYSTEM VERSIONING;

SELECT * FROM accounts FOR SYSTEM_TIME AS OF '2024-09-15 00:00:00';
```

MariaDB 的应用 PERIOD 用主键里的 `WITHOUT OVERLAPS` 充当无重叠约束，是 PG `EXCLUDE WITH &&` 的标准化版本。底层仍是两列 + 自动检查。

### MySQL / Percona / TiDB / OceanBase

MySQL 系（含派生）至今不支持 range 类型也不支持应用 PERIOD：

```sql
-- 通用替代：双列 + CHECK + 触发器（伪 EXCLUDE）
CREATE TABLE reservations (
    room_id INT,
    check_in  DATE,
    check_out DATE,
    CHECK (check_in < check_out)
);

DELIMITER //
CREATE TRIGGER no_overlap BEFORE INSERT ON reservations
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM reservations
        WHERE room_id = NEW.room_id
          AND check_in  < NEW.check_out
          AND check_out > NEW.check_in
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reservation overlap';
    END IF;
END //
DELIMITER ;

-- 注意：触发器无法防御并发竞态，必须在 SERIALIZABLE 下才安全
```

OceanBase 在 Oracle 兼容模式下也没有提供 Temporal Validity，需要手写约束。

### CrateDB

CrateDB 提供整数区间字面量但没有完整的 range 类型系统：

```sql
-- INT_RANGE 字面量（4.x 起）
INSERT INTO t (col) VALUES ('[1,10)'::int_range);

-- 仅支持 int_range；没有 daterange/tstzrange
-- 没有运算符 &&、@>，只能用 lower/upper 函数模拟
SELECT lower(col), upper(col) FROM t;
```

### DuckDB / ClickHouse / Snowflake / Trino：双列 + 函数

这些分析引擎都没有 range 类型，但提供了一些近似能力：

```sql
-- DuckDB / Snowflake / Trino：使用 OVERLAPS 谓词（SQL 标准早期就有）
SELECT *
FROM bookings a, bookings b
WHERE a.room_id = b.room_id
  AND a.booking_id < b.booking_id
  AND (a.start_time, a.end_time) OVERLAPS (b.start_time, b.end_time);

-- ClickHouse：用 Tuple 表达 + 自定义函数
SELECT (start_time, end_time) AS p
FROM bookings
WHERE NOT (end_time <= '2026-04-25' OR start_time >= '2026-04-26');

-- Snowflake：CONTAINS_WITHIN 不存在，需要双列布尔表达
SELECT *
FROM bookings
WHERE start_time <= '2026-04-25' AND end_time > '2026-04-25';
```

### Spark SQL / Databricks / Hive / Flink SQL

这些引擎的"range"指分区策略中的 `PARTITION BY RANGE` 或 `RANGE BETWEEN`（窗口函数），与本文讨论的 range 数据类型不是同一概念：

```sql
-- Spark SQL：分区 RANGE 与窗口 RANGE 都是别的东西
CREATE TABLE events (event_time TIMESTAMP, value DOUBLE)
USING parquet
PARTITIONED BY (DATE(event_time));

-- 窗口函数中的 RANGE：值范围而不是行数
SELECT *,
       AVG(value) OVER (
           ORDER BY event_time
           RANGE BETWEEN INTERVAL 1 HOUR PRECEDING AND CURRENT ROW
       ) AS rolling_avg
FROM events;
```

### Snowflake：OVERLAPS 谓词与 RANGE_INTERSECT

```sql
-- Snowflake 没有 range 类型，但有针对 INTERVAL 与时间戳对的 OVERLAPS
SELECT *
FROM time_slots a JOIN time_slots b
  ON a.id < b.id
 AND (a.start_ts, a.end_ts) OVERLAPS (b.start_ts, b.end_ts);
```

### Materialize / RisingWave

虽然标榜 PG 兼容，目前 range 类型都不在第一优先级：

```sql
-- Materialize 0.x
CREATE TABLE t (col tstzrange);
-- ERROR: type "tstzrange" does not exist
```

## Range 运算符深入

### && 重叠（overlap）

`a && b` 当且仅当 `a` 与 `b` 至少有一个公共元素：

```
a:        [1,5)
b:           [4,9)
a && b: true            (公共元素为 [4,5))

a:        [1,5)
b:             [5,9)
a && b: false           (5 不在 a 中，因为右开)

a:        [1,5)
b:             (5,9)    -- 注意 b 左开
a && b: false
```

实现层面，`a && b` 的判断公式为：

```
NOT (a.upper <= b.lower OR b.upper <= a.lower)
↔  a.lower < b.upper AND b.lower < a.upper      （左闭右开规范化后）
```

EXCLUDE WITH `&&` 是无重叠约束的核心。

### @> / <@ 包含与被包含

```sql
-- 范围包含值
SELECT '[1,10)'::int4range @> 5;      -- t
SELECT '[1,10)'::int4range @> 10;     -- f（右开）

-- 范围包含范围
SELECT '[1,10)'::int4range @> '[3,8)'::int4range;   -- t
SELECT '[1,10)'::int4range @> '[3,12)'::int4range;  -- f
SELECT '[1,10)'::int4range @> 'empty'::int4range;   -- t（空集是任何集合的子集）

-- multirange 同样适用
SELECT '{[1,5),[8,12)}'::int4multirange @> 9;       -- t
SELECT '{[1,5),[8,12)}'::int4multirange @> '[2,4)'::int4range;  -- t
SELECT '{[1,5),[8,12)}'::int4multirange @> '[2,9)'::int4range;  -- f
```

### -|- 相邻（adjacent）

`a -|- b` 当且仅当 `a` 与 `b` 不重叠且并集是连续的：

```sql
SELECT '[1,5)'::int4range -|- '[5,10)'::int4range;   -- t（5 是共同边界）
SELECT '[1,5)'::int4range -|- '[6,10)'::int4range;   -- f（中间有 5）
SELECT '[1,5]'::int4range -|- '[5,10)'::int4range;   -- 规范化后变成 [1,6) 与 [5,10) → 重叠 → false

-- 在合并连续段时非常有用
SELECT a.id, b.id
FROM segments a JOIN segments b ON a.id < b.id
WHERE a.range -|- b.range;
```

### + / * / - 集合运算

```sql
-- 并集（要求两 range 重叠或相邻）
SELECT '[1,5)'::int4range + '[4,10)'::int4range;     -- [1,10)
SELECT '[1,5)'::int4range + '[7,10)'::int4range;     -- ERROR: result of range union would not be contiguous

-- 交集
SELECT '[1,5)'::int4range * '[3,8)'::int4range;      -- [3,5)
SELECT '[1,5)'::int4range * '[6,8)'::int4range;      -- empty

-- 差集（PG 14+ 在不连续时返回 multirange）
SELECT '[1,10)'::int4range - '[3,5)'::int4range;     -- {[1,3),[5,10)}（multirange）

-- 在 PG 13 及更早，差集不连续时直接报错
```

### lower / upper / lower_inc / upper_inc / isempty

```sql
SELECT lower('[3,9)'::int4range);          -- 3
SELECT upper('[3,9)'::int4range);          -- 9
SELECT lower_inc('[3,9)'::int4range);      -- t
SELECT upper_inc('[3,9)'::int4range);      -- f
SELECT isempty('(5,5)'::int4range);        -- t
SELECT lower_inf('(,9)'::int4range);       -- t（无下界）
SELECT upper_inf('[3,)'::int4range);       -- t（无上界）
```

### 位置比较：`<<`, `>>`, `&<`, `&>`

```sql
SELECT '[1,5)'::int4range << '[6,10)'::int4range;     -- t（a 严格在 b 左侧）
SELECT '[1,5)'::int4range >> '[6,10)'::int4range;     -- f
SELECT '[1,5)'::int4range &< '[3,10)'::int4range;     -- t（a 不延伸到 b 右侧）
SELECT '[1,5)'::int4range &> '[3,10)'::int4range;     -- f
```

这些运算符在地理空间和时间序列分析里有用，例如"找出在某时间点之前结束的所有任务"。

## Multirange 用例

### 用例 1：可用窗口的空隙检测（gap detection）

```sql
-- 一个会议室一天的所有占用记录
CREATE TABLE meeting_slots (
    room_id INT,
    period tstzrange
);

INSERT INTO meeting_slots VALUES
    (1, '[2026-04-25 09:00+08, 2026-04-25 10:00+08)'),
    (1, '[2026-04-25 10:30+08, 2026-04-25 12:00+08)'),
    (1, '[2026-04-25 14:00+08, 2026-04-25 15:30+08)');

-- 找出 09:00-18:00 之间所有空闲段
WITH workday AS (
    SELECT tstzrange('2026-04-25 09:00+08', '2026-04-25 18:00+08') AS day
),
busy AS (
    SELECT range_agg(period) AS occupied
    FROM meeting_slots
    WHERE room_id = 1
)
SELECT day - occupied AS free_windows
FROM workday, busy;
-- → {[2026-04-25 10:00, 2026-04-25 10:30),
--    [2026-04-25 12:00, 2026-04-25 14:00),
--    [2026-04-25 15:30, 2026-04-25 18:00)}
```

在 PostgreSQL 13 及更早，需要写复杂的 LAG + 自连接逻辑：

```sql
-- 旧式做法（PG 13 及更早）
WITH ordered AS (
    SELECT period, lag(upper(period)) OVER (ORDER BY lower(period)) AS prev_end
    FROM meeting_slots WHERE room_id = 1
)
SELECT tstzrange(prev_end, lower(period)) AS gap
FROM ordered
WHERE prev_end IS NOT NULL AND prev_end < lower(period);
```

### 用例 2：员工任职区间合并

```sql
-- 员工的多段任职（可能同公司同部门多次入职）
CREATE TABLE employment (
    emp_id INT,
    company TEXT,
    period daterange
);

-- 计算每个员工在每家公司的"实际任职 multirange"
SELECT emp_id, company, range_agg(period) AS total_employment
FROM employment
GROUP BY emp_id, company;
-- 自动合并相邻、重叠的区间
```

### 用例 3：所有人都空闲的公共时段

```sql
-- 每个员工自己的空闲 multirange
CREATE TABLE free_time (
    emp_id INT,
    free tstzrange
);

-- 所有人的公共空闲段
SELECT range_intersect_agg(free) AS common_free
FROM free_time
WHERE emp_id IN (SELECT emp_id FROM team WHERE team_id = 7);
```

### 用例 4：无重叠约束的并发安全保证

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE seat_reservations (
    show_id INT,
    seat_no INT,
    period tstzrange,
    user_id BIGINT,
    EXCLUDE USING gist (
        show_id WITH =,
        seat_no WITH =,
        period WITH &&
    )
);

-- 两个并发事务尝试预订同一座位的重叠时段
-- T1: INSERT (1, 5, '[19:00, 21:00)', 100);
-- T2: INSERT (1, 5, '[20:00, 22:00)', 200);
-- T2 在提交时被 GiST 索引拒绝：conflicting key value violates exclusion constraint
-- 不需要应用层加锁，不需要 SERIALIZABLE 隔离级别
```

### 用例 5：API 限速窗口

```sql
-- 每个用户的速率限制：把每次调用记一条 range
CREATE TABLE rate_log (
    user_id BIGINT,
    period tstzrange   -- 通常是单点：[t, t+1ms)
);

-- 检查最近 1 分钟的调用次数
SELECT count(*) FROM rate_log
WHERE user_id = 42
  AND period && tstzrange(now() - interval '1 minute', now());
```

## Range 字面量与边界规范化

### 边界类型

| 字面量 | 含义 |
|--------|------|
| `'[a,b]'` | 闭闭区间：a ≤ x ≤ b |
| `'[a,b)'` | 闭开区间：a ≤ x < b（最常用） |
| `'(a,b]'` | 开闭区间：a < x ≤ b |
| `'(a,b)'` | 开开区间：a < x < b |
| `'[a,]'` | 无上界：a ≤ x |
| `'[,b)'` | 无下界：x < b |
| `'(,)'` | 完全无界：所有元素 |
| `'empty'` | 空集 |

### 离散类型规范化

PostgreSQL 对离散类型（integer、date 等）会把闭区间规范化为左闭右开：

```sql
SELECT int4range(1, 5, '[]');     -- [1,6)
SELECT int4range(1, 5, '(]');     -- [2,6)
SELECT int4range(1, 5, '()');     -- [2,5)
SELECT int4range(1, 5, '[)');     -- [1,5)（已规范）

SELECT daterange('2026-01-01', '2026-12-31', '[]');
-- → [2026-01-01, 2027-01-01)

-- 连续类型（numeric、timestamp）不规范化
SELECT numrange(1.0, 5.0, '[]') = numrange(1.0, 5.0, '[)');
-- → false（连续类型上的 [] 与 [) 在右端点不同）
```

为什么离散类型要规范化？因为：

```
[1,5] 和 [1,6) 在 integer 上代表相同的元素集合 {1,2,3,4,5}
统一为 [1,6) 后，比较、合并、运算逻辑只需要考虑左闭右开一种形式
```

### 无界与空范围

```sql
SELECT '[3,)'::int4range;          -- [3,) 即 x ≥ 3
SELECT '(,)'::int4range;           -- 所有 integer
SELECT 'empty'::int4range;         -- 空集

SELECT '[3,)'::int4range @> 1000000000;     -- t
SELECT 'empty'::int4range @> 5;             -- f
SELECT 'empty'::int4range && '[1,5)'::int4range;   -- f
```

无界范围在表达"截至目前没有结束日期"时很有用：

```sql
-- 当前任职：upper 为无穷
INSERT INTO employment VALUES (42, 'ACME', '[2024-01-01,)');

-- 查询"现在仍在任职"
SELECT * FROM employment WHERE upper_inf(period);
SELECT * FROM employment WHERE period @> CURRENT_DATE;  -- 等价
```

## EXCLUDE 约束的工作原理

EXCLUDE 是 PostgreSQL 把"任意两行不能同时满足某些运算符"的约束统一表达：

```sql
EXCLUDE USING <index_method> (
    col1 WITH op1,
    col2 WITH op2,
    ...
) [WHERE (predicate)]
```

含义：表中任意两行 r1, r2，**不能**同时满足 `r1.col1 op1 r2.col1` AND `r1.col2 op2 r2.col2` AND ...

```sql
-- UNIQUE 是 EXCLUDE 的特例
ALTER TABLE t ADD UNIQUE (email);
-- 等价于
ALTER TABLE t ADD EXCLUDE USING btree (email WITH =);

-- 无重叠约束
ALTER TABLE bookings ADD EXCLUDE USING gist (
    room_id WITH =,
    stay WITH &&
);
-- 含义：不存在两行同 room_id 且 stay 重叠
```

EXCLUDE 的实现：
1. 在指定的 index_method 上为约束列建索引
2. 插入/更新时，遍历索引查找冲突候选
3. 在事务内做 check & insert，由索引的 page lock 保证原子

支持的 index_method：
- `btree`（仅 `=` 运算符）
- `hash`（仅 `=` 运算符）
- `gist`（支持 `&&`, `@>`, `<@` 等）
- `spgist`（PG 14+ 起支持 range 重叠）

`btree_gist` 扩展让 btree 支持的标量类型也能放入 gist 索引，因此 `room_id WITH =` 与 `stay WITH &&` 才能在同一个 gist 索引中。

## SQL:2011 PERIOD vs PostgreSQL Range：实现成本对比

| 实现方面 | SQL:2011 PERIOD | PostgreSQL Range |
|----------|-----------------|------------------|
| 类型系统改动 | 元数据（PERIOD FOR 子句） | 新增类型类别（range type generator） |
| 物理存储 | 复用现有标量列 | 新的二进制格式（lower/upper/flags） |
| 索引改动 | 复用 B-tree（PRIMARY KEY/UNIQUE 内的 WITHOUT OVERLAPS） | 必须实现 GiST/SP-GiST 算子族 |
| 约束系统 | 在 PRIMARY KEY/UNIQUE 中扩展 WITHOUT OVERLAPS | 新增 EXCLUDE 约束类（与 UNIQUE 解耦） |
| DDL 改动 | PERIOD FOR / WITHOUT OVERLAPS / FOR PORTION OF | CREATE TYPE ... AS RANGE / multirange_type_name |
| DML 改动 | DELETE/UPDATE FOR PORTION OF（自动拆行） | 用户自行写 SQL |
| 标准兼容 | SQL:2011 / SQL:2016 标准化 | 非标准（PG 专属） |
| 表达力 | 仅时间区间，仅 WITHOUT OVERLAPS | 通用 range，全套运算符代数 |
| 学习成本 | 低（看起来像两列） | 中（需要理解运算符与 GiST） |

引擎开发者选型建议：
- **优先 SQL:2011 PERIOD**：项目主要需求是无重叠约束 + 时态查询，且希望最小化对现有类型/索引/约束系统的改动
- **优先 PG Range**：希望提供通用的"区间值"语义，要支持丰富的集合运算与多范围类型

## 对引擎开发者的实现建议

### 1. Range 的内部表示

```rust
struct RangeValue<T> {
    lower: Option<T>,       // None = -infinity
    upper: Option<T>,       // None = +infinity
    lower_inclusive: bool,
    upper_inclusive: bool,
    is_empty: bool,         // 空范围标记
}
```

可优化点：
- 离散类型在构造时规范化为左闭右开，省去后续比较的边界判断分支
- 用一个 byte 的 flags 字段同时存 lower_inc/upper_inc/lower_inf/upper_inf/is_empty

### 2. GiST 算子族实现要点

GiST 索引对 range 类型的算子族需要实现：

| 算子 | GiST consistent 函数判断 |
|------|-------------------------|
| `&&` 重叠 | 子树边界框与查询 range 重叠 |
| `@>` 包含 | 子树边界框可能包含查询 range/值 |
| `<@` 被包含 | 子树边界框被查询 range 包含 |
| `-|-` 相邻 | 子树边界框与查询 range 相邻 |
| `=` 相等 | 边界框与查询 range 相等且无 wildcard |

边界框（union）函数：取所有子节点 range 的最小覆盖 range。

### 3. Multirange 的存储与运算

```rust
struct MultirangeValue<T> {
    ranges: Vec<RangeValue<T>>,    // 已排序、不重叠、不相邻的 range 序列
}
```

关键不变量：multirange 内部的 range 必须**已排序、两两不重叠、两两不相邻**。这意味着构造函数与运算符返回值必须做 normalize：

```
normalize:
  1. 按 lower 排序
  2. 合并相邻/重叠的 range（用 -|- 与 && 检查）
  3. 移除空 range
```

### 4. range_agg 的实现

range_agg 是聚合，可以用线性扫描 + 排序合并：

```rust
fn range_agg<T: Ord>(rows: impl Iterator<Item = RangeValue<T>>) -> MultirangeValue<T> {
    let mut sorted: Vec<_> = rows.filter(|r| !r.is_empty).collect();
    sorted.sort_by(|a, b| a.lower.cmp(&b.lower));
    let mut result = Vec::new();
    for r in sorted {
        if let Some(last) = result.last_mut() {
            if last.overlaps_or_adjacent(&r) {
                *last = last.union(&r);
                continue;
            }
        }
        result.push(r);
    }
    MultirangeValue { ranges: result }
}
```

并行实现：分组聚合时，每个 worker 局部 range_agg → 中间结果再做一次 normalize 合并。

### 5. EXCLUDE 约束的实现

EXCLUDE 与 UNIQUE 共享代码路径，区别仅在索引算子族：

```
INSERT 时:
  for each EXCLUDE constraint:
    打开约束的 GiST 索引
    用 (col1 op1 NEW.col1, col2 op2 NEW.col2, ...) 作为搜索条件
    if 找到任何已存在的行（不是 NEW 自己）:
      raise exclusion_violation
    把 NEW 插入索引（在事务内、有 page lock）
```

并发安全：与 B-tree UNIQUE 一样，靠索引 page 上的 lock 保证 check & insert 原子。

### 6. 与查询优化器的交互

- **行数估计**：range && range 的选择性一般估计为 0.05-0.15，可改进到基于直方图的 lower/upper 联合分布
- **谓词推理**：`a @> 5 AND a @> 10` 可以推断为 `a @> int4range(5,11,'[]')`
- **索引选择**：包含 `@>`/`&&` 的谓词优先考虑 GiST/SP-GiST 索引

### 7. multirange 与 range_agg 的优化

```
GROUP BY x → range_agg(period) 的执行：
  1. 局部预排序：每个 hash partition 内按 lower 排序
  2. 合并：扫描排序后的 range 序列，O(n) 合并
  3. 输出：按 group key 输出 multirange
  
比 array_agg + 应用层合并快 5-10 倍
```

### 8. 与 SQL:2011 PERIOD 的兼容层

如果引擎选择实现 SQL:2011 PERIOD，可以考虑提供一个内部的 range 适配层：

```
对外：PERIOD(start_col, end_col) 是元数据
内部：编译期把 (start_col, end_col) 视为 range
WITHOUT OVERLAPS → EXCLUDE WITH (group_cols WITH =, period WITH &&)
```

这样可以同时支持标准语法与丰富的内部运算。

## 性能与索引：基准对比

| 场景 | 双列 + B-tree | range + GiST | range + SP-GiST | multirange + GiST |
|------|--------------|--------------|-----------------|-------------------|
| 时间点查询（@> point） | 必须扫双列；可借用复合索引 | 索引查找 O(log n) | 更快 O(log n) | 不直接适用 |
| 时间段重叠（&&） | 复杂 OR 条件，索引利用差 | 索引扫 O(log n + k) | 同 GiST | 索引扫 O(log n + k) |
| 无重叠约束（写入） | 触发器或应用层；并发不安全 | EXCLUDE 原生支持 | 同 GiST | 不直接适用 |
| range_agg / 合并 | 应用层或 LAG/LEAD | 应用层 | 应用层 | 单 SQL 表达 |
| 数据规模 1M 行 @> 查询 | 100ms+ | 1-5ms | 1-3ms | -- |
| 数据规模 1M 行 && 查询 | 1s+ | 10-50ms | 10-30ms | -- |

注：以上数字是 PostgreSQL 在 NVMe 上的典型量级，仅用于相对比较。

## 设计争议与陷阱

### 1. 边界包含性的默认值

PostgreSQL 选择 `[)`（左闭右开）作为离散类型的规范形式，这与编程习惯（Python `range()`、Rust `0..n`）一致，方便表示"长度 n"。但这与人类直觉的"从 1 月 1 日到 12 月 31 日"不一样——后者通常理解为闭闭区间，需要显式 `[]` 并接受规范化为 `[1月1日, 次年1月1日)`。

陷阱：

```sql
-- 错误意图：希望表示 2026 全年
INSERT INTO t VALUES ('[2026-01-01, 2026-12-31)'::daterange);
-- 实际：不包含 12 月 31 日！

-- 正确：
INSERT INTO t VALUES ('[2026-01-01, 2027-01-01)'::daterange);
-- 或
INSERT INTO t VALUES (daterange('2026-01-01', '2026-12-31', '[]'));
-- 后者会被规范化为 [2026-01-01, 2027-01-01)
```

### 2. multirange 之前差集运算的失败

PG 13 及更早，差集结果不连续时直接报错：

```sql
-- PG 13
SELECT '[1,10)'::int4range - '[3,5)'::int4range;
-- ERROR: result of range difference would not be contiguous

-- PG 14+
SELECT '[1,10)'::int4range - '[3,5)'::int4range;
-- → {[1,3),[5,10)}
```

这一改动对 query 兼容是个隐患：从 13 升级到 14 后，原本会报错的差集表达式开始返回 multirange，可能改变下游列类型。

### 3. EXCLUDE 与分布式分片的冲突

CockroachDB 至今不支持 EXCLUDE 约束，YugabyteDB 支持但限制多。原因是：跨分片的 GiST 索引一致性维护成本极高，必须做分布式锁或全局索引。

Citus 通过"约束列必须包含分布键"绕过这个问题——这样所有候选冲突行都在同一 shard 内。

### 4. 时区与 tstzrange 的陷阱

```sql
-- session timezone = 'Asia/Shanghai'
INSERT INTO t VALUES ('[2026-04-25 14:00, 2026-04-25 16:00)'::tstzrange);
-- 字符串里没有时区 → 按会话时区解释为 +08:00

-- session timezone = 'UTC'
SELECT * FROM t WHERE col @> '2026-04-25 06:00:00+00'::timestamptz;
-- 上海 14:00 = UTC 06:00 → 命中
```

迁移时如果数据库会话时区从应用所在时区改为 UTC，含 tstzrange 的查询语义会变。

### 5. range_agg 对空 range 的处理

```sql
SELECT range_agg(r) FROM (VALUES
    ('[1,5)'::int4range),
    ('empty'::int4range),
    ('[7,10)'::int4range)
) t(r);
-- → {[1,5),[7,10)}     空 range 被忽略
```

如果业务希望空 range 影响结果（例如表示"占用 0 时长但占用了某资源"），需要单独处理。

### 6. SQL:2011 PERIOD 的可移植性幻觉

虽然 PERIOD 是标准，但各引擎实现差异巨大：

| 特性 | DB2 | Teradata | MariaDB | Oracle | SQL Server |
|------|-----|----------|---------|--------|------------|
| 应用 PERIOD（PERIOD FOR 业务时间） | 是 | 是 | 是（10.4+） | 是（12c+） | -- |
| 系统 PERIOD（SYSTEM_TIME） | 是 | 部分 | 是（SYSTEM_VERSIONING） | 是（Flashback） | 是 |
| WITHOUT OVERLAPS | 是 | -- | 是（10.5+） | -- | -- |
| FOR PORTION OF DML | 是 | 是 | 是 | -- | -- |
| FOR ... AS OF 时态查询 | 是 | 是 | 是 | 是 | 是 |
| OVERLAPS / CONTAINS 谓词 | 是 | 是 | 部分 | 是 | -- |

跨厂商的 PERIOD 代码移植率非常低，通常需要按目标引擎重写。

### 7. PG range 与时区敏感的 SYSTEM_TIME 时态表

PostgreSQL 没有内置 SYSTEM_TIME 时态表（pg_temporal 等扩展提供）。如果业务同时需要应用时间段（用 tstzrange）与系统时间段（审计），通常用两个 tstzrange 列 + 触发器自动维护系统列。

## 跨引擎迁移建议

### 从 Oracle/SQL Server 双列模型迁移到 PostgreSQL Range

```sql
-- 旧 Oracle 表
CREATE TABLE OLD_BOOKINGS (
    BOOKING_ID NUMBER PRIMARY KEY,
    ROOM_ID NUMBER,
    CHECK_IN DATE,
    CHECK_OUT DATE
);

-- PG 等价
CREATE TABLE bookings (
    booking_id BIGSERIAL PRIMARY KEY,
    room_id BIGINT NOT NULL,
    stay daterange NOT NULL CHECK (NOT isempty(stay)),
    EXCLUDE USING gist (room_id WITH =, stay WITH &&)
);

-- 数据迁移
INSERT INTO bookings (booking_id, room_id, stay)
SELECT booking_id, room_id, daterange(check_in, check_out, '[)')
FROM old_bookings_staging;
```

### 从 PostgreSQL Range 迁移到 BigQuery RANGE\<T\>

```sql
-- PG
SELECT * FROM bookings
WHERE stay @> '2026-04-25'::date AND room_id = 1;

-- BigQuery
SELECT * FROM bookings
WHERE RANGE_CONTAINS(stay, DATE '2026-04-25') AND room_id = 1;
```

注意：
- PG 的 numrange/int4range 在 BigQuery 没有对应类型，需用双列
- multirange 完全没有对应；range_agg 需用 ARRAY_AGG 后应用层合并
- EXCLUDE 没有对应，需用 MERGE INTO + 应用层先 SELECT 再判断

### 从 SQL:2011 PERIOD 迁移到 PG Range

```sql
-- DB2
CREATE TABLE policy (
    policy_id INT,
    business_start DATE NOT NULL,
    business_end DATE NOT NULL,
    PERIOD BUSINESS_TIME(business_start, business_end),
    PRIMARY KEY (policy_id, BUSINESS_TIME WITHOUT OVERLAPS)
);
SELECT * FROM policy FOR BUSINESS_TIME AS OF DATE '2024-09-15';

-- PG
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE policy (
    policy_id INT,
    business daterange NOT NULL,
    EXCLUDE USING gist (policy_id WITH =, business WITH &&)
);
SELECT * FROM policy WHERE business @> DATE '2024-09-15';
```

## 总结对比矩阵

### 核心能力总览

| 能力 | PG 14+ | PG 9.2-13 | BigQuery | DB2 | Teradata | MariaDB | Oracle | SQL Server |
|------|--------|-----------|----------|-----|----------|---------|--------|------------|
| Range 类型 | 是 | 是 | 部分 | -- | PERIOD | -- | -- | -- |
| 多种元素类型 | int/num/date/ts/tstz/自定义 | 同左 | DATE/DATETIME/TIMESTAMP | DATE/TIMESTAMP | DATE/TIMESTAMP | DATE | DATE | -- |
| Multirange | 是 | -- | -- | -- | -- | -- | -- | -- |
| && / @> / <@ | 是 | 是 | RANGE_OVERLAPS / CONTAINS | OVERLAPS / CONTAINS | OVERLAPS / CONTAINS | -- | OVERLAPS | -- |
| -|- 相邻 | 是 | 是 | -- | -- | MEETS | -- | -- | -- |
| + - * 集合运算 | 是（- 返回 multirange） | 是（- 不连续报错） | RANGE_UNION/INTERSECT | -- | P_INTERSECT/P_DIFFERENCE | -- | -- | -- |
| range_agg | 是 | -- | -- | -- | -- | -- | -- | -- |
| range_intersect_agg | 是 | -- | -- | -- | -- | -- | -- | -- |
| 无重叠约束 | EXCLUDE WITH && | EXCLUDE WITH && | -- | WITHOUT OVERLAPS | -- | WITHOUT OVERLAPS | -- | -- |
| GiST/SP-GiST 索引 | 是 | 是（GiST） | -- | -- | -- | -- | -- | -- |
| FOR PORTION OF DML | -- | -- | -- | 是 | -- | 是 | -- | -- |
| 时态查询 AS OF | 仅借助扩展 | -- | -- | 是 | 是 | 是 | 是 | 是（仅 SYSTEM） |

### 典型场景的引擎选择建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 复杂区间运算 + 通用类型 | PostgreSQL 14+ | range + multirange + 完整代数 |
| 标准化时态业务系统 | DB2 / MariaDB | SQL:2011 PERIOD + WITHOUT OVERLAPS + FOR PORTION OF |
| 云数仓上的时间段查询 | BigQuery | RANGE\<T\> + RANGE_OVERLAPS/CONTAINS |
| 已有 Oracle 投资 | Oracle Temporal Validity | PERIOD FOR + AS OF |
| 已有 SQL Server 投资 | SQL Server Temporal Tables（仅 SYSTEM） + 应用层 | 应用 PERIOD 需自行实现 |
| MySQL 生态 | MariaDB（升级） 或 双列+触发器 | MySQL 本身不支持 |
| 分布式 PG 兼容 | Citus / TimescaleDB | 注意分布键约束 |
| 嵌入式分析 | DuckDB + 应用层 | 没有 range 类型，但有 OVERLAPS 谓词 |

## 参考资料

- PostgreSQL: [Range Types](https://www.postgresql.org/docs/current/rangetypes.html)
- PostgreSQL: [Multirange Types (PG 14+)](https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-BUILTIN)
- PostgreSQL: [Range Functions and Operators](https://www.postgresql.org/docs/current/functions-range.html)
- PostgreSQL: [Range Aggregate Functions](https://www.postgresql.org/docs/current/functions-aggregate.html)
- PostgreSQL: [EXCLUDE Constraint](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-EXCLUDE)
- PostgreSQL: [GiST Indexes for Range Types](https://www.postgresql.org/docs/current/gist-builtin-opclasses.html)
- BigQuery: [RANGE Type](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#range_type)
- BigQuery: [Range Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/range_functions)
- IBM DB2: [Application-period temporal tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-creating-application-period-temporal-table)
- Teradata: [PERIOD Data Type](https://docs.teradata.com/r/Teradata-Database-SQL-Data-Types-and-Literals)
- MariaDB: [Application-Time Periods](https://mariadb.com/kb/en/application-time-periods/)
- MariaDB: [System-Versioned Tables](https://mariadb.com/kb/en/system-versioned-tables/)
- Oracle: [Temporal Validity (12c+)](https://docs.oracle.com/database/121/ADFNS/adfns_design.htm#ADFNS968)
- SQL Server: [Temporal Tables](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables)
- SQL:2011 标准: ISO/IEC 9075-2, Section 4.6.3 (Periods) 与 Section 7.13 (WITHOUT OVERLAPS)
- Snodgrass, R. "Developing Time-Oriented Database Applications in SQL" (1999)
- Date, C.J., Darwen, H., Lorentzos, N. "Time and Relational Theory" (2014)
