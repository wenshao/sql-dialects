# TiDB: 条件函数

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

```

Simple CASE (same as MySQL)
```sql
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

```

IF (same as MySQL)
```sql
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

```

IFNULL (same as MySQL)
```sql
SELECT IFNULL(phone, 'N/A') FROM users;

```

COALESCE (same as MySQL)
```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;

```

NULLIF (same as MySQL)
```sql
SELECT NULLIF(age, 0) FROM users;

```

CAST / CONVERT (same as MySQL)
```sql
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT('123', SIGNED);

```

ELT / FIELD (same as MySQL)
```sql
SELECT ELT(2, 'a', 'b', 'c');
SELECT FIELD('b', 'a', 'b', 'c');

```

GREATEST / LEAST (same as MySQL)
```sql
SELECT GREATEST(1, 3, 2);
SELECT LEAST(1, 3, 2);

```

ISNULL (same as MySQL)
```sql
SELECT ISNULL(phone) FROM users;

```

TiDB-specific: conditional with TiFlash
When using TiFlash replicas, conditional expressions are pushed down
```sql
SELECT /*+ READ_FROM_STORAGE(TIFLASH[users]) */ username,
    CASE WHEN age >= 18 THEN 'adult' ELSE 'minor' END AS category
FROM users;

```

TiDB-specific: CAST to JSON types
```sql
SELECT CAST('{"a":1}' AS JSON);
SELECT CAST(123 AS JSON);  -- not available in MySQL 5.7, works in TiDB

```

Limitations:
All MySQL conditional functions work identically
No differences in CASE, IF, IFNULL, COALESCE, NULLIF behavior
Type casting follows MySQL rules
Some edge cases in CAST behavior may differ slightly from MySQL
