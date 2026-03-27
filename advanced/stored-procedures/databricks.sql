-- Databricks SQL: 存储过程和函数
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- Databricks 没有传统存储过程
-- 使用以下替代方案：SQL UDF、Python UDF、Notebooks、Delta Live Tables

-- ============================================================
-- SQL UDF（用户自定义函数，Databricks 2023+）
-- ============================================================

-- 标量 SQL UDF
CREATE OR REPLACE FUNCTION full_name(first STRING, last STRING)
RETURNS STRING
RETURN CONCAT(first, ' ', last);

SELECT full_name('Alice', 'Smith');          -- 'Alice Smith'

-- 带条件的 SQL UDF
CREATE OR REPLACE FUNCTION age_category(age INT)
RETURNS STRING
RETURN CASE
    WHEN age < 18 THEN 'minor'
    WHEN age < 65 THEN 'adult'
    ELSE 'senior'
END;

SELECT username, age_category(age) FROM users;

-- 表值 SQL UDF（返回表）
CREATE OR REPLACE FUNCTION active_users_in_city(p_city STRING)
RETURNS TABLE (id BIGINT, username STRING, email STRING, age INT)
RETURN SELECT id, username, email, age FROM users WHERE status = 1 AND city = p_city;

SELECT * FROM active_users_in_city('Shanghai');

-- ============================================================
-- Python UDF（在 SQL 中使用 Python）
-- ============================================================

-- Python 标量 UDF
CREATE OR REPLACE FUNCTION normalize_email(email STRING)
RETURNS STRING
LANGUAGE PYTHON
AS $$
def normalize_email(email):
    if email is None:
        return None
    return email.strip().lower()
return normalize_email(email)
$$;

SELECT normalize_email('  Alice@Example.COM  ');

-- Python UDF 使用外部库
CREATE OR REPLACE FUNCTION parse_json_field(json_str STRING, field STRING)
RETURNS STRING
LANGUAGE PYTHON
AS $$
import json
def parse_json_field(json_str, field):
    try:
        data = json.loads(json_str)
        return str(data.get(field, ''))
    except:
        return None
return parse_json_field(json_str, field)
$$;

-- ============================================================
-- SQL 过程（Databricks 2024+，SQL Scripting）
-- ============================================================

-- 基本过程
CREATE OR REPLACE PROCEDURE greet(name STRING)
LANGUAGE SQL
AS $$
BEGIN
    SELECT CONCAT('Hello, ', name);
END
$$;

CALL greet('Alice');

-- ============================================================
-- Notebooks 作为存储过程（推荐方式）
-- ============================================================

-- Databricks 推荐使用 Notebooks 替代存储过程：
-- 1. 在 Notebook 中编写 PySpark / SQL 逻辑
-- 2. 使用 Databricks Jobs 调度执行
-- 3. 使用参数化 Widgets 传入参数

-- 示例 Notebook 逻辑（伪代码）：
-- dbutils.widgets.text("city", "Shanghai")
-- city = dbutils.widgets.get("city")
-- spark.sql(f"SELECT * FROM users WHERE city = '{city}'")

-- ============================================================
-- Delta Live Tables（DLT，声明式管道）
-- ============================================================

-- DLT 是 Databricks 推荐的数据管道方式
-- 替代传统的存储过程编排：

-- @dlt.table
-- def cleaned_users():
--     return spark.read.table("raw_users").filter("age > 0")

-- @dlt.table
-- @dlt.expect("valid_email", "email IS NOT NULL")
-- def valid_users():
--     return spark.read.table("cleaned_users")

-- ============================================================
-- 删除函数/过程
-- ============================================================

DROP FUNCTION IF EXISTS full_name;
DROP FUNCTION IF EXISTS active_users_in_city;
DROP PROCEDURE IF EXISTS greet;

-- 查看函数
SHOW FUNCTIONS;
SHOW USER FUNCTIONS;
DESCRIBE FUNCTION full_name;
DESCRIBE FUNCTION EXTENDED full_name;

-- 注意：Databricks 没有传统的存储过程（PL/SQL / T-SQL 风格）
-- 注意：SQL UDF 是最简单的复用方式
-- 注意：Python UDF 可以使用 Python 生态的所有库
-- 注意：Notebooks + Jobs 是推荐的编排方式
-- 注意：DLT 是声明式数据管道，替代存储过程编排
-- 注意：Unity Catalog 管理 UDF 的访问权限
-- 注意：SQL Scripting（2024+）支持基本的过程式编程
