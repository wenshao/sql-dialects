# Databricks SQL: INSERT

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


单行插入
```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```


多行插入
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);
```


从查询结果插入
```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;
```


INSERT OVERWRITE（覆盖整个表）
```sql
INSERT OVERWRITE users
SELECT * FROM staging_users;
```


INSERT OVERWRITE 分区（只覆盖指定分区）
```sql
INSERT OVERWRITE events PARTITION (event_date = '2024-01-15')
SELECT id, event_type, user_id, data FROM staging_events;
```


动态分区覆盖
```sql
SET spark.sql.sources.partitionOverwriteMode = dynamic;
INSERT OVERWRITE events
SELECT * FROM staging_events;
```


## COPY INTO（从外部存储加载，推荐方式）


CSV 格式（从 S3）
```sql
COPY INTO users
FROM 's3://my-bucket/data/users/'
FILEFORMAT = CSV
FORMAT_OPTIONS (
    'header' = 'true',
    'delimiter' = ',',
    'inferSchema' = 'true'
)
COPY_OPTIONS ('mergeSchema' = 'true');
```


JSON 格式
```sql
COPY INTO events
FROM 's3://my-bucket/data/events/'
FILEFORMAT = JSON
FORMAT_OPTIONS ('multiLine' = 'true');
```


Parquet 格式
```sql
COPY INTO orders
FROM 's3://my-bucket/data/orders/'
FILEFORMAT = PARQUET;
```


从 ADLS
```sql
COPY INTO users
FROM 'abfss://container@account.dfs.core.windows.net/data/users/'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true');
```


COPY INTO 幂等性（不重复加载已加载的文件）
```sql
COPY INTO events
FROM 's3://my-bucket/data/events/'
FILEFORMAT = JSON
COPY_OPTIONS ('force' = 'false');            -- 默认不重复加载
```


## CTAS


```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

CREATE OR REPLACE TABLE users_summary AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;
```


CTAS 指定表属性
```sql
CREATE TABLE orders_optimized
USING DELTA
CLUSTER BY (order_date, user_id)
AS SELECT * FROM orders;
```


## Schema Evolution（写入时自动演进 Schema）


启用 Schema 合并
```sql
INSERT INTO users
SELECT * FROM staging_users;
```

如果 staging_users 有新列，需要先设置：
ALTER TABLE users SET TBLPROPERTIES ('delta.autoOptimize.optimizeWrite' = 'true');
或在会话级设置：SET spark.databricks.delta.schema.autoMerge.enabled = true;

## 多表插入（Databricks 2024+）


```sql
INSERT ALL
    INTO young_users (username, age) VALUES (username, age)
    INTO all_users (username, age) VALUES (username, age)
SELECT username, age FROM candidates WHERE age < 30;
```


## 临时视图加载


```sql
CREATE TEMPORARY VIEW staging_data AS
SELECT * FROM csv.`s3://my-bucket/data/file.csv`;

INSERT INTO users (username, email)
SELECT col1, col2 FROM staging_data;
```


## Auto Loader（Structured Streaming，增量加载）

Auto Loader 是 Databricks 推荐的增量文件加载方式
在 notebook/jobs 中使用，不是纯 SQL：
spark.readStream.format("cloudFiles")
.option("cloudFiles.format", "csv")
.load("s3://my-bucket/data/")
.writeStream.toTable("users")

IDENTITY 列自动生成
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
-- id 列由 GENERATED ALWAYS AS IDENTITY 自动生成
```


注意：COPY INTO 幂等，不会重复加载同一文件（推荐批量加载）
注意：INSERT OVERWRITE 在分区表上只覆盖涉及的分区（动态模式）
注意：Delta Lake 的 ACID 保证所有写入操作的原子性
注意：Schema Evolution 允许写入时自动添加新列
注意：Auto Loader 是增量加载的最佳选择（流式处理新文件）
注意：GENERATED ALWAYS AS IDENTITY 列不接受手动值
