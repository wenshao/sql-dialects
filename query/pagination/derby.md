# Derby: 分页

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)
> - FETCH FIRST（Derby 推荐语法）

```sql
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## OFFSET + FETCH（10.5+）

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## 仅 OFFSET

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS;
```

## ROW_NUMBER 分页（10.11+）


```sql
SELECT * FROM (
    SELECT username, age,
        ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t WHERE rn BETWEEN 21 AND 30;
```

## 取每组前 N 条

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```

## 游标分页（Keyset Pagination，推荐）


## 第一页

```sql
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## 下一页（基于上一页最后一条的 id）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## 老版本分页（不支持 OFFSET 的版本）


## 使用子查询模拟 OFFSET

```sql
SELECT * FROM users
WHERE id NOT IN (
    SELECT id FROM users ORDER BY id FETCH FIRST 20 ROWS ONLY
)
ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

注意：Derby 使用 FETCH FIRST ... ROWS ONLY 语法
注意：不支持 LIMIT 关键字
注意：OFFSET 在 10.5+ 才支持
注意：不支持 WITH TIES
注意：游标分页在大数据量下性能更好
