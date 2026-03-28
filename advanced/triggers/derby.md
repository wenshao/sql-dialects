# Derby: 触发器

Derby 支持 SQL 触发器（不需要 Java 类）
BEFORE INSERT（不能修改数据，仅用于验证）
Derby 的 BEFORE 触发器不支持修改 NEW 值
AFTER INSERT

```sql
CREATE TRIGGER trg_users_after_insert
AFTER INSERT ON users
REFERENCING NEW AS newrow
FOR EACH ROW
INSERT INTO audit_log (table_name, action, record_id, created_at)
VALUES ('users', 'INSERT', newrow.id, CURRENT_TIMESTAMP);
```

## AFTER UPDATE

```sql
CREATE TRIGGER trg_users_after_update
AFTER UPDATE ON users
REFERENCING OLD AS oldrow NEW AS newrow
FOR EACH ROW
INSERT INTO audit_log (table_name, action, record_id, old_data, new_data, created_at)
VALUES ('users', 'UPDATE', newrow.id,
        oldrow.username, newrow.username, CURRENT_TIMESTAMP);
```

## AFTER DELETE

```sql
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
REFERENCING OLD AS oldrow
FOR EACH ROW
INSERT INTO audit_log (table_name, action, record_id, created_at)
VALUES ('users', 'DELETE', oldrow.id, CURRENT_TIMESTAMP);
```

## NO CASCADE BEFORE INSERT（验证型触发器）

```sql
CREATE TRIGGER trg_validate_age
NO CASCADE BEFORE INSERT ON users
REFERENCING NEW AS newrow
FOR EACH ROW
WHEN (newrow.age < 0 OR newrow.age > 200)
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid age';
```

## NO CASCADE BEFORE UPDATE

```sql
CREATE TRIGGER trg_validate_email
NO CASCADE BEFORE UPDATE ON users
REFERENCING NEW AS newrow
FOR EACH ROW
WHEN (newrow.email IS NULL)
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email required';
```

## 语句级触发器

```sql
CREATE TRIGGER trg_users_after_stmt
AFTER INSERT ON users
FOR EACH STATEMENT
INSERT INTO log (message, created_at)
VALUES ('Batch insert on users', CURRENT_TIMESTAMP);
```

## 删除触发器

```sql
DROP TRIGGER trg_users_after_insert;
```

## 查看触发器

```sql
SELECT * FROM SYS.SYSTRIGGERS;
```

注意：Derby BEFORE 触发器不能修改 NEW 值
注意：NO CASCADE BEFORE 用于验证（可以阻止操作）
注意：触发器体只能包含一条 SQL 语句
注意：支持 REFERENCING NEW/OLD
注意：不支持 INSTEAD OF 触发器
