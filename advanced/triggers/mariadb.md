# MariaDB: 触发器

与 MySQL 语法一致, 支持多触发器 (同 MySQL 5.7+)

参考资料:
[1] MariaDB Knowledge Base - Triggers
https://mariadb.com/kb/en/triggers/

## 1. 基本触发器

```sql
DELIMITER //
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.created_at = IFNULL(NEW.created_at, NOW());
    SET NEW.username = LOWER(NEW.username);
END //
DELIMITER ;
```


## 2. AFTER 触发器 (审计日志)

```sql
DELIMITER //
CREATE TRIGGER trg_users_after_update
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, row_id, action, old_value, new_value, changed_at)
    VALUES ('users', NEW.id, 'UPDATE',
            JSON_OBJECT('email', OLD.email, 'age', OLD.age),
            JSON_OBJECT('email', NEW.email, 'age', NEW.age),
            NOW());
END //
DELIMITER ;
```


## 3. 多个同类触发器 (10.2.3+, MySQL 5.7+)

同一事件可以有多个触发器, 用 FOLLOWS/PRECEDES 控制顺序
```sql
CREATE TRIGGER trg_users_audit2
AFTER UPDATE ON users
FOR EACH ROW
FOLLOWS trg_users_after_update
INSERT INTO audit_summary (action, cnt) VALUES ('user_update', 1)
ON DUPLICATE KEY UPDATE cnt = cnt + 1;
```


## 4. 系统版本表与触发器的交互

系统版本表的 UPDATE 会自动生成历史行
如果同时有 AFTER UPDATE 触发器:
触发器在版本化操作之后执行
OLD.* 是更新前的值, NEW.* 是更新后的值
历史行的生成是透明的, 触发器中无需处理

## 5. 对引擎开发者的启示

MySQL/MariaDB 触发器的限制:
1. 只支持行级触发器 (FOR EACH ROW), 不支持语句级
2. 触发器中不能调用返回结果集的存储过程
3. 触发器中不能使用 PREPARE/EXECUTE (动态SQL)
**对比 PostgreSQL: 同时支持行级和语句级触发器, INSTEAD OF 触发器**

**对比 Oracle: 支持复合触发器 (一个触发器包含多个时间点的逻辑)**

触发器对性能的影响: 每行 DML 都会执行触发器逻辑
批量 INSERT 10 万行 = 触发器执行 10 万次 (串行, 无法并行)
