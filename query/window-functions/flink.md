# Flink SQL: 窗口函数

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

```

Partition
```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

```

Aggregate window functions
```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

```

Offset functions
```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY age) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY age) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

```

NTILE
```sql
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;

```

Frame clauses
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

```

RANGE frame
```sql
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS nearby_count
FROM users;

```

Deduplication (streaming Top-1 pattern, Flink-optimized)
Flink recognizes this pattern and optimizes it for streaming
```sql
SELECT user_id, username, email, event_time
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS rn
    FROM user_events
)
WHERE rn = 1;

```

Top-N per group (streaming, Flink-optimized)
Flink maintains incremental Top-N state
```sql
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY sales DESC) AS rn
    FROM products
)
WHERE rn <= 3;

```

Group Window Functions (Flink-specific streaming windows)

TUMBLE window (fixed-size, non-overlapping)
```sql
SELECT
    user_id,
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY
    user_id,
    TUMBLE(event_time, INTERVAL '1' HOUR);

```

HOP window (sliding, overlapping)
```sql
SELECT
    user_id,
    HOP_START(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR) AS window_start,
    HOP_END(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR) AS window_end,
    COUNT(*) AS event_count
FROM events
GROUP BY
    user_id,
    HOP(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR);

```

SESSION window (gap-based)
```sql
SELECT
    user_id,
    SESSION_START(event_time, INTERVAL '30' MINUTE) AS window_start,
    SESSION_END(event_time, INTERVAL '30' MINUTE) AS window_end,
    COUNT(*) AS event_count
FROM events
GROUP BY
    user_id,
    SESSION(event_time, INTERVAL '30' MINUTE);

```

CUMULATE window (Flink 1.13+, expanding windows)
```sql
SELECT
    user_id,
    window_start,
    window_end,
    SUM(amount) AS cumulative_amount
FROM TABLE(
    CUMULATE(TABLE orders, DESCRIPTOR(event_time), INTERVAL '1' HOUR, INTERVAL '1' DAY)
)
GROUP BY user_id, window_start, window_end;

```

Window TVF (Table-Valued Functions, Flink 1.13+, recommended over GROUP BY windows)
TUMBLE TVF
```sql
SELECT window_start, window_end, user_id, COUNT(*) AS cnt
FROM TABLE(
    TUMBLE(TABLE events, DESCRIPTOR(event_time), INTERVAL '10' MINUTE)
)
GROUP BY window_start, window_end, user_id;

```

HOP TVF
```sql
SELECT window_start, window_end, user_id, SUM(amount) AS total
FROM TABLE(
    HOP(TABLE orders, DESCRIPTOR(event_time), INTERVAL '5' MINUTE, INTERVAL '1' HOUR)
)
GROUP BY window_start, window_end, user_id;

```

SESSION TVF (Flink 1.14+)
```sql
SELECT window_start, window_end, user_id, COUNT(*) AS cnt
FROM TABLE(
    SESSION(TABLE events, DESCRIPTOR(event_time), INTERVAL '30' MINUTE)
)
GROUP BY window_start, window_end, user_id;

```

Note: Flink supports standard OVER window functions (ROW_NUMBER, RANK, etc.)
Note: Group windows (TUMBLE/HOP/SESSION) are unique to stream processing
Note: Window TVFs (Flink 1.13+) are the recommended way to define group windows
Note: Deduplication and Top-N patterns are specially optimized in streaming mode
Note: No QUALIFY clause (use subquery pattern)
Note: No FILTER clause on window functions
Note: No PERCENT_RANK / CUME_DIST in streaming mode (batch only)
Note: OVER windows in streaming mode require ORDER BY on a time attribute
