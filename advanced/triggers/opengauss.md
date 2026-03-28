# openGauss/GaussDB: 触发器

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)


## 触发器函数（必须先创建）

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
    EXECUTE PROCEDURE trg_update_timestamp();
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
    EXECUTE PROCEDURE trg_audit_insert();
```

触发器变量
TG_OP: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
TG_TABLE_NAME: 表名
TG_WHEN: 'BEFORE', 'AFTER', 'INSTEAD OF'
OLD: 旧行（UPDATE/DELETE）
NEW: 新行（INSERT/UPDATE）
条件触发器（WHEN 子句）

```sql
CREATE TRIGGER trg_users_email_changed
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE PROCEDURE notify_email_change();
```

## 语句级触发器

```sql
CREATE TRIGGER trg_users_truncate
    AFTER TRUNCATE ON users
    FOR EACH STATEMENT
    EXECUTE PROCEDURE log_truncate();
```

## INSTEAD OF（在视图上）

```sql
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_view
    FOR EACH ROW
    EXECUTE PROCEDURE handle_view_insert();
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
触发器语法与 PostgreSQL 兼容
openGauss 使用 EXECUTE PROCEDURE（而非 EXECUTE FUNCTION）
支持行级和语句级触发器
支持 INSTEAD OF 触发器
支持条件触发（WHEN 子句）
