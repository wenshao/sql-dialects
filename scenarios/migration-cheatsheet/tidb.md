# TiDB: 迁移速查表

> 参考资料:
> - [TiDB Documentation - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB Migration Guide](https://docs.pingcap.com/tidb/stable/migration-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 七、数据类型映射（从 MySQL 到 TiDB）

MySQL → TiDB: 高度兼容
  所有 MySQL 数据类型基本直接支持
  INT → INT, BIGINT → BIGINT, FLOAT → FLOAT,
  DOUBLE → DOUBLE, DECIMAL → DECIMAL,
  VARCHAR → VARCHAR, TEXT → TEXT, BLOB → BLOB,
  DATE → DATE, DATETIME → DATETIME, TIMESTAMP → TIMESTAMP,
  BOOLEAN → BOOLEAN (TINYINT(1) 别名),
  JSON → JSON, ENUM → ENUM, SET → SET,
  AUTO_INCREMENT → AUTO_INCREMENT (行为不同!)
差异:
  AUTO_INCREMENT 不保证连续（分布式自增）
  推荐 AUTO_RANDOM 避免写入热点

八、函数等价映射
MySQL → TiDB: 基本完全兼容
  IFNULL, NOW(), DATE_FORMAT, STR_TO_DATE,
  CONCAT, GROUP_CONCAT, LIMIT, OFFSET
差异:
  部分 MySQL 特有函数可能不支持
  窗口函数完全支持

九、常见陷阱补充
  分布式架构（大事务有限制，默认 100MB）
  AUTO_INCREMENT 不保证连续（使用分布式自增）
  推荐 AUTO_RANDOM 主键避免热点
  TiKV 存储引擎 vs InnoDB 行为差异
  乐观/悲观事务模式选择（默认悲观 4.0+）
  热点问题需要合理设计主键
  不支持外键约束
  不支持 FULLTEXT 索引
  临时表语法差异
  TiFlash 列存副本加速分析查询

十、NULL 处理
IFNULL(a, b); COALESCE(a, b, c);
NULLIF(a, b); <=> (NULL安全等于);
ISNULL(a) 返回 0 或 1

十一、分页语法
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;    -- 与 MySQL 相同
