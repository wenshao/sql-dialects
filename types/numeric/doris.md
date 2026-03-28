# Apache Doris: 数值类型

 Apache Doris: 数值类型

 参考资料:
   [1] Doris Documentation - Numeric Types
       https://doris.apache.org/docs/sql-manual/data-types/

## 1. 整数类型

TINYINT:   1 字节, -128 ~ 127
SMALLINT:  2 字节, -32768 ~ 32767
INT:       4 字节, -2^31 ~ 2^31-1
BIGINT:    8 字节, -2^63 ~ 2^63-1
LARGEINT: 16 字节, -2^127 ~ 2^127-1 (Doris/StarRocks 独有)


```sql
CREATE TABLE examples (
    tiny_val TINYINT, small_val SMALLINT, int_val INT,
    big_val BIGINT, huge_val LARGEINT
) DUPLICATE KEY(int_val) DISTRIBUTED BY HASH(int_val);

```

 LARGEINT 是 128 位整数——MySQL/PG/ClickHouse 都没有。
 用途: UUID 数值存储、大精度计数。
 不支持 UNSIGNED(与 MySQL 不同)。

## 2. 浮点与定点

FLOAT: 4 字节单精度, DOUBLE: 8 字节双精度
DECIMAL(P, S): P 最大 38, S 最大 P
DECIMALV3(1.2+): 更高性能的定点数实现


```sql
CREATE TABLE prices (price DECIMAL(10,2), value DOUBLE)
DUPLICATE KEY(price) DISTRIBUTED BY HASH(price);

```

## 3. BOOLEAN

 TRUE / FALSE / NULL

## 4. 特殊聚合类型 (Doris/StarRocks 独有)

BITMAP:          位图(精确去重)
HLL:             HyperLogLog(近似去重)
QUANTILE_STATE:  分位数(Doris 独有，StarRocks 无)

```sql
CREATE TABLE agg_table (
    dt DATE, user_id BITMAP BITMAP_UNION, uv HLL HLL_UNION
) AGGREGATE KEY(dt) DISTRIBUTED BY HASH(dt);

SELECT BITMAP_COUNT(BITMAP_UNION(user_id)) FROM agg_table;
SELECT HLL_UNION_AGG(uv) FROM agg_table;

```

对比:
ClickHouse: AggregateFunction(uniq, UInt64)(类似但语法不同)
BigQuery:   无 BITMAP/HLL 类型(内置 APPROX_COUNT_DISTINCT)
MySQL/PG:   无(需应用层实现)

