# Trino: UPSERT

> 参考资料:
> - [Trino - MERGE](https://trino.io/docs/current/sql/merge.html)
> - [Trino - INSERT](https://trino.io/docs/current/sql/insert.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

```sql
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

从表 MERGE
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

带条件的 MERGE
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

跨 catalog MERGE
```sql
MERGE INTO iceberg.db.users AS t
USING mysql.db.staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

Iceberg connector MERGE
MERGE 产生新 snapshot，支持 Time Travel
```sql
MERGE INTO iceberg.db.users AS t
USING iceberg.db.updates AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET email = s.email
WHEN NOT MATCHED THEN
    INSERT (id, username, email) VALUES (s.id, s.username, s.email);

```

Delta Lake connector MERGE
```sql
MERGE INTO delta.db.users AS t
USING delta.db.updates AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET email = s.email
WHEN NOT MATCHED THEN
    INSERT (id, username, email) VALUES (s.id, s.username, s.email);

```

仅插入不存在的行
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

**限制:**
不支持 ON CONFLICT / ON DUPLICATE KEY 语法
MERGE 性能取决于底层 connector
部分 connector 不支持 MERGE
