# Spanner: 日期序列填充

> 参考资料:
> - [Google Cloud Spanner Documentation](https://cloud.google.com/spanner/docs/reference/standard-sql/array_functions)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 准备数据


CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

## 生成日期序列


使用 GENERATE_DATE_ARRAY + UNNEST 生成日期序列
```sql
SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
)) AS d;

SELECT d AS date, COALESCE(ds.amount, 0) AS amount
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY)) AS d
LEFT JOIN daily_sales ds ON ds.sale_date = d ORDER BY d;

```

## COALESCE 填零


SELECT date, COALESCE(amount, 0) AS amount FROM date_series LEFT JOIN daily_sales ...

## 用最近已知值填充


COUNT 分组法模拟 IGNORE NULLS
WITH filled AS (
    SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp
    FROM ...
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) FROM filled;

## 累计和


SUM(COALESCE(amount, 0)) OVER (ORDER BY date) AS running_total

**注意:** Google Cloud Spanner 的日期序列生成方式见上述代码
**注意:** 使用 COALESCE 将缺失值替换为 0
**注意:** COUNT 分组法是通用的 IGNORE NULLS 模拟方案
