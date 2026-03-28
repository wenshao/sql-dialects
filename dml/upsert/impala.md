# Apache Impala: UPSERT

> 参考资料:
> - [Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)
> - [Impala Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_functions.html)


注意: Impala UPSERT 仅支持 Kudu 表
HDFS 表不支持 UPSERT

=== Kudu 表: UPSERT ===

基本 UPSERT（存在则更新，不存在则插入）
```sql
UPSERT INTO users_kudu VALUES (1, 'alice', 'new@example.com', 26);
```


批量 UPSERT
```sql
UPSERT INTO users_kudu VALUES
    (1, 'alice', 'alice_new@example.com', 26),
    (2, 'bob', 'bob_new@example.com', 31),
    (3, 'charlie', 'charlie@example.com', 35);
```


从查询 UPSERT
```sql
UPSERT INTO users_kudu
SELECT id, username, email, age FROM staging_users;
```


指定列 UPSERT
```sql
UPSERT INTO users_kudu (id, email)
VALUES (1, 'alice_updated@example.com');
-- 未指定的列使用默认值（如果已存在，非指定列的值会被默认值覆盖）
```


=== INSERT IGNORE（忽略重复主键错误） ===

已存在的行不会被更新，也不会报错
```sql
INSERT IGNORE INTO users_kudu VALUES (1, 'alice', 'skip@example.com', 99);
```


=== HDFS 表的替代方案 ===

方式一：INSERT OVERWRITE + FULL OUTER JOIN
```sql
INSERT OVERWRITE users
SELECT
    COALESCE(s.id, t.id) AS id,
    COALESCE(s.username, t.username) AS username,
    COALESCE(s.email, t.email) AS email,
    COALESCE(s.age, t.age) AS age
FROM users t
FULL OUTER JOIN staging_users s ON t.id = s.id;
```


方式二：UNION ALL + 去重
```sql
INSERT OVERWRITE users
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM (
        SELECT * FROM staging_users
        UNION ALL
        SELECT * FROM users
    ) combined
) ranked WHERE rn = 1;
```


方式三：LEFT ANTI JOIN（仅插入新行）
```sql
INSERT INTO users
SELECT s.* FROM staging_users s
LEFT ANTI JOIN users u ON s.id = u.id;
```


注意：UPSERT 是 Impala 的原生关键字（不是 INSERT ON CONFLICT）
注意：UPSERT 仅适用于 Kudu 表
注意：UPSERT 未指定列会使用默认值覆盖
注意：INSERT IGNORE 忽略主键冲突（Kudu 表）
注意：不支持 MERGE 语法
