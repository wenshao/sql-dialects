# TiDB: 日期函数

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT SYSDATE();
SELECT UTC_TIMESTAMP();

```

Date arithmetic (same as MySQL)
```sql
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);
SELECT '2024-01-15' + INTERVAL 7 DAY;

```

Date diff (same as MySQL)
```sql
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01 00:00:00', '2024-01-02 12:00:00');

```

Extract (same as MySQL)
```sql
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT EXTRACT(YEAR FROM '2024-01-15');

```

Formatting (same as MySQL)
```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

```

Unix timestamp (same as MySQL)
```sql
SELECT UNIX_TIMESTAMP();
SELECT UNIX_TIMESTAMP('2024-01-15');
SELECT FROM_UNIXTIME(1705276800);
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');

```

TiDB-specific: TSO-related time functions
TIDB_PARSE_TSO: convert TiDB timestamp oracle value to datetime
```sql
SELECT TIDB_PARSE_TSO(@@tidb_current_ts);

```

TIDB_BOUNDED_STALENESS: read data from a time range (5.0+)
Used with stale read feature for reading historical data
```sql
SELECT * FROM users AS OF TIMESTAMP TIDB_BOUNDED_STALENESS(
    NOW() - INTERVAL 5 SECOND,
    NOW()
);

```

Stale read: read historical data at a specific timestamp (5.1+)
```sql
SELECT * FROM users AS OF TIMESTAMP '2024-01-15 10:00:00';
SELECT * FROM users AS OF TIMESTAMP NOW() - INTERVAL 10 SECOND;

```

NOW() vs SYSDATE() in distributed context:
NOW(): fixed at statement start time, consistent across all nodes
SYSDATE(): actual execution time, may differ across TiDB nodes
Recommendation: use NOW() for consistency

Timezone-related
```sql
SET time_zone = '+08:00';
SELECT CONVERT_TZ('2024-01-15 10:00:00', '+00:00', '+08:00');

```

Limitations:
All MySQL date functions work identically
SYSDATE() may return slightly different times on different TiDB nodes
Timezone tables may need manual loading for named timezone support
AS OF TIMESTAMP for stale reads is TiDB-specific
TIDB_PARSE_TSO is TiDB-specific
