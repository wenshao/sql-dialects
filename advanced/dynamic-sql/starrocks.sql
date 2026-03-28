-- StarRocks: 动态 SQL
--
-- 参考资料:
--   [1] StarRocks Documentation
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- ============================================================
-- 1. StarRocks 不支持服务端动态 SQL
-- ============================================================
-- 与 Doris 相同的设计决策: OLAP 引擎不需要服务端动态 SQL。
--
-- 对比 Doris: 完全相同——两者都是 MPP OLAP 引擎，都不支持。
-- 对比 MySQL: 完整的 PREPARE/EXECUTE/DEALLOCATE 支持。
-- 对比 BigQuery: Scripting(DECLARE/SET/IF/WHILE)——不是传统动态 SQL。

-- ============================================================
-- 2. PREPARE / EXECUTE (MySQL 兼容)
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- 参数化查询(不支持动态表名/列名)。

-- ============================================================
-- 3. 应用层替代方案
-- ============================================================
-- Python (pymysql): 与 Doris 完全相同的方式
-- conn = pymysql.connect(host='fe_host', port=9030, user='root', db='mydb')
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))

-- Java (JDBC):
-- PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
-- ps.setLong(1, 42);

-- ============================================================
-- 4. 会话变量
-- ============================================================
SET exec_mem_limit = 8589934592;
SET query_timeout = 3600;
SET pipeline_dop = 8;

-- StarRocks 特有变量:
-- SET new_planner_optimize_timeout = 3000;  -- CBO 优化器超时(ms)
-- SET enable_global_runtime_filter = true;  -- 全局 Runtime Filter

-- ============================================================
-- 5. StarRocks vs Doris 差异
-- ============================================================
-- 两者完全相同: 都不支持动态 SQL / 存储过程。
-- 差异仅在会话变量名:
--   StarRocks: pipeline_dop(Pipeline 并行度)
--   Doris:     parallel_fragment_exec_instance_num
--
-- 对引擎开发者的启示:
--   不支持动态 SQL 不是"功能缺失"而是"架构选择"。
--   OLAP 引擎的价值在于高效执行单条复杂查询，
--   而非执行多条简单查询组成的过程化逻辑。
