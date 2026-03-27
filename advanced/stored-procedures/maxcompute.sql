-- MaxCompute (ODPS): 存储过程和函数
--
-- 参考资料:
--   [1] MaxCompute SQL - Script Mode
--       https://help.aliyun.com/zh/maxcompute/user-guide/script-mode
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- MaxCompute 不支持传统的存储过程
-- 使用 UDF（用户定义函数）和脚本模式替代

-- ============================================================
-- SQL UDF（内联函数）
-- ============================================================

-- 标量函数
CREATE FUNCTION my_add(@a BIGINT, @b BIGINT) AS @a + @b;

-- 使用
SELECT my_add(1, 2);

-- 删除
DROP FUNCTION IF EXISTS my_add;

-- ============================================================
-- Java UDF（最常用的扩展方式）
-- ============================================================

-- 1. 编写 Java 类，实现 com.aliyun.odps.udf.UDF 接口
-- 2. 打包成 JAR 文件
-- 3. 上传到 MaxCompute
-- 4. 注册为函数

-- 上传 JAR
ADD JAR my_functions.jar;

-- 注册 UDF
CREATE FUNCTION my_lower AS 'com.example.udf.Lower' USING 'my_functions.jar';

-- 使用
SELECT my_lower(username) FROM users;

-- ============================================================
-- Python UDF
-- ============================================================

-- Python 2 UDF（旧方式）
CREATE FUNCTION my_len AS 'my_udf.py.my_len' USING 'my_udf.py'
WITH RESOURCES 'my_udf.py';

-- Python 3 UDF（推荐）
-- 需要在 DataWorks 中配置 Python 3 运行环境

-- ============================================================
-- UDTF（用户定义表生成函数）
-- ============================================================

-- Java UDTF，一行输入生成多行输出
-- 实现 com.aliyun.odps.udf.UDTF 接口

CREATE FUNCTION my_explode AS 'com.example.udtf.Explode' USING 'my_functions.jar';

-- 使用 UDTF（需要 LATERAL VIEW）
SELECT u.id, t.tag
FROM users u
LATERAL VIEW my_explode(u.tags) t AS tag;

-- ============================================================
-- UDAF（用户定义聚合函数）
-- ============================================================

-- Java UDAF，实现 com.aliyun.odps.udf.Aggregator 接口
CREATE FUNCTION my_median AS 'com.example.udaf.Median' USING 'my_functions.jar';

SELECT my_median(age) FROM users;

-- ============================================================
-- 内置聚合函数和高级函数替代存储过程
-- ============================================================

-- 窗口函数
SELECT id, username,
    ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rank
FROM employees;

-- TRANSFORM（调用外部脚本）
SELECT TRANSFORM(id, username, email)
USING 'python my_script.py'
AS (new_id, new_username, processed_email)
FROM users;

-- ============================================================
-- 脚本模式（Script Mode）
-- ============================================================

-- MaxCompute 支持脚本模式，可以编写多条 SQL 语句
-- 在 DataWorks 中使用

-- 变量
SET @today = '20240115';
SELECT * FROM orders WHERE dt = @today;

-- 条件执行（通过 DataWorks 调度）
-- 不支持 IF/ELSE 等过程式语法

-- ============================================================
-- MaxCompute Spark（复杂逻辑替代方案）
-- ============================================================

-- 对于需要复杂逻辑的场景，使用 MaxCompute Spark
-- 通过 Spark 编写 Scala/Python/Java 程序

-- 注意：MaxCompute 不支持传统存储过程
-- 注意：UDF 是扩展功能的主要方式（Java/Python）
-- 注意：复杂 ETL 逻辑通过 DataWorks 调度编排实现
-- 注意：MaxCompute Spark 适合更复杂的数据处理逻辑
-- 注意：TRANSFORM 可以调用任意脚本（Python/Shell 等）
