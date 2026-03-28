# Spanner: 迁移速查表

> 参考资料:
> - [Cloud Spanner SQL Reference](https://cloud.google.com/spanner/docs/reference/standard-sql/)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 七、数据类型映射（从 MySQL/PostgreSQL/Oracle 到 Spanner）

MySQL → Spanner:
- INT → INT64, BIGINT → INT64, FLOAT → FLOAT64,
- DOUBLE → FLOAT64, DECIMAL → NUMERIC,
- VARCHAR(n) → STRING(n), TEXT → STRING(MAX),
- DATETIME → TIMESTAMP, DATE → DATE,
- BOOLEAN → BOOL, BLOB → BYTES(MAX),
- JSON → JSON, AUTO_INCREMENT → 不支持,
- ARRAY → ARRAY<T> (原生支持)
PostgreSQL → Spanner:
- INTEGER → INT64, TEXT → STRING(MAX),
- SERIAL → 不支持, BOOLEAN → BOOL,
- JSONB → JSON, BYTEA → BYTES(MAX),
- ARRAY → ARRAY<T>
Oracle → Spanner:
- NUMBER → INT64/NUMERIC, VARCHAR2 → STRING,
- CLOB → STRING(MAX), DATE → TIMESTAMP,
- SEQUENCE → bit_reverse(SEQUENCE)


### 八、函数等价映射

MySQL → Spanner:
- IFNULL → IFNULL/COALESCE, NOW() → CURRENT_TIMESTAMP(),
- DATE_FORMAT → FORMAT_TIMESTAMP, CONCAT → CONCAT,
- GROUP_CONCAT → STRING_AGG, LIMIT → LIMIT


### 九、常见陷阱补充

  - 全球分布式数据库（强一致性）
  - 主键设计很关键（避免热点，不建议自增主键）
  - 推荐 UUID 或 bit-reversed 序列
  - DDL 和 DML 必须在不同事务中
  - interleaved tables 是 Spanner 特色（父子表物理共存）
  - 无 AUTO_INCREMENT
  - SEQUENCE 只在 GoogleSQL 方言支持
  - 读写事务 vs 只读事务 性能差异大


### 十、NULL 处理

IFNULL(a, b); COALESCE(a, b, c);
NULLIF(a, b);
IF(a IS NULL, b, a);


### 十一、分页语法

SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;


### 十二、Interleaved Table 示例

CREATE TABLE Orders (
  - CustomerId INT64, OrderId INT64, ...
) PRIMARY KEY (CustomerId, OrderId),
  - INTERLEAVE IN PARENT Customers ON DELETE CASCADE;
