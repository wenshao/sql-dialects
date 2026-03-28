# Azure Synapse Analytics: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [Azure Synapse Analytics Documentation](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


## 准备数据


CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

## 1. 生成日期序列


使用数字表交叉连接生成日期序列
```sql
;WITH E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1),
     E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
     nums(n) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 FROM E2)
SELECT DATEADD(DAY, n, '2024-01-01') AS d FROM nums WHERE n < 10;
```


Serverless SQL Pool 支持递归 CTE

## 2. COALESCE 填零


SELECT date, COALESCE(amount, 0) AS amount FROM date_series LEFT JOIN daily_sales ...

## 3. 用最近已知值填充


COUNT 分组法模拟 IGNORE NULLS
WITH filled AS (
SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp
FROM ...
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) FROM filled;

## 4. 累计和


SUM(COALESCE(amount, 0)) OVER (ORDER BY date) AS running_total

注意：Azure Synapse Analytics 的日期序列生成方式见上述代码
注意：使用 COALESCE 将缺失值替换为 0
注意：COUNT 分组法是通用的 IGNORE NULLS 模拟方案
