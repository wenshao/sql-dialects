-- Snowflake: INSERT
--
-- 参考资料:
--   [1] Snowflake SQL Reference - INSERT
--       https://docs.snowflake.com/en/sql-reference/sql/insert
--   [2] Snowflake SQL Reference - COPY INTO
--       https://docs.snowflake.com/en/sql-reference/sql/copy-into-table

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

-- INSERT OVERWRITE（覆盖整个表）
INSERT OVERWRITE INTO users (username, email, age)
SELECT username, email, age FROM staging_users;

-- 多列插入（INSERT ALL）
INSERT ALL
    INTO users (username, email) VALUES ('alice', 'alice@example.com')
    INTO users (username, email) VALUES ('bob', 'bob@example.com')
SELECT 1;

-- 条件插入
INSERT ALL
    WHEN age < 30 THEN INTO young_users (username, age) VALUES (username, age)
    WHEN age >= 30 THEN INTO senior_users (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

-- INSERT FIRST（只插入第一个匹配的）
INSERT FIRST
    WHEN age < 18 THEN INTO minors (username, age) VALUES (username, age)
    WHEN age < 65 THEN INTO adults (username, age) VALUES (username, age)
    ELSE INTO seniors (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- COPY INTO（从 Stage 加载文件，适合批量导入）
COPY INTO users
FROM @my_stage/users.csv
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

-- COPY INTO（从外部存储）
COPY INTO users
FROM 's3://mybucket/data/'
CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...')
FILE_FORMAT = (TYPE = 'PARQUET');

-- 指定默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- DEFAULT VALUES（所有列使用默认值）
INSERT INTO logs DEFAULT VALUES;

-- AUTOINCREMENT / IDENTITY 列自动生成
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
-- id 列由 AUTOINCREMENT 自动生成
