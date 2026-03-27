-- Apache Spark SQL: 错误处理 (Error Handling)
--
-- 参考资料:
--   [1] Spark SQL Reference - Error Classes
--       https://spark.apache.org/docs/latest/sql-error-conditions.html
--   [2] Spark SQL Reference - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html
--   [3] Spark Configuration - Error Handling
--       https://spark.apache.org/docs/latest/configuration.html

-- ============================================================
-- 1. Spark SQL 错误处理概述
-- ============================================================
-- Spark SQL 不支持服务端存储过程或异常处理语法。
-- 错误处理通过两种途径实现:
--   (a) 应用层 API 捕获异常 (PySpark / Scala / Java)
--   (b) SQL 层面的 try_* 安全函数避免运行时错误

-- ============================================================
-- 2. 应用层错误捕获
-- ============================================================

-- PySpark 示例: 基本 try/except
-- from pyspark.errors import AnalysisException, SparkRuntimeException
-- try:
--     spark.sql("SELECT * FROM nonexistent_table")
-- except AnalysisException as e:
--     print(f"Analysis error: {e}")
-- except SparkRuntimeException as e:
--     print(f"Runtime error: {e}")

-- PySpark 示例: 按错误类型分别处理
-- from pyspark.errors import (
--     AnalysisException,           -- 编译/分析阶段错误 (表不存在等)
--     ArithmeticException,         -- 算术异常 (除零等)
--     UnsupportedOperationException,
--     ParseException,              -- SQL 解析错误
-- )
-- try:
--     spark.sql("SELECT 1/0").show()
-- except ArithmeticException as e:
--     print(f"Arithmetic error: {e.getErrorClass()}")
-- except ParseException as e:
--     print(f"Parse error at line {e.getErrorClass()}")

-- Scala 示例:
-- import org.apache.spark.sql.AnalysisException
-- try {
--     spark.sql("SELECT * FROM nonexistent_table")
-- } catch {
--     case e: AnalysisException => println(s"Analysis: ${e.message}")
--     case e: Exception => println(s"General: ${e.getMessage}")
-- }

-- ============================================================
-- 3. Spark 错误分类体系 (3.4+)
-- ================================================================

-- Spark 3.4+ 统一错误分类 (Error Classes):
--   ARITHMETIC_OVERFLOW       = 算术溢出
--   DIVIDE_BY_ZERO            = 除零错误
--   INVALID_PARAMETER_VALUE   = 参数无效
--   UNRESOLVED_COLUMN         = 列名无法解析
--   TABLE_OR_VIEW_NOT_FOUND   = 表或视图不存在
--   COLUMN_ALREADY_EXISTS     = 列已存在
--   SCHEMA_NOT_COMPATIBLE     = Schema 不兼容
--   INVALID_FORMAT            = 格式错误 (日期/数字解析)
--   PARTITION_NOT_FOUND       = 分区不存在
--   PATH_ALREADY_EXISTS       = 路径已存在 (数据文件)
--   MALFORMED_RECORD           = 数据格式损坏

-- 每个错误类包含: errorClass, messageParameters, queryContext
-- SQL 代码中查看: DESC FUNCTION EXTENDED try_divide;

-- ============================================================
-- 4. SQL 层面的安全函数 (Error Avoidance)
-- ============================================================

-- TRY_CAST: 类型转换失败返回 NULL 而非报错
SELECT TRY_CAST('abc' AS INT);          -- NULL
SELECT TRY_CAST('2024-01-01' AS DATE);  -- 2024-01-01 (成功)
SELECT TRY_CAST('invalid' AS DATE);     -- NULL

-- try_divide: 安全除法，除零返回 NULL               -- 3.2+
SELECT try_divide(10, 0);                -- NULL
SELECT try_divide(10, 3);                -- 3.333...
SELECT try_divide(0, 0);                 -- NULL

-- try_add: 安全加法，溢出返回 NULL                   -- 3.2+
SELECT try_add(2147483647, 1);           -- NULL (INT 溢出)
SELECT try_add(9223372036854775807L, 1); -- NULL (BIGINT 溢出)

-- try_subtract: 安全减法                              -- 3.2+
SELECT try_subtract(-2147483648, 1);     -- NULL (INT 下溢)

-- try_multiply: 安全乘法                              -- 3.2+
SELECT try_multiply(2147483647, 2);      -- NULL (INT 溢出)

-- try_to_timestamp: 安全时间戳解析                    -- 3.4+
SELECT try_to_timestamp('2024-13-01', 'yyyy-MM-dd');  -- NULL (月份无效)

-- try_avg / try_sum: 聚合时忽略异常                   -- 3.4+
SELECT try_avg(CAST('NaN' AS DOUBLE));   -- NULL

-- ============================================================
-- 5. 防御性 SQL 写法
-- ============================================================

-- 使用 IF NOT EXISTS 避免建表冲突
CREATE TABLE IF NOT EXISTS users (
    id   INT,
    name STRING
) USING DELTA;

-- 使用 MERGE INTO 实现 UPSERT
MERGE INTO users AS target
USING (SELECT 1 AS id, 'alice' AS name) AS source
ON target.id = source.id
WHEN MATCHED THEN UPDATE SET target.name = source.name
WHEN NOT MATCHED THEN INSERT (id, name) VALUES(source.id, source.name);

-- 使用 COALESCE + TRY_CAST 处理脏数据
SELECT
    id,
    COALESCE(TRY_CAST(age_str AS INT), -1) AS age,
    COALESCE(TRY_CAST(price_str AS DOUBLE), 0.0) AS price
FROM raw_data;

-- 使用 CASE WHEN 替代可能失败的表达式
SELECT
    id,
    CASE WHEN denom = 0 THEN NULL ELSE numer / denom END AS ratio
FROM measurements;

-- ============================================================
-- 6. 诊断: Spark 系统视图与日志
-- ============================================================

-- 查看 Spark 作业执行信息
SELECT * FROM information_schema.tables;

-- Spark UI: http://driver-host:4040
--   - Jobs 页面: 查看作业失败原因
--   - SQL 页面: 查看 SQL 执行计划和错误
--   - Executors 页面: 查看资源使用和任务失败

-- Spark 日志配置:
-- SET spark.sql.ansi.enabled = false;        -- 关闭 ANSI 模式 (默认)
-- SET spark.sql.ansi.enabled = true;         -- 开启 ANSI 模式 (严格)
-- SET spark.sql.storeAssignmentPolicy = STRICT;  -- 严格类型转换
-- SET spark.sql.analyzeBinaryFileSize = true;

-- ANSI 模式的影响:
--   ANSI=false: 1/0 = NULL, CAST('abc' AS INT) = NULL
--   ANSI=true:  1/0 = ERROR, CAST('abc' AS INT) = ERROR

-- ============================================================
-- 7. 版本说明
-- ============================================================
-- Spark 3.0: TRY_CAST 引入
-- Spark 3.2: try_divide, try_add, try_subtract, try_multiply 引入
-- Spark 3.3: 改进错误消息，新增 SQLSTATE 编码
-- Spark 3.4: 统一错误分类体系 (Error Classes), try_to_timestamp
-- Spark 3.5: 增强错误诊断信息
-- 注意: 无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL 语法
-- 注意: try_* 函数是 Spark SQL 错误避免的核心手段
-- 限制: 不支持存储过程，错误处理完全依赖应用层 API
