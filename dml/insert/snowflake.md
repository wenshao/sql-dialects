# Snowflake: INSERT

> 参考资料:
> - [1] Snowflake SQL Reference - INSERT
>   https://docs.snowflake.com/en/sql-reference/sql/insert
> - [2] Snowflake SQL Reference - COPY INTO <table>
>   https://docs.snowflake.com/en/sql-reference/sql/copy-into-table


## 1. 基本语法


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

INSERT OVERWRITE（覆盖整个表，Snowflake 独有）

```sql
INSERT OVERWRITE INTO users (username, email, age)
SELECT username, email, age FROM staging_users;

```

DEFAULT VALUES

```sql
INSERT INTO logs DEFAULT VALUES;

```

指定默认值

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

```

CTE + INSERT

```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 INSERT vs COPY INTO: 两种加载路径

Snowflake 有两种截然不同的数据加载方式:

INSERT (DML 路径):
- 逐行或小批量插入
- 走 SQL 解析 → 优化器 → 执行引擎完整流程
- 适合: 小批量实时写入、应用层插入
- 性能: 中等（受 SQL 解析和事务开销影响）

COPY INTO (批量加载路径):
- 从 Stage (S3/Azure/GCS) 读取文件直接加载
- 跳过 SQL 优化器，使用专用的加载引擎
- 支持 CSV/JSON/Parquet/Avro/ORC 格式
- 适合: ETL/ELT 批量加载、TB 级数据迁移
- 性能: 极高（并行加载，自动分片）

COPY INTO 是 Snowflake 数据加载的最佳实践:

```sql
COPY INTO users
FROM @my_stage/users.csv
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

```

从外部存储直接加载:

```sql
COPY INTO users
FROM 's3://mybucket/data/'
CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...')
FILE_FORMAT = (TYPE = 'PARQUET');

```

 COPY INTO 的设计意义:
   传统数据库: INSERT 是唯一的写入路径（PostgreSQL COPY 是例外）
   Snowflake: COPY INTO 是独立的加载路径，绕过 DML 管道
   这是云数仓的核心设计: 批量加载性能 > 逐行插入性能

 对比:
   PostgreSQL: COPY FROM 'file' WITH CSV（类似但只支持本地文件或 STDIN）
   MySQL:      LOAD DATA INFILE（类似但只支持本地文件）
   BigQuery:   bq load / LOAD DATA（从 GCS 加载，最接近 COPY INTO）
   Redshift:   COPY FROM 's3://...'（与 Snowflake COPY INTO 非常类似）
   Databricks: COPY INTO（借鉴 Snowflake 语法设计）

 对引擎开发者的启示:
   如果目标是数仓引擎，批量加载路径是必须的。
   COPY INTO 的关键实现: 并行读取文件、自动分片、跳过事务锁。
   Snowflake 和 Redshift 都将 COPY 作为主要数据入口，INSERT 仅作为补充。

### 2.2 INSERT OVERWRITE: 原子全表替换

 INSERT OVERWRITE 原子地替换表的全部数据:
   (a) 执行 SELECT 查询
   (b) 将结果写入新的微分区
   (c) 原子替换表的元数据指向新分区
   (d) 旧分区进入 Time Travel（可恢复）

 对比 DELETE + INSERT:
   DELETE FROM t; INSERT INTO t SELECT ... FROM s;
   → 两步操作，中间有空表的瞬间（读者可能看到空表）
   INSERT OVERWRITE INTO t SELECT ... FROM s;
   → 原子操作，读者要么看到旧数据要么看到新数据

 对比:
   BigQuery:   WRITE_TRUNCATE 选项（类似语义）
   Redshift:   无原生 INSERT OVERWRITE
   Databricks: INSERT OVERWRITE（Delta Lake 支持）
   Hive:       INSERT OVERWRITE（最早的实现）

## 3. INSERT ALL: 多表条件分发


无条件分发（每行插入所有目标表）

```sql
INSERT ALL
    INTO users (username, email) VALUES ('alice', 'alice@example.com')
    INTO users (username, email) VALUES ('bob', 'bob@example.com')
SELECT 1;

```

条件分发

```sql
INSERT ALL
    WHEN age < 30 THEN INTO young_users (username, age) VALUES (username, age)
    WHEN age >= 30 THEN INTO senior_users (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

```

INSERT FIRST（只匹配第一个条件）

```sql
INSERT FIRST
    WHEN age < 18 THEN INTO minors (username, age) VALUES (username, age)
    WHEN age < 65 THEN INTO adults (username, age) VALUES (username, age)
    ELSE INTO seniors (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

```

 对比:
   Oracle:     INSERT ALL / INSERT FIRST（语法完全一致，Snowflake 借鉴）
   PostgreSQL: 无原生多表 INSERT（需要 CTE + 多条 INSERT 或触发器）
   MySQL:      无原生多表 INSERT
   SQL Server: 无原生多表 INSERT（需要多条 INSERT 语句）

## 4. Snowpipe: 持续自动加载


 Snowpipe 在文件到达 Stage 时自动触发 COPY INTO:
 CREATE PIPE auto_load
     AUTO_INGEST = TRUE
 AS COPY INTO users FROM @my_stage FILE_FORMAT = (TYPE = 'CSV');

 触发机制: S3 Event Notification / Azure Event Grid / GCS Pub/Sub
 延迟: 通常 < 1 分钟
 计费: 按加载的文件大小计费（不使用 Warehouse）

 对比:
   BigQuery:   BigQuery Data Transfer / Streaming API
   Redshift:   无原生流式加载（需要 Kinesis Firehose）
   Databricks: Auto Loader（类似 Snowpipe）

## 5. AUTOINCREMENT 列


AUTOINCREMENT 列自动生成，INSERT 时不需要指定:

```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
```

 id 列由 AUTOINCREMENT 自动生成

## 横向对比: INSERT 能力矩阵

| 能力            | Snowflake      | BigQuery       | PostgreSQL  | MySQL |
|------|------|------|------|------|
| 基本 INSERT     | 支持           | 支持           | 支持        | 支持 |
| 批量加载        | COPY INTO      | LOAD DATA      | COPY        | LOAD DATA |
| INSERT OVERWRITE| 支持           | WRITE_TRUNCATE | 不支持      | 不支持 |
| INSERT ALL/FIRST| 支持(Oracle式) | 不支持         | 不支持      | 不支持 |
| CTE + INSERT    | 支持           | 支持           | 支持        | 支持(8.0+) |
| 流式加载        | Snowpipe       | Streaming API  | 无原生      | 无原生 |
| RETURNING       | 不支持         | 不支持         | 支持        | 不支持 |
| ON CONFLICT     | 不支持(用MERGE)| 不支持         | 支持        | ON DUP KEY |

