# 分层存储 (Tiered Storage / Hot-Cold Storage)

一张 100TB 的订单历史表，其中 95% 的查询只访问最近 30 天的 5TB 数据——为这些冷数据支付与热数据相同的 NVMe 存储价格是对成本的严重浪费。分层存储让数据库根据访问温度自动在 SSD、HDD、对象存储之间迁移数据，是大规模数据系统实现成本-性能平衡的核心能力。

## 没有 SQL 标准

SQL 标准（SQL:2023）至今没有定义分层存储的语法或接口。每个数据库厂商基于自己的存储架构独立实现，语法、自动化程度、透明度差异极大。常见的实现方式包括：

1. **存储策略（Storage Policy / Tiering Policy）**：声明式配置，定义哪些数据在哪个存储层
2. **生命周期管理（ILM / Lifecycle Management）**：基于时间或访问频率的自动迁移规则
3. **手动迁移 DDL**：`ALTER TABLE ... MOVE TABLESPACE`、`ALTER TABLE ... ARCHIVE`
4. **存算分离架构**：Snowflake / Redshift RA3 / StarRocks 3.0 天生将存储放在对象存储
5. **热点缓存**：保持存储不变，通过内存 + 本地 SSD 缓存模拟热层

## 支持矩阵（45+ 引擎）

### 基础能力对比

| 引擎 | 原生分层存储 | 自动迁移 | 手动迁移 DDL | 查询透明 | 分层压缩 | 对象存储集成 | 版本 |
|------|------------|---------|-------------|---------|---------|-------------|------|
| PostgreSQL | 部分（表空间） | -- | `ALTER TABLE ... SET TABLESPACE` | 是 | -- | 扩展 | 8.0+ |
| MySQL | -- | -- | 表空间迁移 | 是 | -- | -- | 5.7+ |
| MariaDB | -- | -- | 表空间迁移 | 是 | -- | -- | 10.0+ |
| SQLite | -- | -- | -- | -- | -- | -- | 不支持 |
| Oracle | 是（ILM/ADO） | 是 | `ALTER TABLE ... MOVE` | 是 | 是 | 是（云） | 12c+ (2013) |
| SQL Server | Stretch（已弃用） | 是 | `ALTER TABLE ... STRETCH_CONFIGURATION` | 是 | -- | 是（Azure） | 2016-2022 |
| DB2 | 是（Multi-Temp） | 是 | `ALTER TABLESPACE` | 是 | 是 | 部分 | 10.1+ |
| Snowflake | 是（自动） | 是 | -- | 完全 | 是 | 是（S3/GCS/Azure） | GA |
| BigQuery | 长期存储 | 是（90 天） | -- | 完全 | -- | 原生 GCS | GA |
| Redshift | RA3 | 缓存机制 | -- | 完全 | 是 | 是（S3） | RA3 2019+ |
| DuckDB | -- | -- | -- | -- | -- | httpfs 扩展 | -- |
| ClickHouse | 是（存储策略） | 是（TTL MOVE） | `ALTER TABLE ... MOVE PART` | 是 | 是 | S3 disk | 19.15+ |
| Trino | 外部表 | -- | -- | 是（跨连接器） | -- | 是 | GA |
| Presto | 外部表 | -- | -- | 是 | -- | 是 | GA |
| Spark SQL | 外部表 | -- | -- | 是 | -- | 是 | GA |
| Hive | 是（HDFS 存储策略） | 是 | `ALTER TABLE ... SET STORAGE POLICY` | 是 | -- | 是（S3/HDFS） | 2.6+ |
| Flink SQL | 外部表 | -- | -- | 是 | -- | 是 | GA |
| Databricks | Delta Lake | 部分 | `VACUUM` + 路径管理 | 是 | 是 | 是 | GA |
| Teradata | 是（Temperature） | 是（TVI） | 是 | 是 | 是 | QueryGrid | 14+ |
| Greenplum | 外部表 | -- | -- | 是 | 是 | 是（PXF） | GA |
| CockroachDB | 是（zone config） | 是 | `CONFIGURE ZONE` | 是 | -- | -- | 19.1+ |
| TiDB | TiFlash + TiKV | 手动 | `ALTER TABLE ... SET TIFLASH REPLICA` | 是 | 是 | 实验性 | 4.0+ / 7.0+ |
| OceanBase | 是（归档） | 是 | 是 | 是 | 是 | 是（4.x） | 3.0+ |
| YugabyteDB | 表空间 | -- | 是 | 是 | -- | -- | 2.14+ |
| SingleStore | 是（Unlimited Storage） | 是 | -- | 是 | 是 | 是（S3） | 7.3+ |
| Vertica | 是（Storage Location） | 是（ATM） | 是 | 是 | 是 | 是（Eon Mode） | 9.0+ |
| Impala | 外部表 | -- | -- | 是 | -- | 是 | GA |
| StarRocks | 是（共享数据） | 是 | -- | 是 | 是 | 是（S3/HDFS） | 3.0+ (2023) |
| Doris | 是（冷数据） | 是 | 是 | 是 | 是 | 是（S3） | 2.0+ |
| MonetDB | -- | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | 是（partition） | 手动 | 是 | 是 | -- | 是 | 4.0+ |
| TimescaleDB | 是（Cloud） | 是 | `add_tiering_policy` | 是 | 是 | 是（S3，仅云） | Cloud |
| QuestDB | 部分 | 是 | 是 | 是 | -- | 实验性 | 7.0+ |
| Exasol | -- | -- | -- | -- | -- | -- | 不支持 |
| SAP HANA | 是（NSE/DTE） | 是 | 是 | 是 | 是 | 是 | 2.0+ |
| Informix | 是（存储空间） | -- | 是 | 是 | 是 | -- | 11+ |
| Firebird | -- | -- | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | 外部表 | -- | S3 生命周期 | 是 | -- | 原生 S3 | GA |
| Azure Synapse | 是（池） | -- | -- | 是 | 是 | 是（ADLS） | GA |
| Google Spanner | -- | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | 是（对象存储） | 是 | -- | 是 | -- | 是 | GA |
| InfluxDB | 保留策略 | 是 | -- | 部分 | -- | 是（Cloud） | 1.0+ |
| DatabendDB | 是 | 是 | -- | 是 | 是 | 是（S3） | GA |
| Yellowbrick | 是（ILM） | 是 | 是 | 是 | 是 | 是 | GA |
| Firebolt | 是 | 是 | -- | 完全 | 是 | 是（S3） | GA |

