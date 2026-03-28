# BigQuery: CREATE TABLE

> 参考资料:
> - [1] BigQuery SQL Reference - CREATE TABLE
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_table
> - [2] BigQuery - Partitioned Tables
>   https://cloud.google.com/bigquery/docs/partitioned-tables
> - [3] BigQuery - Clustered Tables
>   https://cloud.google.com/bigquery/docs/clustered-tables
> - [4] BigQuery - External Tables
>   https://cloud.google.com/bigquery/docs/external-tables
> - [5] BigQuery - Pricing
>   https://cloud.google.com/bigquery/pricing


## 基本建表

BigQuery 是无服务器的列式分析引擎。没有索引、没有连接池、没有调优旋钮。
你能控制的是: 表结构、分区、聚集。选对这三个 = 省钱 + 快查询。

```sql
CREATE TABLE myproject.mydataset.users (
    id         INT64 NOT NULL,
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    age        INT64,
    balance    NUMERIC(10,2),                -- NUMERIC: 38 位精度, BIGNUMERIC: 76 位
    bio        STRING,
    tags       ARRAY<STRING>,                -- 原生数组 (不支持 ARRAY<ARRAY<T>>)
    address    STRUCT<                       -- 原生结构体，可嵌套
        street STRING,
        city   STRING,
        zip    STRING,
        geo    STRUCT<lat FLOAT64, lng FLOAT64>
    >,
    metadata   JSON,                         -- JSON 类型 (2022+)，灵活但查询比 STRUCT 慢
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

```

 设计要点:
### 1. 命名: project.dataset.table 三级命名，dataset 是核心组织单位

### 2. NOT NULL: BigQuery 支持但不强制 (只是文档性质)

      PRIMARY KEY / FOREIGN KEY 同样存在但不强制执行!
      它们只用于查询优化器生成更好的执行计划
### 3. 没有自增列: 用 GENERATE_UUID() 或应用层生成 ID

### 4. 没有索引: 通过分区和聚集优化查询（这是最核心的概念）

### 5. 列名大小写不敏感: user_Id 和 USER_ID 是同一列

### 6. ARRAY: 不能嵌套 (但 ARRAY<STRUCT<ARRAY<T>>> 可以)

### 7. STRUCT vs JSON: STRUCT 有 schema 约束且查询更快; JSON 灵活但每次查询都需解析


## 分区策略: 选对分区 = 直接省钱

BigQuery 按扫描数据量计费 ($6.25/TB on-demand, 2024 年价格)
分区可以让查询只扫描需要的数据子集 = 扫描更少 = 账单更小

方式一: 时间单位分区（最常用）

```sql
CREATE TABLE events_daily (
    event_id   STRING,
    user_id    INT64,
    event_type STRING,
    event_time TIMESTAMP,
    payload    JSON
)
PARTITION BY DATE(event_time);               -- 按天分区

```

也可以按小时/月/年:
PARTITION BY TIMESTAMP_TRUNC(event_time, HOUR)    -- 高频数据
PARTITION BY TIMESTAMP_TRUNC(event_time, MONTH)   -- 历史数据
PARTITION BY TIMESTAMP_TRUNC(event_time, YEAR)    -- 极长期数据

方式二: 摄取时间分区（数据本身没有时间列时）

```sql
CREATE TABLE raw_imports (
    source STRING,
    data   JSON
)
PARTITION BY _PARTITIONDATE;                 -- 按 INSERT 时间自动分区
```

_PARTITIONTIME 和 _PARTITIONDATE 是伪列，可以在 WHERE 中使用:
SELECT * FROM raw_imports WHERE _PARTITIONDATE = '2024-01-15'

方式三: 整数范围分区

```sql
CREATE TABLE customer_segments (
    customer_id INT64,
    segment     STRING,
    revenue     NUMERIC
)
PARTITION BY RANGE_BUCKET(customer_id, GENERATE_ARRAY(0, 1000000, 10000));
```

每 10000 个 ID 一个分区，共 100 个分区
适用: 没有时间维度但有整数维度的数据

