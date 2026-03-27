-- StarRocks: Dynamic SQL
--
-- 参考资料:
--   [1] StarRocks Documentation - SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/

-- ============================================================
-- PREPARE / EXECUTE (MySQL 兼容协议)
-- ============================================================
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- 应用层替代方案
-- ============================================================
-- StarRocks 兼容 MySQL 协议，可使用 MySQL 驱动
-- import pymysql
-- conn = pymysql.connect(host='localhost', port=9030, user='root', db='mydb')
-- cursor = conn.cursor()
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))

-- 注意：StarRocks 兼容 MySQL 协议
-- 注意：PREPARE/EXECUTE 通过 MySQL 协议兼容层支持
-- 限制：无存储过程
-- 限制：无 EXECUTE IMMEDIATE
-- 限制：面向 OLAP 分析场景
