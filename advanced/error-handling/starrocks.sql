-- StarRocks: Error Handling
--
-- 参考资料:
--   [1] StarRocks Documentation
--       https://docs.starrocks.io/docs/sql-reference/

-- ============================================================
-- StarRocks 不支持服务端错误处理
-- ============================================================
-- StarRocks 不支持存储过程或异常处理

-- ============================================================
-- 应用层替代方案 (Python/pymysql)
-- ============================================================
-- import pymysql
--
-- conn = pymysql.connect(host='localhost', port=9030,
--                        user='root', database='test')
-- cursor = conn.cursor()
--
-- try:
--     cursor.execute('INSERT INTO users VALUES(1, "test")')
-- except pymysql.IntegrityError:
--     print('Constraint violation')
-- except pymysql.ProgrammingError as e:
--     print(f'SQL error: {e}')
-- except pymysql.OperationalError as e:
--     print(f'Operational error: {e}')

-- ============================================================
-- 应用层替代方案 (Java/JDBC)
-- ============================================================
-- try {
--     Statement stmt = conn.createStatement();
--     stmt.execute("INSERT INTO users VALUES(1, 'test')");
-- } catch (SQLException e) {
--     System.err.println("Error code: " + e.getErrorCode());
--     System.err.println("Message: " + e.getMessage());
-- }

-- ============================================================
-- SQL 层面的错误避免
-- ============================================================
-- IF NOT EXISTS / IF EXISTS 防止常见 DDL 错误
CREATE TABLE IF NOT EXISTS users (id INT, name VARCHAR(100))
DISTRIBUTED BY HASH(id) BUCKETS 8;

DROP TABLE IF EXISTS temp_table;
CREATE DATABASE IF NOT EXISTS analytics;

-- ============================================================
-- 数据导入时的错误容忍
-- ============================================================
-- Stream Load 支持设置错误容忍率
-- curl -X PUT -H "max_filter_ratio:0.1" \
--   -T data.csv \
--   http://host:8030/api/db/table/_stream_load

-- Broker Load 错误容忍配置
-- LOAD LABEL db.label_1
-- (DATA INFILE("hdfs://path/data.csv")
--  INTO TABLE users
--  COLUMNS TERMINATED BY ",")
-- PROPERTIES ("max_filter_ratio" = "0.1");

-- ============================================================
-- 常见错误场景
-- ============================================================
-- 1. 表不存在: ERROR 1064 - Unknown table
-- 2. 列类型不匹配: ERROR 1064 - Type mismatch
-- 3. 内存不足: ERROR 1064 - Memory limit exceeded
-- 4. 副本不足: ERROR 1064 - Tablet not available

-- 注意：StarRocks 兼容 MySQL 协议，使用 MySQL 客户端连接
-- 注意：Stream Load 和 Broker Load 支持 max_filter_ratio 容错
-- 限制：无存储过程或异常处理语法
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
