# SAP HANA: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [SAP HANA Documentation](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/5f14e09987ef4c638a83e1a015e3bd17.html)
> - [SAP HANA Documentation](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767)


## 准备数据


```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
```

## SAP HANA 特有：SERIES_GENERATE_DATE


```sql
SELECT GENERATED_PERIOD_START AS d
FROM SERIES_GENERATE_DATE(
    'INTERVAL 1 DAY',
    DATE '2024-01-01',
    DATE '2024-01-11'
);

SELECT seq.GENERATED_PERIOD_START AS date,
       COALESCE(ds.amount, 0) AS amount
FROM SERIES_GENERATE_DATE('INTERVAL 1 DAY',
    DATE '2024-01-01', DATE '2024-01-11') seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.GENERATED_PERIOD_START
ORDER BY date;
```

## LEFT JOIN 填充间隙 + COALESCE 填零


## 使用上述日期序列 LEFT JOIN 原始数据

COALESCE(amount, 0) 将 NULL 替换为 0

## 用最近已知值填充


COUNT 分组法模拟 IGNORE NULLS
WITH filled AS (
SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp
FROM date_series LEFT JOIN daily_sales ...
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled
FROM filled;
注意：SAP HANA 的日期序列生成方式见上述特有语法
注意：使用 COALESCE 进行空值替换
注意：COUNT 分组法是模拟 IGNORE NULLS 的通用方案
