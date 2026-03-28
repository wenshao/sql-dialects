# Teradata: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [Teradata Documentation](https://docs.teradata.com/r/SQL-Data-Manipulation-Language)
> - [Teradata Documentation](https://docs.teradata.com/r/SQL-Functions-Expressions-and-Predicates)


## 准备数据


```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
```


## Teradata 特有：sys_calendar.calendar


```sql
SELECT c.calendar_date, COALESCE(ds.amount, 0) AS amount
FROM sys_calendar.calendar c
LEFT JOIN daily_sales ds ON ds.sale_date = c.calendar_date
WHERE c.calendar_date BETWEEN DATE '2024-01-01' AND DATE '2024-01-10'
ORDER BY c.calendar_date;
```


## LEFT JOIN 填充间隙 + COALESCE 填零


使用上述日期序列 LEFT JOIN 原始数据
COALESCE(amount, 0) 将 NULL 替换为 0

## 用最近已知值填充


COUNT 分组法模拟 IGNORE NULLS
WITH filled AS (
SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp
FROM date_series LEFT JOIN daily_sales ...
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled
FROM filled;

注意：Teradata 的日期序列生成方式见上述特有语法
注意：使用 COALESCE 进行空值替换
注意：COUNT 分组法是模拟 IGNORE NULLS 的通用方案