> 统计：约 33 个引擎提供某种形式的分层存储或等价机制；约 14 个引擎不支持或仅依赖外部工具。

### 存储层架构分类

| 引擎 | 热层（Hot） | 温层（Warm） | 冷层（Cold） | 典型介质 |
|------|-----------|------------|-------------|---------|
| Oracle | Buffer Cache + SSD 表空间 | HDD 表空间 | 压缩表 / 云存储 | NVMe / SAS / S3 |
| SQL Server | Buffer Pool | -- | Azure（Stretch） | 本地 SSD / Azure Blob |
| Snowflake | 本地 SSD 缓存（warehouse） | -- | S3 / GCS / Azure Blob | NVMe / 对象存储 |
| BigQuery | Capacitor（Colossus） | -- | Long-term storage（90 天） | 同底层，但价格减半 |
| Redshift RA3 | 本地 SSD 缓存 | -- | Managed Storage（S3） | NVMe / S3 |
| ClickHouse | default (SSD) | warm (HDD) | cold (S3/HDFS) | 用户自定义 |
| Cassandra | Memtable | SSTable (SSD) | -- | RAM / SSD |
| InfluxDB | Cache + WAL | TSM file | Parquet (Cloud) | RAM / SSD / S3 |
| TimescaleDB | 热 chunk（主存储） | 压缩 chunk | S3（仅云） | NVMe / SSD / S3 |
| TiDB | TiKV（RocksDB） | TiFlash（列存） | S3（7.0+ 实验性） | SSD / SSD / S3 |
| StarRocks | 本地 SSD 缓存 | -- | 对象存储 | NVMe / S3 |
| Doris | 本地 SSD | -- | S3 / HDFS | SSD / S3 |
| Vertica | ROS（磁盘）+ WOS | -- | Communal Storage | SSD / S3 |
| SAP HANA | 内存 | 扩展存储 NSE | DTE | RAM / SSD / HDD |
| Teradata | Temperature (Very Hot) | Hot / Warm | Cold / VeryCold | SSD / HDD |
| Firebolt | F3（本地 SSD 缓存） | -- | S3 | NVMe / S3 |

### 自动迁移策略对比

| 引擎 | 迁移触发条件 | 配置粒度 | 可编程性 |
|------|------------|---------|---------|
| Oracle ADO | 条件（时间/访问/空间） | 段 / 表 / 分区 | PL/SQL 策略 |
| Snowflake | 自动缓存淘汰（LRU） | 微分区 | 全自动，无配置 |
| BigQuery | 90 天未修改 | 分区级 | 全自动，无配置 |
| Redshift RA3 | 访问频率（热点缓存） | Block | 全自动，无配置 |
| ClickHouse | TTL 表达式 | 分区 / 部分 | SQL TTL 表达式 |
| TimescaleDB | 时间间隔 | Chunk | `add_tiering_policy` |
| Cassandra | Compaction 策略 | SSTable | 表级配置 |
| Vertica ATM | 访问频率 + 年龄 | Storage Location | SQL 策略 |
| SAP HANA DTE | 时间 / 访问热度 | 分区 | SQL 定义 |
| Hive | HDFS 存储策略 | 目录 | XML + ALTER |
| Doris | 时间 TTL | Partition | ALTER TABLE |
| StarRocks | 时间 TTL | Partition | ALTER TABLE |
| InfluxDB | Retention Policy | Measurement | CREATE RETENTION POLICY |

## 各引擎详解

### Oracle（最成熟的 ILM 实现）

Oracle 自 12c (2013) 引入 Automatic Data Optimization (ADO)，是传统数据库中最成熟的分层存储方案。

#### Heat Map（访问热度追踪）

```sql
-- 启用 Heat Map（数据库级）
ALTER SYSTEM SET HEAT_MAP = ON;

-- 查询段的访问热度
SELECT object_name, segment_write_time, segment_read_time, full_scan, lookup_scan
FROM v$heat_map_segment
WHERE object_name = 'SALES';

-- 查询块的最后修改时间
SELECT object_name, subobject_name, track_time, segment_write
FROM dba_heat_map_segment;
```

#### ADO 策略定义

```sql
-- 策略 1：行级压缩（180 天未修改）
ALTER TABLE sales ILM ADD POLICY
  ROW STORE COMPRESS ADVANCED
  ROW AFTER 180 DAYS OF NO MODIFICATION;

-- 策略 2：段级压缩（1 年未访问）
ALTER TABLE sales ILM ADD POLICY
  COLUMN STORE COMPRESS FOR QUERY HIGH
  SEGMENT AFTER 365 DAYS OF NO ACCESS;

-- 策略 3：归档压缩并迁移到低速表空间
ALTER TABLE sales ILM ADD POLICY
  COLUMN STORE COMPRESS FOR ARCHIVE HIGH
  SEGMENT AFTER 730 DAYS OF NO MODIFICATION
  TIER TO archive_tbs;

-- 策略 4：基于存储压力的自动迁移（读写变少时迁移）
ALTER TABLE sales ILM ADD POLICY
  TIER TO low_cost_tbs
  READ ONLY
  SEGMENT AFTER 365 DAYS OF NO MODIFICATION;

-- 查看策略
SELECT policy_name, object_name, action_type, condition_type, condition_days
FROM user_ilmpolicies;

-- 手动执行 ADO 评估
DECLARE
  task_id NUMBER;
BEGIN
  DBMS_ILM.EXECUTE_ILM(
    owner       => USER,
    object_name => 'SALES',
    execution_mode => DBMS_ILM.ILM_EXECUTION_OFFLINE,
    task_id     => task_id);
END;
/
```

#### 手动迁移

```sql
-- 整表迁移到其他表空间
ALTER TABLE sales MOVE TABLESPACE cold_tbs;

-- 分区迁移
ALTER TABLE sales MOVE PARTITION sales_2020 TABLESPACE cold_tbs;

-- 在线迁移（不阻塞 DML，12c+）
ALTER TABLE sales MOVE TABLESPACE cold_tbs ONLINE;

-- 标记分区只读 + 迁移 + 压缩（典型冷数据处理）
ALTER TABLE sales MOVE PARTITION sales_2020
  TABLESPACE cold_tbs
  COMPRESS FOR ARCHIVE HIGH
  ONLINE;
ALTER TABLE sales MODIFY PARTITION sales_2020 READ ONLY;
```

#### Oracle Autonomous Database 的分层存储

