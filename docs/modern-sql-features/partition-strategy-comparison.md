# 分区策略：各 SQL 方言实现全对比

> 参考资料:
> - [MySQL 8.0 - Partitioning](https://dev.mysql.com/doc/refman/8.0/en/partitioning.html)
> - [PostgreSQL - Table Partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
> - [Oracle - Partitioning Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/partition-concepts.html)
> - [BigQuery - Partitioned Tables](https://cloud.google.com/bigquery/docs/partitioned-tables)
> - [ClickHouse - Custom Partitioning Key](https://clickhouse.com/docs/engines/table-engines/mergetree-family/custom-partitioning-key)

分区 (Partitioning) 是将一张逻辑表拆分为多个物理片段的技术。正确的分区策略可以将 TB 级表的查询从全表扫描变为只扫描单个分区，性能提升 10~100 倍。但不同引擎对分区的支持差异巨大——从完全手动到完全自动，从仅支持 RANGE 到支持任意表达式。

## 分区类型支持矩阵

```
引擎            RANGE  LIST  HASH  KEY  COMPOSITE  特殊类型
─────────────  ─────  ────  ────  ───  ─────────  ────────────────────────
MySQL           ✓      ✓     ✓    ✓     ✓         LINEAR HASH/KEY
PostgreSQL      ✓      ✓     ✓    ✗     ✓         (10+ 声明式, 11+ 复合)
Oracle          ✓      ✓     ✓    ✗     ✓         INTERVAL, REFERENCE, SYSTEM
SQL Server      ✓      ✗     ✗    ✗     ✗         仅通过 Partition Function
SQLite          ✗      ✗     ✗    ✗     ✗         不支持原生分区
BigQuery        ✓(*)   ✗     ✗    ✗     ✗         DATE/TIMESTAMP, INTEGER RANGE, 摄入时间
Snowflake       ✗      ✗     ✗    ✗     ✗         自动 micro-partitioning (用户无法控制)
ClickHouse      ✓(*)   ✗     ✗    ✗     ✗         任意表达式分区
Hive            ✓(*)   ✗     ✗    ✗     ✓         动态分区, 基于目录结构
Spark SQL       ✓(*)   ✗     ✗    ✗     ✓         继承 Hive 分区 + bucketing
Trino/Presto    取决于 connector (Hive/Iceberg/Delta)
MaxCompute      ✓      ✗     ✓    ✗     ✓         多级分区, LIFECYCLE
StarRocks       ✓      ✓(*)  ✓    ✗     ✓(必选)   RANGE+HASH 必选, 自动分区
Doris           ✓      ✓(*)  ✓    ✗     ✓(必选)   RANGE+HASH 必选, 自动分区
TiDB            ✓      ✓     ✓    ✓     ✗         MySQL 兼容
OceanBase       ✓      ✓     ✓    ✓     ✓         MySQL/Oracle 双模式
CockroachDB     ✓(*)   ✓(*)  ✓    ✗     ✗         基于 PARTITION BY 语法
DuckDB          ✗      ✗     ✗    ✗     ✗         Hive 分区数据可读取

✓(*) = 支持但语法/语义与传统 RANGE/LIST 不同
```

## 各引擎分区语法详解

### MySQL (5.1+)

```sql
-- RANGE 分区: 按连续范围划分
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount     DECIMAL(10,2)
)
PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- LIST 分区: 按离散值划分
CREATE TABLE users (
    id     BIGINT NOT NULL,
    region VARCHAR(20)
)
PARTITION BY LIST COLUMNS (region) (
    PARTITION p_asia    VALUES IN ('CN', 'JP', 'KR'),
    PARTITION p_europe  VALUES IN ('DE', 'FR', 'GB'),
    PARTITION p_america VALUES IN ('US', 'CA', 'BR')
);

-- HASH 分区: 按 hash 值均匀分布
CREATE TABLE logs (
    id      BIGINT NOT NULL,
    user_id BIGINT NOT NULL
)
PARTITION BY HASH (user_id) PARTITIONS 16;

-- KEY 分区: 类似 HASH, 但使用 MySQL 内部 hash 函数
CREATE TABLE sessions (
    id      BIGINT NOT NULL,
    user_id BIGINT NOT NULL
)
PARTITION BY KEY (user_id) PARTITIONS 8;

-- COMPOSITE (子分区): RANGE + HASH
CREATE TABLE access_log (
    id         BIGINT NOT NULL,
    log_date   DATE NOT NULL,
    user_id    BIGINT NOT NULL
)
PARTITION BY RANGE (YEAR(log_date))
SUBPARTITION BY HASH (user_id) SUBPARTITIONS 4 (
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026)
);
-- 结果: 2 个分区 * 4 个子分区 = 8 个物理分片

-- LINEAR HASH: 使用线性 2 的幂次算法, ADD/DROP 更快
CREATE TABLE events (
    id BIGINT NOT NULL,
    ts TIMESTAMP NOT NULL
)
PARTITION BY LINEAR HASH (UNIX_TIMESTAMP(ts)) PARTITIONS 32;
```

### PostgreSQL (10+ 声明式分区)

```sql
-- PostgreSQL 10 以前只能通过表继承 + CHECK 约束模拟分区
-- PostgreSQL 10+ 引入声明式分区

-- RANGE 分区
CREATE TABLE orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    order_date DATE NOT NULL,
    amount     NUMERIC(10,2)
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2024 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- LIST 分区
CREATE TABLE users (
    id     BIGINT,
    region TEXT NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE users_asia PARTITION OF users
    FOR VALUES IN ('CN', 'JP', 'KR');
CREATE TABLE users_europe PARTITION OF users
    FOR VALUES IN ('DE', 'FR', 'GB');

-- HASH 分区 (PostgreSQL 11+)
CREATE TABLE logs (
    id      BIGINT,
    user_id BIGINT NOT NULL
) PARTITION BY HASH (user_id);

CREATE TABLE logs_p0 PARTITION OF logs
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE logs_p1 PARTITION OF logs
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE logs_p2 PARTITION OF logs
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE logs_p3 PARTITION OF logs
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- 多级分区 (PostgreSQL 11+): 分区表本身也可以被分区
CREATE TABLE events (
    id         BIGINT,
    event_date DATE NOT NULL,
    region     TEXT NOT NULL
) PARTITION BY RANGE (event_date);

CREATE TABLE events_2025 PARTITION OF events
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01')
    PARTITION BY LIST (region);  -- 二级分区

CREATE TABLE events_2025_asia PARTITION OF events_2025
    FOR VALUES IN ('CN', 'JP', 'KR');

-- DEFAULT 分区 (PostgreSQL 11+)
CREATE TABLE orders_other PARTITION OF orders DEFAULT;
```

### Oracle (8i+)

```sql
-- RANGE 分区 (最常用)
CREATE TABLE orders (
    id         NUMBER,
    order_date DATE,
    amount     NUMBER(10,2)
)
PARTITION BY RANGE (order_date) (
    PARTITION p_2024q1 VALUES LESS THAN (DATE '2024-04-01'),
    PARTITION p_2024q2 VALUES LESS THAN (DATE '2024-07-01'),
    PARTITION p_2024q3 VALUES LESS THAN (DATE '2024-10-01'),
    PARTITION p_2024q4 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p_max    VALUES LESS THAN (MAXVALUE)
);

-- INTERVAL 分区 (11g+): 自动创建新分区
CREATE TABLE sales (
    id        NUMBER,
    sale_date DATE,
    amount    NUMBER(10,2)
)
PARTITION BY RANGE (sale_date)
INTERVAL (NUMTOYMINTERVAL(1, 'MONTH')) (
    PARTITION p_init VALUES LESS THAN (DATE '2024-01-01')
);
-- 当插入 2024-03-15 的数据时, Oracle 自动创建覆盖 2024-03 的分区

-- HASH 分区
CREATE TABLE customers (
    id   NUMBER,
    name VARCHAR2(100)
)
PARTITION BY HASH (id) PARTITIONS 16;

-- LIST 分区
CREATE TABLE employees (
    id     NUMBER,
    region VARCHAR2(20)
)
PARTITION BY LIST (region) (
    PARTITION p_east  VALUES ('CN', 'JP', 'KR'),
    PARTITION p_west  VALUES ('US', 'CA'),
    PARTITION p_other VALUES (DEFAULT)
);

-- REFERENCE 分区 (11g+): 子表自动继承父表分区
CREATE TABLE order_items (
    id       NUMBER,
    order_id NUMBER NOT NULL,
    item     VARCHAR2(100),
    CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(id)
)
PARTITION BY REFERENCE (fk_order);
-- order_items 的分区与 orders 完全一致, 无需重复定义

-- COMPOSITE 分区: RANGE-HASH
CREATE TABLE big_table (
    id         NUMBER,
    created_at DATE,
    user_id    NUMBER
)
PARTITION BY RANGE (created_at)
SUBPARTITION BY HASH (user_id) SUBPARTITIONS 8 (
    PARTITION p_2024 VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p_2025 VALUES LESS THAN (DATE '2026-01-01')
);
```

### SQL Server

```sql
-- SQL Server 分区模型: Partition Function + Partition Scheme + 表
-- 只支持 RANGE 类型 (LEFT 或 RIGHT)

-- 步骤 1: 创建 Partition Function (定义边界)
CREATE PARTITION FUNCTION pf_order_date (DATE)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', '2024-04-01', '2024-07-01', '2024-10-01', '2025-01-01'
);
-- RANGE LEFT: 边界值属于左边分区
-- RANGE RIGHT: 边界值属于右边分区

-- 步骤 2: 创建 Partition Scheme (映射到文件组)
CREATE PARTITION SCHEME ps_order_date
AS PARTITION pf_order_date
TO (fg_2023, fg_2024q1, fg_2024q2, fg_2024q3, fg_2024q4, fg_2025);

-- 步骤 3: 创建表时指定 Partition Scheme
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount     DECIMAL(10,2)
) ON ps_order_date (order_date);  -- 注意: ON 子句而非 PARTITION BY

-- SQL Server 不支持 LIST, HASH, KEY 分区
-- 需要 LIST 语义? 用 Computed Column + RANGE 变通:
ALTER TABLE orders ADD region_code AS (
    CASE region WHEN 'CN' THEN 1 WHEN 'JP' THEN 2 WHEN 'US' THEN 3 ELSE 99 END
) PERSISTED;
-- 然后对 region_code 建 RANGE 分区

-- 滑动窗口: 合并旧分区 + 拆分新分区
ALTER PARTITION FUNCTION pf_order_date() MERGE RANGE ('2024-01-01');
ALTER PARTITION FUNCTION pf_order_date() SPLIT RANGE ('2025-04-01');
```

### BigQuery

```sql
-- DATE/TIMESTAMP 分区 (最常用)
CREATE TABLE project.dataset.events (
    event_id    INT64,
    event_time  TIMESTAMP,
    event_type  STRING,
    payload     JSON
)
PARTITION BY DATE(event_time);
-- 自动按天创建分区, 无需手动定义每个分区

-- DATE 列分区
CREATE TABLE project.dataset.orders (
    id         INT64,
    order_date DATE,
    amount     NUMERIC
)
PARTITION BY order_date;

-- INTEGER RANGE 分区
CREATE TABLE project.dataset.users (
    user_id  INT64,
    name     STRING,
    age      INT64
)
PARTITION BY RANGE_BUCKET(user_id, GENERATE_ARRAY(0, 1000000, 10000));
-- 按 user_id 每 10000 一个分区

-- 摄入时间分区 (按数据到达时间)
CREATE TABLE project.dataset.raw_logs (
    data STRING
)
PARTITION BY _PARTITIONDATE;
-- _PARTITIONDATE 是伪列, 记录数据被写入 BigQuery 的日期

-- 分区过期: 自动删除旧分区
CREATE TABLE project.dataset.temp_events (
    event_time TIMESTAMP,
    data       STRING
)
PARTITION BY DATE(event_time)
OPTIONS (
    partition_expiration_days = 90  -- 90 天后自动删除
);

-- 查询时必须过滤分区列, 否则扫描全表
-- 可启用 require_partition_filter
CREATE TABLE project.dataset.orders (
    id         INT64,
    order_date DATE
)
PARTITION BY order_date
OPTIONS (require_partition_filter = TRUE);
-- SELECT * FROM orders; -> 报错, 必须带 WHERE order_date = ...
```

### Snowflake

```
Snowflake 没有用户可控的分区:
  - 数据自动组织为 micro-partition (每个 50~500MB 压缩后)
  - 每个 micro-partition 存储了列的 min/max 元数据
  - 查询优化器利用 min/max 做 partition pruning (称为 "pruning" 而非 "partition pruning")

用户能做的:
  1. 选择 Cluster Key 来影响 micro-partition 的数据排列
  2. 使用 AUTOMATIC CLUSTERING 让 Snowflake 后台重新组织数据

为什么这么设计?
  - 免运维: 无需预测分区策略
  - 自适应: 数据分布变化时自动调整
  - 但: 无法做精确分区 (如按天、按地区)
```

```sql
-- Snowflake: 通过 Cluster Key 优化数据布局
CREATE TABLE events (
    event_id   NUMBER,
    event_date DATE,
    user_id    NUMBER,
    event_type VARCHAR
)
CLUSTER BY (event_date, event_type);
-- 不是分区! 只是建议 Snowflake 按这些列排列 micro-partition 中的数据

-- 查看 clustering 效果
SELECT SYSTEM$CLUSTERING_INFORMATION('events', '(event_date)');
-- 返回: cluster_depth, overlap 等指标

-- 开启自动 re-clustering
ALTER TABLE events RESUME RECLUSTER;

-- 查看 micro-partition 裁剪情况
SELECT * FROM events WHERE event_date = '2025-01-15';
-- EXPLAIN 中可以看到 "partitions scanned" vs "partitions total"
```

### ClickHouse

```sql
-- ClickHouse: 任意表达式分区
-- 分区键 (PARTITION BY) 可以是任意表达式

-- 按月分区
CREATE TABLE events (
    event_id   UInt64,
    event_time DateTime,
    user_id    UInt64,
    event_type String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)   -- 按 "202501" 格式分区
ORDER BY (user_id, event_time);

-- 按天分区
CREATE TABLE daily_logs (
    ts   DateTime,
    msg  String
)
ENGINE = MergeTree()
PARTITION BY toDate(ts)
ORDER BY ts;

-- 按任意表达式分区
CREATE TABLE custom (
    id   UInt64,
    city String,
    ts   DateTime
)
ENGINE = MergeTree()
PARTITION BY (toYYYYMM(ts), cityHash64(city) % 10)  -- 时间 + 城市 hash
ORDER BY id;

-- 分区 TTL: 自动删除过期数据
CREATE TABLE logs (
    ts  DateTime,
    msg String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY ts
TTL ts + INTERVAL 6 MONTH DELETE;  -- 6 个月后自动删除

-- 查看分区信息
SELECT partition, name, rows, bytes_on_disk
FROM system.parts
WHERE table = 'events' AND active;
```

### Hive

```sql
-- Hive 分区 = HDFS 目录结构
-- /warehouse/orders/dt=2025-01-01/region=CN/

-- 静态分区
CREATE TABLE orders (
    id     BIGINT,
    amount DOUBLE
)
PARTITIONED BY (dt STRING, region STRING)
STORED AS PARQUET;

-- 静态分区插入: 手动指定分区值
INSERT INTO orders PARTITION (dt='2025-01-15', region='CN')
SELECT id, amount FROM raw_orders WHERE dt = '2025-01-15' AND region = 'CN';

-- 动态分区插入: 自动根据数据创建分区
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

INSERT INTO orders PARTITION (dt, region)
SELECT id, amount, dt, region FROM raw_orders;
-- Hive 自动为每个 (dt, region) 组合创建 HDFS 目录和分区

-- 多级分区
CREATE TABLE logs (
    msg STRING
)
PARTITIONED BY (year INT, month INT, day INT)
STORED AS ORC;
-- 目录: /warehouse/logs/year=2025/month=1/day=15/

-- MSCK REPAIR: 修复元数据与 HDFS 目录的不一致
MSCK REPAIR TABLE orders;
-- 扫描 HDFS 目录, 发现新分区并注册到 Metastore

-- 分区统计信息
ANALYZE TABLE orders PARTITION (dt='2025-01-15') COMPUTE STATISTICS;
```

### Spark SQL

```sql
-- Spark 对 Hive 表: 继承 Hive 分区模型
CREATE TABLE events (
    event_id   BIGINT,
    event_time TIMESTAMP,
    payload    STRING
)
USING HIVE
PARTITIONED BY (dt STRING)
STORED AS PARQUET;

-- Spark DataFrame API 写分区数据
-- df.write.partitionBy("dt", "region").parquet("/path/to/events")

-- Spark bucketing (分桶): 不同于分区, 用于 JOIN 优化
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DOUBLE
)
USING PARQUET
CLUSTERED BY (user_id) INTO 64 BUCKETS;
-- 两个表按相同列、相同桶数分桶 -> Sort-Merge Join 无需 shuffle

-- Spark 3.0+ 动态分区覆盖
SET spark.sql.sources.partitionOverwriteMode = dynamic;
INSERT OVERWRITE TABLE events PARTITION (dt)
SELECT event_id, event_time, payload, dt FROM staging;
-- 只覆盖 staging 中出现的 dt 分区, 不影响其他分区

-- Delta Lake 分区
CREATE TABLE delta_events (
    event_id   BIGINT,
    event_time TIMESTAMP,
    region     STRING
)
USING DELTA
PARTITIONED BY (region);
-- Delta 支持 partition evolution (更改分区列, 无需重写数据)
```

### MaxCompute

```sql
-- MaxCompute: 一级/二级分区
CREATE TABLE orders (
    id     BIGINT,
    amount DECIMAL(10,2)
)
PARTITIONED BY (dt STRING, region STRING)
LIFECYCLE 365;  -- 分区超过 365 天自动回收
-- LIFECYCLE 是 MaxCompute 独有特性, 类似 TTL

-- 插入分区数据
INSERT INTO orders PARTITION (dt='2025-01-15', region='CN')
SELECT id, amount FROM raw_data WHERE dt = '2025-01-15';

-- 动态分区
INSERT INTO orders PARTITION (dt, region)
SELECT id, amount, dt, region FROM raw_data;

-- HASH 分区 (MaxCompute 2.0+)
CREATE TABLE user_actions (
    user_id  BIGINT,
    action   STRING,
    ts       TIMESTAMP
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (ts) INTO 64 BUCKETS;
-- 类似 Hive bucketing

-- 查看分区
SHOW PARTITIONS orders;

-- 修改 LIFECYCLE
ALTER TABLE orders SET LIFECYCLE 180;
```

### StarRocks

```sql
-- StarRocks: RANGE 分区 + HASH 分桶 (必选)
CREATE TABLE orders (
    id         BIGINT,
    order_date DATE,
    user_id    BIGINT,
    amount     DECIMAL(10,2)
)
ENGINE = OLAP
PARTITION BY RANGE (order_date) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01')),
    PARTITION p202403 VALUES [('2024-03-01'), ('2024-04-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

-- 自动分区 (StarRocks 3.1+): 无需手动定义每个 RANGE 分区
CREATE TABLE events (
    event_id   BIGINT,
    event_time DATETIME,
    data       VARCHAR(1024)
)
ENGINE = OLAP
PARTITION BY date_trunc('month', event_time)  -- 自动按月分区
DISTRIBUTED BY HASH(event_id) BUCKETS 8
PROPERTIES ("replication_num" = "3");
-- 插入数据时自动创建对应月份的分区

-- Expression 分区 (StarRocks 3.1+)
CREATE TABLE logs (
    ts   DATETIME,
    msg  VARCHAR(2048)
)
ENGINE = OLAP
PARTITION BY date_trunc('day', ts)
DISTRIBUTED BY RANDOM BUCKETS 8;
-- DISTRIBUTED BY RANDOM: 随机分桶, 适合无明显分桶键的场景

-- LIST 分区 (StarRocks 3.1+)
CREATE TABLE region_data (
    id     BIGINT,
    region VARCHAR(20),
    data   VARCHAR(1024)
)
ENGINE = OLAP
PARTITION BY LIST (region) (
    PARTITION p_cn VALUES IN ('CN'),
    PARTITION p_us VALUES IN ('US'),
    PARTITION p_eu VALUES IN ('DE', 'FR', 'GB')
)
DISTRIBUTED BY HASH(id) BUCKETS 8;
```

### Doris

```sql
-- Doris: RANGE 分区 + HASH 分桶 (必选, 与 StarRocks 同源)
CREATE TABLE orders (
    id         BIGINT,
    order_date DATE,
    user_id    BIGINT,
    amount     DECIMAL(10,2)
)
ENGINE = OLAP
PARTITION BY RANGE (order_date) (
    PARTITION p202401 VALUES [('2024-01-01'), ('2024-02-01')),
    PARTITION p202402 VALUES [('2024-02-01'), ('2024-03-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

-- 动态分区 (Doris): 自动创建/删除分区
CREATE TABLE dynamic_orders (
    id         BIGINT,
    order_date DATE,
    amount     DECIMAL(10,2)
)
ENGINE = OLAP
PARTITION BY RANGE (order_date) ()  -- 初始无分区
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",     -- 保留过去 30 天
    "dynamic_partition.end" = "3",         -- 预创建未来 3 天
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "8"
);

-- Auto Partition (Doris 2.1+)
CREATE TABLE events (
    event_time DATETIME,
    event_id   BIGINT,
    data       VARCHAR(1024)
)
ENGINE = OLAP
AUTO PARTITION BY RANGE (date_trunc(event_time, 'month'))
DISTRIBUTED BY HASH(event_id) BUCKETS 8;

-- LIST 分区 (Doris 2.1+)
CREATE TABLE region_data (
    id     BIGINT,
    region VARCHAR(20),
    data   VARCHAR(1024)
)
ENGINE = OLAP
PARTITION BY LIST (region) (
    PARTITION p_cn VALUES IN ('CN'),
    PARTITION p_us VALUES IN ('US')
)
DISTRIBUTED BY HASH(id) BUCKETS 8;

-- Auto LIST Partition (Doris 2.1+)
CREATE TABLE auto_region (
    id     BIGINT,
    region VARCHAR(20),
    data   VARCHAR(1024)
)
ENGINE = OLAP
AUTO PARTITION BY LIST (region)
DISTRIBUTED BY HASH(id) BUCKETS 8;
-- 插入 region='JP' 的数据时, 自动创建 p_JP 分区
```

### TiDB

```sql
-- TiDB: MySQL 兼容的分区语法
-- RANGE 分区
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount     DECIMAL(10,2)
)
PARTITION BY RANGE (YEAR(order_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- RANGE COLUMNS (TiDB 5.0+)
CREATE TABLE logs (
    id  BIGINT NOT NULL,
    dt  DATE NOT NULL,
    msg TEXT
)
PARTITION BY RANGE COLUMNS (dt) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01')
);

-- HASH 分区
CREATE TABLE users (
    id   BIGINT NOT NULL,
    name VARCHAR(50)
)
PARTITION BY HASH (id) PARTITIONS 16;

-- KEY 分区 (TiDB 7.0+)
CREATE TABLE sessions (
    id      BIGINT NOT NULL,
    user_id BIGINT NOT NULL
)
PARTITION BY KEY (user_id) PARTITIONS 8;

-- LIST 分区 (TiDB 5.0+)
CREATE TABLE employees (
    id     BIGINT NOT NULL,
    region VARCHAR(20)
)
PARTITION BY LIST COLUMNS (region) (
    PARTITION p_asia   VALUES IN ('CN', 'JP', 'KR'),
    PARTITION p_europe VALUES IN ('DE', 'FR', 'GB')
);

-- TiDB 特有: PLACEMENT POLICY 结合分区
-- 将不同分区放在不同地域的 TiKV 节点
ALTER TABLE orders PARTITION p2025 PLACEMENT POLICY = policy_ssd;
```

### OceanBase

```sql
-- OceanBase MySQL 模式: 与 MySQL 分区语法兼容
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    order_date DATE NOT NULL
)
PARTITION BY RANGE COLUMNS (order_date) (
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p2025 VALUES LESS THAN ('2026-01-01')
);

-- OceanBase 独有: RANGE + HASH 模板化子分区
CREATE TABLE big_table (
    id         BIGINT NOT NULL,
    order_date DATE NOT NULL,
    user_id    BIGINT NOT NULL
)
PARTITION BY RANGE COLUMNS (order_date)
SUBPARTITION BY HASH (user_id) SUBPARTITIONS 8 (
    PARTITION p2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p2025 VALUES LESS THAN ('2026-01-01')
);

-- OceanBase Oracle 模式: 与 Oracle 分区语法兼容
-- 支持 INTERVAL 分区、HASH 分区等 Oracle 语法
```

### CockroachDB

```sql
-- CockroachDB: 基于 PARTITION BY 但语义是数据放置
CREATE TABLE orders (
    id         INT8 DEFAULT unique_rowid(),
    order_date DATE NOT NULL,
    region     STRING NOT NULL,
    amount     DECIMAL(10,2)
)
PARTITION BY LIST (region) (
    PARTITION us VALUES IN ('us-east', 'us-west'),
    PARTITION eu VALUES IN ('eu-west', 'eu-central')
);

-- 分区的主要用途: 地理分区 (Geo-Partitioning)
ALTER PARTITION us OF TABLE orders
    CONFIGURE ZONE USING constraints='[+region=us]';
ALTER PARTITION eu OF TABLE orders
    CONFIGURE ZONE USING constraints='[+region=eu]';
-- 将 us 分区的数据固定存储在 us 区域的节点上
```

## 分区裁剪 (Partition Pruning)

```
分区裁剪: 查询只扫描相关分区, 跳过不需要的分区

触发条件:
  WHERE 条件中包含分区键的常量比较

引擎            静态裁剪    动态裁剪    支持的谓词
─────────────  ─────────  ─────────  ──────────────────────────────
MySQL           ✓          ✗          =, IN, <, >, BETWEEN, IS NULL
PostgreSQL      ✓          ✓ (11+)    =, IN, <, >, BETWEEN, IS NULL
Oracle          ✓          ✓          =, IN, <, >, BETWEEN, LIKE prefix
SQL Server      ✓          ✓          =, IN, <, >, BETWEEN
BigQuery        ✓          ✓          =, IN, <, >, BETWEEN
Snowflake       ✓ (*)      ✓ (*)      =, IN, <, >, BETWEEN (min/max pruning)
ClickHouse      ✓          ✓          =, IN, <, >, BETWEEN
Hive            ✓          ✓          =, IN, <, >, BETWEEN
Spark SQL       ✓          ✓ (3.0+)   =, IN, <, >, BETWEEN
StarRocks       ✓          ✓          =, IN, <, >, BETWEEN
Doris           ✓          ✓          =, IN, <, >, BETWEEN
TiDB            ✓          ✓ (6.3+)   =, IN, <, >, BETWEEN
OceanBase       ✓          ✓          =, IN, <, >, BETWEEN

静态裁剪: 编译时确定要扫描哪些分区 (WHERE dt = '2025-01-01')
动态裁剪: 运行时基于其他表的 JOIN 结果动态决定分区 (大表 JOIN 小表, 小表过滤后反向裁剪大表)
```

```sql
-- 静态裁剪示例 (所有引擎)
SELECT * FROM orders WHERE order_date = '2025-01-15';
-- 优化器直接定位到 p2025 分区

-- 动态裁剪示例 (PostgreSQL 11+, Oracle, Spark 3.0+)
SELECT o.* FROM orders o
JOIN dim_date d ON o.order_date = d.dt
WHERE d.is_holiday = TRUE;
-- 先扫描 dim_date 获取假日日期列表
-- 再用这些日期动态裁剪 orders 的分区

-- MySQL 不支持动态裁剪: 上面的查询会扫描 orders 全部分区
-- 变通方案: 先查出日期列表, 再用 IN 条件
SELECT * FROM orders
WHERE order_date IN (SELECT dt FROM dim_date WHERE is_holiday = TRUE);
-- MySQL 8.0 的子查询优化可能帮助裁剪, 但不保证

-- ⚠️ 分区裁剪的隐式类型转换陷阱:
-- 如果分区键是 DATETIME 但查询用字符串 '2024-01-01'，某些引擎会因
-- 隐式类型转换导致裁剪失效，变成全分区扫描！
-- 原则: 分区键查询条件必须严格类型匹配，显式 CAST 而非依赖隐式转换

-- ⚠️ MySQL 分区表的唯一键限制:
-- MySQL 要求所有唯一索引（含主键）必须包含分区列！
-- 如果按 create_time 分区，主键必须从 (id) 改为 (id, create_time)
-- Oracle/SQL Server/TiDB/OceanBase 通过全局索引（Global Index）规避了此限制
-- ⚠️ 但全局索引有写入放大代价：更新会触发跨分区分布式事务
-- 金律：全局索引是查询的利器，但是写入吞吐的杀手
-- 大规模写入场景应优先通过业务逻辑重构，让查询对齐本地分区索引
-- 这是 Oracle → MySQL 分区迁移时最常导致架构推倒重来的约束

-- 验证分区裁剪
-- MySQL
EXPLAIN SELECT * FROM orders WHERE order_date = '2025-01-15';
-- 看 "partitions" 列, 应该只显示 p2025

-- PostgreSQL
EXPLAIN (ANALYZE) SELECT * FROM orders WHERE order_date = '2025-01-15';
-- 看是否只扫描了 orders_2025 子表

-- Snowflake
SELECT * FROM orders WHERE order_date = '2025-01-15';
-- 查看 Query Profile: "Partitions scanned" vs "Partitions total"
```

## 分区数限制

```
各引擎分区数上限:

引擎            最大分区数        说明
─────────────  ──────────────  ─────────────────────────────────
MySQL           8192            每表, 包含子分区 (5.6.7+ 默认, 之前 1024)
PostgreSQL      无硬性上限       实测超过数千时性能下降, 建议 < 几千
Oracle          1048575 (1M)    每表, 包含子分区
SQL Server      15000           每表
BigQuery        4000            每表 (摄入时间分区可到 10000)
Snowflake       N/A             micro-partition 数量不受限
ClickHouse      无硬性上限       但分区过多影响 merge 性能, 建议 < 1000 活跃分区
Hive            无硬性上限       但元数据服务是瓶颈, 建议 < 10000~50000
Spark SQL       取决于数据源     Hive 表同 Hive 限制
MaxCompute      60000           每表
StarRocks       无硬性上限       建议合理控制, 分区过多影响元数据管理
Doris           无硬性上限       建议 < 10000, 过多分区影响 FE 元数据管理
TiDB            8192            与 MySQL 兼容
OceanBase       无硬性上限       分区*子分区总数建议 < 几万
CockroachDB     无硬性上限       分区过多增加 leaseholder 管理开销

实践建议:
  - 时间分区按月而非按天 (减少分区数)
  - 定期合并或删除旧分区
  - 分区数超过 1000 时需要评估元数据管理开销
  - OLAP 引擎 (StarRocks/Doris/ClickHouse): 分区粒度不宜过细
```

## 动态分区

### Hive 动态分区

```sql
-- Hive 动态分区: 根据 SELECT 结果自动创建分区
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;
-- strict 模式: 至少有一个静态分区
-- nonstrict 模式: 所有分区都可以动态

-- 关键参数
SET hive.exec.max.dynamic.partitions = 1000;           -- 总动态分区上限
SET hive.exec.max.dynamic.partitions.pernode = 100;    -- 每个节点上限

INSERT INTO TABLE orders PARTITION (dt, region)
SELECT id, amount, dt, region FROM staging;
-- Hive 自动为每个 (dt, region) 创建 HDFS 目录

-- 问题: 大量小文件
-- 动态分区容易生成大量小文件 (每个 reducer * 每个分区 = 一个文件)
-- 解决: distribute by + sort by
INSERT INTO TABLE orders PARTITION (dt, region)
SELECT id, amount, dt, region FROM staging
DISTRIBUTE BY dt, region;
-- 相同分区的数据发到同一个 reducer, 减少小文件
```

### MaxCompute LIFECYCLE

```sql
-- MaxCompute LIFECYCLE: 分区级自动回收
CREATE TABLE logs (
    msg STRING
)
PARTITIONED BY (dt STRING)
LIFECYCLE 90;
-- 分区创建 90 天后自动删除

-- 修改 LIFECYCLE
ALTER TABLE logs SET LIFECYCLE 180;

-- 每个分区有 LastModifiedTime
-- 当 current_time - LastModifiedTime > LIFECYCLE -> 分区被回收

-- 手动触发某个分区的访问 (重置过期时间)
ALTER TABLE logs PARTITION (dt='2025-01-01') TOUCH;
```

### Oracle INTERVAL 自动分区

```sql
-- Oracle INTERVAL 分区: 自动按间隔创建新分区
CREATE TABLE transactions (
    id   NUMBER,
    ts   TIMESTAMP,
    data VARCHAR2(4000)
)
PARTITION BY RANGE (ts)
INTERVAL (NUMTODSINTERVAL(1, 'DAY')) (
    PARTITION p_init VALUES LESS THAN (TIMESTAMP '2025-01-01 00:00:00')
);
-- 当插入 2025-03-28 的数据时, Oracle 自动创建覆盖该天的分区
-- 无需预先定义每个分区, 无需定时脚本

-- INTERVAL 支持的单位:
-- NUMTOYMINTERVAL(n, 'YEAR' | 'MONTH')
-- NUMTODSINTERVAL(n, 'DAY' | 'HOUR' | 'MINUTE' | 'SECOND')
```

## 分区级 DDL

```
分区级操作支持矩阵:

引擎            ADD     DROP    TRUNCATE  EXCHANGE  SPLIT   MERGE   RENAME
─────────────  ─────   ─────   ────────  ────────  ─────   ─────   ──────
MySQL           ✓       ✓       ✓         ✓(5.7+)   ✓(5.1+) ✓(5.1+) ✗
PostgreSQL      ✓       ✓(*)    ✓         ✓(ATTACH) ✗       ✗       ✗
Oracle          ✓       ✓       ✓         ✓         ✓       ✓       ✓
SQL Server      ✓(**)   ✓(**)   ✓         ✓(***)    ✓(**)   ✓(**)   ✗
BigQuery        ✗(自动)  ✓       ✗         ✗         ✗       ✗       ✗
ClickHouse      ✗(自动)  ✓       ✗         ✓(ATTACH) ✗       ✗       ✗
Hive            ✓       ✓       ✗         ✗         ✗       ✗       ✓
StarRocks       ✓       ✓       ✓         ✗         ✗       ✗       ✗
Doris           ✓       ✓       ✓         ✗         ✗       ✗       ✗
TiDB            ✓       ✓       ✓         ✓(6.0+)   ✗       ✗       ✗
OceanBase       ✓       ✓       ✓         ✗         ✗       ✗       ✗
CockroachDB     ✗       ✗       ✗         ✗         ✗       ✗       ✗

✓(*)   PostgreSQL: DETACH 解绑分区（变为独立表，数据不丢失）；DROP 会连带数据删除
✓(**)  SQL Server 通过 MERGE/SPLIT Partition Function 实现
✓(***) SQL Server SWITCH = EXCHANGE
```

```sql
-- ADD PARTITION
-- MySQL
ALTER TABLE orders ADD PARTITION (
    PARTITION p2026 VALUES LESS THAN (2027)
);

-- PostgreSQL
CREATE TABLE orders_2026 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- Oracle
ALTER TABLE orders ADD PARTITION p2026
    VALUES LESS THAN (DATE '2027-01-01');

-- DROP PARTITION
-- MySQL / TiDB / OceanBase
ALTER TABLE orders DROP PARTITION p2023;

-- PostgreSQL: DETACH (数据保留在独立表中)
ALTER TABLE orders DETACH PARTITION orders_2023;
-- orders_2023 变为普通独立表, 可以单独查询或删除

-- PostgreSQL: DETACH CONCURRENTLY (不阻塞查询, 14+)
ALTER TABLE orders DETACH PARTITION orders_2023 CONCURRENTLY;

-- TRUNCATE PARTITION (清空数据但保留分区结构)
-- MySQL / TiDB
ALTER TABLE orders TRUNCATE PARTITION p2023;

-- Oracle
ALTER TABLE orders TRUNCATE PARTITION p2023;

-- EXCHANGE PARTITION (将分区与独立表交换, 用于快速加载/归档)
-- MySQL 5.7+
ALTER TABLE orders EXCHANGE PARTITION p2023 WITH TABLE orders_archive;

-- Oracle
ALTER TABLE orders EXCHANGE PARTITION p2023
    WITH TABLE orders_staging INCLUDING INDEXES;

-- PostgreSQL (ATTACH = 将独立表加入分区表)
ALTER TABLE orders ATTACH PARTITION orders_new
    FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');
-- 前提: orders_new 的数据必须满足分区约束, 否则报错

-- SQL Server: SWITCH (等价于 EXCHANGE)
ALTER TABLE orders SWITCH PARTITION 5 TO archive_orders;
```

## Auto-partitioning 对比

```
自动分区策略:

策略                引擎              原理
─────────────────  ──────────────   ──────────────────────────────────
全自动              Snowflake        micro-partition, 用户无需任何操作
半自动 (声明间隔)   Oracle INTERVAL  定义间隔, 数据到达时自动创建分区
半自动 (表达式)     StarRocks 3.1+   date_trunc 表达式, 自动创建分区
半自动 (表达式)     Doris 2.1+       AUTO PARTITION BY RANGE/LIST
半自动 (动态属性)   Doris            dynamic_partition 属性, 定时创建/删除
半自动 (分区过期)   BigQuery         partition_expiration_days 自动删除
半自动 (LIFECYCLE)  MaxCompute       LIFECYCLE N 天后自动回收
手动                MySQL/PG/TiDB   完全手动 ADD/DROP PARTITION
```

```sql
-- Snowflake: 完全自动
-- 无需任何分区相关的 DDL
-- 写入数据 -> 自动组织为 micro-partition
-- 查询数据 -> 自动基于 min/max 裁剪
SELECT * FROM events WHERE event_date = '2025-03-28';
-- Snowflake 自动决定扫描哪些 micro-partition

-- BigQuery: 声明式, 自动按天/月/小时创建分区
CREATE TABLE events (ts TIMESTAMP, data STRING)
PARTITION BY DATE(ts)
OPTIONS (partition_expiration_days = 365);
-- 写入 2025-03-28 的数据 -> 自动创建 20250328 分区
-- 超过 365 天的分区自动删除

-- Oracle: INTERVAL 自动创建, 但不自动删除
-- 自动删除需要用 DBMS_SCHEDULER + DROP PARTITION 脚本

-- StarRocks: 按表达式自动创建
CREATE TABLE t (...) PARTITION BY date_trunc('day', ts) ...;
-- 写入 2025-03-28 的数据 -> 自动创建 [2025-03-28, 2025-03-29) 分区
-- 删除: 手动 ALTER TABLE DROP PARTITION 或配置 TTL

-- Doris: 两种自动模式
-- 1. dynamic_partition: 基于时间窗口预创建/自动删除
-- 2. AUTO PARTITION: 基于数据到达自动创建

-- 手动模式引擎的常见解决方案:
-- MySQL/TiDB/PostgreSQL: 定时任务 (cron) 提前创建分区
-- 例: 每月 1 号创建下个月的分区
```

## 横向总结

```
从引擎开发者的角度, 分区策略可以分为三代:

第一代: 手动分区 (MySQL, PostgreSQL, SQL Server, TiDB)
  - 用户完全控制分区定义
  - 需要提前规划分区方案
  - 需要定时脚本维护 (创建新分区、删除旧分区)
  - 优点: 精确控制, 可预测
  - 缺点: 运维负担重

第二代: 半自动分区 (Oracle INTERVAL, Hive 动态分区, Doris/StarRocks)
  - 引擎根据规则自动创建/管理分区
  - 用户只需声明策略, 不需要逐个定义分区
  - 优点: 运维简化
  - 缺点: 仍需要选择分区键和策略

第三代: 全自动分区 (Snowflake, 某种程度上 BigQuery)
  - 引擎自动决定数据组织方式
  - 用户只需选择 Cluster Key (Snowflake) 或分区列 (BigQuery)
  - 优点: 几乎零运维
  - 缺点: 无法精细控制, 某些场景可能不是最优
```

## 引擎开发者建议

```
1. 分区策略选型

   如果你在开发新引擎:
     - OLTP 场景: RANGE 分区必须支持, LIST 可选, HASH 用于负载均衡
     - OLAP 场景: RANGE + HASH 二级分区是标配 (参考 StarRocks/Doris)
     - 云原生场景: 考虑全自动方案 (参考 Snowflake micro-partition)
     - MySQL 兼容: 必须支持 RANGE, LIST, HASH, KEY 四种类型

2. 分区裁剪是核心

   分区如果不能裁剪, 等于没有分区:
     - 静态裁剪是最低要求 (编译时确定分区)
     - 动态裁剪是竞争力 (运行时根据 JOIN 结果裁剪)
     - 谓词下推到分区级别: =, IN, <, >, BETWEEN 是基本集合
     - 计划缓存与分区裁剪的交互: 注意参数化查询场景

3. 自动分区是趋势

   手动管理分区的时代正在结束:
     - 至少支持 INTERVAL 类自动创建 (Oracle 模式)
     - 最好支持 TTL/LIFECYCLE 自动回收
     - 终极目标: 用户只需声明分区列, 引擎自动处理一切

4. 分区数限制

   分区元数据管理是性能关键:
     - 每个分区的元数据开销 (内存、锁)
     - 查询规划时遍历分区列表的开销
     - 建议: 默认上限 8192 (与 MySQL 兼容), 可配置

5. 分区级 DDL

   生产环境必须支持的操作:
     - ADD / DROP PARTITION: 最基本要求
     - TRUNCATE PARTITION: 快速清空分区
     - EXCHANGE PARTITION: 快速数据交换 (ETL 场景必备)
     - Online (非阻塞) 分区操作: 不能锁表

6. 与分布式的交互

   分布式引擎中, 分区 (Partition) 和分片 (Shard/Tablet) 是两个维度:
     - 分区: 逻辑组织, 服务于查询裁剪
     - 分片: 物理分布, 服务于并行度和负载均衡
     - StarRocks/Doris 模型 (PARTITION + DISTRIBUTED BY) 是良好实践
     - 避免混淆这两个概念
```
