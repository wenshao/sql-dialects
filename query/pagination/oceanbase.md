# OceanBase: 分页查询

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


LIMIT / OFFSET
```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

Shorthand form
```sql
SELECT * FROM users ORDER BY id LIMIT 20, 10;

```

Window function pagination
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

```

Cursor-based pagination (recommended)
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

```

## Oracle Mode


ROWNUM (classic Oracle pagination)
Page 3 (rows 21-30):
```sql
SELECT * FROM (
    SELECT u.*, ROWNUM AS rn
    FROM (SELECT * FROM users ORDER BY id) u
    WHERE ROWNUM <= 30
)
WHERE rn > 20;

```

FETCH FIRST (Oracle 12c+ syntax, supported in OceanBase 4.0+)
```sql
SELECT * FROM users ORDER BY id
FETCH FIRST 10 ROWS ONLY;

```

OFFSET ... FETCH (Oracle 12c+ syntax)
```sql
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

```

FETCH with PERCENT
```sql
SELECT * FROM users ORDER BY age DESC
FETCH FIRST 10 PERCENT ROWS ONLY;

```

FETCH with TIES (include ties at boundary)
```sql
SELECT * FROM users ORDER BY age DESC
FETCH FIRST 10 ROWS WITH TIES;

```

ROW_NUMBER pagination (Oracle mode)
```sql
SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
)
WHERE rn BETWEEN 21 AND 30;

```

Cursor-based pagination (Oracle mode)
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id
FETCH FIRST 10 ROWS ONLY;

```

Parallel pagination hint
```sql
SELECT /*+ PARALLEL(4) */ * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

```

Limitations:
MySQL mode: same as MySQL (LIMIT/OFFSET)
Oracle mode: ROWNUM, FETCH FIRST, OFFSET FETCH supported
Large OFFSET performance degrades in both modes
Cursor-based pagination recommended for large datasets
