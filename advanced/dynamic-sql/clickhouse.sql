-- ClickHouse: Dynamic SQL
--
-- 参考资料:
--   [1] ClickHouse Documentation - SQL Statements
--       https://clickhouse.com/docs/en/sql-reference/statements
--   [2] ClickHouse Documentation - system.query_log
--       https://clickhouse.com/docs/en/operations/system-tables/query_log

-- ============================================================
-- ClickHouse 没有传统的动态 SQL / 存储过程
-- ============================================================
-- ClickHouse 是 OLAP 引擎，不支持存储过程、PREPARE/EXECUTE
-- 动态 SQL 需在应用层或通过 clickhouse-client 实现

-- ============================================================
-- 应用层替代方案: clickhouse-client
-- ============================================================
-- 使用 --query 参数传递动态 SQL
-- clickhouse-client --query="SELECT * FROM users WHERE age > 18"
-- clickhouse-client --query="$(cat dynamic_query.sql)"

-- ============================================================
-- 应用层替代方案: Python (clickhouse-driver)
-- ============================================================
-- from clickhouse_driver import Client
-- client = Client('localhost')
--
-- # 参数化查询（防止 SQL 注入）
-- result = client.execute(
--     'SELECT * FROM users WHERE age > %(min_age)s AND status = %(status)s',
--     {'min_age': 18, 'status': 'active'}
-- )
--
-- # 动态表名（需要验证）
-- table = 'users'
-- result = client.execute(f'SELECT COUNT(*) FROM {table}')

-- ============================================================
-- 应用层替代方案: HTTP API
-- ============================================================
-- curl 'http://localhost:8123/?query=SELECT+count()+FROM+users'
-- curl 'http://localhost:8123/' --data-binary "SELECT * FROM users WHERE id = {id:UInt64}" \
--      --data-urlencode "param_id=42"

-- ============================================================
-- ClickHouse 参数化查询 (HTTP 接口)
-- ============================================================
-- ClickHouse HTTP 接口支持参数化查询:
-- SELECT * FROM users WHERE id = {id:UInt64}
-- SELECT * FROM users WHERE name = {name:String}
-- 参数通过 URL 参数 param_name=value 传递

-- ============================================================
-- 使用字典 (Dictionary) 替代部分动态查询场景
-- ============================================================
CREATE DICTIONARY user_dict (
    id UInt64,
    username String,
    email String
) PRIMARY KEY id
SOURCE(CLICKHOUSE(TABLE 'users'))
LAYOUT(FLAT())
LIFETIME(MIN 300 MAX 600);

-- 使用字典查找（替代动态查询）
SELECT dictGet('user_dict', 'username', toUInt64(42));

-- 注意：ClickHouse 不支持存储过程或服务端动态 SQL
-- 注意：所有动态 SQL 必须在应用层实现
-- 注意：HTTP 接口支持参数化查询 ({name:Type} 语法)
-- 注意：clickhouse-client 支持 --param_name=value 参数
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：无存储过程 / 函数（用户定义函数除外）
