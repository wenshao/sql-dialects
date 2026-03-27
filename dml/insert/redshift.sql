-- Redshift: INSERT
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- IDENTITY 列自动生成
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
-- id 列由 IDENTITY 自动生成

-- DEFAULT 值
INSERT INTO users (username, email, status) VALUES ('alice', 'alice@example.com', DEFAULT);

-- ============================================================
-- COPY 命令（推荐的批量加载方式，从 S3 加载）
-- ============================================================

-- CSV 格式
COPY users (username, email, age)
FROM 's3://my-bucket/data/users.csv'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
CSV
IGNOREHEADER 1
DELIMITER ','
REGION 'us-east-1';

-- JSON 格式
COPY events (id, event_type, data)
FROM 's3://my-bucket/data/events.json'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
FORMAT AS JSON 'auto';

-- JSON 格式（指定 JSONPaths 文件）
COPY events
FROM 's3://my-bucket/data/events.json'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
FORMAT AS JSON 's3://my-bucket/jsonpaths/events_paths.json';

-- Parquet 格式
COPY orders
FROM 's3://my-bucket/data/orders.parquet'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
FORMAT AS PARQUET;

-- GZIP 压缩
COPY users
FROM 's3://my-bucket/data/users.csv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
CSV GZIP;

-- Manifest 文件（精确指定要加载的文件列表）
COPY users
FROM 's3://my-bucket/manifests/users.manifest'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
CSV MANIFEST;

-- COPY 常用选项
COPY users
FROM 's3://my-bucket/data/users.csv'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
CSV
IGNOREHEADER 1                              -- 跳过头行
DELIMITER ','                               -- 分隔符
DATEFORMAT 'YYYY-MM-DD'                     -- 日期格式
TIMEFORMAT 'auto'                           -- 时间格式
NULL AS '\\N'                               -- NULL 值表示
MAXERROR 100                                -- 允许的最大错误数
ACCEPTINVCHARS '?'                          -- 无效字符替换
TRUNCATECOLUMNS                             -- 截断超长数据
COMPUPDATE ON                               -- 自动设置压缩编码
STATUPDATE ON;                              -- 自动更新统计信息

-- ============================================================
-- UNLOAD（导出到 S3）
-- ============================================================

UNLOAD ('SELECT * FROM users WHERE age > 25')
TO 's3://my-bucket/export/users_'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
FORMAT AS PARQUET;

UNLOAD ('SELECT * FROM users')
TO 's3://my-bucket/export/users_'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
CSV
HEADER
PARALLEL ON;

-- ============================================================
-- 深拷贝（Deep Copy，重建表以优化性能）
-- ============================================================

-- 方式一：CTAS（推荐）
CREATE TABLE users_new AS SELECT * FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

-- 方式二：LIKE + INSERT
CREATE TABLE users_new (LIKE users);
INSERT INTO users_new SELECT * FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

-- 查看 COPY 错误
SELECT * FROM stl_load_errors ORDER BY starttime DESC LIMIT 10;
SELECT * FROM stl_load_commits ORDER BY starttime DESC LIMIT 10;

-- 注意：COPY 是加载大量数据的推荐方式（比 INSERT 快得多）
-- 注意：COPY 自动并行从多个文件加载（文件数是切片数的倍数最优）
-- 注意：INSERT 单行效率低，不适合大批量场景
-- 注意：不支持 INSERT ... ON CONFLICT / ON DUPLICATE KEY
-- 注意：IDENTITY 列在 COPY 时可以指定 EXPLICIT_IDS 选项手动提供值
