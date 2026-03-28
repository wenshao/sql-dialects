# YugabyteDB: 迁移速查表

> 参考资料:
> - [YugabyteDB Documentation](https://docs.yugabyte.com/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## 七、数据类型映射（从 PostgreSQL/MySQL 到 YugabyteDB）

PostgreSQL → YugabyteDB: 高度兼容
  INT → INT, TEXT → TEXT, JSONB → JSONB,
  SERIAL → SERIAL (全局序列), BOOLEAN → BOOLEAN,
  ARRAY → ARRAY, UUID → UUID
MySQL → YugabyteDB:
  INT → INTEGER, VARCHAR(n) → VARCHAR(n),
  DATETIME → TIMESTAMP, TINYINT(1) → BOOLEAN,
  AUTO_INCREMENT → SERIAL, JSON → JSONB,
  ENUM → VARCHAR + CHECK

八、函数等价映射
MySQL → YugabyteDB:
  IFNULL → COALESCE, NOW() → NOW(),
  DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_DATE,
  CONCAT(a,b) → a || b, GROUP_CONCAT → STRING_AGG

九、常见陷阱补充
  分布式事务延迟高于单节点 PostgreSQL
  选择合适的分片键避免热点（推荐 UUID/HASH 分片）
  COLOCATION 策略: 将小表放在同一 Tablet 优化 JOIN
  部分 DDL 操作需要在线不可用（如添加主键）
  Tablet splitting 影响性能
  二级索引是全局的（分布式索引），影响写入性能
  部分 PostgreSQL 扩展不支持

十、NULL 处理: 与 PostgreSQL 相同
COALESCE(a, b, c); NULLIF(a, b);
IS DISTINCT FROM / IS NOT DISTINCT FROM

十一、分页语法
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

十二、YCQL API (Cassandra 兼容)
YugabyteDB 还提供 YCQL API (兼容 Cassandra)
适合宽列/时序数据场景
