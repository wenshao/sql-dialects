-- Azure Synapse: CREATE TABLE
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- 基本建表（T-SQL 语法 + Synapse 分布扩展）
-- 适用于 Synapse 专用 SQL 池（Dedicated SQL Pool）
CREATE TABLE users (
    id         BIGINT IDENTITY(1, 1) NOT NULL,
    username   NVARCHAR(64) NOT NULL,
    email      NVARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10, 2) DEFAULT 0.00,
    bio        NVARCHAR(4000),               -- NVARCHAR 最大 4000，或用 MAX
    created_at DATETIME2 NOT NULL DEFAULT GETDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETDATE()
)
WITH (
    DISTRIBUTION = HASH(id),                 -- 分布方式
    CLUSTERED COLUMNSTORE INDEX              -- 默认索引类型
);

-- 分布方式（DISTRIBUTION）
-- HASH(column): 按列值哈希分布（大事实表推荐）
-- ROUND_ROBIN: 轮询均匀分布（默认，加载最快）
-- REPLICATE: 每个计算节点一份完整拷贝（小维度表推荐）

-- ROUND_ROBIN 分布（默认）
CREATE TABLE staging_data (
    id         BIGINT,
    data       NVARCHAR(MAX)
)
WITH (
    DISTRIBUTION = ROUND_ROBIN
);

-- REPLICATE 分布（小维度表）
CREATE TABLE countries (
    code       CHAR(2) NOT NULL,
    name       NVARCHAR(100) NOT NULL
)
WITH (
    DISTRIBUTION = REPLICATE
);

-- 索引类型
-- CLUSTERED COLUMNSTORE INDEX（默认，适合分析查询）
-- CLUSTERED INDEX (col): 行存储聚集索引
-- HEAP: 无索引堆表（适合临时暂存）

-- 堆表（快速加载暂存区）
CREATE TABLE staging_orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10, 2)
)
WITH (
    DISTRIBUTION = ROUND_ROBIN,
    HEAP
);

-- 聚集索引（行存储，适合点查）
CREATE TABLE lookup_table (
    id         INT NOT NULL,
    value      NVARCHAR(200)
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED INDEX (id)
);

-- 有序聚集列存储索引（Ordered CCI，性能优化）
CREATE TABLE orders (
    id         BIGINT IDENTITY(1, 1) NOT NULL,
    user_id    BIGINT NOT NULL,
    amount     DECIMAL(10, 2),
    order_date DATE
)
WITH (
    DISTRIBUTION = HASH(user_id),
    CLUSTERED COLUMNSTORE INDEX ORDER (order_date)
);

-- 分区
CREATE TABLE sales (
    id         BIGINT IDENTITY(1, 1),
    sale_date  DATE NOT NULL,
    amount     DECIMAL(10, 2),
    region     NVARCHAR(50)
)
WITH (
    DISTRIBUTION = HASH(id),
    PARTITION (sale_date RANGE RIGHT FOR VALUES
        ('2023-01-01', '2024-01-01', '2025-01-01'))
);

-- CTAS（Synapse 中最重要的模式，推荐用于数据转换）
CREATE TABLE users_backup
WITH (
    DISTRIBUTION = HASH(id),
    CLUSTERED COLUMNSTORE INDEX
)
AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- CTAS 重建表（改变分布/索引）
CREATE TABLE orders_new
WITH (
    DISTRIBUTION = HASH(user_id),
    CLUSTERED COLUMNSTORE INDEX ORDER (order_date)
)
AS SELECT * FROM orders;

RENAME OBJECT orders TO orders_old;
RENAME OBJECT orders_new TO orders;

-- 临时表
CREATE TABLE #temp_users (id BIGINT, username NVARCHAR(64));
-- 或 CTAS 临时表
CREATE TABLE #temp_active
WITH (DISTRIBUTION = ROUND_ROBIN)
AS SELECT * FROM users WHERE status = 1;

-- 外部表（PolyBase，查询 ADLS/Blob Storage）
CREATE EXTERNAL DATA SOURCE my_adls
WITH (
    TYPE = HADOOP,
    LOCATION = 'abfss://container@account.dfs.core.windows.net'
);

CREATE EXTERNAL FILE FORMAT parquet_format
WITH (FORMAT_TYPE = PARQUET);

CREATE EXTERNAL TABLE external_events (
    id         BIGINT,
    event_type NVARCHAR(50),
    event_date DATE
)
WITH (
    LOCATION = '/events/',
    DATA_SOURCE = my_adls,
    FILE_FORMAT = parquet_format
);

-- Serverless SQL Pool（不同的语法）
-- 使用 OPENROWSET 直接查询文件
SELECT * FROM OPENROWSET(
    BULK 'https://account.dfs.core.windows.net/container/path/*.parquet',
    FORMAT = 'PARQUET'
) AS data;

-- 注意：Synapse 专用池基于 MPP 架构，60 个固定分布
-- 注意：CLUSTERED COLUMNSTORE INDEX 是默认且推荐的索引类型
-- 注意：CTAS 是 Synapse 中执行数据转换的主要模式
-- 注意：不支持 UNIQUE 约束（仅 NOT NULL 强制执行）
-- 注意：IDENTITY 列不保证值的唯一性（在 CTAS 中可能重复）
-- 注意：不支持 FOREIGN KEY 约束
-- 注意：NVARCHAR(MAX) 存储上限为列存 8000 字节 / 行存 2GB