```sql
-- Autonomous Data Warehouse：自动对象存储分层
-- 数据默认存储于 Exadata，冷数据可迁移到对象存储

-- 外部表引用对象存储（冷数据查询）
CREATE TABLE sales_archive
  ORGANIZATION EXTERNAL (
    TYPE ORACLE_BIGDATA
    DEFAULT DIRECTORY DATA_PUMP_DIR
    ACCESS PARAMETERS (
      com.oracle.bigdata.fileformat=parquet
    )
    LOCATION ('https://objectstorage.us-ashburn-1.oraclecloud.com/...'))
  REJECT LIMIT UNLIMITED;
```

### SQL Server / Azure SQL（Stretch Database 已弃用）

SQL Server 2016 引入 Stretch Database，自动将冷数据迁移到 Azure，但于 2022 年宣布弃用，2025 年停止服务。

```sql
-- Stretch Database 配置（遗留语法，不推荐新项目使用）
-- 启用 Stretch（数据库级）
ALTER DATABASE SalesDB SET REMOTE_DATA_ARCHIVE = ON (
  SERVER = 'myazureserver.database.windows.net',
  CREDENTIAL = StretchCredential
);

-- 启用表级 Stretch，按谓词迁移
ALTER TABLE Orders
  SET (REMOTE_DATA_ARCHIVE = ON (
    FILTER_PREDICATE = dbo.StretchOldRows(OrderDate),
    MIGRATION_STATE = OUTBOUND));

-- 过滤函数定义哪些行是冷数据
CREATE FUNCTION dbo.StretchOldRows(@col DATETIME)
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
  SELECT 1 AS is_eligible
  WHERE @col < DATEADD(YEAR, -3, GETDATE());
```

SQL Server 2022 替代方案：手动归档 + 外部表 + Azure Managed Instance 存储层级。

```sql
-- Azure SQL Database Hyperscale：自动分层
-- 存储层级：本地 SSD -> Azure Page Server -> Long-term Azure Storage
-- 对用户透明，无需配置

-- Managed Instance General Purpose vs Business Critical
-- Business Critical：本地 SSD，适合热数据
-- General Purpose：Premium Storage，适合温/冷数据
```

### Snowflake（完全透明的自动分层）

Snowflake 架构天然分层：**计算节点本地 SSD 缓存（warehouse）** + **远端对象存储（S3/GCS/Azure Blob）**。用户无需感知，也无需配置。

```sql
-- 加载数据：自动分片为微分区（16MB 压缩）存入对象存储
COPY INTO orders FROM @mystage FILE_FORMAT = (TYPE = PARQUET);

-- 查询时：
-- 1. 首次访问某个微分区 -> 从对象存储下载到 warehouse 本地 SSD
-- 2. 后续访问该微分区 -> 直接命中本地 SSD 缓存
-- 3. Warehouse 挂起（SUSPEND）-> 本地缓存保留（部分）
-- 4. Warehouse 终止或扩容 -> 缓存失效，重新下载

-- 查看缓存命中
SELECT query_id,
       bytes_scanned,
       percentage_scanned_from_cache
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD(day, -1, CURRENT_TIMESTAMP());

-- 强制绕过缓存（用于性能测试）
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 仓库配置：更大的 warehouse = 更大的本地缓存
CREATE WAREHOUSE hot_wh WITH WAREHOUSE_SIZE = 'XLARGE';
-- XLARGE 约有 2TB 本地 SSD 缓存

-- 让热数据尽量留在缓存：利用 warehouse 亲和性
-- 将相同查询路由到同一个 warehouse（通过 resource monitor 或应用层路由）
```

**Snowflake 分层的特点**：
- 用户视角：**完全透明**，只有一个逻辑表
- 成本模型：存储按 T3 标准对象存储计费；Warehouse 本地 SSD 免费（含在计算费用中）
- 没有显式的"冷/热"迁移：数据永远在对象存储，热数据"复制"到缓存
- **Time Travel / Fail-safe 数据**：自动归档到对象存储的独立区域，成本更低

### BigQuery（长期存储自动降价）

BigQuery 的分层机制简单粗暴：**90 天内未修改的表/分区，存储价格自动降 50%**，查询性能和可见性无变化。

```sql
-- 创建分区表
CREATE TABLE dataset.sales (
  order_date DATE,
  customer_id INT64,
  amount FLOAT64
)
PARTITION BY order_date;

-- 加载历史数据
INSERT INTO dataset.sales VALUES
  ('2020-01-01', 1, 100.0),
  ('2025-04-22', 1000, 50.0);

-- 查看分区存储类型
SELECT table_name,
       partition_id,
       storage_tier,  -- ACTIVE 或 LONG_TERM
       total_bytes,
       total_logical_bytes
FROM `dataset.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'sales';

-- storage_tier = 'LONG_TERM' 时价格自动减半
-- 每次分区被修改（INSERT / UPDATE / DELETE / MERGE）重置 90 天计时

-- 强制不修改冷数据（保持长期存储资格）
CREATE TABLE dataset.sales_archive
PARTITION BY order_date
AS SELECT * FROM dataset.sales
WHERE order_date < DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR);

-- 之后避免对 sales_archive 的任何 DML，即可享受 50% 折扣
```

**BigQuery 长期存储特点**：
- 自动化程度：**100%**，无需用户配置
- 粒度：分区级（如果是分区表），否则整表
- 查询价格：与 ACTIVE 分区相同
- 重置条件：任何修改操作（包括 schema 变更）都会重置计时器

### Redshift RA3（存算分离）

Redshift RA3 节点（2019 发布）实现了存算分离：**Managed Storage (S3)** 为持久化层，**本地 NVMe SSD** 为缓存。

```sql
-- RA3 节点类型
-- ra3.xlplus / ra3.4xlarge / ra3.16xlarge
-- 存储层：Redshift Managed Storage（RMS，基于 S3）
-- 计算层：本地 NVMe SSD 作为热数据缓存

-- 查看本地缓存使用情况
SELECT node,
       slice,
       used_perm_cache_kb,
       blocks_cached,
       blocks_on_disk
FROM stv_partitions;

-- Concurrency Scaling：自动弹性计算集群
-- 冷数据查询自动路由到新集群，不影响主集群性能
ALTER USER analyst SET enable_result_cache_for_session TO off;

-- 查看查询是否使用了 Concurrency Scaling 集群
SELECT query, concurrency_scaling_status, userid
FROM stl_query
WHERE starttime > GETDATE() - INTERVAL '1 hour';

