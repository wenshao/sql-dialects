-- Apache Doris: 动态 SQL
--
-- 参考资料:
--   [1] Doris Documentation
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. 设计决策: OLAP 引擎为何不支持动态 SQL
-- ============================================================
-- Doris 不支持服务端动态 SQL / 存储过程。
-- 这是 OLAP 引擎的普遍选择:
--   Doris/StarRocks: 不支持
--   ClickHouse:      不支持
--   BigQuery:        不支持服务端(有 Scripting 但不同)
--   MySQL/PG:        完整支持(PREPARE/EXECUTE/DEALLOCATE)
--
-- 设计理由:
--   OLAP 查询是"批量分析"——一条 SQL 可能扫描数亿行。
--   动态 SQL 的核心价值是"参数化重复执行"——这是 OLTP 场景。
--   OLAP 引擎的优化器需要完整的 SQL 来做 CBO，动态拼接会降低优化效果。
--
-- 对引擎开发者的启示:
--   是否支持存储过程/动态 SQL 是引擎定位的分水岭:
--   OLTP(MySQL/PG): 必须支持——应用逻辑下沉到数据库
--   OLAP(Doris/CH): 不需要——逻辑在应用层/调度层

-- ============================================================
-- 2. PREPARE / EXECUTE (MySQL 兼容协议)
-- ============================================================
-- Doris 兼容 MySQL 协议，支持有限的 PREPARE/EXECUTE
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- 设计分析:
--   这不是真正的动态 SQL，而是参数化查询(Parameterized Query)。
--   主要用于 MySQL 客户端/驱动的兼容，不支持动态表名/列名。

-- ============================================================
-- 3. 应用层替代方案
-- ============================================================
-- Python (pymysql，兼容 MySQL 协议):
-- conn = pymysql.connect(host='fe_host', port=9030, user='root', db='mydb')
-- cursor = conn.cursor()
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))
-- table = 'users'
-- cursor.execute(f'SELECT COUNT(*) FROM `{table}`')  -- 动态表名

-- Java (JDBC):
-- PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
-- ps.setLong(1, 42);
-- ResultSet rs = ps.executeQuery();

-- ============================================================
-- 4. 会话变量
-- ============================================================
SET exec_mem_limit = 8589934592;
SET query_timeout = 3600;
SET parallel_fragment_exec_instance_num = 8;

-- 对比:
--   StarRocks: 同样不支持动态 SQL，替代方案完全相同
--   ClickHouse: 不支持。但 clickhouse-client 支持参数化查询
--   BigQuery:  支持 Scripting(DECLARE/SET/IF/LOOP)，但不是传统存储过程
