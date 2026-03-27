-- Apache Impala: Dynamic SQL
--
-- 参考资料:
--   [1] Apache Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html

-- ============================================================
-- Impala 不支持服务端动态 SQL
-- ============================================================
-- Impala 不支持存储过程或动态 SQL

-- ============================================================
-- 应用层替代方案: impala-shell 变量
-- ============================================================
-- impala-shell --var=table_name=users -q "SELECT COUNT(*) FROM ${var:table_name}"

-- ============================================================
-- 应用层替代方案: Python (impyla)
-- ============================================================
-- from impala.dbapi import connect
-- conn = connect(host='localhost', port=21050)
-- cursor = conn.cursor()
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))
--
-- # 动态表名
-- table = 'users'
-- cursor.execute(f'SELECT COUNT(*) FROM {table}')

-- ============================================================
-- JDBC 替代方案
-- ============================================================
-- PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
-- ps.setInt(1, 42);
-- ResultSet rs = ps.executeQuery();

-- 注意：Impala 面向交互式 OLAP，不支持存储过程
-- 注意：通过 impala-shell --var 实现变量替换
-- 注意：推荐在应用层（Python/Java）实现动态 SQL
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：无存储过程
