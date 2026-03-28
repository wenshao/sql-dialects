# Trino: UPDATE

> 参考资料:
> - [Trino - UPDATE](https://trino.io/docs/current/sql/update.html)
> - [Trino - SQL Statement List](https://trino.io/docs/current/sql.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

```sql
UPDATE users SET age = 26 WHERE username = 'alice';

```

多列更新
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

```

子查询更新
```sql
UPDATE users SET age = (SELECT CAST(AVG(age) AS INTEGER) FROM users) WHERE age IS NULL;

```

CASE 表达式
```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

```

自引用更新
```sql
UPDATE users SET age = age + 1;

```

跨 catalog 子查询更新
```sql
UPDATE iceberg.db.users SET status = 1
WHERE id IN (SELECT user_id FROM mysql.db.vip_list);

```

Iceberg connector 特性
UPDATE 会产生新的 snapshot，支持 Time Travel 查看历史版本
```sql
UPDATE iceberg.db.events SET event_name = 'user_login'
WHERE event_name = 'login';

```

Delta Lake connector 特性
UPDATE 操作产生新版本，旧版本保留用于回溯
```sql
UPDATE delta.db.users SET status = 0
WHERE last_login < DATE '2023-01-01';

```

Hive ACID 表更新
需要表配置 transactional = true
```sql
UPDATE hive.db.users SET age = 26 WHERE username = 'alice';

```

**限制:**
不支持多表 JOIN 更新
不支持 FROM 子句
不支持 ORDER BY / LIMIT
性能取决于底层存储和 connector 实现
