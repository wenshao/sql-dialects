# Derby: UPSERT

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)
> - Derby 没有原生 UPSERT 语法
> - 使用 MERGE 语句或应用层逻辑实现
> - ============================================================
> - MERGE（SQL 标准语法，10.11+）
> - ============================================================
> - 基本 MERGE

```sql
MERGE INTO users AS t
USING (VALUES (1, 'alice', 'alice@example.com', 25)) AS s(id, username, email, age)
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET username = s.username, email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);
```

## 从表中 MERGE

```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET username = s.username, email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

## 仅插入不存在的行

```sql
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com')) AS s(username, email)
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email) VALUES (s.username, s.email);
```

## 存储过程模拟 UPSERT（老版本替代方案）


使用 Java 存储过程实现 UPSERT 逻辑
1. 先尝试 UPDATE
2. 如果影响行数为 0，则 INSERT
或在应用层实现：
UPDATE users SET email = ? WHERE username = ?;
如果 affected_rows == 0:
INSERT INTO users (username, email) VALUES (?, ?);

## DELETE + INSERT 模拟（不推荐）


先删除再插入（在事务中执行）
START TRANSACTION;
DELETE FROM users WHERE id = 1;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com');
COMMIT;
注意：MERGE 在 Derby 10.11+ 才支持
注意：老版本需要用存储过程或应用层逻辑模拟
注意：不支持 ON CONFLICT / ON DUPLICATE KEY
注意：MERGE 中 WHEN MATCHED 和 WHEN NOT MATCHED 各最多一个
注意：MERGE 的 source 不支持多行 VALUES（需要用子查询或表）
