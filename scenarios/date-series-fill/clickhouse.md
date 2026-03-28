# ClickHouse: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [1] ClickHouse Documentation - numbers()
>   https://clickhouse.com/docs/en/sql-reference/table-functions/numbers
> - [2] ClickHouse Documentation - WITH FILL
>   https://clickhouse.com/docs/en/sql-reference/statements/select/order-by#order-by-expr-with-fill


## 准备数据


```sql
CREATE TABLE daily_sales (sale_date Date, amount Decimal(10,2))
ENGINE = MergeTree() ORDER BY sale_date;
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

```

## 1. ORDER BY ... WITH FILL（ClickHouse 特有）


WITH FILL 自动填充间隙

```sql
SELECT sale_date, amount
FROM daily_sales
ORDER BY sale_date WITH FILL
    FROM '2024-01-01' TO '2024-01-11' STEP INTERVAL 1 DAY;

```

 多列 WITH FILL
 SELECT sale_date, category, amount
 FROM category_sales
 ORDER BY category, sale_date WITH FILL FROM '2024-01-01' TO '2024-01-11' STEP 1;

## 2. 使用 numbers() 生成日期序列


```sql
SELECT toDate('2024-01-01') + number AS d
FROM numbers(10);

```

LEFT JOIN 填充

```sql
SELECT d, COALESCE(ds.amount, 0) AS amount
FROM (
    SELECT toDate('2024-01-01') + number AS d FROM numbers(10)
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY d;

```

## 3. COALESCE 填零 + 累计和


```sql
SELECT d, COALESCE(ds.amount, toDecimal32(0, 2)) AS amount,
       sum(COALESCE(ds.amount, toDecimal32(0, 2))) OVER (ORDER BY d) AS running_total
FROM (SELECT toDate('2024-01-01') + number AS d FROM numbers(10)) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY d;

```

## 4. WITH FILL + INTERPOLATE（ClickHouse 22.x+）


WITH FILL 配合默认值

```sql
SELECT sale_date, amount
FROM daily_sales
ORDER BY sale_date WITH FILL
    FROM '2024-01-01' TO '2024-01-11' STEP 1
    INTERPOLATE (amount AS 0);

```

## 5. 动态范围


```sql
SELECT d, COALESCE(ds.amount, toDecimal32(0, 2)) AS amount
FROM (
    SELECT toDate((SELECT MIN(sale_date) FROM daily_sales)) + number AS d
    FROM numbers(toUInt64(
        (SELECT MAX(sale_date) FROM daily_sales) -
        (SELECT MIN(sale_date) FROM daily_sales) + 1
    ))
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY d;

```

## 6. 按维度的间隙填充


使用 arrayJoin 生成日期序列

```sql
SELECT arrayJoin(
    arrayMap(x -> toDate('2024-01-01') + x, range(10))
) AS d;

```

注意：WITH FILL 是 ClickHouse 特有的间隙填充语法
注意：INTERPOLATE 子句可以指定间隙的填充策略
注意：numbers() 是高效的序列生成表函数
注意：ClickHouse 日期相加直接支持 + number（天数）

