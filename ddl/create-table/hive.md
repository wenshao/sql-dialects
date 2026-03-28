# Hive: CREATE TABLE

> 参考资料:
> - [1] Apache Hive Language Manual - DDL
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL
> - [2] Apache Hive - Data Types
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
> - [3] Apache Hive - SerDe
>   https://cwiki.apache.org/confluence/display/Hive/SerDe
> - [4] Apache Hive - Storage Formats
>   https://cwiki.apache.org/confluence/display/Hive/FileFormats


## 1. 基本语法: 管理表 (Managed Table)

```sql
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    age        INT,
    balance    DECIMAL(10,2),
    bio        STRING,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
)
STORED AS ORC;

```

## 2. STORED AS 子句: Hive 最核心的设计创新

Hive 将存储格式提升为 DDL 一等概念，STORED AS 决定数据的物理存储布局。
这一设计源于 Schema-on-Read 哲学: 数据先存在，表定义覆盖在数据之上。

主要存储格式:
TEXTFILE:  纯文本行存储（默认），人类可读，不可分割压缩时需注意
ORC:       Optimized Row Columnar，Hive 原生列式格式，支持 ACID 事务
PARQUET:   Apache Parquet，跨引擎列式格式，Spark/Trino/Impala 兼容性最好
AVRO:      行式序列化格式，自带 Schema 演化，适合数据交换
RCFILE:    早期列式格式（已过时，被 ORC 取代）
SEQUENCEFILE: Hadoop 原生二进制格式，支持块级压缩

设计 trade-off:
优点: 用户在建表时就决定了 I/O 模式（行存 vs 列存），优化器可据此选择执行策略;
同一份逻辑数据可以用不同格式存储多份（物化视图用 ORC，交换表用 AVRO）
缺点: 格式选择不当会严重影响性能（如 TEXTFILE 上执行聚合查询效率极低）;
不同格式的功能支持不一致（只有 ORC 支持 ACID）


```sql
CREATE TABLE users_text (id BIGINT, name STRING)
ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
STORED AS TEXTFILE;                        -- 最简单但性能最差

CREATE TABLE users_orc (id BIGINT, name STRING)
STORED AS ORC;                             -- Hive 原生推荐，支持 ACID

CREATE TABLE users_parquet (id BIGINT, name STRING)
STORED AS PARQUET;                         -- 跨引擎兼容性最佳

```

 对比其他引擎的存储格式声明:
   MySQL:       ENGINE=InnoDB（存储引擎级别，而非文件格式级别）
   Spark SQL:   USING parquet / USING orc（继承自 Hive 但更简洁的 DataSource API）
   Trino:       不在建表语法中声明格式，而是 connector 配置级别决定
   BigQuery:    无格式概念（完全托管存储，内部使用 Capacitor 列式格式）
   ClickHouse:  ENGINE = MergeTree（引擎 + 排序键决定存储布局）
   MaxCompute:  内部列存（不暴露格式选择），但支持读 ORC/Parquet 外部数据
   Flink SQL:   CONNECTOR = '...' + FORMAT = '...'（连接器和格式分离）

 对引擎开发者的启示:
   Hive 的 STORED AS 是"物理存储可见"设计范式的代表。现代 Lakehouse（Delta/Iceberg/Hudi）
   在此基础上增加了 table format 层，将事务管理从文件格式中分离出来。
   如果设计新引擎，考虑: 格式应该暴露给用户还是内部透明处理？
   暴露给用户提供了灵活性（Hive/Spark），透明处理降低了认知负担（BigQuery/Snowflake）。

## 3. 分区表: PARTITIONED BY (分区 = HDFS 目录)

```sql
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_time TIMESTAMP
)
PARTITIONED BY (
    dt     STRING,                          -- 一级分区: /warehouse/orders/dt=2024-01-01/
    region STRING                           -- 二级分区: /warehouse/orders/dt=2024-01-01/region=us/
)
STORED AS ORC;

```

 设计分析: Hive 的分区模型
 Hive 分区列不存在于数据文件中，而是编码在目录路径里。
 这一设计有深远影响:
1. 分区裁剪 = 目录跳过（无需打开文件即可过滤分区）

2. 添加/删除分区 = 创建/删除目录（元数据操作 + 文件系统操作）

3. 分区列的值是目录名的一部分，因此分区列的值域受文件系统路径限制

4. 分区过多 → 小文件问题（每个分区至少一个文件）


 对比其他引擎:
   MySQL/PostgreSQL: PARTITION BY RANGE/LIST/HASH 内部实现，分区键在数据中
   Spark SQL:        继承 Hive 的目录分区模型
   Trino/Impala:     共享 Hive Metastore，复用同一套目录分区
   BigQuery:         按 DATE/TIMESTAMP/INTEGER_RANGE 分区，内部管理
   Iceberg/Delta:    manifest 文件替代目录列表，解决小文件和原子性问题

## 4. 分桶表: CLUSTERED BY

```sql
CREATE TABLE orders_bucketed (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 256 BUCKETS
STORED AS ORC;

```

 设计分析: 分桶 = 分区内的 hash 分布
 分桶将数据按 hash(列值) % 桶数分配到固定数量的文件中。
 核心用途:
1. Bucket Map Join: 两表按相同列分桶 → JOIN 时只需对齐桶号，无需全量 shuffle

2. 采样查询: TABLESAMPLE(BUCKET x OUT OF y) 只读取特定桶

3. 数据均匀分布: 避免分区内的数据倾斜


 Hive 2.x vs 3.0 的重大变化:
   2.x: 分桶是可选的，ACID 表要求分桶
   3.0+: 默认所有托管表为 ACID 表，不再强制要求分桶
         分桶仍然有用（JOIN 优化），但不再是事务表的前提条件

