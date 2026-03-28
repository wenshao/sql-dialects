# Firebird: Views

> 参考资料:
> - [Firebird Documentation - CREATE VIEW](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-ddl-view)
> - [Firebird Documentation - Views](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-ddl-view-create)
> - ============================================
> - 基本视图
> - ============================================

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## CREATE OR ALTER VIEW（创建或修改，Firebird 2.5+）

```sql
CREATE OR ALTER VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## RECREATE VIEW（删除并重新创建）

```sql
RECREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 可更新视图 + WITH CHECK OPTION

Firebird 支持可更新的单表视图

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;
```

## 通过视图进行 DML 操作

```sql
INSERT INTO adult_users (id, username, email, age) VALUES (1, 'alice', 'a@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;
```

## 使用触发器使复杂视图可更新

```sql
CREATE VIEW order_detail AS
SELECT o.id, o.amount, u.username
FROM orders o JOIN users u ON o.user_id = u.id;

CREATE TRIGGER trg_order_detail_insert FOR order_detail
ACTIVE BEFORE INSERT POSITION 0
AS
BEGIN
    INSERT INTO orders (id, amount) VALUES (NEW.id, NEW.amount);
END;
```

## 物化视图

Firebird 不支持物化视图

## 替代方案：使用表 + 触发器 或 存储过程维护

或使用 EXECUTE BLOCK 定期刷新汇总表

## 删除视图

```sql
DROP VIEW active_users;
```

限制：
不支持 CREATE OR REPLACE VIEW（使用 CREATE OR ALTER VIEW）
不支持物化视图
不支持 IF NOT EXISTS
可更新视图限于简单单表查询
可以通过视图触发器使复杂视图可更新
