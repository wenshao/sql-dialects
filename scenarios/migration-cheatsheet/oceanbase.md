# OceanBase: 迁移速查表

> 参考资料:
> - [OceanBase Documentation](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## 七、数据类型映射

MySQL → OceanBase (MySQL模式): 高度兼容
  所有 MySQL 数据类型基本直接支持
  JSON → JSON, GEOMETRY → 部分支持
Oracle → OceanBase (Oracle模式): 高度兼容
  NUMBER → NUMBER, VARCHAR2 → VARCHAR2, CLOB → CLOB,
  DATE → DATE, TIMESTAMP → TIMESTAMP, BLOB → BLOB

八、函数等价映射
MySQL模式: 与 MySQL 完全兼容
  IFNULL, NOW(), DATE_FORMAT, CONCAT, GROUP_CONCAT, LIMIT
Oracle模式: 与 Oracle 兼容
  NVL, SYSDATE, TO_CHAR, TO_DATE, ||, LISTAGG, ROWNUM

九、常见陷阱补充
  分布式架构，多租户（每个租户独立模式）
  PRIMARY KEY 同时决定数据分布
  分区表是核心，选择合适的分区策略
  MySQL 模式和 Oracle 模式语法不可混用
  OMS (OceanBase Migration Service) 辅助迁移
  ob_admin 工具管理集群
  兼容性不是 100%（部分高级特性有差异）

十、NULL 处理
MySQL模式: IFNULL(a,b); COALESCE(a,b,c); NULLIF(a,b); <=>
Oracle模式: NVL(a,b); NVL2(a,b,c); COALESCE(a,b,c); DECODE

十一、分页语法
MySQL模式: SELECT * FROM t LIMIT 10 OFFSET 20;
Oracle模式: SELECT * FROM t FETCH FIRST 10 ROWS ONLY;
  或 WHERE ROWNUM <= 10;
