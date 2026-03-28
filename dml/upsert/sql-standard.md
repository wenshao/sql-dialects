# SQL 标准: UPSERT

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - MERGE](https://modern-sql.com/feature/merge)

- **注意: SQL 标准没有专用的 UPSERT 关键字**
SQL:2003 引入 MERGE 语句作为标准化的"合并"操作
SQL:2008 对 MERGE 进行了增强

## SQL:2003: MERGE 语句

基本 MERGE（UPSERT 语义）
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

## SQL:2008: MERGE 增强

带条件的 WHEN MATCHED
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

多个 WHEN MATCHED / WHEN NOT MATCHED 子句
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.action = 'update' THEN
    UPDATE SET email = s.email, age = s.age
WHEN MATCHED AND s.action = 'delete' THEN
    DELETE
WHEN NOT MATCHED AND s.action = 'insert' THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

MERGE 中的 DELETE（SQL:2008 新增）
SQL:2003 的 MERGE 只支持 UPDATE 和 INSERT
SQL:2008 增加了 WHEN MATCHED THEN DELETE

仅插入不存在的行（INSERT IF NOT EXISTS）
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

## 各版本差异总结

SQL:2003: 引入 MERGE (WHEN MATCHED UPDATE / WHEN NOT MATCHED INSERT)
SQL:2008: MERGE 增加 DELETE 支持, 多个 WHEN 子句, AND 条件
- **注意: ON CONFLICT (PostgreSQL) 不在 SQL 标准中**
- **注意: ON DUPLICATE KEY UPDATE (MySQL) 不在 SQL 标准中**
- **注意: REPLACE INTO (MySQL/SQLite) 不在 SQL 标准中**

## 各数据库 MERGE 支持情况

Oracle:      10g+ (2003)，最早实现 MERGE 的数据库之一
SQL Server:  2008+
PostgreSQL:  15+ (2022)
MySQL:       不支持 MERGE，使用 ON DUPLICATE KEY UPDATE
SQLite:      不支持 MERGE，使用 ON CONFLICT
DB2:         9.1+ (2004)