-- Redshift Spectrum（冷数据层：S3 Parquet/ORC）
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'spectrum_db'
IAM_ROLE 'arn:aws:iam::...:role/RedshiftSpectrumRole';

CREATE EXTERNAL TABLE spectrum_schema.orders_archive (
  order_id BIGINT,
  order_date DATE,
  amount DECIMAL(10,2))
STORED AS PARQUET
LOCATION 's3://my-data-lake/orders/';

-- 统一查询热数据 + 冷数据
SELECT * FROM sales      -- 热数据：Managed Storage
UNION ALL
SELECT * FROM spectrum_schema.orders_archive;  -- 冷数据：S3
```

### ClickHouse（最灵活的存储策略）

ClickHouse 从 19.15 引入多磁盘支持，22.3 (2022) 稳定支持 S3 disk，是开源世界最成熟的分层存储方案。

#### 存储配置

```xml
<!-- /etc/clickhouse-server/config.d/storage.xml -->
<yandex>
  <storage_configuration>
    <disks>
      <default>
        <path>/var/lib/clickhouse/</path>
      </default>
      <hot_ssd>
        <path>/mnt/nvme/clickhouse/</path>
      </hot_ssd>
      <warm_hdd>
        <path>/mnt/hdd/clickhouse/</path>
      </warm_hdd>
      <cold_s3>
        <type>s3</type>
        <endpoint>https://s3.amazonaws.com/my-bucket/clickhouse/</endpoint>
        <access_key_id>AKIA...</access_key_id>
        <secret_access_key>...</secret_access_key>
      </cold_s3>
    </disks>

    <policies>
      <tiered>
        <volumes>
          <hot>
            <disk>hot_ssd</disk>
            <max_data_part_size_bytes>107374182400</max_data_part_size_bytes> <!-- 100GB -->
          </hot>
          <warm>
            <disk>warm_hdd</disk>
          </warm>
          <cold>
            <disk>cold_s3</disk>
          </cold>
        </volumes>
        <move_factor>0.1</move_factor>  <!-- 当热层剩余 < 10% 时触发迁移 -->
      </tiered>
    </policies>
  </storage_configuration>
</yandex>
```

#### 表级 TTL 与自动迁移

```sql
-- 创建带 TTL 的表：自动在层间迁移
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    event_type String,
    payload String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
TTL event_time + INTERVAL 7 DAY TO VOLUME 'warm',
    event_time + INTERVAL 90 DAY TO VOLUME 'cold',
    event_time + INTERVAL 365 DAY DELETE
SETTINGS storage_policy = 'tiered';

-- 查看各层使用情况
SELECT
    disk_name,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE active AND table = 'events'
GROUP BY disk_name;

-- 手动迁移特定分区
ALTER TABLE events
MOVE PARTITION '202401' TO VOLUME 'cold';

ALTER TABLE events
MOVE PART '202401_1_100_5' TO DISK 'cold_s3';

-- 查看 TTL 策略
SELECT database, table, move_ttl_info
FROM system.tables
WHERE name = 'events';

-- 动态修改 TTL
ALTER TABLE events MODIFY TTL
    event_time + INTERVAL 30 DAY TO VOLUME 'warm',
    event_time + INTERVAL 180 DAY TO VOLUME 'cold';

-- 触发后台合并迁移
OPTIMIZE TABLE events PARTITION '202401' FINAL;
```

#### S3 disk 与零拷贝复制

```sql
-- ClickHouse 22.3+ 支持 S3 disk 零拷贝复制
-- 多副本共享同一份 S3 数据，副本间只同步元数据

SELECT name, is_replicated, zero_copy
FROM system.disks
WHERE type = 's3';

-- S3 disk 性能调优
SET s3_max_connections = 100;
SET s3_max_single_part_upload_size = 67108864;  -- 64MB
SET s3_min_upload_part_size = 33554432;          -- 32MB
```

### Cassandra（基于 Compaction 策略的隐式分层）

Cassandra 的"分层"通过 Compaction 策略和分层 SSTable 隐式实现：

```sql
-- 时间窗口压缩策略（TWCS）：按时间分组 SSTable
CREATE TABLE events (
    event_time timestamp,
    user_id uuid,
    data text,
    PRIMARY KEY ((user_id), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC)
AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_size': 1,
    'compaction_window_unit': 'DAYS',
    'max_threshold': 32
}
AND default_time_to_live = 7776000;  -- 90 天自动删除

-- 统一压缩策略（UCS，4.1+）
ALTER TABLE events WITH compaction = {
    'class': 'UnifiedCompactionStrategy',
    'scaling_parameters': 'T4, T4, L4',
    'min_sstable_size_in_mb': '100'
};

-- Cassandra 没有原生的热/冷存储层
-- 冷数据方案：降采样 + 外部归档
-- DataStax Astra DB 提供云端自动分层
```

### InfluxDB（保留策略 + 降采样）

```sql
-- InfluxQL：创建保留策略
CREATE RETENTION POLICY "one_week" ON "metrics"
  DURATION 7d REPLICATION 1 DEFAULT;

CREATE RETENTION POLICY "one_year" ON "metrics"
  DURATION 365d REPLICATION 1;

-- 连续查询：降采样 + 跨 RP 迁移
CREATE CONTINUOUS QUERY "cq_hourly" ON "metrics"
BEGIN
  SELECT mean("value") INTO "one_year"."cpu_1h"
  FROM "one_week"."cpu"
  GROUP BY time(1h), host
END;

-- InfluxDB Cloud：Parquet 冷数据存储
-- 原始数据保留 N 天，降采样后迁移到 Parquet (S3)
-- Flight SQL 接口可统一查询
```

### TimescaleDB（Cloud 独有 S3 分层）

TimescaleDB OSS 只支持压缩，**分层到 S3 仅 Cloud 版本可用**。

```sql
-- 创建 hypertable
SELECT create_hypertable('sensor_data', 'time',
    chunk_time_interval => INTERVAL '1 day');

-- 启用列压缩（OSS + Cloud 均支持）
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',
    timescaledb.compress_orderby = 'time DESC');

-- 压缩策略：7 天后自动压缩
SELECT add_compression_policy('sensor_data', INTERVAL '7 days');

-- 分层策略（仅 Cloud 可用，需 Timescale Cloud）
-- 3 个月前的 chunk 自动迁移到 S3
SELECT add_tiering_policy('sensor_data', INTERVAL '3 months');

