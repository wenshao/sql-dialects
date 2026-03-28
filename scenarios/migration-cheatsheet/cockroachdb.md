# CockroachDB: 迁移速查表

> 参考资料:
> - [CockroachDB Documentation - Migration](https://www.cockroachlabs.com/docs/stable/migration-overview)
> - [CockroachDB SQL Reference](https://www.cockroachlabs.com/docs/stable/sql-statements)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## 七、数据类型映射（从 PostgreSQL/MySQL 到 CockroachDB）

PostgreSQL → CockroachDB: 高度兼容
  INTEGER → INT/INT8, TEXT → STRING, SERIAL → INT DEFAULT unique_rowid(),
  BOOLEAN → BOOL, JSONB → JSONB, UUID → UUID,
  TIMESTAMPTZ → TIMESTAMPTZ, ARRAY → ARRAY,
  BYTEA → BYTES, NUMERIC → DECIMAL
MySQL → CockroachDB:
  INT → INT, BIGINT → INT8, FLOAT → FLOAT,
  DOUBLE → FLOAT8, VARCHAR(n) → STRING/VARCHAR(n),
  TEXT → STRING, DATETIME → TIMESTAMP,
  DATE → DATE, DECIMAL(p,s) → DECIMAL(p,s),
  BOOLEAN → BOOL, AUTO_INCREMENT → INT DEFAULT unique_rowid(),
  JSON → JSONB, ENUM → ENUM (CockroachDB 支持)

八、函数等价映射
MySQL → CockroachDB:
  IFNULL → COALESCE, NOW() → NOW(),
  DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_TIMESTAMP,
  CONCAT(a,b) → a || b, GROUP_CONCAT → STRING_AGG,
  LIMIT → LIMIT

九、常见陷阱补充
  分布式事务（延迟高于单节点 PostgreSQL）
  SERIAL 使用 unique_rowid() 而非序列（不连续）
  推荐 UUID 避免热点: gen_random_uuid()
  部分 PostgreSQL 语法不支持 (LISTEN/NOTIFY, 部分扩展)
  跨区域部署时延迟敏感
  无全表扫描的排他锁
  IMPORT/EXPORT 命令批量数据迁移

十、NULL 处理: 与 PostgreSQL 相同
COALESCE(a, b, c); NULLIF(a, b);
IS DISTINCT FROM / IS NOT DISTINCT FROM

十一、分页语法
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

十二、数据分布
ALTER TABLE t CONFIGURE ZONE USING ...;             -- 区域配置
分片策略自动管理（Range-based sharding）
