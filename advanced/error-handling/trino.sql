-- Trino: 错误处理 (Error Handling)
--
-- 参考资料:
--   [1] Trino Documentation - Error Codes
--       https://trino.io/docs/current/admin/failure-tolerance.html
--   [2] Trino Documentation - Built-in Functions (TRY)
--       https://trino.io/docs/current/functions/conditional.html#try
--   [3] Trino Documentation - SQL Reference
--       https://trino.io/docs/current/sql.html

-- ============================================================
-- 1. Trino 错误处理概述
-- ============================================================
-- Trino 是分布式 SQL 查询引擎，不支持存储过程或 SQL 级异常处理。
-- 错误处理通过两种途径:
--   (a) SQL 层面的 TRY() 函数和安全函数避免运行时错误
--   (b) 应用层 (JDBC/Python) 捕获 Trino 特有异常

-- ============================================================
-- 2. 应用层错误捕获
-- ============================================================

-- Python (trino-python-client) 示例:
-- import trino
-- from trino.exceptions import TrinoQueryError, TrinoUserError
-- conn = trino.dbapi.connect(host='trino-coordinator', port=8080)
-- cursor = conn.cursor()
-- try:
--     cursor.execute('SELECT * FROM nonexistent_table')
--     rows = cursor.fetchall()
-- except TrinoQueryError as e:
--     print(f'Query error [{e.error_code}]: {e.message}')
--     print(f'Error name: {e.error_name}')
--     print(f'Error type: {e.error_type}')
-- except TrinoUserError as e:
--     print(f'User error: {e.message}')
-- except Exception as e:
--     print(f'General error: {e}')

-- Java (JDBC) 示例:
-- import io.trino.jdbc.TrinoSQLException;
-- try {
--     stmt.execute("SELECT 1/0");
-- } catch (TrinoSQLException e) {
--     // Trino 特有异常，包含 error code 和 error name
--     System.out.println("Error: " + e.getMessage());
-- } catch (SQLException e) {
--     System.out.println("SQL error: " + e.getMessage());
-- }

-- ============================================================
-- 3. Trino 错误码体系
-- ============================================================

-- Trino 使用内部错误码 (不遵循 SQL 标准 SQLSTATE):
--   错误码格式: <error_name> (类似 HTTP 状态码的字符串)
--
--   常见错误码:
--   0x0000_0000 = 成功
--   SYNTAX_ERROR              = SQL 语法错误
--   INVALID_TABLE             = 表不存在
--   INVALID_COLUMN            = 列不存在
--   INVALID_FUNCTION          = 函数不存在
--   TYPE_MISMATCH             = 数据类型不匹配
--   DIVISION_BY_ZERO          = 除零错误 (标准模式)
--   NUMERIC_VALUE_OUT_OF_RANGE = 数值溢出
--   CONSTRAINT_VIOLATION      = 约束违反
--   PERMISSION_DENIED         = 权限不足
--   STANDARD_ERROR            = 标准错误 (包含 SQLSTATE 映射)
--   EXCEEDED_CPU_LIMIT        = CPU 限制超限
--   EXCEEDED_MEMORY_LIMIT     = 内存限制超限
--   EXCEEDED_TIME_LIMIT       = 执行超时
--   QUERY_ALREADY_STARTED     = 查询已在执行
--   QUERY_NOT_FOUND           = 查询不存在

-- 错误类型 (error_type):
--   INTERNAL_ERROR   = Trino 内部 bug
--   INSUFFICIENT_RESOURCES = 资源不足
--   EXTERNAL         = 外部系统错误 (connector 错误)
--   USER_ERROR       = 用户输入错误

-- ============================================================
-- 4. TRY() 函数: 核心错误避免机制
-- ============================================================

-- TRY(): 将可能失败的表达式转为 NULL
SELECT TRY(1 / 0);                         -- NULL
SELECT TRY(CAST('abc' AS INTEGER));         -- NULL
SELECT TRY(CAST('2024-13-01' AS DATE));     -- NULL

-- TRY_CAST: 类型转换失败返回 NULL (替代 CAST)
SELECT TRY_CAST('123' AS INTEGER);          -- 123
SELECT TRY_CAST('abc' AS INTEGER);          -- NULL

