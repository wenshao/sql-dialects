-- Hive: CREATE TABLE
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DDL
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-CreateTable
--   [2] Apache Hive - Data Types
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types

-- 基本建表
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
ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
STORED AS TEXTFILE;

-- 常用存储格式
CREATE TABLE users_orc (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS ORC;                              -- 推荐，列式存储，支持 ACID

CREATE TABLE users_parquet (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS PARQUET;                          -- 列式存储，与 Spark 兼容好

-- 分区表
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_time TIMESTAMP
)
PARTITIONED BY (
    dt STRING,                              -- 分区列
    region STRING                           -- 多级分区
)
STORED AS ORC;

-- 分桶表（Bucketed）
CREATE TABLE orders_bucketed (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 256 BUCKETS
STORED AS ORC;

-- 事务表（ACID 表，Hive 0.14+，3.0+ 默认所有托管表为 ACID）
CREATE TABLE users_acid (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- LIKE
CREATE TABLE users_new LIKE users;

-- 外部表（数据不由 Hive 管理，DROP 时不删除数据）
CREATE EXTERNAL TABLE external_logs (
    log_time TIMESTAMP,
    level    STRING,
    message  STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION '/data/logs/';

-- 内部表 vs 外部表：
-- 内部表（MANAGED）: Hive 管理数据，DROP 时数据也删除
-- 外部表（EXTERNAL）: Hive 只管元数据，DROP 时数据保留

-- SerDe（序列化/反序列化）
CREATE TABLE json_table (
    id   BIGINT,
    name STRING,
    data STRING
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS TEXTFILE;

-- 表属性
CREATE TABLE t (id BIGINT)
STORED AS ORC
TBLPROPERTIES (
    'orc.compress' = 'SNAPPY',
    'transactional' = 'true',
    'auto.purge' = 'true'
);

-- 数据类型：
-- TINYINT / SMALLINT / INT / BIGINT: 整数
-- FLOAT / DOUBLE: 浮点
-- DECIMAL(p,s): 定点
-- STRING: 任意长度字符串
-- VARCHAR(n) / CHAR(n): Hive 0.12+
-- BOOLEAN: 布尔
-- BINARY: 二进制
-- TIMESTAMP / DATE: 时间
-- ARRAY<T> / MAP<K,V> / STRUCT<...>: 复杂类型
-- UNIONTYPE<...>: 联合类型（Hive 特有）

-- 注意：没有主键、唯一约束、外键（3.0+ ACID 表支持约束但不强制）
-- 注意：没有自增列
-- 注意：没有索引（3.0+ 废弃了之前的索引功能）
