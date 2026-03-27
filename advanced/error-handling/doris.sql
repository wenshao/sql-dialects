-- Apache Doris: 错误处理 (Error Handling)
--
-- 参考资料:
--   [1] Apache Doris Documentation - Error Codes
--       https://doris.apache.org/docs/admin-manual/maint-monitor/error-codes/
--   [2] Apache Doris Documentation - SQL Reference
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [3] Apache Doris Documentation - Load Error Handling
--       https://doris.apache.org/docs/data-operate/import/import-way/load-err-handling/

-- ============================================================
-- 1. Apache Doris 错误处理概述
-- ============================================================
-- Apache Doris 是 MPP 架构的 OLAP 分析引擎，通过 MySQL 协议提供服务。
-- 不支持存储过程或 SQL 级异常处理语法。
-- 错误处理依赖: 应用层 MySQL 驱动捕获 + SQL 防御性写法 + 导入容错机制。

-- ============================================================
-- 2. 应用层错误捕获
-- ============================================================

-- Python (pymysql) 示例: 基本错误捕获
-- import pymysql
-- conn = pymysql.connect(host='doris-fe', port=9030, user='root')
-- cursor = conn.cursor()
-- try:
--     cursor.execute("INSERT INTO users VALUES(1, 'test')")
-- except pymysql.IntegrityError as e:
--     print(f'Constraint error [{e.args[0]}]: {e.args[1]}')
-- except pymysql.OperationalError as e:
--     print(f'Operational error [{e.args[0]}]: {e.args[1]}')
-- except pymysql.ProgrammingError as e:
--     print(f'Syntax/SQL error [{e.args[0]}]: {e.args[1]}')
-- except pymysql.Error as e:
--     print(f'Doris error: {e}')

-- Java (JDBC) 示例:
-- try {
--     stmt.executeUpdate("INSERT INTO users VALUES(1, 'test')");
-- } catch (java.sql.BatchUpdateException e) {
--     // 批量导入部分失败
--     int[] updateCounts = e.getUpdateCounts();
-- } catch (java.sql.SQLException e) {
--     int errno = e.getErrorCode();
--     String sqlState = e.getSQLState();
--     System.out.println("Error [" + errno + "/" + sqlState + "]: " + e.getMessage());
-- }

-- ============================================================
-- 3. Doris 常见错误码
-- ================================================================

-- Doris 使用 MySQL 兼容错误码:
--   1062  = 重复键错误 (Duplicate Entry)
--   1045  = 访问被拒绝 (Access Denied)
--   1049  = 数据库不存在 (Unknown Database)
--   1050  = 表已存在 (Table Already Exists)
--   1051  = 表不存在 (Unknown Table)
--   1054  = 列不存在 (Unknown Column)
--   1064  = 语法错误 (Syntax Error)
--   1146  = 表不存在 (Table Doesn't Exist)
--   1366  = 数据类型不匹配
--   1064  = SQL 语法错误
--   1105  = Doris 内部错误 (通常附带详细消息)

-- Doris 特有错误码 (通过错误消息前缀区分):
--   ERR_.*           = FE (Frontend) 错误
--   T_ERR_.*         = BE (Backend) 错误
--   PUBLISH_.*       = 导入发布阶段错误
--   LOAD_RUN_FAIL    = 导入运行失败

-- ============================================================
-- 4. SQL 层面的错误避免: 防御性写法
-- ============================================================

-- 使用 IF NOT EXISTS 避免建表冲突
CREATE TABLE IF NOT EXISTS users (
    id       INT,
    name     VARCHAR(100),
    reg_date DATE
)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "1");

-- 使用 IF EXISTS 避免删除不存在的对象
DROP TABLE IF EXISTS temp_data;

-- 使用 INSERT INTO SELECT 避免重复 (需目标表有 UNIQUE KEY 或聚合模型)
INSERT INTO users(id, name, reg_date)
SELECT 1, 'alice', '2024-01-01'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = 1);

-- 使用 GROUP BY 替代 DISTINCT ON (Doris 不支持 DISTINCT ON)
SELECT id, MAX(name) AS name FROM users GROUP BY id;

-- ============================================================
-- 5. Doris 导入错误处理 (特有)
-- ================================================================

-- Stream Load 导入容错配置
-- curl --location-trusted -u user:passwd \
--   -H "column_separator:," \
--   -H "max_filter_ratio:0.1" \          -- 允许 10% 的错误行
--   -H "timeout:600" \
--   -T data.csv \
--   http://doris-fe:8040/api/db/table/_stream_load

-- Broker Load 导入容错
-- LOAD LABEL db.my_label
-- (
--     DATA INFILE("hdfs://path/data.csv")
--     INTO TABLE users
--     COLUMNS TERMINATED BY ","
--     SET (name = UPPER(name))
-- )
-- WITH BROKER
-- PROPERTIES (
--     "max_filter_ratio" = "0.01",       -- 允许 1% 错误行
--     "error_log_path" = "/tmp/load_err"  -- 错误行写入日志
-- );

-- 查看导入任务的错误详情
SHOW LOAD WHERE LABEL = 'my_label';

-- 查看导入错误行
-- SHOW LOAD WARNINGS ON 'my_label';

-- ============================================================
-- 6. 诊断: 系统视图
-- ================================================================

-- 查看导入任务状态和错误
SELECT job_id, label, state, error_msg, create_time
FROM information_schema.loads
ORDER BY create_time DESC
LIMIT 20;

-- 查看查询执行错误
SELECT query_id, time_ms, state, error_code, error_message
FROM information_schema.audit_log
WHERE state = 'FAILED'
ORDER BY time_ms DESC
LIMIT 20;

-- 查看 FE 作业状态
SHOW RUNNING QUERIES;

-- 取消正在执行的查询
-- KILL QUERY 'query_id';

-- 查看 BE 节点状态
SHOW BACKENDS;

-- 查看 tablet 副本状态（排查数据一致性错误）
SHOW TABLET FROM users;

-- 查看数据库/表元数据
SHOW CREATE TABLE users;

-- ============================================================
-- 7. Doris 特有错误场景与处理
-- ================================================================

-- 场景 1: 导入数据类型不匹配
-- 错误: Column type mismatch, expected INT, got STRING
-- 解决: 使用 LOAD 时的 SET 子句做类型转换，或调整 max_filter_ratio

-- 场景 2: 内存超限 (查询)
-- 错误: Memory exceed limit
-- 解决: 调整 query_mem_limit 或拆分查询
--   SET exec_mem_limit = 8589934592;  -- 8 GB

-- 场景 3: 副本不足
-- 错误: Replicas missing or incomplete
-- 解决: 检查 BE 状态，等待副本自动恢复或手动修复
--   ADMIN REPAIR TABLE users;

-- 场景 4: FE/BE 通信超时
-- 错误: Timeout when sending task to BE
-- 解决: 增加 query_timeout 或检查网络
--   SET query_timeout = 600;  -- 10 分钟

-- ============================================================
-- 8. 版本说明
-- ============================================================
-- Doris 0.x:   基础错误码，MySQL 协议兼容
-- Doris 1.0:   导入容错增强 (max_filter_ratio, error_log)
-- Doris 1.2:   新增 information_schema.loads 视图
-- Doris 2.0:   改进错误消息可读性，增强诊断能力
-- Doris 2.1:   存储过程实验性支持
-- 注意: 错误码兼容 MySQL 协议格式
-- 注意: OLAP 引擎特有的导入容错是关键错误处理手段
-- 限制: 不支持 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER, SIGNAL
