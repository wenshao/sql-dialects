# YugabyteDB: 触发器

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## Trigger function (must be created first)


```sql
CREATE OR REPLACE FUNCTION trg_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;  -- BEFORE triggers must return NEW (or NULL to cancel)
END;
$$ LANGUAGE plpgsql;

```

## BEFORE trigger


```sql
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_update_timestamp();

```

## AFTER trigger (audit logging)


```sql
CREATE OR REPLACE FUNCTION trg_audit_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, new_data, created_at)
    VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(NEW), now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_audit_insert();

```

## Trigger variables


TG_OP: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
TG_TABLE_NAME: table name
TG_WHEN: 'BEFORE', 'AFTER', 'INSTEAD OF'
OLD: old row (UPDATE/DELETE)
NEW: new row (INSERT/UPDATE)

## Conditional trigger (WHEN clause)


```sql
CREATE TRIGGER trg_users_email_changed
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION notify_email_change();

```

## Statement-level trigger


```sql
CREATE TRIGGER trg_users_truncate
    AFTER TRUNCATE ON users
    FOR EACH STATEMENT
    EXECUTE FUNCTION log_truncate();

```

## INSTEAD OF trigger (on views)


```sql
CREATE VIEW user_summary AS
SELECT id, username, email FROM users WHERE status = 1;

CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_summary
    FOR EACH ROW
    EXECUTE FUNCTION handle_view_insert();

```

## Multi-event trigger


```sql
CREATE OR REPLACE FUNCTION trg_all_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO changes_log (table_name, action, old_data)
        VALUES (TG_TABLE_NAME, 'DELETE', to_jsonb(OLD));
        RETURN OLD;
    ELSE
        INSERT INTO changes_log (table_name, action, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_changes
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION trg_all_changes();

```

## Manage triggers


Drop trigger
```sql
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;

```

Enable/disable
```sql
ALTER TABLE users DISABLE TRIGGER trg_users_audit;
ALTER TABLE users ENABLE TRIGGER trg_users_audit;
ALTER TABLE users DISABLE TRIGGER ALL;
ALTER TABLE users ENABLE TRIGGER ALL;

```

Note: Full PostgreSQL trigger support (BEFORE, AFTER, INSTEAD OF)
Note: Row-level (FOR EACH ROW) and statement-level triggers
Note: WHEN clause for conditional triggers
Note: Triggers work across distributed tablets
Note: Trigger execution may involve cross-node communication
Note: Based on PostgreSQL 11.2 trigger implementation
Note: Event triggers (DDL events) also supported
