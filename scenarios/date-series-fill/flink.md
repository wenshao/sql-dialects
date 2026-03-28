# Flink SQL: 日期序列填充

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/overview/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 准备数据


CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

## 生成日期序列


Flink SQL 不支持 generate_series 和递归 CTE
使用 Temporal Table 或在源端预生成日期维度表
在批模式下，推荐使用 Spark SQL 或其他引擎生成日期序列

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

**注意:** Flink SQL 的日期序列生成方式见上述代码
**注意:** 使用 COALESCE 将缺失值替换为 0
**注意:** COUNT 分组法是通用的 IGNORE NULLS 模拟方案