什么时候不分区:
表 < 1 GB: 分区的元数据管理开销反而比全表扫描大
BigQuery 建议: 分区数 < 4000，每个分区 > 10 MB
如果每天数据量很小 (< 10 MB/天)，考虑按月分区而不是按天

分区过期: 自动删除旧分区 (数据治理 + 省钱)

```sql
CREATE TABLE logs_with_expiry (
    ts      TIMESTAMP,
    level   STRING,
    message STRING
)
PARTITION BY DATE(ts)
OPTIONS (
    partition_expiration_days = 90            -- 90 天前的分区自动删除
);

```

 require_partition_filter: 强制查询必须包含分区过滤 (防止意外全表扫描)
 ALTER TABLE events_daily SET OPTIONS (require_partition_filter = true);
 设置后: SELECT * FROM events_daily → 报错
 必须: SELECT * FROM events_daily WHERE event_time > '2024-01-01'

## 聚集 (Clustering): 分区内的数据排列优化

聚集 = 分区内按指定列排序存储
类似 ClickHouse 的 ORDER BY，但 BigQuery 自动维护 (不需要手动选择引擎)

```sql
CREATE TABLE events_clustered (
    event_id   STRING,
    user_id    INT64,
    event_type STRING,
    country    STRING,
    event_time TIMESTAMP,
    payload    JSON
)
PARTITION BY DATE(event_time)
CLUSTER BY event_type, country, user_id;     -- 最多 4 列!

```

 聚集列顺序很重要! 和复合索引一样的最左前缀原则:
   WHERE event_type = 'click'                              → 高效
   WHERE event_type = 'click' AND country = 'US'           → 更高效
   WHERE event_type = 'click' AND country = 'US' AND user_id = 123 → 最高效
   WHERE country = 'US'                                    → 部分有效 (跳过第一列)
   WHERE user_id = 123                                     → 最差 (跳过前两列)

 聚集列选择指南:
### 1. 最常出现在 WHERE/JOIN 条件中的列

### 2. 高基数列效果好 (user_id > country > event_type)

      与 ClickHouse 相反! BQ 的聚集更像传统索引
### 3. 列顺序: 按过滤频率从高到低排列

### 4. 不需要分区也可以聚集 (但分区 + 聚集 = 最优)


 聚集的实际效果:
   扫描数据量减少 50-90% (取决于过滤条件的选择性)
   BigQuery 自动收集 min/max 统计信息，跳过不相关的存储块
   每次数据写入后 BigQuery 自动重新聚集 (无需手动维护)

## 存储定价: Active vs Long-term

 BigQuery 存储分两个价格层:
   Active storage: $0.02/GB/月 — 最近 90 天内修改过的表/分区
   Long-term storage: $0.01/GB/月 — 90 天内未修改的表/分区 (自动降价!)

 这意味着:
### 1. 不要 DELETE + INSERT 来"更新"历史数据 (会重置 90 天计时器)

### 2. 追加式写入比全量覆盖便宜

### 3. 分区表的好处: 只有最近分区是 active price，历史分区自动降价


 查询定价 (on-demand):
   $6.25/TB 扫描量 (每个查询最少 10 MB)
   分区过滤和聚集直接减少扫描量 = 直接省钱
   SELECT COUNT(*) 不扫描数据 (免费)
   SELECT col1, col2 只扫描这两列 (列式存储的优势)

 省钱技巧:
### 1. SELECT * 是最大的浪费 — 永远只选需要的列

### 2. 查询前用 --dry_run 预估费用

### 3. 设置 maximum_bytes_billed 防止意外大查询:

 CREATE TABLE protected_table (id INT64) OPTIONS (max_staleness = INTERVAL 15 MINUTE);

## 流式插入的缓冲区影响

 BigQuery 有两种写入方式:

### 1. 批量加载 (Load jobs): 免费! 但有配额限制 (每天 1500 次/表)

    DML (INSERT/UPDATE/DELETE): 按扫描量计费

