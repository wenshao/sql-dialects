-- BigQuery: 存储过程和函数
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Scripting
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/scripting
--   [2] BigQuery SQL Reference - CREATE PROCEDURE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_procedure

-- BigQuery 支持存储过程（Procedure）和用户定义函数（UDF）
-- 使用脚本（Scripting）语法编写过程逻辑

-- ============================================================
-- 用户定义函数（UDF）
-- ============================================================

-- SQL UDF
CREATE OR REPLACE FUNCTION mydataset.full_name(first STRING, last STRING)
RETURNS STRING
AS (CONCAT(first, ' ', last));

SELECT mydataset.full_name('Alice', 'Smith');

-- 带表名限定
CREATE OR REPLACE FUNCTION myproject.mydataset.add_tax(price NUMERIC)
RETURNS NUMERIC
AS (price * 1.1);

-- 临时 UDF（仅在当前查询中有效）
CREATE TEMP FUNCTION add_tax(price NUMERIC) RETURNS NUMERIC AS (price * 1.1);
SELECT add_tax(100);

-- ============================================================
-- JavaScript UDF
-- ============================================================

CREATE OR REPLACE FUNCTION mydataset.parse_json_field(json_str STRING, field STRING)
RETURNS STRING
LANGUAGE js AS r"""
    try {
        var obj = JSON.parse(json_str);
        return obj[field] || null;
    } catch(e) {
        return null;
    }
""";

-- ============================================================
-- 表值函数（TVF，Table-Valued Function）
-- ============================================================

CREATE OR REPLACE TABLE FUNCTION mydataset.users_by_country(country_filter STRING)
AS (
    SELECT id, username, email
    FROM users
    WHERE country = country_filter
);

SELECT * FROM mydataset.users_by_country('US');

-- ============================================================
-- 过程（Procedure，使用脚本语法）
-- ============================================================

CREATE OR REPLACE PROCEDURE mydataset.transfer(
    from_id INT64, to_id INT64, amount NUMERIC
)
BEGIN
    DECLARE balance NUMERIC;

    SELECT bal INTO balance FROM accounts WHERE id = from_id;

    IF balance < amount THEN
        RAISE USING MESSAGE = 'Insufficient balance';
    END IF;

    UPDATE accounts SET bal = bal - amount WHERE id = from_id;
    UPDATE accounts SET bal = bal + amount WHERE id = to_id;
END;

-- 调用过程
CALL mydataset.transfer(1, 2, 100.00);

-- ============================================================
-- 脚本（Scripting）功能
-- ============================================================

-- 变量声明和赋值
DECLARE x INT64 DEFAULT 0;
SET x = 10;

-- 条件
IF x > 5 THEN
    SELECT 'greater';
ELSE
    SELECT 'less or equal';
END IF;

-- 循环
DECLARE i INT64 DEFAULT 0;
WHILE i < 10 DO
    SET i = i + 1;
END WHILE;

-- LOOP + LEAVE
DECLARE j INT64 DEFAULT 0;
LOOP
    SET j = j + 1;
    IF j >= 10 THEN LEAVE; END IF;
END LOOP;

-- FOR ... IN
FOR record IN (SELECT id, username FROM users LIMIT 10) DO
    -- 处理每行
    SELECT record.id, record.username;
END FOR;

-- 异常处理
BEGIN
    -- 可能出错的操作
    INSERT INTO users (id, username) VALUES (1, 'alice');
EXCEPTION WHEN ERROR THEN
    SELECT @@error.message;
END;

-- ============================================================
-- 远程函数（Remote Function，调用 Cloud Functions）
-- ============================================================

CREATE OR REPLACE FUNCTION mydataset.sentiment_analysis(text STRING)
RETURNS FLOAT64
REMOTE WITH CONNECTION `myproject.us.my_connection`
OPTIONS (endpoint = 'https://my-function-url');

-- 删除
DROP FUNCTION IF EXISTS mydataset.full_name;
DROP PROCEDURE IF EXISTS mydataset.transfer;

-- 注意：BigQuery 没有传统的存储过程语言（如 PL/SQL）
-- 注意：过程使用 BigQuery 脚本语法，不是 PL/pgSQL
-- 注意：UDF 可以用 SQL 或 JavaScript 编写
-- 注意：临时 UDF 只在当前查询有效
-- 注意：远程函数可以调用外部 HTTP 端点
