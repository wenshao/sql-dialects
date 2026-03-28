# Vertica: INSERT

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


基本插入
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


CTE + INSERT
```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;
```


COPY（高性能批量加载，推荐方式）
```sql
COPY users FROM '/data/users.csv'
    DELIMITER ',' ENCLOSED BY '"' SKIP 1;
```


COPY 从 STDIN
COPY users FROM STDIN DELIMITER ',';

COPY 从 S3
```sql
COPY users FROM 's3://bucket/data/users.csv'
    DELIMITER ',' ENCLOSED BY '"' SKIP 1;
```


COPY 从 HDFS
```sql
COPY users FROM 'hdfs://namenode:8020/data/users.csv'
    DELIMITER ',' SKIP 1;
```


COPY 加载 JSON
```sql
COPY events_flex FROM '/data/events.json' PARSER fjsonparser();
```


COPY 加载 Parquet
```sql
COPY events FROM '/data/events.parquet' PARQUET;
```


COPY 带错误处理
```sql
COPY users FROM '/data/users.csv'
    DELIMITER ','
    REJECTED DATA '/data/rejects.csv'
    EXCEPTIONS '/data/exceptions.log'
    REJECTMAX 100;
```


COPY LOCAL（从客户端加载）
```sql
COPY users FROM LOCAL '/local/path/users.csv' DELIMITER ',';
```


INSERT 到 Flex 表
```sql
INSERT INTO events_flex (data)
VALUES ('{"event": "login", "user": "alice", "time": "2024-01-15"}');
```


直接路径加载（绕过 WOS，直接写 ROS）
```sql
COPY users FROM '/data/users.csv' DELIMITER ',' DIRECT;
```


MERGE（UPSERT 语义）
```sql
MERGE INTO users t
USING staging_users s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET
    username = s.username, email = s.email
WHEN NOT MATCHED THEN INSERT (id, username, email)
    VALUES (s.id, s.username, s.email);
```


注意：INSERT VALUES 适合少量数据
注意：大批量推荐 COPY 命令
注意：DIRECT 加载绕过 WOS（Write Optimized Store），直接写入 ROS
注意：COPY 是 Vertica 最高效的加载方式
