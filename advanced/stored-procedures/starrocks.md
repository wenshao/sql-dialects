# StarRocks: 存储过程

> 参考资料:
> - [1] StarRocks Documentation
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. 不支持存储过程 (与 Doris 相同)

 StarRocks 同样不支持存储过程、触发器、游标。
 原因与 Doris 相同: OLAP 引擎的架构不适合过程化逻辑。

## 2. 替代方案 (与 Doris 相同)


INSERT INTO ... SELECT

```sql
INSERT INTO users_clean
SELECT id, TRIM(username), LOWER(email), COALESCE(age, 0)
FROM users_raw;

```

CTAS

```sql
CREATE TABLE users_enriched AS
SELECT u.*, COUNT(o.id) AS order_count
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username, u.email, u.age;

```

 外部调度: Airflow / DolphinScheduler

## 3. Java UDF / Global UDF

 StarRocks 支持 Java UDF 和 Global UDF:
 CREATE FUNCTION my_func(INT) RETURNS INT
 PROPERTIES ("file"="...", "symbol"="...", "type"="StarrocksJar");

## 4. Pipe 持续加载 (3.2+，替代部分 ETL 需求)

 CREATE PIPE my_pipe AS INSERT INTO target
 SELECT * FROM FILES('path'='s3://bucket/data/', 'format'='parquet');
 自动监控新文件并加载，类似 Snowpipe。

 设计分析:
   Pipe 是 StarRocks 独有特性，部分替代了存储过程的 ETL 场景。
   对比 Doris: 使用 Routine Load(Kafka) 或外部调度。
   对比 Snowflake: Snowpipe 是更成熟的实现。

## 5. 会话变量

```sql
SET exec_mem_limit = 8589934592;
SET query_timeout = 3600;
SET pipeline_dop = 8;

```
