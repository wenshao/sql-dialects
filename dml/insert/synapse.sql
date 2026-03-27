-- Azure Synapse: INSERT
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', N'alice@example.com', 25);

-- 多行插入
INSERT INTO users (username, email, age) VALUES
    ('alice', N'alice@example.com', 25),
    ('bob', N'bob@example.com', 30),
    ('charlie', N'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- IDENTITY 列自动生成
INSERT INTO users (username, email) VALUES ('alice', N'alice@example.com');
-- id 列由 IDENTITY 自动生成

-- ============================================================
-- CTAS（推荐的数据加载和转换模式）
-- ============================================================

-- CTAS 比 INSERT ... SELECT 效率更高
CREATE TABLE users_active
WITH (
    DISTRIBUTION = HASH(id),
    CLUSTERED COLUMNSTORE INDEX
)
AS
SELECT * FROM users WHERE status = 1;

-- CTAS + 转换
CREATE TABLE orders_summary
WITH (
    DISTRIBUTION = HASH(order_date),
    CLUSTERED COLUMNSTORE INDEX ORDER (order_date)
)
AS
SELECT
    order_date,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY order_date;

-- ============================================================
-- COPY INTO（从外部存储加载，推荐方式）
-- ============================================================

-- CSV 格式（从 ADLS）
COPY INTO users (username, email, age)
FROM 'https://account.dfs.core.windows.net/container/data/users.csv'
WITH (
    FILE_TYPE = 'CSV',
    FIRSTROW = 2,                           -- 跳过头行
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    CREDENTIAL = (IDENTITY = 'Managed Identity')
);

-- Parquet 格式
COPY INTO orders
FROM 'https://account.dfs.core.windows.net/container/data/orders/'
WITH (
    FILE_TYPE = 'PARQUET',
    CREDENTIAL = (IDENTITY = 'Managed Identity')
);

-- CSV 格式（从 Blob Storage）
COPY INTO users
FROM 'https://account.blob.core.windows.net/container/data/'
WITH (
    FILE_TYPE = 'CSV',
    FIRSTROW = 2,
    CREDENTIAL = (IDENTITY = 'Shared Access Signature',
                  SECRET = 'sv=2019-12-12&...')
);

-- ============================================================
-- PolyBase 外部表加载
-- ============================================================

-- 先创建外部表
CREATE EXTERNAL TABLE staging_ext_users (
    username NVARCHAR(64),
    email    NVARCHAR(255),
    age      INT
)
WITH (
    LOCATION = '/data/users/',
    DATA_SOURCE = my_adls,
    FILE_FORMAT = csv_format
);

-- 从外部表加载到内部表
INSERT INTO users (username, email, age)
SELECT username, email, age FROM staging_ext_users;

-- 或 CTAS
CREATE TABLE users_loaded
WITH (DISTRIBUTION = HASH(username), CLUSTERED COLUMNSTORE INDEX)
AS SELECT * FROM staging_ext_users;

-- ============================================================
-- Serverless 池（OPENROWSET 直接查询）
-- ============================================================

-- 注意：Serverless 池不创建持久化表，只读查询外部数据
SELECT * FROM OPENROWSET(
    BULK 'https://account.dfs.core.windows.net/container/data/*.parquet',
    FORMAT = 'PARQUET'
) AS data;

-- OPENROWSET + CSV
SELECT * FROM OPENROWSET(
    BULK 'https://account.dfs.core.windows.net/container/data/users.csv',
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    PARSER_VERSION = '2.0'
) WITH (
    username NVARCHAR(64) 1,
    email    NVARCHAR(255) 2,
    age      INT 3
) AS data;

-- ============================================================
-- 暂存区模式（Staging Pattern）
-- ============================================================

-- 1. 加载到堆表（最快）
CREATE TABLE #staging
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP)
AS SELECT * FROM external_source;

-- 2. 转换和清洗
CREATE TABLE target_table
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS SELECT * FROM #staging WHERE valid = 1;

-- 注意：CTAS 是 Synapse 中最高效的数据加载和转换方式
-- 注意：COPY INTO 是推荐的外部数据加载命令（取代 PolyBase）
-- 注意：堆表（HEAP）加载速度最快，适合暂存区
-- 注意：INSERT 单行效率低，避免在大批量场景使用
-- 注意：IDENTITY 列值在 CTAS 中不保证与源表一致
-- 注意：Serverless 池不支持 INSERT（只读外部数据）
