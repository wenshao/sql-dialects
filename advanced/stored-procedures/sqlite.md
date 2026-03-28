# SQLite: 存储过程

> 参考资料:
> - [SQLite Documentation - SQL Language Reference](https://www.sqlite.org/lang.html)
> - [SQLite Documentation - C API (create_function)](https://www.sqlite.org/c3ref/create_function.html)

## 为什么 SQLite 不支持存储过程

SQLite 不支持 CREATE PROCEDURE / CREATE FUNCTION（SQL 层面）。
没有 PL/SQL、PL/pgSQL 等过程式语言。没有变量、游标、IF/WHILE/LOOP。

为什么?
(a) 嵌入式定位: 存储过程在数据库服务器内执行。
    SQLite 没有独立服务器 → 没有"服务端执行环境"。
    应用代码和数据库在同一个进程中，应用层就是"存储过程"。

(b) 安全边界: 存储过程的一个目的是在服务端封装逻辑，
    客户端只能调用过程，不能直接操作表。
    SQLite 没有客户端/服务端边界，这个安全模型不适用。

(c) 简洁性: 不实现过程式语言大幅减少了引擎复杂度。
    SQLite 的代码量约 15 万行（vs PostgreSQL 约 150 万行）。

## 替代方案

### CTE + 复杂查询（纯 SQL 逻辑封装）

```sql
WITH transfer AS (
    SELECT 1 AS from_id, 2 AS to_id, 100.00 AS amount
)
UPDATE accounts SET balance = CASE
    WHEN id = (SELECT from_id FROM transfer) THEN balance - (SELECT amount FROM transfer)
    WHEN id = (SELECT to_id FROM transfer)   THEN balance + (SELECT amount FROM transfer)
END
WHERE id IN (SELECT from_id FROM transfer UNION SELECT to_id FROM transfer);
```

### 自定义函数（通过宿主语言 API 注册）

这是 SQLite 最强大的扩展机制:
Python:
  conn.create_function("my_upper", 1, lambda x: x.upper() if x else None)
  conn.execute("SELECT my_upper(username) FROM users")

C API:
  sqlite3_create_function(db, "my_func", nArg, encoding, pApp, xFunc, xStep, xFinal);

自定义聚合函数:
  conn.create_aggregate("my_median", 1, MedianClass)

设计分析:
  SQLite 的自定义函数注册在应用层（C/Python/Java）而非 SQL 层。
  这比 SQL UDF 更灵活（可以调用任意宿主语言库），
  但不可移植（函数定义不在数据库文件中）。

### 触发器实现部分自动化逻辑

见 triggers/sqlite.sql
触发器可以在 INSERT/UPDATE/DELETE 时执行复杂的 SQL 逻辑，
是 SQLite 中最接近"存储过程"的功能。

### 视图封装查询逻辑

```sql
CREATE VIEW vw_user_stats AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total
FROM orders GROUP BY user_id;
```

视图 + CTE 可以封装大部分查询逻辑

## 对比与引擎开发者启示

SQLite 不支持存储过程的替代方案:
  CTE + 复杂查询 → 纯 SQL 逻辑
  自定义函数 API → 宿主语言扩展
  触发器 → 事件驱动逻辑
  视图 → 查询封装

对比:
  MySQL:      DELIMITER + CREATE PROCEDURE（自有过程语言）
  PostgreSQL: PL/pgSQL, PL/Python, PL/Perl（最灵活）
  ClickHouse: 用户定义函数 UDF（SQL 表达式或外部脚本，无过程语言）
  BigQuery:   BEGIN...END 脚本 + UDF（JavaScript/SQL）

对引擎开发者的启示:
  嵌入式数据库不需要过程式语言:
  应用代码本身就是"过程"，数据库只需要提供 SQL 和自定义函数 API。
  自定义函数 API（sqlite3_create_function）是比 SQL UDF 更适合嵌入式的设计。
