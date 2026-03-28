# Flink SQL: INSERT

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
INSERT INTO output_table
SELECT user_id, event_type, COUNT(*) AS cnt
FROM input_events
GROUP BY user_id, event_type;

```

Insert values (for testing / batch mode)
```sql
INSERT INTO users (id, username, email) VALUES
    (1, 'alice', 'alice@example.com'),
    (2, 'bob', 'bob@example.com');

```

Insert into Kafka sink from Kafka source (streaming ETL)
```sql
INSERT INTO output_events
SELECT
    user_id,
    event_type,
    COUNT(*) AS event_count,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end
FROM user_events
GROUP BY
    user_id,
    event_type,
    TUMBLE(event_time, INTERVAL '1' HOUR);

```

Insert into JDBC sink (write to database)
```sql
INSERT INTO jdbc_sink_table
SELECT user_id, username, total_amount
FROM aggregated_results;

```

Insert into filesystem (write Parquet/CSV/JSON files)
```sql
INSERT INTO filesystem_output
SELECT * FROM processed_events;

```

Multiple INSERT statements in one job (Flink 1.13+)
STATEMENT SET groups multiple INSERT INTO statements into one job
```sql
BEGIN STATEMENT SET;
INSERT INTO kafka_output_1
SELECT user_id, event_type FROM events WHERE event_type = 'click';
INSERT INTO kafka_output_2
SELECT user_id, event_type FROM events WHERE event_type = 'purchase';
END;

```

INSERT with query hints
```sql
INSERT INTO output_table
SELECT /*+ STATE_TTL('e' = '1d', 'u' = '12h') */
    e.user_id, u.username, COUNT(*) AS cnt
FROM events e
JOIN users FOR SYSTEM_TIME AS OF e.proc_time AS u
ON e.user_id = u.id
GROUP BY e.user_id, u.username;

```

INSERT OVERWRITE (batch mode only, Flink 1.14+)
```sql
INSERT OVERWRITE filesystem_table
SELECT * FROM batch_source;

```

INSERT OVERWRITE with partition
```sql
INSERT OVERWRITE filesystem_table PARTITION (dt = '2024-01-15')
SELECT id, name, amount FROM batch_source
WHERE dt = '2024-01-15';

```

Note: INSERT INTO is the primary way to launch Flink streaming jobs
Note: Each INSERT INTO creates a continuous streaming pipeline
Note: STATEMENT SET is used to run multiple sinks from the same source efficiently
Note: No RETURNING clause
Note: No INSERT OR REPLACE / INSERT OR IGNORE (use upsert connectors instead)
Note: INSERT OVERWRITE only works in batch mode, not streaming
Note: In streaming mode, INSERT INTO runs indefinitely until the job is cancelled
