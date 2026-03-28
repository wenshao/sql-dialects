# StarRocks: 数值类型

> 参考资料:
> - [1] StarRocks Documentation - Numeric Types
>   https://docs.starrocks.io/docs/sql-reference/data-types/


## 与 Doris 完全相同的类型体系

TINYINT(1B) / SMALLINT(2B) / INT(4B) / BIGINT(8B) / LARGEINT(16B)
FLOAT(4B) / DOUBLE(8B)
DECIMAL(P, S): P 最大 38


```sql
CREATE TABLE examples (
    int_val INT, big_val BIGINT, huge_val LARGEINT,
    price DECIMAL(10,2), ratio DOUBLE
) DUPLICATE KEY(int_val) DISTRIBUTED BY HASH(int_val);

```

 BOOLEAN: TRUE / FALSE / NULL

## 特殊聚合类型

BITMAP: 精确去重
HLL:    近似去重
(无 QUANTILE_STATE——Doris 独有)

```sql
CREATE TABLE agg_table (
    dt DATE, user_id BITMAP BITMAP_UNION, uv HLL HLL_UNION
) AGGREGATE KEY(dt) DISTRIBUTED BY HASH(dt);

```

StarRocks vs Doris: 数值类型完全相同。
差异: Doris 有 QUANTILE_STATE，StarRocks 没有(用 PERCENTILE_APPROX 替代)。

