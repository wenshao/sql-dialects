# KingbaseES (人大金仓): 触发器

PostgreSQL compatible syntax.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)


## 触发器函数

```sql
CREATE OR REPLACE FUNCTION trg_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## 创建触发器

```sql
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_update_timestamp();
```

## AFTER 触发器

```sql
CREATE OR REPLACE FUNCTION trg_audit_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, new_data)
    VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(NEW));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_audit_insert();
```

触发器变量
TG_OP: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
TG_TABLE_NAME: 表名
TG_WHEN: 'BEFORE', 'AFTER', 'INSTEAD OF'
条件触发器

```sql
CREATE TRIGGER trg_users_email_changed
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION notify_email_change();
```

## 语句级触发器

```sql
CREATE TRIGGER trg_users_truncate
    AFTER TRUNCATE ON users
    FOR EACH STATEMENT
    EXECUTE FUNCTION log_truncate();
```

## INSTEAD OF

```sql
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_view
    FOR EACH ROW
    EXECUTE FUNCTION handle_view_insert();
```

## 删除触发器

```sql
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
```

## 启用/禁用

```sql
ALTER TABLE users DISABLE TRIGGER trg_users_audit;
ALTER TABLE users ENABLE TRIGGER trg_users_audit;
ALTER TABLE users DISABLE TRIGGER ALL;
```

注意事项：
触发器语法与 PostgreSQL 完全兼容
支持行级和语句级触发器
支持 INSTEAD OF 触发器
支持条件触发（WHEN 子句）
Oracle 兼容模式下支持 Oracle 风格的触发器语法
