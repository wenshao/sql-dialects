-- CockroachDB: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] CockroachDB Documentation - Migration
--       https://www.cockroachlabs.com/docs/stable/migration-overview
--   [2] CockroachDB SQL Reference
--       https://www.cockroachlabs.com/docs/stable/sql-statements

-- 一、数据类型: 与 PostgreSQL 高度兼容
--   INT→INT/INT8, FLOAT→FLOAT/FLOAT8, VARCHAR→VARCHAR/STRING,
--   BOOLEAN→BOOL, TIMESTAMP→TIMESTAMP/TIMESTAMPTZ,
--   JSON→JSONB, UUID→UUID, SERIAL→INT DEFAULT unique_rowid()
-- 二、函数: 与 PostgreSQL 基本兼容
--   差异: 部分PostgreSQL扩展函数不支持, 无LATERAL(部分版本),
--   gen_random_uuid()可用
-- 三、陷阱: 分布式事务(高延迟写入), SERIAL使用unique_rowid()而非序列,
--   无全表扫描的排他锁, 部分PostgreSQL语法不支持(如LISTEN/NOTIFY),
--   跨区域部署时延迟敏感
-- 四、自增: INT DEFAULT unique_rowid() 或 UUID DEFAULT gen_random_uuid()
-- 五、日期: NOW(); CURRENT_DATE; d + INTERVAL '1 day';
--   DATE_PART('day', a-b); TO_CHAR(ts,'YYYY-MM-DD')
--   TO_TIMESTAMP(s,'YYYY-MM-DD HH24:MI:SS'); EXTRACT(YEAR FROM d)
-- 六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTR, REPLACE, POSITION, ||, STRING_AGG

-- ============================================================
-- 七、数据类型映射（从 PostgreSQL/MySQL 到 CockroachDB）
-- ============================================================
-- PostgreSQL → CockroachDB: 高度兼容
--   INTEGER → INT/INT8, TEXT → STRING, SERIAL → INT DEFAULT unique_rowid(),
--   BOOLEAN → BOOL, JSONB → JSONB, UUID → UUID,
--   TIMESTAMPTZ → TIMESTAMPTZ, ARRAY → ARRAY,
--   BYTEA → BYTES, NUMERIC → DECIMAL
-- MySQL → CockroachDB:
--   INT → INT, BIGINT → INT8, FLOAT → FLOAT,
--   DOUBLE → FLOAT8, VARCHAR(n) → STRING/VARCHAR(n),
--   TEXT → STRING, DATETIME → TIMESTAMP,
--   DATE → DATE, DECIMAL(p,s) → DECIMAL(p,s),
--   BOOLEAN → BOOL, AUTO_INCREMENT → INT DEFAULT unique_rowid(),
--   JSON → JSONB, ENUM → ENUM (CockroachDB 支持)

-- 八、函数等价映射
-- MySQL → CockroachDB:
--   IFNULL → COALESCE, NOW() → NOW(),
--   DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_TIMESTAMP,
--   CONCAT(a,b) → a || b, GROUP_CONCAT → STRING_AGG,
--   LIMIT → LIMIT

-- 九、常见陷阱补充
--   分布式事务（延迟高于单节点 PostgreSQL）
--   SERIAL 使用 unique_rowid() 而非序列（不连续）
--   推荐 UUID 避免热点: gen_random_uuid()
--   部分 PostgreSQL 语法不支持 (LISTEN/NOTIFY, 部分扩展)
--   跨区域部署时延迟敏感
--   无全表扫描的排他锁
--   IMPORT/EXPORT 命令批量数据迁移

-- 十、NULL 处理: 与 PostgreSQL 相同
-- COALESCE(a, b, c); NULLIF(a, b);
-- IS DISTINCT FROM / IS NOT DISTINCT FROM

-- 十一、分页语法
-- SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- 十二、数据分布
-- ALTER TABLE t CONFIGURE ZONE USING ...;             -- 区域配置
-- 分片策略自动管理（Range-based sharding）
