-- Snowflake: 存储过程与用户定义函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE PROCEDURE
--       https://docs.snowflake.com/en/sql-reference/sql/create-procedure
--   [2] Snowflake SQL Reference - CREATE FUNCTION
--       https://docs.snowflake.com/en/sql-reference/sql/create-function

-- ============================================================
-- 1. SQL 存储过程 (Snowflake Scripting, 2021+)
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
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 多语言存储过程: Snowflake 的独特设计
-- Snowflake 支持 5 种语言编写存储过程:
--   SQL (Snowflake Scripting, 2021+)
--   JavaScript (最早支持, 2018+)
--   Python (Snowpark, 2022+)
--   Java (2022+)
--   Scala (2022+)
--
-- 设计 trade-off:
--   优点: 开发者可以用熟悉的语言编写过程逻辑
--         Python UDF 可以调用 ML 库（scikit-learn、pandas 等）
--   缺点: 每种语言需要独立的运行时环境（增加引擎复杂度）
--         跨语言调试困难
--         不同语言的性能差异大（SQL > JavaScript > Python）
--
-- 对比:
--   Oracle:      PL/SQL + Java（两种）
--   PostgreSQL:  PL/pgSQL + PL/Python + PL/Perl + PL/Tcl + ...（最灵活）
--   SQL Server:  T-SQL + CLR（.NET 语言）
--   MySQL:       SQL 存储过程（仅一种）
--   BigQuery:    SQL + JavaScript（两种）
--   Databricks:  Python/Scala/Java（通过 Spark UDF）
--
-- 对引擎开发者的启示:
--   多语言支持的实现代价很高（每种语言需要沙箱运行时、权限隔离、资源限制）。
--   推荐路径: 先实现 SQL 过程语言 → 再扩展到 Python/JavaScript。
--   SQL 过程语言的性能最好（引擎内部直接解释执行，无序列化开销）。

-- 2.2 Snowflake Scripting 的语法特点
-- 变量引用使用 :variable（冒号前缀），区别于 SQL 列名
-- 这与 Oracle PL/SQL 的设计一致
-- 对比 PostgreSQL PL/pgSQL: 变量名直接使用，与列名冲突时需要限定前缀

-- ============================================================
-- 3. JavaScript 存储过程
-- ============================================================

CREATE OR REPLACE PROCEDURE process_data(table_name VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var sql = `SELECT COUNT(*) AS cnt FROM ${TABLE_NAME}`;
    var stmt = snowflake.createStatement({sqlText: sql});
    var result = stmt.execute();
    result.next();
    return 'Row count: ' + result.getColumnValue(1);
$$;

-- JavaScript API: snowflake.createStatement() + execute() + getColumnValue()
-- 参数名自动大写（TABLE_NAME，即使定义时是小写 table_name）

-- ============================================================
-- 4. Python 存储过程 (Snowpark)
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

-- Python 过程运行在 Snowflake 管理的沙箱容器中
-- 可以使用 Anaconda 包（pandas, scikit-learn, xgboost 等）
-- 适合 ML 推理、复杂数据转换等场景

-- ============================================================
-- 5. SQL 用户定义函数 (UDF)
-- ============================================================

CREATE OR REPLACE FUNCTION full_name(first VARCHAR, last VARCHAR)
RETURNS VARCHAR
AS $$
    SELECT first || ' ' || last
$$;

SELECT full_name('Alice', 'Smith');

-- ============================================================
-- 6. JavaScript UDF
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
-- 7. Python UDF
-- ============================================================

CREATE OR REPLACE FUNCTION sentiment(text VARCHAR)
RETURNS FLOAT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
HANDLER = 'analyze'
AS $$
def analyze(text):
    positive = ['good', 'great', 'excellent']
    return sum(1 for w in text.lower().split() if w in positive) / max(len(text.split()), 1)
$$;

-- ============================================================
-- 8. 表函数 (UDTF)
-- ============================================================

CREATE OR REPLACE FUNCTION split_to_rows(input VARCHAR, delimiter VARCHAR)
RETURNS TABLE(value VARCHAR)
LANGUAGE SQL
AS $$
    SELECT value FROM TABLE(SPLIT_TO_TABLE(input, delimiter))
$$;

SELECT * FROM TABLE(split_to_rows('a,b,c', ','));

-- ============================================================
-- 9. 权限与安全模型
-- ============================================================

-- EXECUTE AS CALLER: 使用调用者权限（默认 SQL 过程）
-- EXECUTE AS OWNER: 使用过程所有者权限（权限提升）
CREATE OR REPLACE PROCEDURE admin_proc()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS $$ BEGIN RETURN 'admin action'; END; $$;

-- 对比:
--   Oracle:     AUTHID CURRENT_USER / AUTHID DEFINER
--   PostgreSQL: SECURITY INVOKER / SECURITY DEFINER
--   SQL Server: EXECUTE AS CALLER / EXECUTE AS OWNER / EXECUTE AS 'user'

-- ============================================================
-- 10. 异常处理
-- ============================================================

CREATE OR REPLACE PROCEDURE safe_proc()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO users (id, username) VALUES (1, 'alice');
    RETURN 'Success';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$;

-- ============================================================
-- 11. 管理
-- ============================================================

DROP PROCEDURE IF EXISTS transfer(NUMBER, NUMBER, NUMBER);
DROP FUNCTION IF EXISTS full_name(VARCHAR, VARCHAR);
SHOW PROCEDURES IN SCHEMA PUBLIC;
SHOW USER FUNCTIONS IN SCHEMA PUBLIC;
DESCRIBE PROCEDURE transfer(NUMBER, NUMBER, NUMBER);

-- ============================================================
-- 横向对比: 存储过程能力矩阵
-- ============================================================
-- 能力             | Snowflake       | Oracle PL/SQL | PostgreSQL | SQL Server
-- 过程语言         | SQL/JS/Py/Java  | PL/SQL+Java   | PL/pgSQL+  | T-SQL+CLR
-- 包(Package)      | 不支持          | 支持(核心)    | 不支持     | 不支持
-- 游标             | SQL Scripting   | 强大          | 强大       | 强大
-- 异常处理         | EXCEPTION WHEN  | 最完善        | 完善       | TRY..CATCH
-- 调试器           | 无原生          | 完善          | pgAdmin    | SSMS
-- 嵌套事务         | 不支持          | SAVEPOINT     | SAVEPOINT  | SAVE TRAN
-- ML/AI 集成       | Python UDF      | 无            | PL/Python  | R/Python
--
-- 对引擎开发者的启示:
--   Snowflake 的存储过程功能远不及 Oracle PL/SQL（无包、调试有限、游标能力弱）。
--   但多语言支持（特别是 Python）使其在 ML/数据工程场景有独特优势。
--   设计权衡: Oracle 选择深耕一种语言（PL/SQL），Snowflake 选择广度（多语言）。