### 2. 流式插入 (Streaming / Storage Write API):

    数据先进入"流式缓冲区" (streaming buffer)
    缓冲区中的数据:
      - 立即可查询
      - 不能 UPDATE/DELETE (直到刷入永久存储)
      - 不受分区过期策略影响
      - 不能通过 COPY/EXPORT 导出
    缓冲区刷新: 通常几分钟到几小时 (不可控)

 Storage Write API (推荐替代旧版 insertAll):
   exactly-once 语义 (旧版 insertAll 是 at-least-once)
   更便宜: $0.025/GB (vs insertAll 的 $0.05/GB)
   支持 CDC (change data capture) 模式

## 物化视图

```sql
CREATE MATERIALIZED VIEW mydataset.daily_stats AS
SELECT
    DATE(event_time) AS event_date,
    event_type,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS unique_users,
    AVG(CAST(JSON_VALUE(payload, '$.duration') AS FLOAT64)) AS avg_duration
FROM events_clustered
GROUP BY event_date, event_type;

```

 物化视图的特点:
### 1. 自动刷新: 基表数据变化后自动增量更新 (不需要手动 REFRESH)

### 2. 智能查询重写: 查询基表时，优化器自动使用物化视图 (如果能匹配)

      例: SELECT event_type, COUNT(*) FROM events_clustered
          WHERE event_time > '2024-01-01' GROUP BY event_type
      BigQuery 会自动重写为查询 daily_stats
### 3. 存储费用: 物化视图占用的存储按标准存储计费

### 4. 刷新费用: 增量刷新按处理的字节数计费


物化视图的限制:
只支持部分聚合: COUNT, SUM, AVG, MIN, MAX, COUNT DISTINCT (HyperLogLog++)
不支持: JOIN, 子查询, 窗口函数, HAVING, UNION
基表必须是同一 dataset
每个基表最多 20 个物化视图
max_staleness 控制数据新鲜度:

```sql
CREATE MATERIALIZED VIEW mydataset.stats_relaxed
OPTIONS (enable_refresh = true, refresh_interval_minutes = 30,
         max_staleness = INTERVAL 4 HOUR)
AS SELECT DATE(event_time) AS d, COUNT(*) AS cnt
   FROM events_clustered GROUP BY d;

```

## 外部表: 不移动数据就查询

直接查询 Cloud Storage、Bigtable、Drive 中的数据

Cloud Storage (最常用)

```sql
CREATE EXTERNAL TABLE mydataset.gcs_logs
OPTIONS (
    format = 'PARQUET',                      -- 支持: CSV, JSON, AVRO, PARQUET, ORC
    uris = ['gs://my-bucket/logs/2024/*.parquet'],
    hive_partition_uri_prefix = 'gs://my-bucket/logs/',  -- 识别 Hive 分区
    require_hive_partition_filter = true      -- 强制分区过滤
);

```

BigLake 表 (外部表的增强版, 支持行列级安全)

```sql
CREATE EXTERNAL TABLE mydataset.biglake_data
WITH CONNECTION `myproject.us.my-connection`
OPTIONS (
    format = 'PARQUET',
    uris = ['gs://my-bucket/data/*.parquet'],
    metadata_cache_mode = 'AUTOMATIC'        -- 缓存元数据加速查询
);

```

Google Sheets (快速分析小数据)

```sql
CREATE EXTERNAL TABLE mydataset.sheet_data
OPTIONS (
    format = 'GOOGLE_SHEETS',
    uris = ['https://docs.google.com/spreadsheets/d/SPREADSHEET_ID'],
    skip_leading_rows = 1                    -- 跳过标题行
);

```

 外部表的性能:
   比原生表慢 (每次查询都要读外部存储)
   Parquet/ORC >> CSV/JSON (列式格式支持列裁剪和谓词下推)
   不支持聚集
   不收取存储费 (数据在 GCS 中按 GCS 价格计费)
   查询按扫描量计费

## 通配符表 (TABLE_SUFFIX)

 按日期分成多张表的旧模式 (分区表出现前的做法):
 events_20240101, events_20240102, events_20240103 ...

 用通配符一次查询多张表:
 SELECT * FROM `myproject.mydataset.events_*`
 WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131';

 _TABLE_SUFFIX 是通配符匹配到的部分，可以在 WHERE 中过滤
 注意: 所有匹配的表必须有相同的 schema

 新项目不要用通配符表! 用分区表。通配符表是历史遗留模式。
 通配符表的问题:
