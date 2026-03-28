# Hologres: DELETE

> 参考资料:
> - [Hologres SQL - DELETE](https://help.aliyun.com/zh/hologres/user-guide/delete-2)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)
> - 注意: Hologres 兼容 PostgreSQL DELETE 语法
> - 行存表和列存表均支持 DELETE
> - 基本删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 子查询删除

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## USING 子句（多表删除，PostgreSQL 兼容语法）

```sql
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;
```

## EXISTS 子查询

```sql
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);
```

## RETURNING（返回删除的行）

```sql
DELETE FROM users WHERE username = 'alice' RETURNING id, username, email;
```

## CTE + DELETE

```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```

## 条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';
```

## 删除所有行

```sql
DELETE FROM users;
```

## TRUNCATE（更快的清空方式）

```sql
TRUNCATE TABLE users;
```

性能提示:
按主键删除性能最佳
避免频繁单行删除，建议批量操作
大量数据删除建议使用 TRUNCATE 或重建表
