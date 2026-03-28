# OceanBase: 存储过程

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


Basic stored procedure
```sql
DELIMITER //
CREATE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;

```

Call
```sql
CALL get_user('alice');

```

OUT parameter
```sql
DELIMITER //
CREATE PROCEDURE get_user_count(OUT p_count INT)
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END //
DELIMITER ;

CALL get_user_count(@cnt);
SELECT @cnt;

```

Variables and flow control
```sql
DELIMITER //
CREATE PROCEDURE transfer(
    IN p_from BIGINT, IN p_to BIGINT, IN p_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_balance DECIMAL(10,2);
    START TRANSACTION;
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;
    IF v_balance < p_amount THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
    END IF;
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
    COMMIT;
END //
DELIMITER ;

```

Cursor
```sql
DELIMITER //
CREATE PROCEDURE process_users()
BEGIN
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_username VARCHAR(64);
    DECLARE cur CURSOR FOR SELECT username FROM users;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_username;
        IF v_done THEN LEAVE read_loop; END IF;
```

process each row
```sql
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;

```

Function
```sql
DELIMITER //
CREATE FUNCTION full_name(first VARCHAR(50), last VARCHAR(50))
RETURNS VARCHAR(101)
DETERMINISTIC
BEGIN
    RETURN CONCAT(first, ' ', last);
END //
DELIMITER ;

```

Drop
```sql
DROP PROCEDURE IF EXISTS get_user;
DROP FUNCTION IF EXISTS full_name;

```

## Oracle Mode (PL/SQL support)


Basic procedure (PL/SQL syntax)
```sql
CREATE OR REPLACE PROCEDURE get_user(p_username IN VARCHAR2)
IS
BEGIN
```

Note: Oracle mode procedures use SELECT INTO or cursors for output
```sql
    DBMS_OUTPUT.PUT_LINE('Getting user: ' || p_username);
END;
/

```

Call (Oracle syntax)
```sql
CALL get_user('alice');
```

Or: EXEC get_user('alice');

OUT parameter
```sql
CREATE OR REPLACE PROCEDURE get_user_count(p_count OUT NUMBER)
IS
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END;
/

```

IN OUT parameter
```sql
CREATE OR REPLACE PROCEDURE increment(p_val IN OUT NUMBER, p_step IN NUMBER)
IS
BEGIN
    p_val := p_val + p_step;
END;
/

```

Variables and flow control (PL/SQL)
```sql
CREATE OR REPLACE PROCEDURE transfer(
    p_from IN NUMBER, p_to IN NUMBER, p_amount IN NUMBER
)
IS
    v_balance NUMBER;
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;
    IF v_balance < p_amount THEN
        RAISE_APPLICATION_ERROR(-20001, 'Insufficient balance');
    END IF;
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

```

FOR loop (PL/SQL)
```sql
CREATE OR REPLACE PROCEDURE process_users
IS
BEGIN
    FOR rec IN (SELECT username, age FROM users) LOOP
        IF rec.age >= 18 THEN
            DBMS_OUTPUT.PUT_LINE('Adult: ' || rec.username);
        END IF;
    END LOOP;
END;
/

```

Cursor (explicit, PL/SQL)
```sql
CREATE OR REPLACE PROCEDURE process_with_cursor
IS
    CURSOR cur_users IS SELECT username, age FROM users;
    v_username VARCHAR2(64);
    v_age NUMBER;
BEGIN
    OPEN cur_users;
    LOOP
        FETCH cur_users INTO v_username, v_age;
        EXIT WHEN cur_users%NOTFOUND;
```

process each row
```sql
    END LOOP;
    CLOSE cur_users;
END;
/

```

Package (Oracle mode, grouping related procedures/functions)
```sql
CREATE OR REPLACE PACKAGE user_pkg AS
    PROCEDURE get_user(p_id IN NUMBER);
    FUNCTION get_count RETURN NUMBER;
END;
/

CREATE OR REPLACE PACKAGE BODY user_pkg AS
    PROCEDURE get_user(p_id IN NUMBER) IS
        v_name VARCHAR2(64);
    BEGIN
        SELECT username INTO v_name FROM users WHERE id = p_id;
        DBMS_OUTPUT.PUT_LINE(v_name);
    END;

    FUNCTION get_count RETURN NUMBER IS
        v_cnt NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM users;
        RETURN v_cnt;
    END;
END;
/

```

Function (Oracle mode)
```sql
CREATE OR REPLACE FUNCTION full_name(first VARCHAR2, last VARCHAR2)
RETURN VARCHAR2
IS
BEGIN
    RETURN first || ' ' || last;
END;
/

```

Drop (Oracle syntax)
```sql
DROP PROCEDURE get_user;
DROP FUNCTION full_name;
DROP PACKAGE user_pkg;

```

Limitations:
MySQL mode: full stored procedure support (same as MySQL)
Oracle mode: PL/SQL support including packages, cursors, exceptions
Oracle mode: DBMS_OUTPUT, RAISE_APPLICATION_ERROR supported
Oracle mode: anonymous PL/SQL blocks supported (BEGIN ... END)
Some advanced PL/SQL features may have limited support
