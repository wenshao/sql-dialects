-- Hologres: 动态 SQL (Dynamic SQL)
--
-- 参考资料:
--   [1] Hologres Documentation - SQL Reference
--       https://www.alibabacloud.com/help/en/hologres/
--   [2] Hologres Documentation - PL/pgSQL (Procedural Language)
--       https://www.alibabacloud.com/help/en/hologres/developer-guide/plpgsql-procedural-language
--   [3] Hologres Documentation - PostgreSQL Compatibility
--       https://www.alibabacloud.com/help/en/hologres/developer-guide/postgresql-compatibility
--   [4] Hologres Documentation - Stored Procedures
--       https://www.alibabacloud.com/help/en/hologres/developer-guide/stored-procedures

-- ============================================================
-- 1. PREPARE / EXECUTE / DEALLOCATE (PostgreSQL 兼容)
-- ============================================================

PREPARE user_by_age(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_by_age(25);
DEALLOCATE user_by_age;
DEALLOCATE ALL;

-- 多参数预编译
PREPARE search_users(TEXT, INT) AS
    SELECT * FROM users WHERE status = $1 AND age >= $2;
EXECUTE search_users('active', 18);
DEALLOCATE search_users;

-- Hologres 的 PREPARE 行为与 PostgreSQL 一致:
--   $1, $2, ... 位置参数用于值绑定。
--   PREPARE 时解析、类型检查；EXECUTE 时绑定参数并执行。
--
-- Hologres 优化器（自研）会根据参数值生成查询计划，
-- 但不支持 PostgreSQL 的 plan_cache_mode 参数。

-- ============================================================
-- 2. PL/pgSQL 动态 SQL (有限支持)
-- ============================================================

-- Hologres 兼容部分 PostgreSQL PL/pgSQL 语法
-- 支持 EXECUTE ... USING 进行参数化动态 SQL

-- 示例: 动态查询函数
-- CREATE OR REPLACE FUNCTION dynamic_query(p_table TEXT, p_min_age INT)
-- RETURNS SETOF RECORD AS $$
-- BEGIN
--     RETURN QUERY EXECUTE
--         'SELECT * FROM ' || quote_ident(p_table) || ' WHERE age >= $1'
--         USING p_min_age;
-- END; $$ LANGUAGE plpgsql;

-- PL/pgSQL 支持范围:
--   ✓ 基本 EXECUTE 语句（动态 SQL 字符串执行）
--   ✓ EXECUTE ... USING（参数化动态 SQL）
--   ✓ EXECUTE ... INTO（结果存入变量）
--   ✓ quote_ident() / quote_literal()（标识符/字面量转义）
--   ✓ 基本控制流（IF/LOOP/WHILE/FOR）
--   ✗ 部分 PL/pgSQL 高级特性（如 REFCURSOR 动态游标）

-- ============================================================
-- 3. SQL 注入防护
-- ============================================================

-- 正确: 使用 quote_ident() 引用标识符
-- EXECUTE 'SELECT * FROM ' || quote_ident(p_table);
-- quote_ident('users')       → users
-- quote_ident('order items') → "order items"（含空格时加引号）
-- quote_ident('drop')        → "drop"（保留字时加引号）

-- 正确: 使用 quote_literal() 转义字面量
-- EXECUTE 'WHERE name = ' || quote_literal(p_name);
-- quote_literal('it''s')     → 'it''s'
-- quote_literal('O"Brien')   → 'O"Brien'

-- 正确: 使用 EXECUTE ... USING（最安全的参数化方式）
-- EXECUTE 'SELECT * FROM users WHERE name = $1' USING p_name;

-- 错误（危险）: 直接拼接用户输入
-- EXECUTE 'SELECT * FROM ' || p_table || ' WHERE name = ''' || p_name || '''';

-- 防护策略优先级:
--   1. EXECUTE ... USING（参数化，最佳）
--   2. quote_ident() + quote_literal()（标识符+字面量转义）
--   3. 应用层参数化查询（psycopg2 %s 占位符）

-- ============================================================
-- 4. 动态 DDL: 分区表管理
-- ============================================================

-- Hologres 常见场景: 动态创建分区表
-- CREATE OR REPLACE FUNCTION create_daily_partition(p_date DATE)
-- RETURNS VOID AS $$
-- BEGIN
--     EXECUTE format(
--         'CREATE TABLE IF NOT EXISTS orders_%s PARTITION OF orders
--          FOR VALUES FROM (%L) TO (%L)',
--         to_char(p_date, 'YYYYMMDD'),
--         p_date,
--         p_date + INTERVAL '1 day'
--     );
-- END; $$ LANGUAGE plpgsql;

-- Hologres 分区表特性:
--   支持多级分区（按日期+地域等）。
--   动态分区可结合 Hologres 的分区自动管理能力。
--   分区 DDL 可通过调度系统定期调用。

-- ============================================================
-- 5. 应用层替代方案: Python (psycopg2)
-- ============================================================

-- import psycopg2
-- conn = psycopg2.connect(
--     host='hgprecn-cn-xxx.hologres.aliyuncs.com',
--     port=80, dbname='mydb', user='access_id', password='access_key'
-- )
-- cursor = conn.cursor()
--
-- -- 参数化查询（防注入）
-- cursor.execute('SELECT * FROM users WHERE age > %s AND status = %s', (18, 'active'))
--
-- -- 动态表名（安全标识符引用）
-- from psycopg2 import sql
-- query = sql.SQL('SELECT * FROM {} WHERE age > %s').format(
--     sql.Identifier('users')
-- )
-- cursor.execute(query, (18,))
--
-- -- 批量导入（通过 COPY 协议，高效）
-- with open('data.csv', 'r') as f:
--     cursor.copy_expert('COPY users FROM STDIN WITH CSV HEADER', f)

-- ============================================================
-- 6. Hologres 特有: OLAP 场景下的动态 SQL 模式
-- ============================================================

-- (1) 动态创建外部表（Foreign Table）关联 MaxCompute/Dataworks
-- CREATE OR REPLACE FUNCTION create_mc_foreign_table(
--     p_table TEXT, p_mc_project TEXT, p_mc_table TEXT
-- ) RETURNS VOID AS $$
-- BEGIN
--     EXECUTE format(
--         'CREATE FOREIGN TABLE IF NOT EXISTS %I (
--             col1 INT, col2 TEXT
--         ) SERVER odps_server OPTIONS (project_name %L, table_name %L)',
--         p_table, p_mc_project, p_mc_table
--     );
-- END; $$ LANGUAGE plpgsql;

-- (2) 动态物化视图管理
-- EXECUTE format(
--     'CREATE MATERIALIZED VIEW %I AS SELECT ...',
--     view_name
-- );

-- (3) 动态优化: 设置表属性
-- EXECUTE format('CALL set_table_property(%L, %L, %L)',
--     'users', 'distribution_key', 'id');

-- ============================================================
-- 7. 横向对比
-- ============================================================

-- 1. PostgreSQL 生态兼容性:
--   Hologres:     PostgreSQL 协议 + 部分 PL/pgSQL + 自研 OLAP 优化器
--   AlloyDB:      PostgreSQL 协议 + 完整 PL/pgSQL + Google 优化增强
--   CockroachDB:  PostgreSQL 协议 + 有限 PL/pgSQL
--   Aurora PG:    完整 PostgreSQL 兼容
--
-- 2. OLAP vs OLTP 动态 SQL 需求:
--   Hologres (OLAP):  侧重 ETL 管道、分区管理、外部表管理
--   PostgreSQL (OLTP): 侧重事务处理、业务逻辑封装
--   Hologres 不建议在动态 SQL 中执行复杂事务操作
--
-- 3. 存储过程支持:
--   Hologres:    部分 PL/pgSQL（持续完善中）
--   PostgreSQL:  完整 PL/pgSQL
--   MySQL:       自有存储过程语法
--   StarRocks:   不支持存储过程

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) PostgreSQL 协议兼容 + 自研引擎的架构模式:
--     Hologres 复用 PG 的前端解析、协议层（JDBC/ODBC 生态）。
--     后端使用自研的向量化执行引擎和分布式存储。
--     PL/pgSQL 支持是"兼容性"要求，不需要完整实现。
--
-- (2) 外部表 + 动态 SQL 的组合在湖仓架构中极为重要:
--     Hologres 通过外部表访问 MaxCompute、DataHub 等数据源。
--     动态创建/管理外部表是元数据管理的关键操作。
--
-- (3) OLAP 引擎中动态 SQL 的安全考量:
--     多租户场景下，动态 SQL 可能涉及跨租户数据访问。
--     行级安全（Row Level Security）结合动态 SQL 提供细粒度权限控制。

-- ============================================================
-- 9. 版本与限制
-- ============================================================
-- Hologres V1.1:  PREPARE / EXECUTE / DEALLOCATE 支持
-- Hologres V1.3:  部分 PL/pgSQL 支持（EXECUTE ... USING）
-- Hologres V2.0:  增强的存储过程支持
-- 注意:            PL/pgSQL 支持持续完善，部分高级特性可能不可用
-- 注意:            面向 OLAP 场景，不建议在动态 SQL 中执行复杂事务
-- 限制:            不支持 PostgreSQL 的 DO 匿名块（部分版本）
-- 限制:            REFCURSOR 等高级游标特性可能不可用
-- 限制:            plan_cache_mode 等参数在 Hologres 中不可用
