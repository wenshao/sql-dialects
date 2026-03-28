# StarRocks: 日期时间类型

> 参考资料:
> - [1] StarRocks Documentation - Data Types
>   https://docs.starrocks.io/docs/sql-reference/data-types/


## 与 Doris 完全相同的类型体系

DATE: 日期
DATETIME: 日期时间(微秒精度)
无 TIME 类型，无 TIMESTAMPTZ


```sql
CREATE TABLE events (
    id BIGINT, event_date DATE, created_at DATETIME, precise_at DATETIME
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id);

SELECT CURRENT_DATE(), NOW(), CURRENT_TIMESTAMP();
SELECT DATE_ADD('2024-01-15', INTERVAL 7 DAY);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT YEAR(NOW()), DATE_FORMAT(NOW(), '%Y-%m-%d');
SELECT DATE_TRUNC('month', NOW());
SELECT UNIX_TIMESTAMP(), FROM_UNIXTIME(1705276800);

```

StarRocks vs Doris: 日期时间类型完全相同(同源)。

