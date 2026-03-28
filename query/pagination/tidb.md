# TiDB: 分页查询

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

Shorthand form (same as MySQL)
```sql
SELECT * FROM users ORDER BY id LIMIT 20, 10;

```

Window function pagination (same as MySQL 8.0)
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

```

Cursor-based pagination (recommended, same as MySQL)
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

```

TiDB TopN optimization:
TiDB pushes ORDER BY ... LIMIT down to TiKV (TopN pushdown)
This avoids scanning entire table for small LIMIT queries
```sql
EXPLAIN SELECT * FROM users ORDER BY age LIMIT 10;
```

Look for "TopN" operator in EXPLAIN output

Coprocessor pushdown:
LIMIT is pushed to TiKV coprocessor, reducing data transfer
Very efficient for simple pagination queries

TiFlash pagination:
For analytical queries with TiFlash, pagination is executed in MPP mode
```sql
SELECT /*+ READ_FROM_STORAGE(TIFLASH[users]) */ city, COUNT(*) AS cnt
FROM users
GROUP BY city
ORDER BY cnt DESC
LIMIT 10;

```

Large OFFSET performance:
Same issue as MySQL: large OFFSET scans and discards rows
Use cursor-based pagination for better performance
For distributed tables, large OFFSET is especially costly as it may
span multiple TiKV regions

Prepared statement with LIMIT (same as MySQL)
```sql
PREPARE stmt FROM 'SELECT * FROM users ORDER BY id LIMIT ? OFFSET ?';
SET @limit = 10;
SET @offset = 20;
EXECUTE stmt USING @limit, @offset;

```

Limitations:
Same large OFFSET performance issue as MySQL
LIMIT without ORDER BY may return non-deterministic results
  (different from MySQL due to distributed storage)
Always use ORDER BY with LIMIT for deterministic pagination
