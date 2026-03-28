# PolarDB: UPDATE

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)


## 基本更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## 多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## 带 LIMIT

```sql
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;
```

## 多表更新（JOIN）

```sql
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;
```

## 子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

## CASE 表达式

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

## 自引用更新

```sql
UPDATE users SET age = age + 1;
```

## WITH CTE

```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;
```

注意事项：
更新分区键的值会导致数据跨分片迁移（性能开销大）
分布式 JOIN UPDATE 需要涉及的表有相同的分区键
广播表的更新会同步到所有节点
不带 WHERE 条件的更新会扫描所有分片
