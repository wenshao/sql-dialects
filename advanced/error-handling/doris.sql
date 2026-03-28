-- Apache Doris: 错误处理
--
-- 参考资料:
--   [1] Doris Documentation - Error Codes
--       https://doris.apache.org/docs/admin-manual/maint-monitor/error-codes/

-- ============================================================
-- 1. 错误处理架构: 无过程式异常处理
-- ============================================================
-- Doris 不支持 TRY/CATCH、EXCEPTION WHEN、DECLARE HANDLER、SIGNAL。
-- 错误处理依赖: 应用层捕获 + SQL 防御性写法 + 导入容错机制。
--
-- 设计理由: 与不支持存储过程的原因一致——OLAP 引擎的错误处理在应用层。
--
-- 对比:
--   StarRocks:  完全相同(同源)
--   ClickHouse: 同样无过程式错误处理
--   MySQL:      DECLARE HANDLER / SIGNAL / RESIGNAL
--   PostgreSQL: BEGIN/EXCEPTION WHEN ... THEN ... END
--   BigQuery:   Scripting 中的 BEGIN/EXCEPTION

-- ============================================================
-- 2. Doris 错误码 (MySQL 兼容 + Doris 特有)
-- ============================================================
-- MySQL 兼容错误码:
--   1045 = 访问被拒绝     1049 = 数据库不存在
--   1050 = 表已存在        1051 = 表不存在
--   1054 = 列不存在        1064 = 语法错误
--   1062 = 重复键          1105 = Doris 内部错误
--
-- Doris 特有错误(通过消息前缀区分):
--   ERR_*:          FE (Frontend) 错误
--   T_ERR_*:        BE (Backend) 错误
--   LOAD_RUN_FAIL:  导入运行失败

-- ============================================================
-- 3. 应用层错误捕获
-- ============================================================
-- Python (pymysql):
-- try:
--     cursor.execute("INSERT INTO users VALUES(1, 'test')")
-- except pymysql.IntegrityError as e:
--     print(f'Constraint error: {e}')
-- except pymysql.OperationalError as e:
--     print(f'Operational error: {e}')
-- except pymysql.ProgrammingError as e:
--     print(f'SQL error: {e}')

-- ============================================================
-- 4. SQL 防御性写法
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id INT, name VARCHAR(100)
) DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "1");

DROP TABLE IF EXISTS temp_data;

-- ============================================================
-- 5. 导入错误处理 (Doris 核心特性)
-- ============================================================
-- Stream Load 容错:
-- curl -H "max_filter_ratio:0.1" -T data.csv \
--   http://fe:8040/api/db/table/_stream_load
-- max_filter_ratio = 0.1 表示允许 10% 的错误行

-- 查看导入错误
SHOW LOAD WHERE LABEL = 'my_label';

-- 设计分析:
--   max_filter_ratio 是 Doris/StarRocks 特有的容错参数。
--   在大批量导入中，少量脏数据不应阻塞整个导入任务。
--   对比 MySQL: LOAD DATA 的 IGNORE 关键字(类似但粒度不同)。
--   对比 BigQuery: bq load --max_bad_records(类似概念)。

-- ============================================================
-- 6. 诊断查询
-- ============================================================
SHOW PROCESSLIST;                             -- 正在执行的查询
SHOW BACKENDS;                                -- BE 节点状态
SHOW TABLET FROM users;                       -- Tablet 副本状态
SHOW CREATE TABLE users;                      -- 表元数据
ADMIN REPAIR TABLE users;                     -- 修复副本

-- 设置查询级参数
SET exec_mem_limit = 8589934592;              -- 8GB 内存限制
SET query_timeout = 600;                      -- 10 分钟超时

-- ============================================================
-- 7. 常见错误场景
-- ============================================================
-- 内存超限: Memory exceed limit → SET exec_mem_limit
-- 副本不足: Replicas missing → ADMIN REPAIR TABLE
-- 导入超时: Timeout → 增加 timeout 参数
-- 类型不匹配: Column type mismatch → LOAD SET 子句做转换
