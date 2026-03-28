# CockroachDB: 触发器

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## No trigger support


The following PostgreSQL syntax is NOT supported:
CREATE TRIGGER ...
CREATE OR REPLACE TRIGGER ...
DROP TRIGGER ...

## Alternative 1: Computed columns (for auto-updated fields)


Use generated columns for derived values
```sql
CREATE TABLE products (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price      DECIMAL(10,2),
    tax_rate   DECIMAL(5,4) DEFAULT 0.08,
    total      DECIMAL(10,2) GENERATED ALWAYS AS (price * (1 + tax_rate)) STORED
);

```

## Alternative 2: ON UPDATE in application layer


Handle updated_at in your application:
UPDATE users SET email = 'new@example.com', updated_at = now() WHERE id = 1;

Or use a function:
```sql
CREATE OR REPLACE FUNCTION update_user(
    p_id UUID, p_email VARCHAR
) RETURNS VOID AS $$
BEGIN
    UPDATE users SET email = p_email, updated_at = now() WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;

```

## Alternative 3: Changefeeds (CockroachDB-specific)


Changefeeds emit row-level changes to external sinks
Similar to trigger functionality but asynchronous

Create changefeed to Kafka
CREATE CHANGEFEED FOR users, orders
    INTO 'kafka://broker:9092'
    WITH updated, resolved;

Create changefeed to cloud storage
CREATE CHANGEFEED FOR users
    INTO 'gs://bucket/path'
    WITH format = 'json', schema_change_policy = 'stop';

Create changefeed to webhook
CREATE CHANGEFEED FOR users
    INTO 'webhook-https://example.com/hook'
    WITH updated;

Core changefeed (to SQL client)
EXPERIMENTAL CHANGEFEED FOR users;

Cancel changefeed
CANCEL JOB (SELECT job_id FROM [SHOW CHANGEFEED JOBS]);

## Alternative 4: Scheduled jobs


Use CockroachDB's scheduled jobs for periodic tasks:
CREATE SCHEDULE daily_cleanup
    RECURRING '0 0 * * *'  -- cron format
    FOR BACKUP INTO 'gs://bucket/backups';

## Alternative 5: Application-level event handling


Use your application framework's ORM hooks:
Before/After save hooks
Model observers
Event-driven architecture with message queues

Note: Triggers are NOT supported in CockroachDB
Note: Changefeeds provide asynchronous change notification
Note: Use computed columns for derived values
Note: Use application logic for complex trigger-like behavior
Note: Changefeeds can target Kafka, cloud storage, or webhooks
Note: Consider event-driven architecture for complex workflows
