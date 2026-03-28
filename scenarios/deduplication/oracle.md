# Oracle: 数据去重

> 参考资料:
> - [Oracle SQL Language Reference - ROWID Pseudocolumn](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ROWID-Pseudocolumn.html)

## 查找重复数据

```sql
SELECT email, COUNT(*) AS cnt
FROM users GROUP BY email HAVING COUNT(*) > 1;
```

## 保留每组一行（ROW_NUMBER）

```sql
SELECT * FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;
```

## 删除重复数据（Oracle 的 ROWID 优势）

方法一: ROWID 去重（Oracle 经典方式，最高效）
```sql
DELETE FROM users
WHERE ROWID NOT IN (
    SELECT MIN(ROWID) FROM users GROUP BY email
);
```

ROWID 的设计:
  ROWID 是 Oracle 的物理行地址（file# + block# + row# within block）。
  它是访问单行最快的方式（直接定位到物理位置，不需要索引）。
  ROWID 在 UPDATE/DELETE WHERE 中使用可以跳过索引查找。

横向对比:
  Oracle:     ROWID（物理地址，18 字符 Base64）
  PostgreSQL: ctid（物理地址，(block, offset) 元组）
  MySQL:      无等价物（InnoDB 通过主键定位行）
  SQL Server: %%physloc%%（未文档化的物理地址）

方法二: 保留最新记录
```sql
DELETE FROM users
WHERE ROWID IN (
    SELECT rid FROM (
        SELECT ROWID AS rid,
               ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
        FROM users
    ) WHERE rn > 1
);
```

方法三: KEEP (DENSE_RANK)（Oracle 独有的聚合函数）
```sql
DELETE FROM users
WHERE ROWID NOT IN (
    SELECT MIN(ROWID) KEEP (DENSE_RANK FIRST ORDER BY created_at DESC)
    FROM users GROUP BY email
);
```

KEEP 在 GROUP BY 中直接取"按排序排名第一的 ROWID"

## 防止重复: MERGE（Oracle 9i+ 首创）

```sql
MERGE INTO users target
USING (SELECT 'a@b.com' AS email, 'alice' AS username FROM DUAL) source
ON (target.email = source.email)
WHEN MATCHED THEN
    UPDATE SET target.username = source.username
WHEN NOT MATCHED THEN
    INSERT (user_id, email, username)
    VALUES (user_seq.NEXTVAL, source.email, source.username);
```

## APPROX_COUNT_DISTINCT（12c+，近似去重计数）

```sql
SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct FROM users;
```

HyperLogLog 算法，大数据量下比 COUNT(DISTINCT) 快 10-100 倍

## '' = NULL 对去重的影响

GROUP BY email: 所有 NULL 和 '' 的行被归为同一组
DISTINCT email: '' 和 NULL 被视为同一个值
这可能导致去重结果与其他数据库不同（其他数据库中 '' 和 NULL 是不同值）

## 去重到新表（CTAS）

```sql
CREATE TABLE users_clean AS
SELECT * FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;
```

## 对引擎开发者的总结

1. ROWID 是 Oracle 去重的经典利器（直接使用物理行地址）。
2. KEEP (DENSE_RANK) 在 GROUP BY 中取排名值，是 Oracle 独有的高效聚合。
3. MERGE 最早由 Oracle 9i 实现，是 UPSERT 和防重复的标准方案。
4. APPROX_COUNT_DISTINCT 使用 HyperLogLog，大数据量场景必备。
5. '' = NULL 导致空字符串和 NULL 在去重时被视为同一值。
