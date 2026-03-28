# Hologres: INSERT

> 参考资料:
> - [Hologres SQL - INSERT](https://help.aliyun.com/zh/hologres/user-guide/insert-into-statement)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)
> - 注意: Hologres 兼容 PostgreSQL 语法，同时针对 OLAP 场景做了优化
> - 单行插入

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```

## 多行插入

```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);
```

## 从查询结果插入

```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;
```

## RETURNING（返回插入的行，与 PostgreSQL 兼容）

```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;
```

## 指定默认值

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);
```

## CTE + INSERT

```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;
```

## 从外部表导入（MaxCompute 外部表）

```sql
INSERT INTO users (username, email, age)
SELECT username, email, age FROM mc_foreign_users;
```

固定计划（Fixed Plan）模式优化写入性能
Hologres 对简单 INSERT VALUES 自动使用 Fixed Plan 加速
对于高 QPS 写入场景，建议使用 JDBC PreparedStatement + 批量提交
COPY 命令（批量导入，PostgreSQL 兼容语法）
COPY users (username, email, age) FROM STDIN WITH (FORMAT csv);
alice,alice@example.com,25
bob,bob@example.com,30
\.
写入分区表（自动路由到对应子表）

```sql
INSERT INTO events (event_date, user_id, event_name)
VALUES ('2024-01-15', 1, 'login');
```

## 写入分区子表

```sql
INSERT INTO events_20240115 (user_id, event_name)
VALUES (1, 'login');
```
