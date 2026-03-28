# Materialize: 数值类型

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)
> - Materialize 兼容 PostgreSQL 数值类型
> - 整数
> - SMALLINT / INT2: 2 字节
> - INTEGER / INT / INT4: 4 字节
> - BIGINT / INT8: 8 字节
> - 浮点数
> - REAL / FLOAT4: 4 字节
> - DOUBLE PRECISION / FLOAT8: 8 字节
> - 定点数
> - NUMERIC(p,s) / DECIMAL(p,s): 精确数值
> - 布尔
> - BOOLEAN / BOOL

```sql
CREATE TABLE products (
    id       INT NOT NULL,
    quantity SMALLINT,
    price    NUMERIC(10,2),
    weight   REAL,
    score    DOUBLE PRECISION,
    active   BOOLEAN DEFAULT TRUE
);
```

## 类型转换

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INT;
SELECT CAST(3.14 AS NUMERIC(10,2));
```

## 特殊数值

```sql
SELECT 'NaN'::FLOAT;
SELECT 'Infinity'::FLOAT;
```

## 数学函数

```sql
SELECT ABS(-5), MOD(10, 3), ROUND(3.14159, 2);
SELECT CEIL(3.14), FLOOR(3.14), TRUNC(3.14159, 2);
SELECT POWER(2, 10), SQRT(144);
```

## 物化视图中的数值计算


```sql
CREATE MATERIALIZED VIEW product_stats AS
SELECT
    COUNT(*) AS total_products,
    SUM(price) AS total_value,
    AVG(price) AS avg_price,
    MIN(price) AS min_price,
    MAX(price) AS max_price
FROM products
WHERE active = TRUE;
```

注意：兼容 PostgreSQL 的数值类型
注意：支持 NUMERIC 精确数值
注意：不支持 SERIAL / BIGSERIAL 自增
注意：物化视图中的数值聚合会增量维护
