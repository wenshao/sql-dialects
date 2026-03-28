# SQL 标准: 锁机制

> 参考资料:
> - [ISO/IEC 9075-2:2023 - SQL/Foundation](https://www.iso.org/standard/76583.html)
> - SQL:2023 Standard - Transaction isolation levels
> - SQL:2023 Standard - Cursor positioning and FOR UPDATE

## SQL 标准定义的隔离级别

SQL 标准定义了四个隔离级别:
```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- 允许脏读
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 禁止脏读
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 禁止不可重复读
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;      -- 完全隔离
```

## SELECT FOR UPDATE（SQL 标准）

SQL 标准定义了 FOR UPDATE 子句
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
```

FOR UPDATE OF 指定列
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE OF status;
```

FOR READ ONLY（显式声明只读）
```sql
SELECT * FROM orders WHERE id = 100 FOR READ ONLY;
```

## 事务管理

开始事务
```sql
START TRANSACTION;
```

或
```sql
BEGIN;
```

提交
```sql
COMMIT;
```

或
```sql
COMMIT WORK;
```

回滚
```sql
ROLLBACK;
```

或
```sql
ROLLBACK WORK;
```

保存点
```sql
SAVEPOINT sp1;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
```

事务访问模式
```sql
SET TRANSACTION READ ONLY;
SET TRANSACTION READ WRITE;
```

## 注意事项

1. SQL 标准定义了隔离级别和 FOR UPDATE 语法
2. 具体的锁实现由各数据库供应商决定
3. LOCK TABLE 不是 SQL 标准的一部分
4. Advisory locks 不是 SQL 标准的一部分
5. NOWAIT / SKIP LOCKED 不在原始 SQL 标准中
6. 各数据库的实际锁行为可能与标准定义有差异
