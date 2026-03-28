# Materialize: UPDATE

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


Materialize 的 TABLE 支持 UPDATE
SOURCE 和 MATERIALIZED VIEW 不支持 UPDATE
基本更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## 多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## 条件更新

```sql
UPDATE users SET status = 'inactive' WHERE age > 65;
```

## CASE 表达式

```sql
UPDATE users SET category = CASE
    WHEN age < 18 THEN 'minor'
    WHEN age < 65 THEN 'adult'
    ELSE 'senior'
END;
```

## 子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age)::INT FROM users) WHERE age IS NULL;
```

## 注意：物化视图自动反映更新


## 更新 TABLE 后，依赖的 MATERIALIZED VIEW 自动增量更新

例如：

```sql
CREATE MATERIALIZED VIEW user_stats AS
SELECT category, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY category;
```

## 更新 users 表后，user_stats 自动反映变化

```sql
UPDATE users SET age = 30 WHERE username = 'alice';
```

## 不支持的操作


不能更新 SOURCE
UPDATE kafka_orders SET amount = 100 WHERE ...;  -- 错误
不能更新 MATERIALIZED VIEW
UPDATE order_summary SET total = 0 WHERE ...;  -- 错误
注意：只有 TABLE 支持 UPDATE
注意：UPDATE 会触发依赖物化视图的增量更新
注意：兼容 PostgreSQL 的 UPDATE 语法
注意：SOURCE 和 MATERIALIZED VIEW 不支持 UPDATE
