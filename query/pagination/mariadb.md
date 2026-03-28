# MariaDB: 分页 (Pagination)

语法与 MySQL 完全一致

参考资料:
[1] MariaDB Knowledge Base - LIMIT
https://mariadb.com/kb/en/limit/

## 1. LIMIT ... OFFSET

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
SELECT * FROM users ORDER BY id LIMIT 20, 10;  -- 同上, MySQL 风格
```


## 2. 性能问题: 深分页

LIMIT 1000000, 10 需要扫描并丢弃前 100 万行
解决方案与 MySQL 相同:
方案 A: 游标分页 (推荐)
```sql
SELECT * FROM users WHERE id > 12345 ORDER BY id LIMIT 10;
-- 方案 B: 延迟关联
SELECT u.* FROM users u
JOIN (SELECT id FROM users ORDER BY id LIMIT 1000000, 10) AS t ON u.id = t.id;
```


## 3. LIMIT ROWS EXAMINED (MariaDB 独有, 10.0+)

```sql
SELECT * FROM users WHERE age > 25 LIMIT ROWS EXAMINED 10000;
```

扫描行数达到 10000 时停止, 无论结果集有多少行
用于防止慢查询消耗过多资源
**对比: MySQL 没有此语法, 需要用 MAX_EXECUTION_TIME hint**


## 4. 对引擎开发者的启示

LIMIT ROWS EXAMINED 的设计动机:
传统 LIMIT 只限制结果行数, 不限制工作量
ROWS EXAMINED 限制工作量, 是资源治理的利器
实现: 在执行器中维护扫描行计数器, 到达阈值时提前终止
**对比: PostgreSQL 的 statement_timeout 按时间限制**

理想方案: 同时提供行数限制和时间限制
