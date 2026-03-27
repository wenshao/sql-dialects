-- Flink SQL: Triggers
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink SQL does NOT support database-style triggers
-- As a stream processing engine, Flink has a different "trigger" concept:
-- Window triggers that control when window results are emitted

-- Flink's Trigger Types (configured via DataStream API, not SQL):

-- 1. Processing-time triggers (default for processing-time windows)
-- Fires when the processing time reaches the window end

-- 2. Event-time triggers (default for event-time windows)
-- Fires when the watermark passes the window end

-- 3. Count triggers (DataStream API only)
-- Fires after N elements in a window

-- In Flink SQL, trigger behavior is implicit in window definitions:

-- Event-time TUMBLE window (triggers when watermark passes window end)
SELECT
    user_id,
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end,
    COUNT(*) AS event_count
FROM events
GROUP BY user_id, TUMBLE(event_time, INTERVAL '1' HOUR);

-- Processing-time window (triggers based on wall clock)
SELECT
    user_id,
    TUMBLE_START(proc_time, INTERVAL '1' MINUTE) AS window_start,
    COUNT(*) AS event_count
FROM events
GROUP BY user_id, TUMBLE(proc_time, INTERVAL '1' MINUTE);

-- Alternatives to database triggers in Flink:

-- 1. Streaming ETL (react to every event as it arrives)
-- This is essentially a "row-level trigger" on INSERT
INSERT INTO audit_log
SELECT
    'events' AS table_name,
    'INSERT' AS action,
    event_id AS record_id,
    event_time AS action_time
FROM events;

-- 2. Pattern detection with MATCH_RECOGNIZE (complex event processing)
-- This is like a "trigger" that fires when a pattern is detected
SELECT *
FROM events
MATCH_RECOGNIZE (
    PARTITION BY user_id
    ORDER BY event_time
    MEASURES
        A.event_time AS login_time,
        LAST(B.event_time) AS last_activity,
        C.event_time AS purchase_time
    ONE ROW PER MATCH
    AFTER MATCH SKIP PAST LAST ROW
    PATTERN (A B* C)
    DEFINE
        A AS A.event_type = 'login',
        B AS B.event_type = 'page_view',
        C AS C.event_type = 'purchase'
);

-- 3. Alerting on conditions (trigger-like alerts)
INSERT INTO alerts
SELECT
    user_id,
    'high_spending' AS alert_type,
    total_amount,
    window_end AS alert_time
FROM (
    SELECT
        user_id,
        SUM(amount) AS total_amount,
        TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end
    FROM orders
    GROUP BY user_id, TUMBLE(event_time, INTERVAL '1' HOUR)
)
WHERE total_amount > 10000;

-- 4. CDC (Change Data Capture) processing
-- React to changes from a database (like a trigger on the source)
CREATE TABLE mysql_orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    status     STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'hostname' = 'localhost',
    'port' = '3306',
    'username' = 'root',
    'password' = 'password',
    'database-name' = 'mydb',
    'table-name' = 'orders'
);

-- Process every change (INSERT, UPDATE, DELETE)
INSERT INTO order_audit
SELECT id, user_id, amount, status, CURRENT_TIMESTAMP AS processed_at
FROM mysql_orders;

-- 5. Side output via STATEMENT SET
BEGIN STATEMENT SET;
-- Main processing
INSERT INTO processed_events
SELECT * FROM events WHERE is_valid = true;
-- Audit/logging (like a trigger)
INSERT INTO event_audit
SELECT event_id, event_type, 'processed', NOW() FROM events;
END;

-- Note: Flink has no CREATE TRIGGER statement
-- Note: Window triggers in Flink control WHEN results are emitted (not database triggers)
-- Note: MATCH_RECOGNIZE provides complex event processing (pattern-based "triggers")
-- Note: CDC connectors allow reacting to database changes in real-time
-- Note: Streaming ETL naturally acts as "INSERT triggers" on source data
-- Note: For custom trigger logic, use Flink's DataStream API with ProcessFunction
