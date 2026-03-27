-- Apache Impala: INSERT
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- 基本插入（性能较低，不推荐大批量使用）
INSERT INTO users VALUES (1, 'alice', 'alice@example.com', 25, 100.00, NULL, NOW(), NOW());

-- 指定列插入
INSERT INTO users (id, username, email, age) VALUES (1, 'alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive
SELECT * FROM users WHERE age > 60;

-- 分区表插入（静态分区）
INSERT INTO orders PARTITION (year=2024, month=1)
SELECT id, user_id, amount FROM staging_orders;

-- 分区表插入（动态分区）
INSERT INTO orders PARTITION (year, month)
SELECT id, user_id, amount, year(order_date), month(order_date)
FROM staging_orders;

-- INSERT OVERWRITE（覆盖写入）
INSERT OVERWRITE users
SELECT * FROM staging_users;

-- INSERT OVERWRITE 分区
INSERT OVERWRITE orders PARTITION (year=2024, month=1)
SELECT id, user_id, amount FROM staging_orders;

-- 动态分区 OVERWRITE
INSERT OVERWRITE orders PARTITION (year, month)
SELECT id, user_id, amount, year(order_date), month(order_date)
FROM staging_orders;

-- Kudu 表插入
INSERT INTO users_kudu VALUES (1, 'alice', 'alice@example.com', 25);

-- Kudu 表多行插入
INSERT INTO users_kudu VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30);

-- 从文件加载（通过外部表中转）
CREATE EXTERNAL TABLE staging_load (
    id       BIGINT,
    username STRING,
    email    STRING,
    age      INT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/data/staging/';

INSERT INTO users
SELECT * FROM staging_load;

-- 带排序的插入（优化 Parquet 文件的 Min/Max 统计）
INSERT INTO orders PARTITION (year=2024, month=1)
SELECT id, user_id, amount FROM staging_orders
ORDER BY user_id;

-- CTAS 方式（创建并填充）
CREATE TABLE users_backup
STORED AS PARQUET AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- 注意：INSERT VALUES 每次生成小文件，不推荐频繁使用
-- 注意：分区表推荐动态分区写入
-- 注意：插入后建议运行 COMPUTE STATS
-- COMPUTE INCREMENTAL STATS orders;
-- 注意：不支持 INSERT RETURNING
-- 注意：不支持 CTE + INSERT
