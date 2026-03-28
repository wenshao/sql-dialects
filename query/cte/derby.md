# Derby: CTE（公共表表达式）

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)


## Derby 对 CTE 的支持有限（10.14+ 部分支持）

## 子查询替代 CTE（推荐的通用方式）


CTE 方式（可能不支持）：
WITH active_users AS (SELECT * FROM users WHERE status = 1)
SELECT * FROM active_users WHERE age > 25;
子查询替代：

```sql
SELECT * FROM (
    SELECT * FROM users WHERE status = 1
) active_users WHERE age > 25;
```

## 多层嵌套替代多个 CTE

```sql
SELECT u.username, o.cnt, o.total
FROM (SELECT * FROM users WHERE status = 1) u
INNER JOIN (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
) o ON u.id = o.user_id;
```

## 视图替代复杂 CTE


## 创建视图代替重复使用的 CTE

```sql
CREATE VIEW active_users AS
SELECT * FROM users WHERE status = 1;

CREATE VIEW user_order_stats AS
SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders GROUP BY user_id;
```

## 使用视图

```sql
SELECT u.username, o.cnt, o.total
FROM active_users u
INNER JOIN user_order_stats o ON u.id = o.user_id;
```

## 清理视图

```sql
DROP VIEW active_users;
DROP VIEW user_order_stats;
```

## 递归查询替代（不支持）


Derby 不支持递归 CTE
层级结构查询需要在应用层实现
或使用存储过程实现递归逻辑
见 advanced/stored-procedures/derby.sql

## 分页查询（不使用 CTE）


## 使用 ROW_NUMBER 替代 CTE 分页

```sql
SELECT * FROM (
    SELECT username, age,
        ROW_NUMBER() OVER (ORDER BY age) AS rn
    FROM users
) t WHERE rn BETWEEN 11 AND 20;
```

注意：Derby 10.14 之前不支持 CTE
注意：不支持递归 CTE
注意：使用子查询和视图替代 CTE
注意：复杂查询建议拆分为多个视图或在应用层处理
