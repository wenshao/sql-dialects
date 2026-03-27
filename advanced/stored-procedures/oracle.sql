-- Oracle: 存储过程和函数（PL/SQL）
--
-- 参考资料:
--   [1] Oracle PL/SQL Language Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/
--   [2] Oracle SQL Language Reference - CREATE PROCEDURE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-PROCEDURE.html

-- ============================================================
-- 1. 基本存储过程
-- ============================================================

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

-- 调用方式
EXEC get_user('alice');
BEGIN get_user('alice'); END;
/

-- ============================================================
-- 2. OUT 参数和函数
-- ============================================================

CREATE OR REPLACE PROCEDURE get_user_count(p_count OUT NUMBER) AS
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END;
/

CREATE OR REPLACE FUNCTION full_name(
    p_first IN VARCHAR2, p_last IN VARCHAR2
) RETURN VARCHAR2
DETERMINISTIC                                  -- 标记为确定性（相同输入相同输出）
AS
BEGIN
    RETURN p_first || ' ' || p_last;
END;
/

SELECT full_name('Alice', 'Smith') FROM DUAL;

-- DETERMINISTIC 的意义:
--   允许优化器缓存函数结果，物化视图中使用函数索引。
--   类似 PostgreSQL 的 IMMUTABLE 标记。

-- ============================================================
-- 3. 包（Package，Oracle PL/SQL 的核心架构模式）
-- ============================================================

-- 包规范（接口声明）
CREATE OR REPLACE PACKAGE user_pkg AS
    PROCEDURE create_user(p_name VARCHAR2, p_email VARCHAR2);
    FUNCTION get_count RETURN NUMBER;
    g_default_status CONSTANT NUMBER := 1;     -- 包级常量
END user_pkg;
/

-- 包体（实现）
CREATE OR REPLACE PACKAGE BODY user_pkg AS
    -- 私有变量（包内可见，外部不可访问）
    v_cache_count NUMBER;

    PROCEDURE create_user(p_name VARCHAR2, p_email VARCHAR2) AS
    BEGIN
        INSERT INTO users (username, email) VALUES (p_name, p_email);
        v_cache_count := NULL;                 -- 失效缓存
    END;

    FUNCTION get_count RETURN NUMBER AS
    BEGIN
        IF v_cache_count IS NULL THEN
            SELECT COUNT(*) INTO v_cache_count FROM users;
        END IF;
        RETURN v_cache_count;
    END;
END user_pkg;
/

-- 使用
EXEC user_pkg.create_user('alice', 'alice@example.com');
SELECT user_pkg.get_count() FROM DUAL;

-- 设计分析: 包的价值
--   1. 封装: 公有接口（规范）和私有实现（包体）分离
--   2. 状态: 包级变量在会话内持久化（类似单例模式）
--   3. 重载: 同名过程/函数可以有不同参数签名
--   4. 依赖管理: 修改包体不影响依赖包规范的对象
--
-- 横向对比:
--   Oracle:     PACKAGE（最强大的过程化编程组织方式）
--   PostgreSQL: 无 PACKAGE（用 SCHEMA + 函数名前缀替代）
--   MySQL:      无 PACKAGE
--   SQL Server: 无 PACKAGE（用 SCHEMA 组织）
--
-- 对引擎开发者的启示:
--   PACKAGE 是 Oracle 的杀手级特性之一，但其他数据库选择不实现。
--   替代方案: SCHEMA 命名空间 + 模块化函数 可以达到类似的组织效果。

-- ============================================================
-- 4. BULK COLLECT + FORALL（Oracle PL/SQL 性能核心）
-- ============================================================

-- BULK COLLECT: 批量获取（减少 PL/SQL ↔ SQL 引擎上下文切换）
DECLARE
    TYPE user_tab IS TABLE OF users%ROWTYPE;
    v_users user_tab;
BEGIN
    SELECT * BULK COLLECT INTO v_users FROM users WHERE status = 1;
    -- LIMIT 子句控制批量大小:
    -- SELECT * BULK COLLECT INTO v_users FROM users WHERE status = 1 LIMIT 1000;
    FOR i IN 1..v_users.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(v_users(i).username);
    END LOOP;
END;
/

-- FORALL: 批量 DML（比循环逐行快 10-50 倍）
DECLARE
    TYPE id_array IS TABLE OF NUMBER;
    v_ids id_array := id_array(1, 2, 3, 4, 5);
BEGIN
    FORALL i IN 1..v_ids.COUNT
        UPDATE users SET status = 0 WHERE id = v_ids(i);
    COMMIT;
END;
/

-- 设计分析:
--   PL/SQL 和 SQL 引擎是独立的执行环境，每次交互有上下文切换开销。
--   BULK COLLECT 和 FORALL 批量化这种交互，是 Oracle 性能优化的核心。
--   这是 Oracle 独有的设计问题（其他数据库的过程语言与 SQL 引擎集成更紧密）。

-- ============================================================
-- 5. 游标（显式 vs 隐式）
-- ============================================================

-- 显式游标
CREATE OR REPLACE PROCEDURE process_users AS
    CURSOR cur IS SELECT username, age FROM users;
    v_rec cur%ROWTYPE;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO v_rec;
        EXIT WHEN cur%NOTFOUND;
        NULL; -- 处理
    END LOOP;
    CLOSE cur;
END;
/

-- 隐式游标（FOR 循环，推荐，更简洁安全）
CREATE OR REPLACE PROCEDURE process_users_v2 AS
BEGIN
    FOR rec IN (SELECT username, age FROM users) LOOP
        DBMS_OUTPUT.PUT_LINE(rec.username || ': ' || rec.age);
    END LOOP;
END;
/

-- ============================================================
-- 6. 自治事务（Autonomous Transaction，Oracle 独有）
-- ============================================================

CREATE OR REPLACE PROCEDURE log_error(p_msg VARCHAR2) AS
    PRAGMA AUTONOMOUS_TRANSACTION;             -- 独立事务!
BEGIN
    INSERT INTO error_log (message, created_at) VALUES (p_msg, SYSTIMESTAMP);
    COMMIT;                                    -- 不影响调用者的事务
END;
/

-- 自治事务允许在过程中开启独立事务（不受调用者事务影响）
-- 典型场景: 错误日志记录（即使主事务回滚，日志也要保留）
-- 其他数据库没有等价功能（PostgreSQL 用 dblink 模拟）

-- ============================================================
-- 7. 删除
-- ============================================================

DROP PROCEDURE get_user;
DROP FUNCTION full_name;
DROP PACKAGE user_pkg;

-- ============================================================
-- 8. 对引擎开发者的总结
-- ============================================================
-- 1. PL/SQL 是最成熟的数据库过程语言，PACKAGE 是其核心组织模式。
-- 2. BULK COLLECT + FORALL 是 Oracle 性能优化的关键（批量化上下文切换）。
-- 3. 自治事务（AUTONOMOUS_TRANSACTION）是 Oracle 独有的事务控制能力。
-- 4. DETERMINISTIC 标记让优化器可以缓存函数结果，值得支持。
-- 5. 隐式游标（FOR loop）比显式游标更安全简洁，应作为推荐模式。
