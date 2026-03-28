# Spanner: UPSERT

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## INSERT OR UPDATE (Spanner-specific, simplest upsert)


Insert if not exists, update all columns if exists (by primary key)
```sql
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 26);

```

INSERT OR UPDATE multiple rows
```sql
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30);

```

INSERT OR UPDATE with THEN RETURN
```sql
INSERT OR UPDATE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 26)
THEN RETURN UserId, Username, Email;

```

## INSERT OR IGNORE (skip if primary key exists)


```sql
INSERT OR IGNORE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice@example.com', 25);
```

No error if UserId=1 already exists

## REPLACE (delete existing + insert)


Deletes existing row with same primary key and inserts new row
```sql
REPLACE INTO Users (UserId, Username, Email, Age)
VALUES (1, 'alice', 'alice_new@example.com', 26);

```

## MERGE (SQL standard, most flexible)


Basic MERGE
```sql
MERGE INTO Users AS t
USING (SELECT 1 AS UserId, 'alice' AS Username, 'alice@example.com' AS Email, 26 AS Age) AS s
ON t.UserId = s.UserId
WHEN MATCHED THEN
    UPDATE SET Email = s.Email, Age = s.Age
WHEN NOT MATCHED THEN
    INSERT (UserId, Username, Email, Age) VALUES (s.UserId, s.Username, s.Email, s.Age);

```

MERGE from another table
```sql
MERGE INTO Users AS t
USING StagingUsers AS s
ON t.UserId = s.UserId
WHEN MATCHED THEN
    UPDATE SET Email = s.Email, Age = s.Age
WHEN NOT MATCHED THEN
    INSERT (UserId, Username, Email, Age)
    VALUES (s.UserId, s.Username, s.Email, s.Age);

```

MERGE with conditional update
```sql
MERGE INTO Users AS t
USING StagingUsers AS s
ON t.UserId = s.UserId
WHEN MATCHED AND s.Age > t.Age THEN
    UPDATE SET Age = s.Age
WHEN MATCHED AND s.Age <= t.Age THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (UserId, Username, Email, Age)
    VALUES (s.UserId, s.Username, s.Email, s.Age);

```

MERGE with THEN RETURN
```sql
MERGE INTO Users AS t
USING (SELECT 1 AS UserId, 'alice' AS Username, 'alice@example.com' AS Email) AS s
ON t.UserId = s.UserId
WHEN MATCHED THEN UPDATE SET Email = s.Email
WHEN NOT MATCHED THEN INSERT (UserId, Username, Email) VALUES (s.UserId, s.Username, s.Email)
THEN RETURN t.UserId, t.Username;

```

Note: INSERT OR UPDATE matches on primary key only
Note: INSERT OR IGNORE silently skips existing rows
Note: REPLACE deletes + re-inserts (triggers ON DELETE CASCADE on interleaved children)
Note: MERGE provides most flexibility with conditions
Note: No INSERT ... ON CONFLICT syntax (use INSERT OR UPDATE or MERGE)
Note: All operations are strongly consistent
