# SQL 标准: 触发器

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [SQL Standard Features Comparison (jOOQ)](https://www.jooq.org/diff)

## SQL-86 / SQL-89 / SQL-92: 没有触发器

早期标准没有触发器定义

## SQL:1999 (SQL3): 首次引入触发器

定义了 CREATE TRIGGER 语法
支持 BEFORE / AFTER
支持 INSERT / UPDATE / DELETE
支持 FOR EACH ROW / FOR EACH STATEMENT
支持 WHEN 条件
支持 OLD / NEW 引用

BEFORE INSERT 触发器
```sql
CREATE TRIGGER trg_before_insert
    BEFORE INSERT ON users
    FOR EACH ROW
    WHEN (NEW.username IS NOT NULL)
BEGIN ATOMIC
    SET NEW.created_at = CURRENT_TIMESTAMP;
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END;
```

AFTER INSERT 触发器
```sql
CREATE TRIGGER trg_audit_insert
    AFTER INSERT ON users
    FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO audit_log (table_name, action, record_id, new_data)
    VALUES ('users', 'INSERT', NEW.id, NEW.username);
END;
```

AFTER UPDATE 触发器
```sql
CREATE TRIGGER trg_audit_update
    AFTER UPDATE ON users
    FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO audit_log (table_name, action, record_id, old_data, new_data)
    VALUES ('users', 'UPDATE', NEW.id, OLD.username, NEW.username);
END;
```

AFTER DELETE 触发器
```sql
CREATE TRIGGER trg_audit_delete
    AFTER DELETE ON users
    FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO audit_log (table_name, action, record_id, old_data)
    VALUES ('users', 'DELETE', OLD.id, OLD.username);
END;
```

多事件触发器
```sql
CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
BEGIN ATOMIC
```

触发器体
```sql
END;
```

## SQL:1999 触发器特性

BEFORE 触发器: 可以修改 NEW 值，返回 NULL 取消操作
AFTER 触发器: 不能修改数据，只能执行额外操作
FOR EACH ROW: 每行触发一次
FOR EACH STATEMENT: 每个语句触发一次（即使影响 0 行）
WHEN: 条件过滤

语句级触发器
```sql
CREATE TRIGGER trg_statement_level
    AFTER INSERT ON users
    FOR EACH STATEMENT
BEGIN ATOMIC
```

每个 INSERT 语句触发一次（不管插入多少行）
```sql
END;
```

WHEN 条件
```sql
CREATE TRIGGER trg_email_change
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email <> NEW.email)
BEGIN ATOMIC
    INSERT INTO email_change_log (user_id, old_email, new_email)
    VALUES (NEW.id, OLD.email, NEW.email);
END;
```

## SQL:2003: 增强

增强了触发器的能力

## SQL:2008: INSTEAD OF 触发器

新增 INSTEAD OF 触发器（用于视图）

```sql
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_view
    FOR EACH ROW
BEGIN ATOMIC
    INSERT INTO users (username, email) VALUES (NEW.username, NEW.email);
END;
```

## SQL:2011: TRUNCATE 触发器

TRUNCATE 也可以触发触发器

## 触发器执行顺序（标准定义）

1. BEFORE 语句级触发器
2. 对每行：BEFORE 行级触发器 -> 操作 -> AFTER 行级触发器
3. AFTER 语句级触发器
4. 约束检查（在 AFTER 触发器之后）

## 各数据库实现对比

MySQL: DELIMITER 包裹，不支持 INSTEAD OF，不支持语句级
PostgreSQL: 触发器函数 + CREATE TRIGGER，最接近标准
Oracle: BEFORE/AFTER/INSTEAD OF，支持复合触发器
SQL Server: AFTER/INSTEAD OF，不支持 BEFORE
SQLite: 支持 BEFORE/AFTER/INSTEAD OF

- **注意：触发器在 SQL:1999 首次引入标准**
- **注意：BEGIN ATOMIC 是标准语法，各数据库实现不同**
- **注意：触发器的执行顺序在标准中有明确定义**
- **注意：分析型数据库（BigQuery、ClickHouse 等）通常不支持触发器**
