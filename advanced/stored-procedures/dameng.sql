-- DamengDB (达梦): 存储过程和函数（DMSQL/PL/SQL）
-- Oracle compatible PL/SQL syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- 创建存储过程
CREATE OR REPLACE PROCEDURE get_user(p_username IN VARCHAR)
AS
    v_email VARCHAR(255);
    v_age   INT;
BEGIN
    SELECT email, age INTO v_email, v_age
    FROM users WHERE username = p_username;

    DBMS_OUTPUT.PUT_LINE('Email: ' || v_email || ', Age: ' || v_age);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('User not found');
END;
/

-- 调用
CALL get_user('alice');
-- 或
BEGIN get_user('alice'); END;
/

-- OUT 参数
CREATE OR REPLACE PROCEDURE get_user_count(p_count OUT INT)
AS
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END;
/

DECLARE v_cnt INT;
BEGIN
    get_user_count(v_cnt);
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_cnt);
END;
/

-- 带事务控制
CREATE OR REPLACE PROCEDURE transfer(
    p_from IN INT, p_to IN INT, p_amount IN DECIMAL
)
AS
    v_balance DECIMAL(10,2);
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE_APPLICATION_ERROR(-20001, 'Insufficient balance');
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    COMMIT;
END;
/

-- 函数
CREATE OR REPLACE FUNCTION full_name(
    p_first IN VARCHAR, p_last IN VARCHAR
)
RETURN VARCHAR
DETERMINISTIC
AS
BEGIN
    RETURN p_first || ' ' || p_last;
END;
/

SELECT full_name('Alice', 'Smith') FROM DUAL;

-- 游标
CREATE OR REPLACE PROCEDURE process_users
AS
    CURSOR cur IS SELECT username, age FROM users;
    v_rec cur%ROWTYPE;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO v_rec;
        EXIT WHEN cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_rec.username || ': ' || v_rec.age);
    END LOOP;
    CLOSE cur;
END;
/

-- 隐式游标
CREATE OR REPLACE PROCEDURE process_users_v2
AS
BEGIN
    FOR rec IN (SELECT username, age FROM users) LOOP
        DBMS_OUTPUT.PUT_LINE(rec.username || ': ' || rec.age);
    END LOOP;
END;
/

-- 包（Package）
CREATE OR REPLACE PACKAGE user_pkg AS
    PROCEDURE create_user(p_name VARCHAR, p_email VARCHAR);
    FUNCTION get_count RETURN INT;
END user_pkg;
/

CREATE OR REPLACE PACKAGE BODY user_pkg AS
    PROCEDURE create_user(p_name VARCHAR, p_email VARCHAR) AS
    BEGIN
        INSERT INTO users (username, email) VALUES (p_name, p_email);
    END;

    FUNCTION get_count RETURN INT AS
        v_cnt INT;
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM users;
        RETURN v_cnt;
    END;
END user_pkg;
/

-- 调用包
CALL user_pkg.create_user('alice', 'alice@example.com');
SELECT user_pkg.get_count() FROM DUAL;

-- 删除
DROP PROCEDURE get_user;
DROP FUNCTION full_name;
DROP PACKAGE user_pkg;

-- 注意事项：
-- PL/SQL 语法与 Oracle 高度兼容
-- 支持包（Package）、游标、异常处理
-- 支持 DBMS_OUTPUT、RAISE_APPLICATION_ERROR 等 Oracle 包
-- 支持自治事务（PRAGMA AUTONOMOUS_TRANSACTION）
-- 支持隐式游标的 FOR 循环
