-- MaxCompute (ODPS): CREATE TABLE
--
-- 参考资料:
--   [1] MaxCompute SQL - CREATE TABLE
--       https://help.aliyun.com/zh/maxcompute/user-guide/create-table-1
--   [2] MaxCompute SQL - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1

-- 基本建表
CREATE TABLE users (
    id         BIGINT NOT NULL,
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    age        INT,
    balance    DECIMAL(10,2),
    bio        STRING,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- 分区表（MaxCompute 最核心的特性）
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_time TIMESTAMP
)
PARTITIONED BY (
    dt STRING,                              -- 日期分区，如 '20240115'
    region STRING                           -- 多级分区
);

-- COMMENT（建议为每列添加注释）
CREATE TABLE users (
    id       BIGINT COMMENT '用户ID',
    username STRING COMMENT '用户名',
    email    STRING COMMENT '邮箱'
)
COMMENT '用户表'
LIFECYCLE 365;                              -- 生命周期（天），到期自动删除

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- LIKE（复制表结构）
CREATE TABLE users_new LIKE users;

-- IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (id BIGINT, username STRING);

-- 外部表（读取 OSS 数据）
CREATE EXTERNAL TABLE oss_data (
    col1 STRING,
    col2 BIGINT
)
STORED BY 'com.aliyun.odps.CsvStorageHandler'
LOCATION 'oss://bucket/path/';

-- 聚集表（Clustered Table）
CREATE TABLE orders_clustered (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

-- 事务表（支持 UPDATE/DELETE，需要显式声明）
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

-- 数据类型说明：
-- TINYINT / SMALLINT / INT / BIGINT: 整数
-- FLOAT / DOUBLE: 浮点
-- DECIMAL(p,s): 定点
-- STRING: 变长字符串（最大 8MB）
-- VARCHAR(n): 变长字符串（1~65535）
-- CHAR(n): 定长字符串（1~255）
-- BOOLEAN: 布尔
-- BINARY: 二进制
-- TIMESTAMP: 时间戳
-- DATETIME: 日期时间
-- DATE: 日期
-- ARRAY<T>: 数组
-- MAP<K,V>: 映射
-- STRUCT<...>: 结构体
-- JSON: JSON 类型

-- 注意：没有自增列
-- 注意：标准表不支持 UPDATE/DELETE（需要事务表）
-- 注意：分区列不是普通数据列
