# Greenplum: 分页

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


LIMIT / OFFSET（标准 SQL）
```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
```


FETCH FIRST（SQL:2008 标准）
```sql
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```


FETCH NEXT
```sql
SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```


窗口函数辅助分页
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;
```


性能优化：游标分页
已知上一页最后一条 id = 100
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```


游标（服务器端分页）
```sql
BEGIN;
DECLARE user_cursor CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH 10 FROM user_cursor;      -- 获取前 10 条
FETCH 10 FROM user_cursor;      -- 获取接下来 10 条
CLOSE user_cursor;
COMMIT;
```


Top-N 查询
```sql
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;
```


分组后 Top-N
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```


注意：Greenplum 兼容 PostgreSQL 分页语法
注意：大 OFFSET 值会导致性能问题
注意：推荐使用游标分页或服务端游标
注意：分布式环境下分页需要排序（有 Motion 开销）
