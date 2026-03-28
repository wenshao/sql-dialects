# Trino: INSERT

> 参考资料:
> - [Trino - INSERT](https://trino.io/docs/current/sql/insert.html)
> - [Trino - SQL Statement List](https://trino.io/docs/current/sql.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

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

跨 catalog 插入（Trino 联邦查询特有）
```sql
INSERT INTO iceberg.db.users (username, email, age)
SELECT username, email, age FROM mysql.db.users WHERE age > 60;

```

跨 catalog 跨数据源
```sql
INSERT INTO hive.warehouse.events
SELECT * FROM kafka.default.raw_events;

```

CTE + INSERT
```sql
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;

```

写入分区表（Hive connector）
```sql
INSERT INTO hive.db.events
SELECT user_id, event_name, event_date FROM staging_events;
```

分区列在最后，自动路由到对应分区

INSERT OVERWRITE（仅 Hive connector 支持）
需要设置 session 属性
SET SESSION hive.insert_existing_partitions_behavior = 'OVERWRITE';
INSERT INTO hive.db.events SELECT ...;

Iceberg connector 特性
写入后自动管理 snapshot
```sql
INSERT INTO iceberg.db.events (user_id, event_name, event_time)
SELECT user_id, event_name, event_time FROM staging_events;

```

创建表并插入 (CTAS)
```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE age > 18;

```

CTAS 指定格式和分区（Hive connector）
```sql
CREATE TABLE hive.db.users_orc
WITH (format = 'ORC', partitioned_by = ARRAY['country'])
AS SELECT * FROM users;

```

**注意:** Trino 不支持 DEFAULT 关键字
需要省略列或显式指定 NULL: INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
