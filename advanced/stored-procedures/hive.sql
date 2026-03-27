-- Hive: 存储过程和函数
--
-- 参考资料:
--   [1] Apache Hive - HPL/SQL
--       https://cwiki.apache.org/confluence/display/Hive/HPL-SQL
--   [2] Apache Hive Language Manual
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual

-- Hive 不支持传统的存储过程
-- 使用 UDF 和 HiveQL 脚本替代

-- ============================================================
-- 内置函数
-- ============================================================

-- Hive 提供丰富的内置函数
SELECT
    UPPER(username),
    LENGTH(email),
    SUBSTR(email, 1, 5),
    CONCAT(first_name, ' ', last_name),
    NVL(phone, 'N/A'),
    COALESCE(phone, mobile, 'N/A'),
    CURRENT_TIMESTAMP()
FROM users;

-- 查看所有函数
SHOW FUNCTIONS;
DESCRIBE FUNCTION concat;
DESCRIBE FUNCTION EXTENDED concat;

-- ============================================================
-- 临时函数（Session 级别）
-- ============================================================

-- 创建临时函数（从 JAR 加载）
ADD JAR /path/to/my_udf.jar;
CREATE TEMPORARY FUNCTION my_lower AS 'com.example.udf.Lower';

SELECT my_lower(username) FROM users;

-- 删除临时函数
DROP TEMPORARY FUNCTION IF EXISTS my_lower;

-- ============================================================
-- 永久函数（Hive 0.13+）
-- ============================================================

CREATE FUNCTION mydb.my_lower AS 'com.example.udf.Lower'
USING JAR 'hdfs:///path/to/my_udf.jar';

SELECT mydb.my_lower(username) FROM users;

DROP FUNCTION IF EXISTS mydb.my_lower;

-- ============================================================
-- Java UDF 类型
-- ============================================================

-- UDF（一进一出）: 继承 org.apache.hadoop.hive.ql.exec.UDF
-- GenericUDF: 更灵活的 UDF 接口
-- UDAF: 聚合函数，继承 AbstractGenericUDAFResolver
-- UDTF: 表生成函数，继承 GenericUDTF

-- ============================================================
-- UDTF（表生成函数）
-- ============================================================

-- 内置 UDTF
SELECT id, tag
FROM users
LATERAL VIEW explode(tags) t AS tag;

-- 多列 UDTF
SELECT id, key, value
FROM users
LATERAL VIEW explode(properties) t AS key, value;

-- 嵌套 LATERAL VIEW
SELECT id, tag, perm
FROM users
LATERAL VIEW explode(tags) t1 AS tag
LATERAL VIEW explode(permissions) t2 AS perm;

-- OUTER LATERAL VIEW（保留没有输出的行）
SELECT id, tag
FROM users
LATERAL VIEW OUTER explode(tags) t AS tag;

-- ============================================================
-- TRANSFORM（调用外部脚本）
-- ============================================================

-- Python 脚本
SELECT TRANSFORM(id, username, email)
USING 'python3 process.py'
AS (new_id BIGINT, new_username STRING, result STRING)
FROM users;

-- Shell 脚本
SELECT TRANSFORM(line)
USING '/bin/cat'
AS (output STRING)
FROM raw_data;

-- 添加脚本文件
ADD FILE process.py;

-- ============================================================
-- 宏（Macro，Hive 0.12+）
-- ============================================================

-- 简单的表达式别名
CREATE TEMPORARY MACRO add_tax(price DOUBLE) price * 1.1;
SELECT add_tax(100.0);

CREATE TEMPORARY MACRO full_name(first STRING, last STRING) CONCAT(first, ' ', last);
SELECT full_name('Alice', 'Smith');

DROP TEMPORARY MACRO IF EXISTS add_tax;

-- ============================================================
-- HPL/SQL（Hive 2.0+，过程式语言）
-- ============================================================

-- HPL/SQL 提供类似 PL/SQL 的过程式语言
-- 但需要单独启用，使用不广泛

-- hplsql -f script.sql
-- 支持 IF/ELSE, WHILE, FOR, CURSOR, EXCEPTION 等

-- 注意：Hive 不支持传统的 CREATE PROCEDURE
-- 注意：UDF 是最主要的扩展方式（Java 编写）
-- 注意：TRANSFORM 可以调用任意外部脚本
-- 注意：复杂逻辑通常通过多步 HiveQL + 调度工具实现
-- 注意：HPL/SQL 提供过程式能力但使用率低
