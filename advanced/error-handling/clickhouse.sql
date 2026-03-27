-- ClickHouse: Error Handling
--
-- 参考资料:
--   [1] ClickHouse Documentation - Error Handling
--       https://clickhouse.com/docs/en/sql-reference/statements

-- ============================================================
-- ClickHouse 没有服务端错误处理
-- ============================================================
-- ClickHouse 不支持存储过程或异常处理语法

-- ============================================================
-- 应用层替代方案: Python
-- ============================================================
-- from clickhouse_driver import Client, errors
-- client = Client('localhost')
-- try:
--     client.execute('INSERT INTO users VALUES (1, \'test\')')
-- except errors.ServerException as e:
--     print(f'ClickHouse error code {e.code}: {e.message}')

-- ============================================================
-- SQL 层面的错误避免策略
-- ============================================================
-- 使用 IF EXISTS / IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (id UInt64, name String) ENGINE = MergeTree() ORDER BY id;
DROP TABLE IF EXISTS temp_table;

-- 使用 -OrDefault / -OrNull 聚合函数变体
SELECT sumOrDefault(amount) FROM orders;          -- 无数据返回 0 而非错误
SELECT avgOrNull(amount) FROM orders;             -- 无数据返回 NULL

-- 使用 try* 函数
SELECT tryBase64Decode('invalid-base64');          -- 失败返回空字符串
-- toUInt64OrZero, toFloat64OrNull 等类型转换安全函数
SELECT toUInt64OrZero('not_a_number');             -- 返回 0
SELECT toUInt64OrNull('not_a_number');             -- 返回 NULL

-- 注意：ClickHouse 不支持服务端错误处理
-- 注意：使用 *OrDefault / *OrNull / try* 函数族避免运行时错误
-- 注意：错误处理在应用层实现
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
-- 限制：无 SIGNAL / RAISE