-- 查看分层状态
SELECT hypertable_name, chunk_name,
       chunk_tablespace, is_tiered,
       pg_size_pretty(chunk_size) AS size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data';

-- 手动下沉某个 chunk
CALL tier_chunk('_timescaledb_internal._hyper_1_5_chunk');

-- 恢复某个 chunk 到本地
CALL untier_chunk('_timescaledb_internal._hyper_1_5_chunk');

-- 删除分层策略
SELECT remove_tiering_policy('sensor_data');
```

### TiDB（TiFlash + 冷存储实验性）

```sql
-- TiDB 原生架构：
-- TiKV：行存，OLTP（热数据默认存储）
-- TiFlash：列存，OLAP 副本（按表启用）

-- 为表添加 TiFlash 副本（列存分析层）
ALTER TABLE orders SET TIFLASH REPLICA 1;

-- 查看副本同步状态
SELECT table_schema, table_name, replica_count, available
FROM information_schema.tiflash_replica
WHERE table_name = 'orders';

-- 查询自动路由到 TiFlash
SET @@tidb_isolation_read_engines = 'tiflash,tikv';
SELECT SUM(amount), COUNT(*) FROM orders;  -- 使用 TiFlash

-- TiDB 7.0+：TiFlash 存算分离 + S3 冷层（实验性）
-- 配置 TiFlash 使用 S3 作为持久层
-- [storage.s3]
-- endpoint = "http://s3.amazonaws.com"
-- bucket = "tiflash-cold"

-- 表级配置 placement rule 冷数据到特定节点
CREATE PLACEMENT POLICY cold_policy
    CONSTRAINTS = "[+zone=cold]";

ALTER TABLE orders PARTITION p2020
    PLACEMENT POLICY = cold_policy;
```

### StarRocks / Doris（共享数据 / 冷数据模式）

#### StarRocks 3.0+ 共享数据（Shared-Data）

```sql
-- StarRocks 3.0 架构：存算分离
-- FE：元数据
-- CN：计算节点（本地 SSD 缓存）
-- 对象存储：持久化数据

-- 创建共享数据集群的存储卷
CREATE STORAGE VOLUME s3_vol
TYPE = S3
LOCATIONS = ("s3://my-bucket/starrocks/")
PROPERTIES (
    "aws.s3.region" = "us-west-2",
    "aws.s3.access_key" = "...",
    "aws.s3.secret_key" = "...",
    "enabled" = "true");

-- 创建表并指定存储卷
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(10,2),
    order_time DATETIME
)
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_time) (
    START ("2024-01-01") END ("2025-12-31") EVERY (INTERVAL 1 MONTH)
)
DISTRIBUTED BY HASH(order_id) BUCKETS 32
PROPERTIES (
    "storage_volume" = "s3_vol",
    "datacache.enable" = "true",       -- 启用本地 SSD 缓存
    "datacache.partition_duration" = "30 days"  -- 缓存 30 天的分区
);

-- 查看缓存命中率
SELECT be_id, disk_name, path, usage_bytes, hit_ratio
FROM information_schema.be_datacache_metrics;
```

#### Doris 2.0+ 冷数据

```sql
-- 创建 S3 资源
CREATE RESOURCE "s3_cold" PROPERTIES (
    "type" = "s3",
    "s3.endpoint" = "s3.amazonaws.com",
    "s3.region" = "us-west-2",
    "s3.bucket" = "doris-cold",
    "s3.root.path" = "/cold",
    "s3.access_key" = "...",
    "s3.secret_key" = "...");

-- 创建存储策略：7 天后迁移到 S3
CREATE STORAGE POLICY cold_policy
PROPERTIES (
    "storage_resource" = "s3_cold",
    "cooldown_ttl" = "604800"  -- 7 天（秒）
);

-- 表级应用策略
CREATE TABLE events (
    event_time DATETIME,
    user_id BIGINT,
    payload STRING
)
DUPLICATE KEY(event_time)
PARTITION BY RANGE(event_time) (
    PARTITION p202501 VALUES LESS THAN ("2025-02-01"),
    PARTITION p202502 VALUES LESS THAN ("2025-03-01")
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES (
    "storage_policy" = "cold_policy",
    "replication_num" = "3"
);

-- 分区级应用策略（更细粒度）
ALTER TABLE events MODIFY PARTITION p202501
SET ("storage_policy" = "cold_policy");

-- 查看分区的存储状态
SHOW PARTITIONS FROM events;
-- StorageMedium = REMOTE 表示已在冷层
```

### Vertica（Storage Locations + ATM）

```sql
-- 创建不同速度的存储位置
CREATE LOCATION '/mnt/nvme/vertica' ALL NODES USAGE 'DATA,TEMP' LABEL 'hot';
CREATE LOCATION '/mnt/hdd/vertica' ALL NODES USAGE 'DATA' LABEL 'cold';

-- 配置存储策略
SELECT SET_OBJECT_STORAGE_POLICY('sales', 'hot');
SELECT SET_OBJECT_STORAGE_POLICY('sales', 'cold',
    '2024-01-01'::TIMESTAMP);  -- 指定迁移时间

-- Active Tier Manager (ATM)：按年龄自动分层
ALTER TABLE sales SET ACTIVEPARTITIONCOUNT 2;
-- 只保留最近 2 个活跃分区在 hot tier

-- Vertica Eon Mode（云原生存算分离）
-- 数据存储于 S3 (Communal Storage)
-- 计算节点（Subcluster）有本地 Depot 缓存
ALTER SUBCLUSTER analytics_sc SET DEPOT_SIZE '2T';

-- 查看 Depot 命中率
SELECT node_name, used_bytes, max_bytes,
       (used_bytes / max_bytes * 100) AS usage_pct
FROM depot_sizes;
```

### Greenplum / Trino（外部表作为冷层）

```sql
-- Greenplum PXF：访问 Hadoop/S3 作为冷数据
CREATE EXTERNAL TABLE orders_archive (
    order_id BIGINT,
    order_date DATE,
    amount DECIMAL(10,2))
LOCATION ('pxf://s3a://my-bucket/orders/?PROFILE=s3:parquet')
FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

-- 统一视图（热 + 冷）
CREATE VIEW orders_all AS
SELECT * FROM orders WHERE order_date >= CURRENT_DATE - INTERVAL '1 year'
UNION ALL
SELECT * FROM orders_archive WHERE order_date < CURRENT_DATE - INTERVAL '1 year';

-- Trino / Presto：跨连接器查询实现分层
CREATE TABLE hive.warehouse.orders_hot (...)  -- HDFS 本地
WITH (format = 'ORC');

CREATE TABLE iceberg.archive.orders_cold (...)  -- S3 Iceberg
WITH (location = 's3://archive/orders/');

-- 联邦查询：Trino 自动跨引擎 JOIN
SELECT *
FROM hive.warehouse.orders_hot h
LEFT JOIN iceberg.archive.orders_cold c ON h.user_id = c.user_id;
```

### SingleStore（Unlimited Storage）

```sql
-- SingleStore Unlimited Storage：自动分层到 S3
-- Rowstore：内存 + 本地 SSD（热数据）
-- Columnstore：本地 SSD + S3（Bottomless Storage）

CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    order_date DATE,
    amount DECIMAL(10,2),
    SORT KEY (order_date)
);

