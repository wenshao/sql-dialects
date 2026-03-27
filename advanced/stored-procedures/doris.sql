-- Apache Doris: 存储过程
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- Doris 不支持存储过程
-- 以下是替代方案

-- ============================================================
-- 替代方案一：使用客户端脚本
-- ============================================================

-- 在 Python / Java / Shell 中编写逻辑
-- 通过 MySQL 协议连接 Doris 执行 SQL

-- Python 示例（伪代码）:
-- conn = pymysql.connect(host='fe_host', port=9030, user='root', db='mydb')
-- cursor = conn.cursor()
-- cursor.execute("SELECT COUNT(*) FROM users WHERE status = 1")
-- count = cursor.fetchone()[0]
-- if count > 0:
--     cursor.execute("INSERT INTO users_archive SELECT * FROM users WHERE status = 0")
--     cursor.execute("DELETE FROM users WHERE status = 0")
-- conn.commit()

-- ============================================================
-- 替代方案二：使用 INSERT INTO ... SELECT 实现 ETL
-- ============================================================

-- 数据清洗
INSERT INTO users_clean
SELECT id, TRIM(username), LOWER(email), COALESCE(age, 0)
FROM users_raw;

-- 增量同步
INSERT INTO users (id, username, email, age)
SELECT id, username, email, age
FROM staging_users
WHERE updated_at > '2024-01-01';

-- ============================================================
-- 替代方案三：使用 CTAS 实现数据转换
-- ============================================================

CREATE TABLE users_enriched AS
SELECT u.*, COUNT(o.id) AS order_count, SUM(o.amount) AS total_spend
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username, u.email, u.age;

-- ============================================================
-- 替代方案四：使用外部调度工具
-- ============================================================

-- Apache Airflow / DolphinScheduler / Azkaban
-- 编排多个 SQL 任务，实现复杂 ETL 流程

-- ============================================================
-- 变量和会话设置
-- ============================================================

-- 设置会话变量（替代存储过程中的变量）
SET exec_mem_limit = 8589934592;
SET query_timeout = 3600;
SET parallel_fragment_exec_instance_num = 8;

-- 注意：Doris 不支持存储过程
-- 注意：不支持 UDF（用户自定义函数）的 SQL 定义
-- 注意：支持 Java UDF（2.0+）和 Remote UDF
-- 注意：复杂逻辑推荐在应用层或调度工具中实现
