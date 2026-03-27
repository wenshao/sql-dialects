-- TDengine: 错误处理 (Error Handling)
--
-- 参考资料:
--   [1] TDengine Documentation - Error Codes
--       https://docs.tdengine.com/reference/taos-error-codes/
--   [2] TDengine Documentation - SQL Reference
--       https://docs.tdengine.com/reference/sql/
--   [3] TDengine Documentation - Connector API
--       https://docs.tdengine.com/connector/

-- ============================================================
-- 1. TDengine 错误处理概述
-- ============================================================
-- TDengine 是高性能时序数据库，不支持存储过程或 SQL 级异常处理。
-- 错误处理完全依赖应用层 (C/Python/Java/Go 等连接器) 和 SQL 防御性写法。
-- TDengine 错误码使用十六进制编码（不同于 SQL 标准 SQLSTATE）。

-- ============================================================
-- 2. 应用层错误捕获
-- ================================================================

-- Python (taospy) 示例: 基本错误捕获
-- import taos
-- conn = taos.connect(host='localhost', port=6030)
-- cursor = conn.cursor()
-- try:
--     cursor.execute("INSERT INTO meters VALUES(NOW, 10.5)")
-- except taos.error.ProgrammingError as e:
--     print(f'TDengine error [{e.errno}]: {e.msg}')
-- except taos.error.OperationalError as e:
--     print(f'Operational error [{e.errno}]: {e.msg}')
-- except taos.error.Error as e:
--     print(f'General error: {e}')

-- Java (JDBC) 示例:
-- import com.taosdata.jdbc.TSDBError;
-- import com.taosdata.jdbc.TSDBErrorNumbers;
-- try {
--     stmt.execute("INSERT INTO meters VALUES(NOW, 10.5)");
-- } catch (SQLException e) {
--     int errno = e.getErrorCode();
--     if (errno == TSDBErrorNumbers.TSDB_CODE_INVALID_SQL) {
--         System.out.println("Invalid SQL: " + e.getMessage());
--     } else if (errno == TSDBErrorNumbers.TSDB_CODE_TABLE_NOT_EXIST) {
--         System.out.println("Table not found: " + e.getMessage());
--     }
-- }

-- C/C++ 示例:
-- TAOS_RES* res = taos_query(conn, "INSERT INTO meters VALUES(NOW, 10.5)");
-- if (res == NULL || taos_errno(res) != 0) {
--     fprintf(stderr, "Error [%d]: %s\n", taos_errno(res), taos_errstr(res));
--     taos_free_result(res);
-- }

-- ============================================================
-- 3. TDengine 常见错误码
-- ============================================================

-- TDengine 使用数字错误码（十六进制），不遵循 SQL 标准 SQLSTATE:
--   0x0000 (0)    = 成功 (Success)
--   0x0200 (512)  = 无效参数 (Invalid Parameters)
--   0x0300 (768)  = 表不存在 (Invalid Table Name)
--   0x0388 (904)  = 数据库不存在 (Invalid Database Name)
--   0x03B4 (948)  = 语法错误 (Syntax Error)
--   0x0A00 (2560) = 网络错误 (Network Error)
--   0x0B00 (2816) = 内存不足 (Out of Memory)
--   0x2600 (9728) = 无效时间戳 (Invalid Timestamp)
--   0x2602 (9730) = 列数据类型不匹配
--   0x2640 (9792) = 标签值过长 (Tag Value Too Long)
--   0x26F0 (9968) = 超级表查询 STABLE 不支持的操作
--   0x0544 (1352) = 重复连接 (Duplicate Connection)
--   0x0545 (1353) = 用户已存在 (User Already Exists)

-- 错误码规律:
--   0x02xx = 参数/输入错误
--   0x03xx = 对象不存在错误
--   0x05xx = 连接/认证错误
--   0x0Axx = 网络错误
--   0x26xx = 数据/时间序列错误

-- ============================================================
-- 4. SQL 层面的错误避免: 防御性写法
-- ============================================================

-- 使用 IF NOT EXISTS 避免对象已存在错误
CREATE DATABASE IF NOT EXISTS mydb;

-- 使用 IF NOT EXISTS 建表
CREATE TABLE IF NOT EXISTS meters (
    ts        TIMESTAMP,
    val       FLOAT,
    status    INT
) TAGS (location NCHAR(20), group_id INT);

-- 使用 IF NOT EXISTS 建超级表
CREATE STABLE IF NOT EXISTS readings (
    ts        TIMESTAMP,
    voltage   FLOAT,
    current   FLOAT
) TAGS (device_id BINARY(32), region NCHAR(16));

-- 安全插入: TDengine 不支持 ON CONFLICT，使用应用层幂等逻辑
-- 策略: 时序数据通常不要求幂等，直接 INSERT 即可
INSERT INTO meters USING readings TAGS('sensor_01', 'north')
VALUES(NOW, 10.5, 1);

-- 批量插入: 减少网络往返以降低错误概率
INSERT INTO meters VALUES
    (NOW - 2h, 10.1, 1)
    (NOW - 1h, 10.3, 1)
    (NOW, 10.5, 1);

-- ============================================================
-- 5. TDengine 特有错误场景与处理
-- ============================================================

-- 场景 1: 时间戳乱序写入
-- 错误: 时间戳早于已有数据（取决于配置）
-- 解决: 设置 keep_time_order 或在应用层保证时序顺序

-- 场景 2: 超级表查询限制
-- 错误: 不支持对超级表进行某些聚合/JOIN
-- 解决: 查询子表或使用 TDengine 3.0+ 的时间序列扩展函数

-- 场景 3: 标签值超长
-- 错误: 标签值超过定义的 NCHAR/BINARY 长度
-- 解决: 建表时预留足够长度，或应用层截断

-- 场景 4: 连接数超限
-- 错误: Too many connections
-- 解决: 调整 maxConnections 配置参数

-- ============================================================
-- 6. 诊断: 系统视图与工具
-- ================================================================

-- 查看数据库列表
SHOW DATABASES;

-- 查看表结构（排查 Schema 错误）
DESCRIBE meters;

-- 查看超级表的子表列表
SHOW TABLES LIKE 'meter_%';

-- 查看 TDengine 系统信息
SHOW VARIABLES;

-- 查看当前连接
SHOW CONNECTIONS;

-- 查看 dnode 状态（集群诊断）
SHOW DNODES;

-- 查看 mnode 状态
SHOW MNODES;

-- 日志诊断:
--   TDengine 日志默认在 /var/log/taos/
--   taosd.log: 服务端日志（包含错误详情）
--   taoslog.*: 客户端日志

-- ============================================================
-- 7. 版本说明
-- ============================================================
-- TDengine 2.x: 基础错误码体系，C/Python/Java 连接器
-- TDengine 3.0:  重构错误码，增强错误消息
-- TDengine 3.1:  新增 STABLE IF NOT EXISTS 语法
-- 注意: 无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER 语法
-- 注意: 时序数据库场景下，错误处理偏重数据写入和查询
-- 限制: 不支持存储过程、触发器
-- 限制: 错误码体系不遵循 SQL 标准 SQLSTATE
