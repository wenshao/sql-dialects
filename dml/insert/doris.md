# Apache Doris: INSERT

 Apache Doris: INSERT

 参考资料:
   [1] Doris Documentation - INSERT / Stream Load / Broker Load
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 写入方式: SQL INSERT vs 专用导入接口

 Doris 提供多种写入方式，选择取决于数据规模:
   INSERT INTO:    适合少量数据(< 10 万行)
   Stream Load:    适合批量数据(HTTP 接口，推荐)
   Broker Load:    适合 HDFS/S3 大文件加载
   Routine Load:   适合 Kafka 持续消费

 设计理由:
   SQL INSERT 每次都要经过 SQL 解析 → 优化 → 执行，开销大。
   Stream Load 直接通过 HTTP 推送二进制数据到 BE，跳过 SQL 层。
   这是 OLAP 引擎的通用设计(ClickHouse 也有 HTTP 接口)。

## 2. SQL INSERT

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@e.com', 25);

INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@e.com', 25),
    ('bob', 'bob@e.com', 30),
    ('charlie', 'charlie@e.com', 35);

INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

```

INSERT OVERWRITE(覆盖写入)

```sql
INSERT OVERWRITE TABLE users (username, email, age)
SELECT username, email, age FROM staging_users;

```

带 Label(幂等重试)

```sql
INSERT INTO users WITH LABEL my_label_20240115
(username, email, age) VALUES ('alice', 'alice@e.com', 25);

```

CTE + INSERT

```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@e.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age) SELECT * FROM new_users;

```

## 3. Stream Load (HTTP 接口，推荐大批量)

 curl -u user:passwd -H "label:load_20240115" -T data.csv \
   http://fe_host:8030/api/db/users/_stream_load

## 4. Broker Load (HDFS/S3)

 LOAD LABEL db.label_20240115 (
     DATA INFILE("s3://bucket/data.csv")
     INTO TABLE users FORMAT AS "CSV"
 ) WITH S3 ("AWS_ENDPOINT"="...", "AWS_ACCESS_KEY"="...");

## 5. Routine Load (Kafka 持续消费)

 CREATE ROUTINE LOAD db.my_load ON users
 COLUMNS (id, username, email, age)
 FROM KAFKA ("kafka_broker_list"="broker:9092", "kafka_topic"="topic");

## 6. INSERT OVERWRITE 分区

```sql
INSERT INTO events PARTITION (p20240115)
SELECT user_id, event_name, event_time FROM staging;

INSERT OVERWRITE TABLE events PARTITION (p20240115)
SELECT user_id, event_name, event_time FROM staging;

```

## 7. 对比其他引擎

写入接口:
Doris:      INSERT + Stream Load(HTTP) + Broker Load + Routine Load
StarRocks:  INSERT + Stream Load(HTTP) + Broker Load + Pipe(3.2+)
ClickHouse: INSERT + HTTP Interface + clickhouse-client
BigQuery:   INSERT + bq load + Streaming Insert(弃用) + Storage Write API

Label 幂等:
Doris/StarRocks: Label 机制(相同 Label 不重复导入)
ClickHouse:      无 Label(应用层保证幂等)
BigQuery:        writeDisposition(WRITE_TRUNCATE/WRITE_APPEND)