-- 配置 Bottomless（Unlimited Storage）
-- 列存分段（segment）自动下沉到 S3
SET GLOBAL bottomless_storage_enabled = 1;

-- 查看 segment 在本地和 S3 的分布
SELECT partition_id,
       segment_id,
       rows,
       on_disk_bytes,
       offload_bytes  -- 已下沉到 S3 的字节数
FROM information_schema.columnar_segments;
```

### SAP HANA（NSE + DTE）

```sql
-- SAP HANA Native Storage Extension (NSE)
-- 将热数据保留在内存，温/冷数据放在 SSD（page loadable）

-- 创建 NSE 表（column loadable = 热，page loadable = 温）
CREATE COLUMN TABLE sales_hot (...) PAGE LOADABLE;
CREATE COLUMN TABLE sales_warm (...) PAGE LOADABLE;

-- 分区级别控制
CREATE COLUMN TABLE sales (
    order_id BIGINT,
    order_date DATE,
    amount DECIMAL(10,2))
PARTITION BY RANGE(YEAR(order_date)) (
    PARTITION VALUE <= 2023 PAGE LOADABLE,    -- 冷
    PARTITION VALUE <= 2024 COLUMN LOADABLE,  -- 热
    PARTITION OTHERS COLUMN LOADABLE
);

-- Data Tiering Extension (DTE)：冷数据迁移到 Hadoop/S3
-- 使用 SAP Data Hub / Data Warehouse Cloud 进行自动迁移
```

### Teradata（Temperature-Based Optimization）

```sql
-- Teradata 的 Virtual Storage / Intelligent Memory
-- 温度自动追踪：VERY HOT, HOT, WARM, COLD, VERY COLD
-- 数据在不同速度的存储介质间自动迁移（SSD / HDD）

-- 查询表的温度分布
SELECT DatabaseName, TableName, TemperatureState,
       SUM(CurrentPerm) / 1024 / 1024 AS MB
FROM DBC.TablesV T
WHERE TableName = 'sales'
GROUP BY DatabaseName, TableName, TemperatureState;

-- 强制将表设为 VERY HOT（固定在最快存储）
BTEQ> FERRET
FERRET> TEMPERATURE HOT -t my_database.sales;

-- Teradata Cloud：自动对象存储分层（AWS S3）
```

## Oracle ILM / ADO 策略深度剖析

### Heat Map 工作原理

Oracle Heat Map 在块级追踪访问热度，数据存储在 `SYS.HEAT_MAP_STAT$` 表中：

- **Segment-Level**：最近一次读/写、全扫描、索引查找时间
- **Block-Level**：最近一次修改时间（用于 row compression 策略）

```sql
-- 设置 Heat Map（数据库级别永久启用）
ALTER SYSTEM SET HEAT_MAP = ON SCOPE = BOTH;

-- 查询某表的访问统计
SELECT object_name,
       segment_write_time,
       segment_read_time,
       full_scan,
       lookup_scan
FROM v$heat_map_segment
WHERE object_name = 'SALES' AND subobject_name IS NULL;

-- 块级修改时间（用于 ROW AFTER N DAYS OF NO MODIFICATION）
SELECT object_name,
       subobject_name,
       track_time,
       segment_write
FROM dba_heat_map_segment
WHERE object_name = 'SALES'
ORDER BY track_time DESC;
```

### ADO 策略的三类动作

| 动作 | 关键字 | 典型用途 |
|------|--------|---------|
| 压缩 | `COMPRESS FOR ...` | 节省空间，不换层 |
| 迁移 | `TIER TO <tablespace>` | 物理迁移到慢速存储 |
| 只读 | `READ ONLY` | 归档标记，减少备份开销 |

```sql
-- 复合策略：180 天后压缩，365 天后迁移到归档表空间
ALTER TABLE sales ILM ADD POLICY
  COMPRESS ADVANCED
  ROW AFTER 180 DAYS OF NO MODIFICATION;

ALTER TABLE sales ILM ADD POLICY
  TIER TO archive_tbs
  SEGMENT AFTER 365 DAYS OF NO MODIFICATION;

-- 基于表空间压力触发
ALTER TABLE sales ILM ADD POLICY
  TIER TO low_cost_tbs
  SEGMENT;  -- 无条件时子句，由 DBMS_ILM 判断空间压力

-- 分区级策略
ALTER TABLE sales MODIFY PARTITION sales_2020
  ILM ADD POLICY COMPRESS FOR ARCHIVE HIGH
  SEGMENT AFTER 730 DAYS OF NO MODIFICATION;

-- 条件类型
-- NO MODIFICATION（无修改）
-- NO ACCESS（无访问，包括读和写）
-- CREATION（自创建起）
```

### ADO 任务监控

```sql
-- 查看 ADO 任务
SELECT task_id, state, creation_time, completion_time
FROM dba_ilmtasks
ORDER BY creation_time DESC;

-- 查看执行的动作
SELECT task_id, policy_name, object_name, action_type,
       job_state, comments
FROM dba_ilmresults
ORDER BY task_id DESC;

-- 手动触发评估
DECLARE
  task_id NUMBER;
BEGIN
  DBMS_ILM.EXECUTE_ILM(
    owner          => 'SALES_OWNER',
    object_name    => 'SALES',
    execution_mode => DBMS_ILM.ILM_EXECUTION_OFFLINE,
    task_id        => task_id);
  DBMS_OUTPUT.PUT_LINE('Task ID: ' || task_id);
END;
/

