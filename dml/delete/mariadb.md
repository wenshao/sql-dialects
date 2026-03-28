# MariaDB: DELETE

核心差异: RETURNING 子句, DELETE HISTORY, 截断差异

参考资料:
[1] MariaDB Knowledge Base - DELETE
https://mariadb.com/kb/en/delete/

## 1. 基本语法 (与 MySQL 相同)

```sql
DELETE FROM users WHERE age < 18;
DELETE FROM users ORDER BY created_at ASC LIMIT 100;
```


多表删除
```sql
DELETE u FROM users u JOIN blacklist b ON u.email = b.email;
```


TRUNCATE
```sql
TRUNCATE TABLE temp_data;
```


## 2. DELETE ... RETURNING (10.5+) -- MariaDB 独有

```sql
DELETE FROM users WHERE age < 18
RETURNING id, username, email;
-- 返回被删除的行, 可用于审计日志或归档
```

**对比 PostgreSQL: DELETE ... RETURNING (8.2+)**

**对比 MySQL: 不支持**


## 3. DELETE HISTORY (10.3.4+) -- 系统版本表

清理系统版本表的历史数据 (当前数据不受影响)
```sql
DELETE HISTORY FROM products;                              -- 删除所有历史
DELETE HISTORY FROM products BEFORE SYSTEM_TIME '2024-01-01';  -- 删除指定时间前的历史
```

这是维护系统版本表的关键操作, 防止历史数据无限膨胀
其他数据库的等价操作:
SQL Server: 需要先关闭版本控制, 手动删除历史表数据, 再重新启用
MariaDB 的方案更优雅: 一条 DDL 即可

## 4. 对引擎开发者的启示

DELETE RETURNING 的实现:
在 DELETE 扫描到行并标记删除前, 先读取需要返回的列值
多行删除: 返回所有被删除行的结果集
注意: 外键级联删除的行不在 RETURNING 中 (只返回直接删除的行)

DELETE HISTORY 的实现:
历史数据通常存在单独的分区或段中
DELETE HISTORY 等价于 DROP 历史分区 (而非逐行删除), 速度很快
需要在存储层区分"当前行"和"历史行"
