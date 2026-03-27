-- Materialize: 动态 SQL (Dynamic SQL)
--
-- 参考资料:
--   [1] Materialize Documentation - SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize Documentation - PREPARE
--       https://materialize.com/docs/sql/prepare/
--   [3] Materialize Documentation - EXECUTE
--       https://materialize.com/docs/sql/execute/
--   [4] Materialize Documentation - PostgreSQL Compatibility
--       https://materialize.com/docs/connect/

-- ============================================================
-- 1. PREPARE / EXECUTE / DEALLOCATE (PostgreSQL 兼容)
-- ============================================================

PREPARE user_by_age(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_by_age(25);
DEALLOCATE user_by_age;
DEALLOCATE ALL;

-- Materialize 的 PREPARE 继承自 PostgreSQL 语义:
--   查询在 PREPARE 时解析、类型检查，EXECUTE 时执行。
--   占位符使用 $1, $2, ... 位置参数（与 PostgreSQL 一致）。
--
-- 差异:
--   PostgreSQL: PREPARE 会缓存执行计划（custom/generic plan 切换）
--   Materialize: 面向增量计算，数据维护在内存/磁盘索引中，
--                PREPARE 更多是语法兼容，执行策略与 PG 不同。

-- ============================================================
-- 2. 动态查询构建: 应用层模式 (PostgreSQL 驱动)
-- ============================================================

-- Materialize 兼容 PostgreSQL wire protocol，可使用 psycopg2/psycopg3 驱动
-- import psycopg2
-- conn = psycopg2.connect("host=localhost port=6875 dbname=materialize")
-- cursor = conn.cursor()
--
-- -- 参数化查询（防注入）
-- cursor.execute('SELECT * FROM users WHERE age > %s', (18,))
--
-- -- 动态表名（需要手动引用，psycopg2.sql 模块）
-- from psycopg2 import sql
-- query = sql.SQL('SELECT * FROM {} WHERE age > %s').format(
--     sql.Identifier('users')
-- )
-- cursor.execute(query, (18,))

-- psycopg2.sql 模块提供了安全的标识符引用:
--   sql.Identifier('table')  → "table"（自动加引号）
--   sql.Literal('value')     → 'value'（自动转义）
--   sql.SQL('...')           → 原始 SQL 片段（不转义）

-- ============================================================
-- 3. SQL 注入防护
-- ============================================================

-- 正确: 使用参数化查询
-- cursor.execute('SELECT * FROM users WHERE name = %s', (user_input,))

-- 错误（危险）: 字符串拼接
-- cursor.execute(f"SELECT * FROM users WHERE name = '{user_input}'")

-- 动态表名/列名: 使用 psycopg2.sql 模块
-- from psycopg2 import sql
-- safe_query = sql.SQL('SELECT {} FROM {}').format(
--     sql.Identifier(column_name),   -- 安全的标识符引用
--     sql.Identifier(table_name)
-- )

-- 设计原则:
--   值参数 → 使用 %s 占位符（PREPARE 参数或驱动参数化）
--   标识符 → 使用 psycopg2.sql.Identifier 或手动双引号

-- ============================================================
-- 4. 流式查询与动态 SQL 结合
-- ============================================================

-- Materialize 的核心能力: SUBSCRIBE（增量流式输出）
-- SUBSCRIBE 本身不支持参数化，但可以结合 PREPARE 使用

PREPARE subscribe_users(INT) AS
    SUBSCRIBE (SELECT * FROM users WHERE age > $1);
EXECUTE subscribe_users(25);
DEALLOCATE subscribe_users;

-- 应用层动态构建 SUBSCRIBE:
-- import psycopg2
-- from psycopg2 import sql
-- conn = psycopg2.connect("host=localhost port=6875 dbname=materialize")
-- cursor = conn.cursor()
--
-- min_age = 25
-- cursor.execute(sql.SQL('SUBSCRIBE (SELECT * FROM {} WHERE age > {})').format(
--     sql.Identifier('users'),
--     sql.Literal(min_age)
-- ))
-- for row in cursor:
--     print(row)  -- 持续接收变更流

-- ============================================================
-- 5. 动态 DDL: 通过应用层执行
-- ============================================================

-- Materialize 支持的 DDL 可通过驱动动态执行
-- cursor.execute('CREATE SOURCE kafka_users FROM KAFKA ...')
-- cursor.execute('CREATE MATERIALIZED VIEW active_users AS SELECT * FROM users WHERE status = %s', ('active',))
-- 注意: DDL 语句通常不使用参数化，需在应用层拼接时注意注入防护

-- ============================================================
-- 6. Materialize 特有: 增量计算视角下的动态 SQL
-- ============================================================

-- Materialize 维护物化视图的增量更新，与传统数据库的动态 SQL 场景不同:
--   传统数据库: 动态 SQL → 每次执行时优化查询计划
--   Materialize: 数据在源头变更时自动更新索引，查询是"读取"而非"计算"
--
-- 因此在 Materialize 中，动态 SQL 的主要用途:
--   (1) 临时探索性查询 (ad-hoc query)
--   (2) 动态创建/管理 source 和 view
--   (3) 参数化的 SUBSCRIBE 流式订阅

-- ============================================================
-- 7. 横向对比
-- ============================================================

-- 1. 协议兼容性:
--   Materialize:  PostgreSQL wire protocol
--   CockroachDB:  PostgreSQL wire protocol
--   Hologres:     PostgreSQL wire protocol
--   StarRocks:    MySQL wire protocol
--
-- 2. 服务端动态 SQL:
--   Materialize:  PREPARE/EXECUTE（兼容 PG，无 PL/pgSQL）
--   PostgreSQL:   PREPARE/EXECUTE + PL/pgSQL EXECUTE
--   MySQL:        PREPARE/EXECUTE（无匿名块）
--   Hologres:     PREPARE/EXECUTE（有限 PL/pgSQL）
--
-- 3. 流式查询:
--   Materialize:  SUBSCRIBE（增量输出，独有特性）
--   ksqlDB:       EMIT CHANGES（Kafka 流）
--   Flink SQL:    动态表（基于时间窗口）

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) PostgreSQL wire protocol 兼容是极大的生态优势:
--     Materialize 直接复用 psycopg2、pgjdbc、JDBC 生态。
--     动态 SQL 的应用层模式（参数化查询、标识符引用）开箱即用。
--
-- (2) 增量计算引擎中，"动态 SQL"的语义需要重新定义:
--     传统数据库的动态 SQL = 运行时构造查询并执行。
--     增量计算引擎中，查询结果持续更新，动态性体现在 source/view 管理。
--
-- (3) SUBSCRIBE + PREPARE 的组合设计:
--     允许参数化流式订阅，是流处理 SQL 引擎的优秀实践。

-- ============================================================
-- 9. 版本与限制
-- ============================================================
-- Materialize 0.x:  PREPARE / EXECUTE / DEALLOCATE 支持
-- Materialize 0.x:  PostgreSQL wire protocol 兼容
-- 限制:              无存储过程 / PL/pgSQL
-- 限制:              无 EXECUTE IMMEDIATE（服务端动态字符串执行）
-- 限制:              面向增量计算，动态 SQL 场景有限
-- 限制:              SUBSCRIBE 不支持所有 SQL 语句类型