-- 设置 ADO 执行窗口（只在维护窗口执行）
BEGIN
  DBMS_ILM_ADMIN.CUSTOMIZE_ILM(
    DBMS_ILM_ADMIN.EXECUTION_MODE,
    DBMS_ILM_ADMIN.ILM_EXECUTION_OFFLINE);
  DBMS_ILM_ADMIN.CUSTOMIZE_ILM(
    DBMS_ILM_ADMIN.POLICY_TIME,
    DBMS_ILM_ADMIN.ILM_POLICY_IN_DAYS);
END;
/
```

## ClickHouse 存储策略与 S3 disk 深度剖析

### 多卷存储策略

```xml
<!-- 复杂策略：3 层 + move_factor -->
<policies>
  <three_tier>
    <volumes>
      <hot>
        <disk>fast_nvme</disk>
        <max_data_part_size_bytes>53687091200</max_data_part_size_bytes> <!-- 50GB -->
      </hot>
      <warm>
        <disk>sata_hdd</disk>
        <max_data_part_size_bytes>536870912000</max_data_part_size_bytes> <!-- 500GB -->
      </warm>
      <cold>
        <disk>s3_disk</disk>
      </cold>
    </volumes>
    <move_factor>0.2</move_factor>
    <!-- 当 hot 剩余 < 20% 时，后台将最老的 part 迁移到 warm -->
  </three_tier>
</policies>
```

### 迁移的三种触发方式

```sql
-- 1. 空间压力触发（move_factor）
-- 后台任务监控各卷的可用空间，超过阈值时自动迁移最老的 part

