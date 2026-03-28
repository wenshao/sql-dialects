# SQLite: 触发器

> 参考资料:
> - [SQLite Documentation - CREATE TRIGGER](https://www.sqlite.org/lang_createtrigger.html)

## 基本语法

BEFORE INSERT
```sql
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
BEGIN
    SELECT RAISE(ABORT, 'Username too short')
    WHERE length(NEW.username) < 2;
END;
```

AFTER INSERT（审计日志）
```sql
CREATE TRIGGER trg_users_audit_insert
AFTER INSERT ON users
BEGIN
    INSERT INTO audit_log (action, table_name, row_id, timestamp)
    VALUES ('INSERT', 'users', NEW.id, datetime('now'));
END;
```

AFTER UPDATE
```sql
CREATE TRIGGER trg_users_audit_update
AFTER UPDATE ON users
BEGIN
    INSERT INTO audit_log (action, table_name, row_id, old_value, new_value)
    VALUES ('UPDATE', 'users', OLD.id, OLD.email, NEW.email);
END;
```

AFTER DELETE
```sql
CREATE TRIGGER trg_users_audit_delete
AFTER DELETE ON users
BEGIN
    INSERT INTO audit_log (action, table_name, row_id)
    VALUES ('DELETE', 'users', OLD.id);
END;
```

条件触发（WHEN 子句）
```sql
CREATE TRIGGER trg_users_email_change
AFTER UPDATE OF email ON users     -- 仅当 email 列被修改时触发
WHEN OLD.email != NEW.email
BEGIN
    INSERT INTO email_change_log (user_id, old_email, new_email)
    VALUES (OLD.id, OLD.email, NEW.email);
END;

DROP TRIGGER trg_users_before_insert;
DROP TRIGGER IF EXISTS trg_users_before_insert;
```

## INSTEAD OF 触发器（使视图可写）

SQLite 视图不可直接写入。INSTEAD OF 触发器是唯一的方式:
```sql
CREATE VIEW user_orders AS
SELECT u.id, u.username, o.amount FROM users u JOIN orders o ON u.id = o.user_id;

CREATE TRIGGER trg_user_orders_insert
INSTEAD OF INSERT ON user_orders
BEGIN
    INSERT INTO orders (user_id, amount) VALUES (NEW.id, NEW.amount);
END;
```

设计分析:
  SQLite 用 INSTEAD OF 触发器替代自动可更新视图判断。
  优点: 开发者完全控制写入逻辑
  缺点: 样板代码多（每个视图需要 INSERT/UPDATE/DELETE 三个触发器）
  对比: MySQL 自动判断视图是否可更新（简单视图自动可写）

## RAISE 函数（触发器内的错误处理）

RAISE 是 SQLite 触发器内唯一的错误抛出机制:
RAISE(IGNORE)              → 跳过当前操作
RAISE(ROLLBACK, 'message') → 回滚整个事务
RAISE(ABORT, 'message')    → 回滚当前语句（默认行为）
RAISE(FAIL, 'message')     → 终止但保留已执行的修改

```sql
CREATE TRIGGER trg_check_balance
BEFORE UPDATE ON accounts
WHEN NEW.balance < 0
BEGIN
    SELECT RAISE(ABORT, 'Balance cannot be negative');
END;
```

这是 SQLite 实现 CHECK 约束逻辑的另一种方式:
CHECK 约束只能用简单表达式，触发器可以执行任意复杂的验证。

## 触发器的嵌入式特色

SQLite 触发器不支持:
  FOR EACH STATEMENT（只支持 FOR EACH ROW，默认且唯一）
  ENABLE / DISABLE TRIGGER（不能临时禁用）
  ALTER TRIGGER（必须 DROP + CREATE）
  EXECUTE PROCEDURE（没有存储过程）

但支持嵌套触发器:
```sql
  INSERT → trigger A → INSERT → trigger B → ...
```

  默认嵌套深度限制: SQLITE_MAX_TRIGGER_DEPTH = 1000
  可通过 PRAGMA recursive_triggers = ON 控制递归触发器

## 对比与引擎开发者启示

SQLite 触发器的设计:
  (1) 只有 FOR EACH ROW → 简化实现
  (2) INSTEAD OF → 视图可写性的唯一途径
  (3) RAISE → 触发器内的错误处理
  (4) 无 ENABLE/DISABLE → 简化但不灵活

对比:
  MySQL:      BEFORE/AFTER + FOR EACH ROW（无 INSTEAD OF，无 FOR EACH STATEMENT）
  PostgreSQL: BEFORE/AFTER/INSTEAD OF + FOR EACH ROW/STATEMENT + EXECUTE FUNCTION
  ClickHouse: 无触发器（物化视图是 INSERT 触发器的替代）
  BigQuery:   无触发器

对引擎开发者的启示:
  嵌入式引擎的触发器应保持简洁（只需 ROW 级别）。
  INSTEAD OF 触发器是避免实现复杂视图更新规则的优雅方案。
