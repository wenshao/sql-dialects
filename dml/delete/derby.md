# Derby: DELETE

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)
> - [Derby Tuning Guide](https://db.apache.org/derby/docs/10.16/tuning/)


## 基本 DELETE


## 单行删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 多条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < DATE('2023-01-01');
```

## 使用 LIKE 条件

```sql
DELETE FROM users WHERE email LIKE '%@spam.example.com';
```

## 使用 BETWEEN 条件

```sql
DELETE FROM logs WHERE created_at BETWEEN DATE('2023-01-01') AND DATE('2023-01-31');
```

## 删除所有行（逐行删除，产生日志，可回滚）

```sql
DELETE FROM users;
```

## 快速清空表（DDL 操作，10.11+）

```sql
TRUNCATE TABLE users;
```

## 子查询删除


## IN 子查询

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## NOT IN 子查询（删除没有订单的用户）

```sql
DELETE FROM users WHERE id NOT IN (
    SELECT DISTINCT user_id FROM orders
);
```

## EXISTS 关联删除

```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = users.email);
```

## NOT EXISTS（保留有订单的用户）

```sql
DELETE FROM users
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = users.id);
```

## 标量子查询

```sql
DELETE FROM users WHERE age < (SELECT AVG(age) - 50 FROM users);
```

## 相关子查询

```sql
DELETE FROM users u1
WHERE u1.age < (
    SELECT AVG(u2.age) FROM users u2 WHERE u2.city = u1.city
);
```

## WHERE CURRENT OF（游标定位删除）

在嵌入式 SQL 或存储过程中使用:
DECLARE cur CURSOR FOR SELECT * FROM users FOR UPDATE;
OPEN cur;
FETCH NEXT FROM cur;
WHILE SQLCODE = 0 DO
IF some_condition THEN
DELETE FROM users WHERE CURRENT OF cur;
END IF;
FETCH NEXT FROM cur;
END WHILE;
CLOSE cur;
适用场景:
需要对查询结果逐行判断是否删除
在 JDBC 中使用 positioned delete
比 "先 SELECT 再 DELETE WHERE id = ?" 更高效（避免二次查找）

## Derby DELETE 的限制


不支持 LIMIT / OFFSET 子句:
不能写 DELETE FROM users WHERE status = 0 LIMIT 100;
替代方案: 使用子查询 + FETCH FIRST
DELETE FROM users WHERE id IN (
SELECT id FROM users WHERE status = 0 FETCH FIRST 100 ROWS ONLY
);
不支持多表 JOIN DELETE:
不能写 DELETE u FROM users u JOIN blacklist b ON u.email = b.email;
替代方案: 使用子查询或 EXISTS
不支持 RETURNING 子句:
DELETE 后无法直接返回被删除的行
替代方案: 先 SELECT 出需要的列，再 DELETE
SELECT id, username INTO temp_table FROM users WHERE status = 0;
DELETE FROM users WHERE status = 0;
不支持 CTE (WITH) + DELETE:
不能在 DELETE 语句前使用 WITH 子句
替代方案: 先用 CTE 查询插入临时表，再基于临时表删除

## 系统目录与依赖管理

Derby 的系统目录（System Catalogs）存储元数据:
查看表的外键约束
SELECT c.CONSTRAINTNAME, c.TYPE, t.TABLENAME
FROM SYS.SYSCONSTRAINTS c
JOIN SYS.SYSTABLES t ON c.TABLEID = t.TABLEID
WHERE t.TABLENAME = 'USERS';
删除有外键引用的表数据:
(1) 先删除子表数据，再删除父表数据

```sql
DELETE FROM orders WHERE user_id IN (SELECT id FROM users WHERE status = 0);
DELETE FROM users WHERE status = 0;
```

(2) 或使用 ON DELETE CASCADE 外键约束
ALTER TABLE orders ADD CONSTRAINT fk_user
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
之后 DELETE FROM users WHERE status = 0 会自动级联删除 orders 中的对应行
清理系统目录中无效的统计信息
CALL SYSCS_UTIL.SYSCS_UPDATE_STATISTICS('APP', 'USERS', NULL);
大量 DELETE 后建议更新统计信息，优化后续查询计划

## 批量删除策略

Derby 是嵌入式数据库，DELETE 策略与其他数据库不同:
策略 1: 分批删除（嵌入式场景推荐）
在 Java 应用中:
PreparedStatement ps = conn.prepareStatement(
"DELETE FROM logs WHERE created_at < ? FETCH FIRST 5000 ROWS ONLY");
int total = 0;
do {
ps.setDate(1, java.sql.Date.valueOf("2023-01-01"));
int rows = ps.executeUpdate();
total += rows;
conn.commit();  -- 分批提交，避免长事务
} while (rows > 0);
注意: Derby 不支持 FETCH FIRST 与 DELETE 直接组合
实际替代方案:
PreparedStatement sel = conn.prepareStatement(
"SELECT id FROM logs WHERE created_at < ? FETCH FIRST 5000 ROWS ONLY");
PreparedStatement del = conn.prepareStatement(
"DELETE FROM logs WHERE id = ?");
策略 2: TRUNCATE（清空整表，最快）

```sql
TRUNCATE TABLE logs;
```

策略 3: DROP + 重建（比 DELETE 更快）
DROP TABLE logs;
CREATE TABLE logs (...);

## 事务控制

Derby DELETE 的事务特性:
DELETE 受事务控制，可以 ROLLBACK
默认自动提交模式（autocommit=true），每条 DELETE 自动提交
关闭自动提交后可以批量操作:
conn.setAutoCommit(false);
stmt.executeUpdate("DELETE FROM users WHERE status = 0");
conn.commit();  -- 或 conn.rollback();
行锁与并发:
Derby 使用行级锁（默认隔离级别 READ_COMMITTED）
DELETE 的行会加排他锁，阻塞其他事务修改同一行
大量删除可能导致锁表（取决于锁升级策略）

## Derby 的定位与适用场景

Derby (Apache Derby / JavaDB) 特点:
纯 Java 实现的嵌入式数据库
体积小（约 3MB jar），零配置
支持 JDBC 标准，SQL 标准兼容性好
适合测试环境、桌面应用、原型开发
不适合高并发 OLTP 或大数据量分析
DELETE 在 Derby 中的典型场景:
(1) 单元测试中清理测试数据
(2) 嵌入式应用中的数据过期清理
(3) 内存模式（in-memory）下的临时数据处理
在生产 OLTP 场景中，通常使用 PostgreSQL/MySQL/Oracle 替代
