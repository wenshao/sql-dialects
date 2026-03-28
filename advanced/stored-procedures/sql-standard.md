# SQL 标准: 存储过程和函数

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [SQL Standard Features Comparison (jOOQ)](https://www.jooq.org/diff)

## SQL-86 / SQL-89: 没有过程式功能

早期标准只有声明式 SQL，没有过程式语言

## SQL-92 (SQL2): 没有过程式功能

仍然只有声明式 SQL

## SQL:1999 (SQL3): 首次引入过程式功能（SQL/PSM）

SQL/PSM = SQL / Persistent Stored Modules
新增 CREATE PROCEDURE, CREATE FUNCTION
新增 DECLARE, SET, IF/ELSE, WHILE, LOOP, FOR
新增 SIGNAL / RESIGNAL（异常）
新增 CALL 语句

创建函数
```sql
CREATE FUNCTION full_name(first VARCHAR(50), last VARCHAR(50))
RETURNS VARCHAR(101)
DETERMINISTIC
CONTAINS SQL
RETURN first || ' ' || last;
```

调用函数
```sql
SELECT full_name('Alice', 'Smith');
```

创建过程
```sql
CREATE PROCEDURE transfer(
    IN p_from BIGINT, IN p_to BIGINT, IN p_amount DECIMAL(10,2)
)
MODIFIES SQL DATA
BEGIN
    DECLARE v_balance DECIMAL(10,2);
```

```sql
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from;
```

```sql
    IF v_balance < p_amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
    END IF;
```

```sql
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
END;
```

调用过程
```sql
CALL transfer(1, 2, 100.00);
```

## SQL:1999 控制流

IF / ELSE IF / ELSE
```sql
CREATE PROCEDURE categorize_age(IN p_age INTEGER, OUT p_category VARCHAR(20))
BEGIN
    IF p_age < 18 THEN
        SET p_category = 'minor';
    ELSEIF p_age < 65 THEN
        SET p_category = 'adult';
    ELSE
        SET p_category = 'senior';
    END IF;
END;
```

WHILE
```sql
CREATE PROCEDURE count_to(IN p_n INTEGER)
BEGIN
    DECLARE i INTEGER DEFAULT 0;
    WHILE i < p_n DO
        SET i = i + 1;
    END WHILE;
END;
```

LOOP + LEAVE
```sql
CREATE PROCEDURE loop_example()
BEGIN
    DECLARE i INTEGER DEFAULT 0;
    main_loop: LOOP
        SET i = i + 1;
        IF i >= 10 THEN
            LEAVE main_loop;
        END IF;
    END LOOP;
END;
```

FOR（游标循环）
```sql
CREATE PROCEDURE process_users()
BEGIN
    FOR row AS SELECT id, username FROM users DO
```

处理每行
```sql
    END FOR;
END;
```

CASE
```sql
CREATE FUNCTION status_text(s INTEGER) RETURNS VARCHAR(20)
DETERMINISTIC
RETURN CASE s WHEN 0 THEN 'inactive' WHEN 1 THEN 'active' ELSE 'unknown' END;
```

## SQL:1999 异常处理

```sql
CREATE PROCEDURE safe_insert()
BEGIN
    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
    BEGIN
```

处理唯一约束冲突
```sql
    END;
```

```sql
    INSERT INTO users (id, username) VALUES (1, 'alice');
END;
```

SIGNAL（主动抛出异常）
```sql
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Custom error';
```

RESIGNAL（在 HANDLER 中重新抛出异常）

## SQL:2003: 增强

函数特性声明更完善
DETERMINISTIC / NOT DETERMINISTIC
CONTAINS SQL / READS SQL DATA / MODIFIES SQL DATA / NO SQL

```sql
CREATE FUNCTION get_count()
RETURNS BIGINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count BIGINT;
    SELECT COUNT(*) INTO v_count FROM users;
    RETURN v_count;
END;
```

## SQL:2023: 最新增强

增强了过程式语言能力

## 各数据库实现对比

MySQL: DELIMITER 包裹，BEGIN...END，SIGNAL
PostgreSQL: $$ 分隔符，PL/pgSQL，RAISE EXCEPTION
Oracle: PL/SQL（独立标准，早于 SQL/PSM）
SQL Server: T-SQL（独立标准）
SQLite: 不支持存储过程

- **注意：SQL/PSM 标准定义了过程式语言，但各数据库实现差异很大**
- **注意：Oracle 的 PL/SQL 和 SQL Server 的 T-SQL 早于标准且不兼容**
- **注意：MySQL 最接近 SQL/PSM 标准**
- **注意：分析型数据库（BigQuery、ClickHouse 等）通常不支持存储过程**