-- 2. TTL 表达式触发
CREATE TABLE logs (
    event_time DateTime,
    message String
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY event_time
TTL event_time + INTERVAL 1 DAY TO DISK 'warm_hdd',
    event_time + INTERVAL 7 DAYS TO DISK 'cold_s3',
    event_time + INTERVAL 90 DAYS DELETE
SETTINGS storage_policy = 'tiered';

-- 3. 手动 ALTER 触发
ALTER TABLE logs MOVE PART 'all_1_1_0' TO DISK 'cold_s3';
ALTER TABLE logs MOVE PARTITION '20240101' TO VOLUME 'warm';
```

### S3 disk 的性能考量

```sql
-- S3 disk 性能优化参数（system.merge_tree_settings）
SELECT name, value FROM system.merge_tree_settings
WHERE name LIKE 's3_%' OR name LIKE 'storage_%';

-- 关键参数：
-- s3_max_connections：S3 连接池大小（默认 1024）
-- s3_min_upload_part_size：分片上传最小块（默认 32MB）
-- s3_max_single_part_upload_size：单次上传最大块（默认 32MB）
-- s3_cache_path：本地 S3 缓存路径
-- enable_filesystem_cache：启用文件系统缓存

-- 查询性能：热分区在本地，冷分区在 S3
EXPLAIN PIPELINE
SELECT count() FROM logs WHERE event_time > now() - INTERVAL 1 HOUR;
-- 仅扫描本地热数据

EXPLAIN PIPELINE
SELECT count() FROM logs WHERE event_time > now() - INTERVAL 90 DAY;
-- 跨层扫描：hot + warm + cold
```

### S3 disk 零拷贝复制（22.3+）

```xml
<storage_configuration>
  <disks>
    <s3_shared>
      <type>s3</type>
      <endpoint>https://s3.amazonaws.com/bucket/</endpoint>
      <access_key_id>...</access_key_id>
      <secret_access_key>...</secret_access_key>
      <support_batch_delete>true</support_batch_delete>
      <zero_copy>true</zero_copy>  <!-- 启用零拷贝 -->
    </s3_shared>
  </disks>
</storage_configuration>
```

零拷贝语义：多副本共享 S3 上同一份数据文件，只同步元数据（part 信息）。写入时只有一个副本真正上传。

## Snowflake 完全透明的分层

### 架构三层

```
┌─────────────────────────────────────────┐
│  Cloud Services (元数据、查询编译)         │
├─────────────────────────────────────────┤
│  Compute (Virtual Warehouses)            │
│    ├── XS (8 GB RAM, ~60 GB SSD cache)   │
│    ├── S, M, L                            │
│    └── XXL (2560 GB RAM, ~16 TB SSD)     │
├─────────────────────────────────────────┤
│  Storage (S3/GCS/Azure Blob)             │
│    └── 16 MB micro-partitions (columnar)  │
└─────────────────────────────────────────┘
```

### 缓存层级

```sql
-- 三级缓存
-- L1: Result Cache (24 小时，跨 warehouse)
-- L2: Metadata Cache (pruning 信息)
-- L3: Warehouse Local Disk Cache (SSD, LRU)

-- 查看缓存命中
SELECT query_id,
       warehouse_name,
       bytes_scanned,
       bytes_scanned / 1024 / 1024 AS mb_scanned,
       percentage_scanned_from_cache,
       total_elapsed_time
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD(hour, -1, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;

-- 查看 warehouse 缓存统计（近似）
SHOW WAREHOUSES LIKE 'ANALYTICS_WH';

-- 检查 Query Acceleration Service（冷查询加速）
ALTER WAREHOUSE analytics_wh SET
  QUERY_ACCELERATION_MAX_SCALE_FACTOR = 8;
```

### 存储的自动管理

Snowflake 的存储完全由平台管理，用户可见信息：

```sql
-- 查看表的存储字节数
SELECT table_name,
       active_bytes,        -- 活跃存储
       time_travel_bytes,   -- Time Travel 保留（1-90 天）
       failsafe_bytes,      -- Fail-safe 保留（7 天）
       retained_for_clone_bytes  -- 克隆保留
FROM snowflake.account_usage.table_storage_metrics
WHERE table_name = 'SALES';

-- 所有数据物理上都在对象存储
-- Warehouse 本地缓存在查询时按需下载
-- 没有 "冷数据迁移" 的概念，只有 "未缓存的数据"
```

## 关键发现

### 1. 分层存储的三种实现范式

- **显式策略**（Oracle ILM、ClickHouse Storage Policy、Doris）：用户声明规则，引擎执行。最灵活但需要 DBA 理解细节。
- **自动透明**（Snowflake、BigQuery、Redshift RA3）：用户完全无感，存储层自动管理。零运维但失去控制力。
- **存算分离架构**（StarRocks 3.0、Vertica Eon、Firebolt、SingleStore）：天然将数据放在对象存储，通过本地缓存模拟"热层"。

### 2. 云原生分析引擎全面拥抱对象存储

自 2019 年 Redshift RA3 发布以来，云原生引擎几乎都已采用对象存储作为持久层：

- Snowflake：S3/GCS/Azure Blob（GA 起）
- Redshift：RA3 Managed Storage (S3)（2019）
- Databricks：Delta Lake on S3/ADLS/GCS
- StarRocks 3.0：S3/HDFS（2023）
- Doris 2.0：S3（2023）
- Firebolt：F3 + S3（GA）
- DatabendDB：S3（GA）
- RisingWave：S3（GA）

### 3. 传统数据库的分层存储能力差距巨大

- Oracle 是传统数据库中唯一提供完整 ILM 能力的（自 12c, 2013）
- SQL Server 的 Stretch Database 方案失败（2022 弃用，2025 停服）
- PostgreSQL 仅有表空间，依赖外部工具或扩展（如 Citus, TimescaleDB Cloud）
- MySQL/MariaDB 完全没有原生分层存储
- 中小型数据库（SQLite、Firebird、H2、HSQLDB、Derby）全部不支持

### 4. 时序/流数据库的特殊模型

- InfluxDB：Retention Policy + Continuous Query 降采样
- TimescaleDB：Chunk 自动压缩 + Cloud 独有 S3 分层
- QuestDB：Parquet + 对象存储（7.0+）
- Cassandra：TWCS 时间窗口压缩

时序场景天然适合分层：数据热度随时间快速衰减，TTL + 降采样是标准模式。

### 5. 迁移的触发条件设计

| 触发条件 | 代表引擎 | 优缺点 |
|---------|---------|--------|
| 时间 TTL | ClickHouse、Doris、InfluxDB | 简单但僵化，无法识别"老而热"数据 |
| 访问热度 | Oracle ADO、Teradata、Vertica ATM | 智能但配置复杂 |
| 空间压力 | ClickHouse move_factor | 自动响应容量，但可能误迁热数据 |
| 未修改时间 | Oracle、BigQuery | 适合归档场景（历史不变） |
| 完全自动 | Snowflake、Redshift | 零配置但失去控制 |

### 6. 查询透明度是分水岭

用户查询时是否需要区分"数据在哪一层"：

- **完全透明**：Snowflake、BigQuery、Redshift、ClickHouse（单表跨层）
- **半透明**：传统分区表（跨分区自动 UNION）
- **不透明**：外部表方案（Trino/Presto/Hive 显式 UNION ALL 冷热表）

查询透明是现代分层存储的基本要求，任何要求用户手写 UNION 的方案都难以在生产中规模化。

### 7. 成本效益的典型数据

- BigQuery 长期存储：节省 50% 存储成本
- Snowflake S3 vs 本地 SSD：S3 约 $0.023/GB/月 vs NVMe 约 $0.20+/GB/月，差 ~10 倍
- Oracle ADO Archive Compression：行级压缩比 4-10x，归档压缩 20-50x
- Redshift RA3 vs DC2：存储按需付费，不再为冷数据支付计算成本
- ClickHouse S3 disk：S3 成本约为本地 SSD 的 1/10，但查询延迟增加 10-100ms

### 8. 与冷备份的边界模糊

分层存储的冷层和备份归档的边界越来越模糊：

- Snowflake Time Travel（1-90 天）+ Fail-safe（7 天）本质是自动冷备份
- AWS Glacier 的行为类似 SQL 外部表（查询需要先还原）
- Oracle ADO 的 `READ ONLY` + 归档压缩接近备份语义

### 9. 实现上的工程挑战

- **元数据一致性**：数据在多层时，元数据（统计信息、索引）必须准确
- **迁移的原子性**：迁移过程中的查询语义（读旧还是读新？）
- **跨层 JOIN**：冷数据 JOIN 热数据时的性能悬崖
- **缓存一致性**：本地缓存与远端存储的失效机制
- **云账单震惊**：S3 请求费用可能超过存储费用本身（查询冷数据时 GET 请求爆发）

### 10. 未来趋势

- **向量/AI 数据的分层**：OpenSearch、Pinecone 等向量库开始支持冷存储（大部分向量很少被查询）
- **Iceberg/Delta/Hudi 成为事实标准冷层**：任何分析引擎都可以读 S3 上的 Iceberg 表
- **S3 Express One Zone**：低延迟 S3（~1ms）模糊了温冷层的界限
- **FDW / Foreign Data Wrappers 复兴**：PostgreSQL 社区希望通过 FDW 对接 Iceberg 实现分层

## 参考资料

- Oracle: [Automatic Data Optimization](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/ilm-ado-overview.html)
- Oracle: [ILM and Heat Map](https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/ilm.html)
- SQL Server: [Stretch Database (deprecated)](https://learn.microsoft.com/en-us/sql/sql-server/stretch-database/stretch-database)
- Snowflake: [Storage Cost Optimization](https://docs.snowflake.com/en/user-guide/data-lifecycle)
- BigQuery: [Long-term Storage Pricing](https://cloud.google.com/bigquery/pricing#long-term-storage)
- Redshift: [RA3 Node Types](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-clusters.html#rs-ra3-node-types)
- ClickHouse: [Storage Policies and Tiering](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-multiple-volumes)
- ClickHouse: [S3 Table Engine](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)
- Cassandra: [TimeWindowCompactionStrategy](https://cassandra.apache.org/doc/latest/cassandra/managing/operating/compaction/twcs.html)
- InfluxDB: [Retention Policies](https://docs.influxdata.com/influxdb/v1/query_language/manage-database/#retention-policy-management)
- TimescaleDB: [Data Tiering](https://docs.timescale.com/use-timescale/latest/data-tiering/)
- TiDB: [TiFlash Storage](https://docs.pingcap.com/tidb/stable/tiflash-overview)
- StarRocks: [Shared-Data Cluster](https://docs.starrocks.io/docs/deployment/shared_data/)
- Doris: [Cold/Hot Data Separation](https://doris.apache.org/docs/admin-manual/cluster-management/resource-management)
- Vertica: [Storage Locations](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AdministratorsGuide/StorageLocations/ManagingStorageLocations.htm)
- SingleStore: [Unlimited Storage](https://docs.singlestore.com/cloud/reference/configuration-reference/unlimited-storage/)
- SAP HANA: [Native Storage Extension](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/4efaa94f8057425c8c7021da6fc2ddf5.html)
- Teradata: [Virtual Storage](https://docs.teradata.com/r/Teradata-VantageTM-Virtual-Storage)
