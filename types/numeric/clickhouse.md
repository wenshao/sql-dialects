# ClickHouse: 数值类型

> 参考资料:
> - [1] ClickHouse - Numeric Data Types
>   https://clickhouse.com/docs/en/sql-reference/data-types/int-uint
> - [2] ClickHouse - Decimal
>   https://clickhouse.com/docs/en/sql-reference/data-types/decimal


## 1. 整数类型: 有符号 + 无符号（最精细的整数类型系统）


ClickHouse 的整数类型比任何其他数据库都精细:
有符号: Int8(-128~127), Int16, Int32, Int64, Int128, Int256
无符号: UInt8(0~255), UInt16, UInt32, UInt64, UInt128, UInt256


```sql
CREATE TABLE metrics (
    id          UInt64,
    status      UInt8,       -- 0~255，用于枚举值
    count       UInt32,      -- 0~4B
    timestamp   Int64,       -- Unix 时间戳
    big_number  Int128       -- 超大整数（如加密哈希）
) ENGINE = MergeTree() ORDER BY id;

```

 为什么如此精细?
 (a) 列式存储: 每列独立存储，类型宽度直接影响存储大小和压缩率
     UInt8 列: 1 亿行 = 100 MB
     UInt64 列: 1 亿行 = 800 MB（8 倍差异!）
 (b) SIMD 优化: 窄类型可以在单条 SIMD 指令中处理更多值
     UInt8: 256-bit SIMD 一次处理 32 个值
     UInt64: 256-bit SIMD 一次处理 4 个值
 (c) 默认 NOT NULL: 没有 NULL 标记的开销（Nullable 需要额外 1 byte/行）

 对比:
   MySQL:      TINYINT(1B) / SMALLINT(2B) / INT(4B) / BIGINT(8B) + UNSIGNED
   PostgreSQL: SMALLINT(2B) / INTEGER(4B) / BIGINT(8B)，无 UNSIGNED
   BigQuery:   只有 INT64（8B），无更小的整数类型
   SQLite:     只有 INTEGER（1-8B 自适应）

## 2. 浮点类型


Float32 (4 字节, ~7 位有效数字)
Float64 (8 字节, ~15 位有效数字)

```sql
CREATE TABLE measurements (
    sensor_id UInt32,
    value     Float64,
    approx    Float32       -- 精度要求低时节省空间
) ENGINE = MergeTree() ORDER BY sensor_id;

```

 特殊值: inf, -inf, nan 都支持
 SELECT 1.0 / 0;  → inf
 SELECT 0.0 / 0;  → nan

## 3. Decimal 类型（精确小数）


Decimal(P, S): P=有效位数, S=小数位数
Decimal32(S): P=1~9, 4 字节
Decimal64(S): P=1~18, 8 字节
Decimal128(S): P=1~38, 16 字节
Decimal256(S): P=1~76, 32 字节


```sql
CREATE TABLE financials (
    price    Decimal(10, 2),     -- 10 位有效数字，2 位小数
    quantity Decimal64(4),       -- 18 位有效数字，4 位小数
    total    Decimal128(6)       -- 38 位有效数字，6 位小数
) ENGINE = MergeTree() ORDER BY price;

```

 设计分析:
   ClickHouse 的 Decimal 分为 4 种底层存储宽度（32/64/128/256 位）。
   这是列存的优化: 选择最小的宽度减少存储和提高压缩率。
   对比 MySQL: DECIMAL(P,S) 使用变长存储（4 字节一组 9 位数字）

## 4. 布尔: Bool 类型（21.12+）


ClickHouse 21.12+ 添加了 Bool 类型（别名 UInt8）

```sql
CREATE TABLE flags (
    id UInt64,
    is_active Bool DEFAULT true
) ENGINE = MergeTree() ORDER BY id;
```

 存储为 UInt8: true=1, false=0

## 5. 枚举类型（Enum8 / Enum16）


ClickHouse 独有的枚举类型:

```sql
CREATE TABLE events (
    id     UInt64,
    level  Enum8('debug' = 0, 'info' = 1, 'warn' = 2, 'error' = 3)
) ENGINE = MergeTree() ORDER BY id;
```

 存储为 Int8/Int16，但显示和输入为字符串
 比 String 更节省空间（1 字节 vs 平均 5 字节）
 比 CHECK 约束更安全（只接受定义的值）

## 6. 对比与引擎开发者启示

ClickHouse 数值类型的核心设计:
(1) 最精细的整数类型 → 列存空间优化
(2) 无符号类型 → 存储效率（状态码、计数器）
(3) 4 种 Decimal 宽度 → 精确小数 + 存储效率
(4) Enum 类型 → 比 String 更高效的枚举存储
(5) 默认 NOT NULL → 无 NULL 标记开销

对引擎开发者的启示:
列存引擎的类型系统应该"窄"（小类型 → 高压缩率 → 高查询性能）。
提供 UInt8/UInt16 等窄类型是列存引擎的标配。
Enum 类型对日志/事件数据极有价值（高重复率 → 高压缩率）。

