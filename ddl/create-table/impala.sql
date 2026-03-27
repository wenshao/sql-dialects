-- Apache Impala: CREATE TABLE
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 内部表（Managed Table，默认 Parquet 格式）
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
STORED AS PARQUET;

-- 指定分隔符的文本格式表
CREATE TABLE users_csv (
    id         BIGINT,
    username   STRING,
    email      STRING,
    age        INT
)
ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
STORED AS TEXTFILE;

-- 分区表
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date STRING
)
PARTITIONED BY (year INT, month INT)
STORED AS PARQUET;

-- 添加分区
ALTER TABLE orders ADD PARTITION (year=2024, month=1);
ALTER TABLE orders ADD PARTITION (year=2024, month=2);

-- 外部表（数据在 HDFS/S3 上）
CREATE EXTERNAL TABLE ext_logs (
    log_time   TIMESTAMP,
    level      STRING,
    message    STRING
)
STORED AS PARQUET
LOCATION '/data/logs/';

-- ORC 格式
CREATE TABLE events_orc (
    event_id   BIGINT,
    event_name STRING,
    event_time TIMESTAMP
)
STORED AS ORC;

-- Avro 格式
CREATE TABLE events_avro (
    event_id   BIGINT,
    event_name STRING,
    event_time TIMESTAMP
)
STORED AS AVRO;

-- Kudu 表（支持 UPDATE/DELETE）
CREATE TABLE users_kudu (
    id         BIGINT,
    username   STRING,
    email      STRING,
    age        INT,
    PRIMARY KEY (id)
)
PARTITION BY HASH (id) PARTITIONS 16
STORED AS KUDU;

-- Kudu 表（Range 分区）
CREATE TABLE orders_kudu (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date STRING,
    PRIMARY KEY (id, order_date)
)
PARTITION BY HASH (id) PARTITIONS 8,
    RANGE (order_date) (
        PARTITION VALUES < '2024-04-01',
        PARTITION '2024-04-01' <= VALUES < '2024-07-01',
        PARTITION '2024-07-01' <= VALUES < '2024-10-01',
        PARTITION '2024-10-01' <= VALUES
    )
STORED AS KUDU;

-- CTAS
CREATE TABLE users_backup
STORED AS PARQUET AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- LIKE（复制表结构）
CREATE TABLE users_copy LIKE users;

-- 表属性
CREATE TABLE events_compressed (
    id         BIGINT,
    event_name STRING
)
STORED AS PARQUET
TBLPROPERTIES ('parquet.compression' = 'SNAPPY');

-- 注意：Impala 使用 Hive Metastore 管理元数据
-- 注意：分区列不在数据列中，以目录形式存储
-- 注意：不支持 NOT NULL / DEFAULT 约束（Kudu 表除外）
-- 注意：没有自增列
-- 注意：COMPUTE STATS 可以收集统计信息优化查询
-- COMPUTE STATS users;
-- COMPUTE INCREMENTAL STATS orders;
