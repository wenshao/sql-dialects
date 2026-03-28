# Trino: 迁移速查表

> 参考资料:
> - [Trino Documentation](https://trino.io/docs/current/)
> - [Trino SQL Syntax](https://trino.io/docs/current/sql.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 七、数据类型映射（从 MySQL/PostgreSQL/Hive 到 Trino）

MySQL → Trino:
  INT → INTEGER, BIGINT → BIGINT, FLOAT → REAL,
  DOUBLE → DOUBLE, DECIMAL(p,s) → DECIMAL(p,s),
  VARCHAR(n) → VARCHAR, TEXT → VARCHAR,
  DATETIME → TIMESTAMP, DATE → DATE,
  BOOLEAN → BOOLEAN, JSON → JSON,
  BLOB → VARBINARY, AUTO_INCREMENT → 取决于connector
PostgreSQL → Trino:
  INTEGER → INTEGER, TEXT → VARCHAR,
  SERIAL → 取决于connector, BOOLEAN → BOOLEAN,
  JSONB → JSON, BYTEA → VARBINARY,
  ARRAY → ARRAY(T)
Hive → Trino: 基本兼容
  STRING → VARCHAR, MAP → MAP(K,V),
  ARRAY → ARRAY(T), STRUCT → ROW(...)

八、函数等价映射
MySQL → Trino:
  IFNULL → COALESCE, NOW() → now()/current_timestamp,
  DATE_FORMAT → format_datetime (注意格式码不同),
  CONCAT(a,b) → concat(a,b) 或 a||b,
  GROUP_CONCAT → array_join(array_agg(col), ','),
  LIMIT → LIMIT, STR_TO_DATE → date_parse

九、常见陷阱补充
  查询引擎（不存储数据），功能取决于 connector
  部分 connector 不支持 DML (INSERT/UPDATE/DELETE)
  类型系统严格（需显式 CAST）
  区分 catalog.schema.table 三级命名
  无 AUTO_INCREMENT（数据在底层存储）
  EXPLAIN ANALYZE 查看查询计划
  不同 connector 的行为可能不同

十、NULL 处理
COALESCE(a, b, c); NULLIF(a, b);
IF(a IS NULL, b, a);
try(expression);                                   -- 表达式失败返回 NULL

十一、分页语法
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

十二、日期格式码 (Java DateTimeFormatter 格式)
yyyy=年, MM=月, dd=日, HH=24时, mm=分, ss=秒
**注意:** date_parse 使用 strftime 格式 (%Y/%m/%d)