### 1. 每张表有独立的元数据 → 上千张表时 BigQuery API 变慢

### 2. 不支持 DML (不能 UPDATE/DELETE)

### 3. 不支持流式插入

### 4. 权限管理更复杂


## 其他建表模式


CREATE TABLE AS SELECT (CTAS): 从查询创建表

```sql
CREATE TABLE mydataset.active_users
PARTITION BY DATE(last_login)
CLUSTER BY country
AS SELECT user_id, email, last_login, country
   FROM mydataset.users
   WHERE last_login > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY);
```

CTAS 可以指定分区和聚集! 这比先建表再 INSERT INTO ... SELECT 更高效

CREATE OR REPLACE: 原子替换

```sql
CREATE OR REPLACE TABLE mydataset.daily_report
AS SELECT DATE(event_time) AS dt, COUNT(*) AS cnt
   FROM events_clustered
   WHERE event_time > TIMESTAMP '2024-01-01'
   GROUP BY dt;

```

CREATE TABLE LIKE (复制 schema，不复制数据)

```sql
CREATE TABLE mydataset.users_staging LIKE mydataset.users;

```

CREATE TABLE COPY (复制 schema + 数据，免费!)

```sql
CREATE TABLE mydataset.users_backup COPY mydataset.users;
```

COPY 是元数据操作，不扫描数据，不计费!

CREATE SNAPSHOT TABLE (时间点快照, 7 天内可用)

```sql
CREATE SNAPSHOT TABLE mydataset.users_snapshot
CLONE mydataset.users FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);
```

 用于: 误删数据的恢复、时间旅行查询

## 表选项

```sql
CREATE TABLE mydataset.managed_table (
    id       INT64,
    data     STRING,
    ts       TIMESTAMP
)
PARTITION BY DATE(ts)
CLUSTER BY id
OPTIONS (
    description = 'Core business data with lifecycle management',
    labels = [('env', 'prod'), ('team', 'data-eng')],
    partition_expiration_days = 365,          -- 分区级过期
    require_partition_filter = true,          -- 强制分区过滤 (防止全表扫描)
    friendly_name = 'Managed Data Table'
    -- expiration_timestamp: 表级过期 (整张表到期后删除)
    -- default_rounding_mode: NUMERIC 的舍入模式
);

```

## 数据类型速查

 INT64:      64 位整数 (唯一的整数类型，没有 INT32/INT16)
 FLOAT64:    64 位浮点 (唯一的浮点类型)
 NUMERIC:    精确小数, 38 位精度, 9 位小数 (金额用这个)
 BIGNUMERIC: 76 位精度, 38 位小数 (极高精度需求)
 BOOL:       TRUE / FALSE
 STRING:     UTF-8 字符串 (无长度限制，单值最大 10 MB)
 BYTES:      原始字节串
 DATE:       日期 (0001-01-01 ~ 9999-12-31)
 TIME:       时间 (不含日期和时区)
 DATETIME:   日期+时间 (不含时区)
 TIMESTAMP:  微秒精度 UTC 时间戳 (含时区)
 INTERVAL:   时间间隔
 JSON:       半结构化 JSON
 ARRAY<T>:   有序数组 (不可嵌套)
 STRUCT<>:   命名字段结构体 (可嵌套)
 GEOGRAPHY:  地理空间 (WKT/GeoJSON)
 RANGE<T>:   范围类型 (DATE/DATETIME/TIMESTAMP)

## 版本演进 / 重要特性时间线

2016: 标准 SQL 支持 (从 Legacy SQL 迁移)
2018: 聚集表
2019: 物化视图 (预览), 整数范围分区
2020: BigQuery Omni (多云查询)
2021: MERGE 支持, 物化视图 GA
2022: JSON 类型, CREATE TABLE COPY/CLONE/SNAPSHOT
2023: BigLake 外部表增强, VECTOR SEARCH
2024: Object Table (非结构化数据), Continuous Query, Pipe Syntax |>
Remote Function (调用 Cloud Functions)

