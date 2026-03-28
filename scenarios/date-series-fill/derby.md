# Apache Derby: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [Apache Derby Documentation](https://db.apache.org/derby/docs/10.16/ref/rrefsqljwith.html)
> - [Apache Derby Documentation](https://db.apache.org/derby/docs/10.16/ref/)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
```

## Derby 日期序列（10.12+）


Derby 的日期运算有限
推荐使用辅助数字表
递归 CTE 从 Derby 10.12 开始支持

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
注意：Apache Derby 的日期序列生成方式见上述特有语法
注意：使用 COALESCE 进行空值替换
注意：COUNT 分组法是模拟 IGNORE NULLS 的通用方案
