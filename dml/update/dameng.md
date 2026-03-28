# DamengDB (达梦): UPDATE

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


## 基本更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## 多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## 子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

## 相关子查询更新

```sql
UPDATE users u SET email = (
    SELECT email FROM user_emails e WHERE e.user_id = u.id
) WHERE EXISTS (
    SELECT 1 FROM user_emails e WHERE e.user_id = u.id
);
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

## MERGE 实现条件更新

```sql
MERGE INTO users t
USING (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000) s
ON (t.id = s.user_id)
WHEN MATCHED THEN
    UPDATE SET t.status = 2;
```

RETURNING（PL/SQL 中使用）
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id INTO v_id;
注意事项：
语法与 Oracle 兼容
没有 MySQL 风格的 JOIN UPDATE 语法
使用 MERGE 或子查询实现多表更新
支持 RETURNING 在 PL/SQL 中使用
