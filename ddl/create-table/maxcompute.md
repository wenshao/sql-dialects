# MaxCompute (ODPS): CREATE TABLE

> 参考资料:
> - [1] MaxCompute SQL - CREATE TABLE
>   https://help.aliyun.com/zh/maxcompute/user-guide/create-table-1
> - [2] MaxCompute SQL - Data Types
>   https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
> - [3] MaxCompute 存储架构 - AliORC
>   https://help.aliyun.com/zh/maxcompute/product-overview/storage-architecture


## 1. 基本建表


### 1.0 类型系统（默认，Hive 兼容）: 只有 BIGINT/DOUBLE/STRING/BOOLEAN/DATETIME

```sql
CREATE TABLE users (
    id         BIGINT NOT NULL,
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    balance    DECIMAL(10,2),
    created_at DATETIME
)
COMMENT '用户表'
LIFECYCLE 365;                              -- 365 天后自动回收

```

### 2.0 类型系统: 开启后可用 INT/FLOAT/VARCHAR/CHAR/TIMESTAMP/DATE/DECIMAL(p,s)/JSON

```sql
SET odps.sql.type.system.odps2 = true;

CREATE TABLE users_v2 (
    id         BIGINT NOT NULL,
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2),
    bio        STRING,
    created_at TIMESTAMP,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true'); -- 事务表才能声明 PK

```

## 2. 分区表 —— MaxCompute 最核心的建表模式


设计决策: 分区列不是普通列
值编码在目录路径中: /orders/dt=20240115/region=cn/data_files
不存储在 AliORC 数据文件中
对比 BigQuery/Snowflake: 分区列是普通列，分区对用户透明
Hive/MaxCompute: 分区列与数据列行为不一致（SELECT * 时分区列在最后）

```sql
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_time DATETIME
)
PARTITIONED BY (
    dt     STRING,                          -- 日期分区 '20240115'
    region STRING                           -- 二级分区
)
LIFECYCLE 90;

```

 设计分析: LIFECYCLE 是 MaxCompute 独创的存储治理 DDL 化
   将 TTL 声明在建表语句中，避免维护外部定时清理任务
   对比:
     ClickHouse:  TTL timestamp + INTERVAL 90 DAY（在表引擎中定义）
     BigQuery:    partition_expiration_days 选项
     Hive:        无内置 TTL，依赖外部调度删除旧分区
     Snowflake:   DATA_RETENTION_TIME_IN_DAYS（只影响 Time Travel，不自动删除）
   对引擎开发者: 新引擎应在 CREATE TABLE 中原生支持 TTL/LIFECYCLE

## 3. 事务表 vs 普通表 —— 两种截然不同的存储引擎


### 3.1 普通表（默认）: 不可变文件模型

   写入方式: INSERT INTO（追加）/ INSERT OVERWRITE（整分区替换）
   不支持 UPDATE/DELETE
   底层存储: AliORC 文件直接写入盘古分布式文件系统
   优势: 写入快、存储紧凑、读取高效
   适用: 事实表、日志表等海量追加写入场景

### 3.2 事务表: Delta File + Compaction 模型

```sql
CREATE TABLE users_transactional (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

```

   写入方式: INSERT/UPDATE/DELETE/MERGE 均支持
   底层实现: 基础文件 + delta 文件，定期 compaction 合并
   对比:
     Hive ACID:   相同架构（base + delta + delete delta + compaction）
     Delta Lake:  Parquet 文件 + JSON 事务日志，类似思路
     Iceberg:     Parquet + Avro manifest，行级 delete 文件
   代价: 读取时需要合并 delta，小文件增多需要 compaction
   适用: 维度表、需要行级更新的场景

## 4. 聚集表 —— 数据组织优化


Hash Clustering: 按 user_id 哈希分桶，桶内按 id 排序

```sql
CREATE TABLE orders_clustered (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

```

Range Clustering: 按 user_id 范围分桶

```sql
CREATE TABLE orders_range_clustered (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
RANGE CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

```

 设计分析:
   Hash Clustering 优化等值 JOIN（同 key 数据在同一桶，可做 bucket JOIN）
   Range Clustering 优化范围查询（有序数据支持范围裁剪）
   对比 Hive: CLUSTERED BY ... INTO N BUCKETS 语法完全相同
   对比 Spark: 3.0 引入 CLUSTER BY 但语义略不同
   对引擎开发者: 数据物理排列对 JOIN 性能影响巨大，值得在 DDL 中暴露

