# StarRocks: 临时表

> 参考资料:
> - [1] StarRocks Documentation
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. 不支持临时表 (与 Doris 相同)

 替代方案: CTE、Staging 表、INSERT INTO SELECT。

## 2. CTE

```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u JOIN stats s ON u.id = s.user_id;

```

## 3. Staging 表

```sql
CREATE TABLE staging_results (
    user_id BIGINT,
    total   DECIMAL(10,2)
) DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ("replication_num" = "1");

INSERT INTO staging_results
SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

DROP TABLE staging_results;

```

## 4. CTAS 替代 (3.0+ 自动分布)

```sql
CREATE TABLE temp_result AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;
```

StarRocks 3.0+ CTAS 自动推断分布策略，不需要 DISTRIBUTED BY。


```sql
DROP TABLE temp_result;

```

对比 Doris: CTAS 仍需显式 DISTRIBUTED BY(某些场景)。
StarRocks 的自动推断降低了 Staging 表的使用门槛。