-- COALESCE + TRY: 提供默认值
SELECT COALESCE(TRY(CAST(value_str AS INTEGER)), 0) AS value
FROM raw_data;

-- TRY 在聚合中的应用
SELECT
    COUNT(*) AS total_rows,
    COUNT(TRY_CAST(age_str AS INTEGER)) AS valid_rows,
    COUNT(*) - COUNT(TRY_CAST(age_str AS INTEGER)) AS invalid_rows
FROM raw_data;

-- CASE WHEN + TRY: 复杂条件下的安全计算
SELECT
    id,
    CASE
        WHEN TRY(price / quantity) IS NULL THEN 'INVALID'
        ELSE CAST(price / quantity AS VARCHAR)
    END AS unit_price
FROM orders;

-- ============================================================
-- 5. 更多防御性 SQL 写法
-- ============================================================

-- 使用 IF NOT EXISTS 避免建表冲突
CREATE TABLE IF NOT EXISTS users (
    id   INTEGER,
    name VARCHAR(100)
);

-- 使用 NULLIF 避免除零
SELECT id, numerator / NULLIF(denominator, 0) AS ratio
FROM measurements;

-- 使用 COALESCE 处理 NULL
SELECT id, COALESCE(name, 'UNKNOWN') AS name FROM users;

-- 安全的 JSON 解析
SELECT TRY(json_parse('invalid json'));     -- NULL
SELECT TRY(json_extract_scalar(data, '$.field')) FROM json_table;

-- ============================================================
-- 6. Trino 特有错误场景与处理
-- ================================================================

-- 场景 1: Connector 错误 (外部数据源)
-- 错误: ConnectorError / EXTERNAL error type
-- 解决: 检查 catalog 配置和外部数据源连接
--   SHOW CATALOGS;                           -- 查看可用的 catalog
--   SHOW SCHEMAS FROM my_catalog;            -- 查看可用的 schema

-- 场景 2: 内存超限
-- 错误: EXCEEDED_MEMORY_LIMIT
-- 解决: 增加 query.max-memory 或优化查询
--   SET SESSION query_max_memory = '8GB';    -- 会话级调大内存限制
--   SET SESSION query_max_total_memory = '16GB';

-- 场景 3: 查询超时
-- 错误: EXCEEDED_TIME_LIMIT
-- 解决: 优化查询或增加超时时间
--   SET SESSION query_max_run_time = '30m';

-- 场景 4: 节点故障 (Exchange 失败)
-- 错误: REMOTE_TASK_FAILED / ExchangeError
-- 解决: Trino 自动重试（如果启用了 failure-tolerance）
--   SET SESSION retry_policy = 'QUERY';      -- 启用查询级重试

-- ============================================================
-- 7. 诊断: 系统视图与监控
-- ================================================================

-- 查看已完成查询（含失败查询）
SELECT query_id, state, error_code, error_type, query
FROM system.runtime.queries
WHERE state = 'FAILED'
ORDER BY created DESC
LIMIT 20;

-- 查看查询执行统计
SELECT query_id, state, elapsed_time, peak_memory, analysis_time
FROM system.runtime.queries
ORDER BY created DESC
LIMIT 10;

-- 查看当前节点信息
SELECT * FROM system.runtime.nodes;

-- 查看事务信息
SELECT * FROM system.runtime.transactions;

-- Trino UI: http://coordinator:8080
--   - 查看查询执行计划、Stage 分解、Task 错误

-- ============================================================
-- 8. 版本说明
-- ============================================================
-- Trino 350:     TRY() 函数引入
-- Trino 351:     TRY_CAST 引入
-- Trino 380:     改进错误消息，新增 error_type 分类
-- Trino 390:     查询级重试 (failure-tolerance)
-- Trino 400+:    增强 EXCEEDED_* 错误的诊断信息
-- Trino 420+:    resource group 错误隔离增强
-- 注意: 无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL 语法
-- 注意: TRY() 是 Trino SQL 错误避免的核心函数
-- 注意: Trino 面向 OLAP 交互式查询，容错偏重分布式执行层面
-- 限制: 不支持存储过程、触发器
-- 限制: 错误码体系不遵循 SQL 标准 SQLSTATE
