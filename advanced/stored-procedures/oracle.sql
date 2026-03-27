-- Oracle: 存储过程和函数（PL/SQL）
--
-- 参考资料:
--   [1] Oracle PL/SQL Language Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/
--   [2] Oracle SQL Language Reference - CREATE PROCEDURE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-PROCEDURE.html

-- 创建存储过程
CREATE OR REPLACE PROCEDURE get_user(p_username IN VARCHAR2)
AS
    v_email VARCHAR2(255);
    v_age   NUMBER;
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
EXEC get_user('alice');
-- 或
BEGIN get_user('alice'); END;
/

-- OUT 参数
CREATE OR REPLACE PROCEDURE get_user_count(p_count OUT NUMBER)
AS
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END;
/

DECLARE v_cnt NUMBER;
BEGIN
    get_user_count(v_cnt);
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_cnt);
END;
/

-- 带事务控制
CREATE OR REPLACE PROCEDURE transfer(
    p_from IN NUMBER, p_to IN NUMBER, p_amount IN NUMBER
)
AS
    v_balance NUMBER;
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
    p_first IN VARCHAR2, p_last IN VARCHAR2
)
RETURN VARCHAR2
DETERMINISTIC
AS
BEGIN
    RETURN p_first || ' ' || p_last;
END;
/

SELECT full_name('Alice', 'Smith') FROM dual;

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
        -- 处理 v_rec.username, v_rec.age
    END LOOP;
    CLOSE cur;
END;
/

-- 隐式游标（FOR 循环，更简洁）
CREATE OR REPLACE PROCEDURE process_users_v2
AS
BEGIN
    FOR rec IN (SELECT username, age FROM users) LOOP
        DBMS_OUTPUT.PUT_LINE(rec.username || ': ' || rec.age);
    END LOOP;
END;
/

-- 包（Package，组织相关的过程和函数）
CREATE OR REPLACE PACKAGE user_pkg AS
    PROCEDURE create_user(p_name VARCHAR2, p_email VARCHAR2);
    FUNCTION get_count RETURN NUMBER;
END user_pkg;
/

CREATE OR REPLACE PACKAGE BODY user_pkg AS
    PROCEDURE create_user(p_name VARCHAR2, p_email VARCHAR2) AS
    BEGIN
        INSERT INTO users (username, email) VALUES (p_name, p_email);
    END;

    FUNCTION get_count RETURN NUMBER AS
        v_cnt NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM users;
        RETURN v_cnt;
    END;
END user_pkg;
/

-- 调用包中的过程
EXEC user_pkg.create_user('alice', 'alice@example.com');
SELECT user_pkg.get_count() FROM dual;

-- 删除
DROP PROCEDURE get_user;
DROP FUNCTION full_name;
DROP PACKAGE user_pkg;
