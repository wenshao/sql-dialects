# Databricks SQL: 分页

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


LIMIT / OFFSET
```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
```


LIMIT（不跳过）
```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```


ROW_NUMBER() 窗口函数分页
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;
```


CTE + ROW_NUMBER()
```sql
WITH paged AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
)
SELECT * FROM paged WHERE rn BETWEEN 21 AND 30;
```


QUALIFY + ROW_NUMBER()（更简洁）
```sql
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;
```


游标分页（Keyset Pagination）
第一页
```sql
SELECT * FROM users ORDER BY id LIMIT 10;
-- 后续页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```


TABLESAMPLE（随机取样，非分页）
```sql
SELECT * FROM users TABLESAMPLE (10 PERCENT);
SELECT * FROM users TABLESAMPLE (100 ROWS);
```


注意：LIMIT / OFFSET 是标准分页语法
注意：大偏移量时 OFFSET 效率降低，推荐游标分页
注意：QUALIFY 可以简化窗口函数分页写法
注意：分布式系统中全局排序需要 Shuffle，有性能开销
注意：TABLESAMPLE 用于数据探索，不适合精确分页
