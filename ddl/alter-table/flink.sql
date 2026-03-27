-- Flink SQL: ALTER TABLE (Flink 1.13+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Rename table
ALTER TABLE users RENAME TO members;

-- Set table properties (connector options)
ALTER TABLE users SET (
    'scan.startup.mode' = 'earliest-offset'
);

-- Reset (remove) table properties (Flink 1.14+)
ALTER TABLE users RESET ('scan.startup.mode');

-- Add column (Flink 1.17+)
ALTER TABLE users ADD phone STRING;
ALTER TABLE users ADD (phone STRING, address STRING);

-- Add column with position (Flink 1.17+)
ALTER TABLE users ADD phone STRING AFTER email;
ALTER TABLE users ADD phone STRING FIRST;

-- Add computed column (Flink 1.17+)
ALTER TABLE users ADD total_price AS price * quantity;

-- Add watermark (Flink 1.17+)
ALTER TABLE users ADD WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND;

-- Drop column (Flink 1.17+)
ALTER TABLE users DROP phone;
ALTER TABLE users DROP (phone, address);

-- Drop watermark (Flink 1.17+)
ALTER TABLE users DROP WATERMARK;

-- Drop computed column
ALTER TABLE users DROP total_price;

-- Rename column (Flink 1.17+)
ALTER TABLE users RENAME phone TO mobile;

-- Modify column type (Flink 1.17+)
ALTER TABLE users MODIFY phone STRING;
ALTER TABLE users MODIFY (phone STRING, age BIGINT);

-- Modify column position (Flink 1.17+)
ALTER TABLE users MODIFY phone STRING AFTER email;
ALTER TABLE users MODIFY phone STRING FIRST;

-- Modify watermark
ALTER TABLE users MODIFY WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND;

-- Add primary key (Flink 1.17+)
ALTER TABLE users ADD PRIMARY KEY (id) NOT ENFORCED;

-- Drop primary key (Flink 1.17+)
ALTER TABLE users DROP PRIMARY KEY;

-- Change table comment (Flink 1.17+)
ALTER TABLE users SET ('table.comment' = 'User events table');

-- Note: ALTER TABLE operations are catalog-dependent (some catalogs may not support all)
-- Note: PRIMARY KEY is NOT ENFORCED (semantic hint for optimization only)
-- Note: No ALTER TABLE ... ADD FOREIGN KEY (not supported)
-- Note: No ALTER TABLE ... ADD UNIQUE (not supported)
-- Note: Column changes may require restarting the Flink job
-- Note: Watermark changes affect event-time processing semantics
