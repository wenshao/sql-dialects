-- Apache Doris: Dynamic SQL
--
-- 参考资料:
--   [1] Apache Doris Documentation
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- Doris 不支持服务端动态 SQL / 存储过程
-- ============================================================
-- Apache Doris 是 OLAP 分析引擎，不支持存储过程或动态 SQL

-- ============================================================
-- 应用层替代方案: Python (pymysql，兼容 MySQL 协议)
-- ============================================================
-- import pymysql
-- conn = pymysql.connect(host='localhost', port=9030, user='root', db='mydb')
-- cursor = conn.cursor()
--
-- # 参数化查询（防止 SQL 注入）
-- cursor.execute('SELECT * FROM users WHERE age > %s AND status = %s', (18, 'active'))
--
-- # 动态表名
-- table = 'users'
-- cursor.execute(f'SELECT COUNT(*) FROM `{table}`')

-- ============================================================
-- PREPARE / EXECUTE (通过 MySQL 兼容协议)
-- ============================================================
-- Doris 兼容 MySQL 协议，支持有限的 PREPARE/EXECUTE
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- 注意：Doris 主要面向 OLAP 分析场景
-- 注意：兼容 MySQL 协议，部分 PREPARE 功能可用
-- 注意：推荐在应用层处理动态 SQL
-- 限制：无存储过程
-- 限制：无 EXECUTE IMMEDIATE