## 5. 外部表: CREATE EXTERNAL TABLE

```sql
CREATE EXTERNAL TABLE external_logs (
    log_time TIMESTAMP,
    level    STRING,
    message  STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION '/data/logs/';

```

 管理表 vs 外部表: 数据所有权问题
   管理表(Managed): Hive 拥有数据，DROP TABLE 删除元数据 + 数据文件
   外部表(External): Hive 不拥有数据，DROP TABLE 只删除元数据

 外部表的设计意义:
   允许 Hive 以"视图"方式叠加在已有数据上。多个引擎（Hive/Spark/Trino）
   可以各自定义外部表指向同一份 HDFS 数据，互不干扰。
   这是数据湖"计算存储分离"思想的早期体现。

 Hive 3.0 变化: 默认托管表为 ACID，外部表不支持 ACID
 实际影响: 如果只需要 INSERT OVERWRITE 模式，外部表比 ACID 管理表性能更好

## 6. SerDe: 可插拔序列化/反序列化

```sql
CREATE TABLE json_logs (
    id   BIGINT,
    name STRING,
    data STRING
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS TEXTFILE;

```

 SerDe 是 Hive 架构中最独特的抽象层:
 查询引擎不直接理解数据格式，而是通过 SerDe 接口将字节流转换为行对象。
 这意味着:
1. 添加新格式只需实现 SerDe 接口（无需修改引擎核心）

2. 同一份文件可以用不同 SerDe 解读（Schema-on-Read 的基础）

3. 用户可以编写自定义 SerDe 处理私有格式（如自定义日志格式）


 常用 SerDe:
   LazySimpleSerDe:   TEXTFILE 默认的 SerDe，基于分隔符解析
   JsonSerDe:         JSON 格式
   AvroSerDe:         Avro 格式
   OrcSerde:          ORC 格式（STORED AS ORC 自动使用）
   ParquetHiveSerDe:  Parquet 格式
   RegexSerDe:        正则表达式解析（适合非结构化日志）
   OpenCSVSerde:      CSV 格式

 对引擎开发者的启示:
   SerDe 模式将"如何读写数据"与"如何处理数据"解耦。
   Spark 的 DataSource API、Flink 的 Format 接口都延续了这一思想。
   但 SerDe 粒度是行级别的，对列式格式（ORC/Parquet）效率不高，
   因此 ORC/Parquet 实际上绕过了 SerDe 使用原生 Reader/Writer。

## 7. ACID 事务表 (Hive 0.14+, 3.0+ 默认)

```sql
CREATE TABLE users_acid (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

```

 ACID 表的限制:
1. 仅 ORC 格式支持（Parquet 不支持 ACID）

2. 必须是管理表（外部表不支持）

3. 需要 delta 文件 + compaction 机制（读写放大）

4. Hive 3.0+ 默认所有管理表为 ACID → 不想要 ACID 就用外部表


## 8. CTAS 与 LIKE

```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

CREATE TABLE users_new LIKE users;

```

 CTAS 在 Hive 中的特殊意义:
 由于 Hive 没有高效的 INSERT INTO VALUES 路径（每条 INSERT 是一个 MR/Tez 作业），
 CTAS 是创建并填充数据的最高效方式——只需一次 MapReduce/Tez 作业。
 BigQuery 也将 CTAS 作为主要建表方式（设计理念相同: 避免小批量写入）。

## 9. 表属性: TBLPROPERTIES

```sql
CREATE TABLE t_compressed (id BIGINT, data STRING)
STORED AS ORC
TBLPROPERTIES (
    'orc.compress'    = 'SNAPPY',           -- 压缩算法: SNAPPY/ZLIB/LZ4/NONE
    'transactional'   = 'true',             -- 启用 ACID
    'auto.purge'      = 'true',             -- DROP 时跳过回收站
    'orc.stripe.size' = '67108864'          -- ORC stripe 大小 (64MB)
);

```

## 10. 已知限制与设计不足

1. 无 AUTO_INCREMENT / SEQUENCE: Hive 面向批量分析，不需要行级自增;

    生成唯一 ID 用 ROW_NUMBER() 或 UUID()
2. 无主键/唯一约束的强制执行: 3.0+ 支持声明 PK/FK/UNIQUE 但仅信息性（类似 BigQuery/Snowflake）

3. 无索引: 3.0 正式废弃索引功能，替代方案是 ORC/Parquet 的内置 bloom filter 和 min/max 统计

4. STORED AS 绑定格式: 建表后不能更改存储格式（需要 CTAS 重建）

5. 分区列不能出现在数据列中: 分区列是目录路径的一部分，这一约束是目录分区模型的必然结果

6. STRING 类型无长度约束: 与 MySQL VARCHAR(n) 不同，STRING 是无限长度的，

    这简化了 DDL 但丧失了存储优化机会（VARCHAR/CHAR 在 0.12+ 加入但很少使用）
7. 数据类型有限: 无 TIME 类型，无带时区的 TIMESTAMP（3.0+ 有 TIMESTAMPLOCALTZ 但不通用）


## 11. 版本演进

Hive 0.12: VARCHAR/CHAR 类型
Hive 0.13: ORC 格式成熟，Cost-Based Optimizer
Hive 0.14: ACID 事务首次引入（实验性，需要 ORC + 分桶）
Hive 2.0:  LLAP 常驻执行引擎
Hive 3.0:  默认 ACID，废弃索引，不再强制分桶
Hive 4.0:  Iceberg 集成，Metastore 独立部署改进

