# BigQuery: 数值类型

> 参考资料:
> - [1] BigQuery SQL Reference - Numeric Types
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#numeric_types


## 1. BigQuery 的数值类型: 极简但覆盖广


INT64:    8 字节有符号整数（唯一的整数类型!）
FLOAT64:  8 字节 IEEE 754 浮点数
NUMERIC:  16 字节精确小数，38 位有效数字，9 位小数
BIGNUMERIC: 32 字节精确小数，76 位有效数字，38 位小数
BOOL:     布尔值（true / false）


```sql
CREATE TABLE examples (
    id        INT64 NOT NULL,
    ratio     FLOAT64,
    price     NUMERIC,            -- 精确到 9 位小数
    big_price BIGNUMERIC,         -- 精确到 38 位小数
    active    BOOL DEFAULT true
);

```

## 2. 为什么只有 INT64（没有 INT32/INT16）


 BigQuery 只有 INT64，没有 TINYINT/SMALLINT/INT:
 (a) 列式压缩: Capacitor 格式的列压缩会自动检测值范围
     即使声明为 INT64，如果值都在 0~255 范围内，
     压缩后每个值可能只占 1-2 字节。
     → 声明更窄的类型对存储没有显著帮助。

 (b) 简化用户体验: 用户不需要思考 INT vs BIGINT vs SMALLINT
     → 减少类型选择错误（如 INT 溢出需要改 BIGINT）

 (c) 无服务器: 没有"表结构优化"的必要
     → 传统数据库选择窄类型是为了减少行大小和索引大小
     → BigQuery 没有行存储也没有传统索引

 对比:
   MySQL:      TINYINT(1B)/SMALLINT(2B)/INT(4B)/BIGINT(8B) → 精细控制
   ClickHouse: UInt8~UInt256 / Int8~Int256 → 最精细（列存优化）
   SQLite:     INTEGER（自适应 1-8 字节）→ 自动优化
   BigQuery:   INT64 only → 最简单

## 3. NUMERIC vs BIGNUMERIC


 NUMERIC: 精度 38 位，标度 9 位
 范围: -99999999999999999999999999999.999999999
     ~  99999999999999999999999999999.999999999
 用途: 金融计算、精确小数（覆盖 99% 的场景）

 BIGNUMERIC: 精度 76 位，标度 38 位
 用途: 加密货币（wei 级别精度）、科学计算

 对比:
   MySQL DECIMAL(38,9): 与 BigQuery NUMERIC 精度相同，但变长存储
   ClickHouse Decimal128: 精度 38 位，16 字节（与 NUMERIC 接近）
   PostgreSQL NUMERIC: 无限精度（但性能随精度下降）

## 4. 安全算术函数


BigQuery 提供 SAFE 前缀避免算术错误:

```sql
SELECT SAFE_DIVIDE(1, 0);           -- NULL（不报错）
SELECT SAFE_MULTIPLY(9999999999999999999, 9999999999999999999); -- NULL（溢出返回 NULL）
SELECT SAFE_NEGATE(-9223372036854775808); -- NULL（INT64 最小值取反溢出）

```

IEEE 754 特殊值:

```sql
SELECT IEEE_DIVIDE(1.0, 0.0);       -- Infinity
SELECT IEEE_DIVIDE(0.0, 0.0);       -- NaN
SELECT IS_INF(IEEE_DIVIDE(1.0, 0.0)); -- true
SELECT IS_NAN(IEEE_DIVIDE(0.0, 0.0)); -- true

```

 对比: ClickHouse 的 *OrZero/*OrNull 函数族，设计理念相同

## 5. 对比与引擎开发者启示

BigQuery 数值类型的设计:
(1) INT64 only → 简化，列压缩自动优化
(2) NUMERIC + BIGNUMERIC → 两档精确小数
(3) SAFE_* 函数 → 避免运行时错误
(4) BOOL 是独立类型 → 不是 INT 的别名

对引擎开发者的启示:
列存引擎如果有好的压缩算法，可以只提供一种整数类型。
但 OLTP 和列存的需求不同:
- OLTP: 窄类型减少行大小和索引大小 → 需要多种整数类型
- 列存: 压缩算法自动优化 → 可以只用 INT64
SAFE_* 函数是优秀的设计: 分析查询不应因一行脏数据而失败。

