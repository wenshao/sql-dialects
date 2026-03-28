# Flink SQL: CTE 公共表表达式

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

```

Multiple CTEs
```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;

```

CTE referencing another CTE
```sql
WITH
base AS (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
),
ranked AS (
    SELECT city, cnt, ROW_NUMBER() OVER (ORDER BY cnt DESC) AS rn
    FROM base
)
SELECT * FROM ranked WHERE rn <= 5;

```

CTE with streaming aggregation
```sql
WITH hourly_stats AS (
    SELECT
        user_id,
        TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
        COUNT(*) AS event_count,
        SUM(amount) AS total_amount
    FROM orders
    GROUP BY user_id, TUMBLE(event_time, INTERVAL '1' HOUR)
)
SELECT * FROM hourly_stats WHERE event_count > 10;

```

CTE for deduplication
```sql
WITH deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS rn
    FROM user_events
)
SELECT user_id, event_type, event_time
FROM deduplicated
WHERE rn = 1;

```

CTE for Top-N per group
```sql
WITH ranked_products AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY sales DESC) AS rn
    FROM products
)
SELECT product_id, category, sales
FROM ranked_products
WHERE rn <= 3;

```

CTE with INSERT INTO
```sql
WITH enriched_events AS (
    SELECT
        e.user_id,
        e.event_type,
        e.event_time,
        u.username
    FROM events e
    JOIN users FOR SYSTEM_TIME AS OF e.proc_time AS u
    ON e.user_id = u.id
)
INSERT INTO output_events
SELECT * FROM enriched_events;

```

CTE with UNION ALL
```sql
WITH combined_events AS (
    SELECT user_id, 'click' AS event_type, click_time AS event_time FROM clicks
    UNION ALL
    SELECT user_id, 'purchase' AS event_type, purchase_time AS event_time FROM purchases
)
SELECT user_id, event_type, COUNT(*) AS cnt
FROM combined_events
GROUP BY user_id, event_type;

```

CTE with windowed aggregation
```sql
WITH user_sessions AS (
    SELECT
        user_id,
        SESSION_START(event_time, INTERVAL '30' MINUTE) AS session_start,
        SESSION_END(event_time, INTERVAL '30' MINUTE) AS session_end,
        COUNT(*) AS page_views
    FROM page_events
    GROUP BY user_id, SESSION(event_time, INTERVAL '30' MINUTE)
)
INSERT INTO session_summary
SELECT * FROM user_sessions;

```

Note: No recursive CTEs (WITH RECURSIVE is not supported)
Note: No writable CTEs (CTE with DELETE/UPDATE combined)
Note: CTE with INSERT INTO is supported and common for streaming pipelines
Note: CTEs help organize complex streaming queries
Note: No MATERIALIZED / NOT MATERIALIZED hints
Note: CTEs in streaming mode follow the same state management rules as subqueries