## 5. 外部表 —— 读取 OSS/其他存储


```sql
CREATE EXTERNAL TABLE oss_logs (
    col1 STRING,
    col2 BIGINT,
    col3 DATETIME
)
STORED BY 'com.aliyun.odps.CsvStorageHandler'
LOCATION 'oss://bucket/path/'
LIFECYCLE 30;

```

 外部表只读元数据，数据留在 OSS
 对比 BigQuery: EXTERNAL TABLE 读 GCS/Drive
 对比 Snowflake: STAGE + EXTERNAL TABLE

## 6. CTAS / LIKE / IF NOT EXISTS


```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > DATETIME '2024-01-01 00:00:00';

CREATE TABLE users_new LIKE users;

CREATE TABLE IF NOT EXISTS audit_log (
    id      BIGINT,
    action  STRING,
    detail  STRING
) LIFECYCLE 30;

```

## 7. 类型系统设计分析（对引擎开发者）


### 7.1 1.0 vs 2.0 两套类型系统并存 —— 一个深刻教训

   1.0（默认）: BIGINT/DOUBLE/STRING/BOOLEAN/DATETIME
     所有整数都是 BIGINT（8 字节），所有字符串都是 STRING
     简化了早期实现，但导致存储浪费和迁移困难
   2.0（需 SET odps.sql.type.system.odps2=true）:
     TINYINT/SMALLINT/INT/FLOAT/VARCHAR/CHAR/DATE/TIMESTAMP/DECIMAL(p,s)/BINARY/JSON
     以及复合类型 ARRAY<T>/MAP<K,V>/STRUCT<...>

   教训: 类型系统一旦发布极难更改。MaxCompute 不得不维护两套系统:
     同一项目内不同表可能使用不同类型系统
     隐式转换规则在两套系统中不一致
     新引擎应从第一天就使用完整的类型系统

### 7.2 AliORC 存储格式

   基于 Apache ORC 优化的列式文件格式:
     C++ Arrow 内存格式（加速向量化计算）
     自适应字典编码（根据数据特征自动选择编码方式）
     异步预读 + I/O 模式管理（减少存储延迟）
     增强的谓词下推（I/O 层面跳过不需要的数据）
   对引擎开发者: 列式存储性能差异主要来自编码策略和 I/O 优化

### 7.3 存储层级: 盘古分布式文件系统

   Project → Table → Partition → Bucket → AliORC File
   每个分区对应盘古上的一个目录
   每个 AliORC 文件包含 Stripe（类似 Parquet RowGroup）

## 8. 横向对比: CREATE TABLE


 自增策略:
   MaxCompute:  无自增（批处理引擎不需要，用 ROW_NUMBER/UUID 代替）
   Hive:        无自增（同理）
   BigQuery:    无自增（分布式系统不应依赖全局序列）
   Snowflake:   AUTOINCREMENT（值不保证连续）
   MySQL:       AUTO_INCREMENT（OLTP 核心需求）

 分区设计:
   MaxCompute/Hive: 分区列不是普通列，编码在目录路径中
   BigQuery:        分区列是普通列，分区对用户透明
   Snowflake:       微分区自动管理，用户无需手动分区
   ClickHouse:      PARTITION BY 表达式灵活，ORDER BY 定义排序键

 存储格式:
   MaxCompute:  AliORC（优化的 ORC）
   Hive:        ORC/Parquet/TextFile 可选
   BigQuery:    Capacitor（自研列式格式）
   Snowflake:   微分区（自研格式）
   Databricks:  Delta Lake（Parquet + 事务日志）

## 9. 对引擎开发者的启示


1. LIFECYCLE: 将 TTL 作为 DDL 一等公民是最简洁的存储治理方案

2. 两套类型系统的维护成本极高，新引擎必须从第一天设计好类型系统

3. 事务表的 delta + compaction 模型是在不可变文件上实现 ACID 的通用方案

4. 分区列不是普通列的设计简化了分区裁剪实现，但增加了用户认知负担

5. 聚集表（CLUSTERED BY）对 JOIN 性能的优化值得在 DDL 层面暴露

6. AliORC 的优化方向（自适应编码、异步预读）比格式本身更重要


注意: 没有 AUTO_INCREMENT/SEQUENCE
注意: 普通表不支持 UPDATE/DELETE（需事务表）
注意: 分区列不是普通数据列，值在目录路径中
注意: STRING 最大 8MB，分区键 STRING 最大 256 字节
注意: 默认存储格式为 AliORC，不可更改（非外部表）

