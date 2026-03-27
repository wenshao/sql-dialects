-- Snowflake: 存储过程和函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE PROCEDURE
--       https://docs.snowflake.com/en/sql-reference/sql/create-procedure
--   [2] Snowflake SQL Reference - CREATE FUNCTION
--       https://docs.snowflake.com/en/sql-reference/sql/create-function

-- Snowflake 支持多种语言编写存储过程和函数

-- ============================================================
-- SQL 存储过程（Snowflake Scripting，2021+）
-- ============================================================

CREATE OR REPLACE PROCEDURE transfer(
    p_from NUMBER, p_to NUMBER, p_amount NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_balance NUMBER;
BEGIN
    SELECT balance INTO :v_balance FROM accounts WHERE id = :p_from;

    IF (v_balance < p_amount) THEN
        RETURN 'Insufficient balance';
    END IF;

    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;

    RETURN 'Success';
END;
$$;

CALL transfer(1, 2, 100.00);

-- ============================================================
-- JavaScript 存储过程
-- ============================================================

CREATE OR REPLACE PROCEDURE process_data(table_name VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var sql_command = `SELECT COUNT(*) AS cnt FROM ${TABLE_NAME}`;
    var stmt = snowflake.createStatement({sqlText: sql_command});
    var result = stmt.execute();
    result.next();
    return 'Row count: ' + result.getColumnValue(1);
$$;

CALL process_data('users');

-- ============================================================
-- Python 存储过程（Snowpark）
-- ============================================================

CREATE OR REPLACE PROCEDURE filter_users(min_age INT)
RETURNS TABLE(id NUMBER, username VARCHAR, age NUMBER)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, min_age):
    return session.table('users').filter(col('age') >= min_age)
$$;

CALL filter_users(18);

-- ============================================================
-- SQL 用户定义函数（UDF）
-- ============================================================

CREATE OR REPLACE FUNCTION full_name(first VARCHAR, last VARCHAR)
RETURNS VARCHAR
AS $$
    SELECT first || ' ' || last
$$;

SELECT full_name('Alice', 'Smith');

-- ============================================================
-- JavaScript UDF
-- ============================================================

CREATE OR REPLACE FUNCTION parse_json_field(json_str VARCHAR, field VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS $$
    try {
        var obj = JSON.parse(JSON_STR);
        return obj[FIELD] || null;
    } catch(e) {
        return null;
    }
$$;

-- ============================================================
-- Python UDF
-- ============================================================

CREATE OR REPLACE FUNCTION sentiment(text VARCHAR)
RETURNS FLOAT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
HANDLER = 'analyze'
AS $$
def analyze(text):
    # 简单的情感分析示例
    positive = ['good', 'great', 'excellent']
    return sum(1 for w in text.lower().split() if w in positive) / max(len(text.split()), 1)
$$;

-- ============================================================
-- 表函数（UDTF）
-- ============================================================

CREATE OR REPLACE FUNCTION split_to_rows(input VARCHAR, delimiter VARCHAR)
RETURNS TABLE(value VARCHAR)
LANGUAGE SQL
AS $$
    SELECT value FROM TABLE(SPLIT_TO_TABLE(input, delimiter))
$$;

SELECT * FROM TABLE(split_to_rows('a,b,c', ','));

-- ============================================================
-- 权限和安全
-- ============================================================

-- EXECUTE AS CALLER: 使用调用者的权限（默认）
-- EXECUTE AS OWNER: 使用过程所有者的权限
CREATE OR REPLACE PROCEDURE admin_proc()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS $$ BEGIN RETURN 'admin action'; END; $$;

-- ============================================================
-- Snowflake Scripting 控制流
-- ============================================================

-- 变量、IF/ELSE、LOOP、FOR、WHILE、CURSOR 等
-- 类似 PL/SQL 语法

-- 异常处理
CREATE OR REPLACE PROCEDURE safe_proc()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- 可能出错的操作
    INSERT INTO users (id, username) VALUES (1, 'alice');
    RETURN 'Success';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$;

-- 删除
DROP PROCEDURE IF EXISTS transfer(NUMBER, NUMBER, NUMBER);
DROP FUNCTION IF EXISTS full_name(VARCHAR, VARCHAR);

-- 注意：支持 SQL、JavaScript、Python、Java、Scala 多种语言
-- 注意：Snowflake Scripting 是 2021 年新增的 SQL 过程语言
-- 注意：Python UDF/过程需要 Anaconda 包支持
-- 注意：EXECUTE AS OWNER 可以实现权限提升
