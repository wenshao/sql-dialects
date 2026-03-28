# SQL Server: 视图

> 参考资料:
> - [SQL Server - CREATE VIEW](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql)
> - [SQL Server - Indexed Views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)

## 基本视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;
```

2016 SP1+: CREATE OR ALTER（SQL Server 独有语法）
```sql
CREATE OR ALTER VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;
```

设计分析（对引擎开发者）:
  CREATE OR ALTER 是 SQL Server 独创的语法（2016 SP1+），
  解决了 CREATE OR REPLACE 的一个缺陷: OR REPLACE 保留原对象的权限，
  而 DROP + CREATE 会丢失权限。CREATE OR ALTER 同样保留权限。
  PostgreSQL/MySQL/Oracle 使用 CREATE OR REPLACE VIEW。
  SQL Server 明确选择了 OR ALTER 而非 OR REPLACE——语义更准确。

## SCHEMABINDING: SQL Server 独有的模式绑定

```sql
CREATE VIEW dbo.user_summary
WITH SCHEMABINDING
AS
SELECT id, username, email FROM dbo.users;
```

SCHEMABINDING 的效果:
  (1) 基表不能被 DROP
  (2) 基表被引用的列不能被 ALTER（不能改类型或删除）
  (3) 必须使用两部分名（dbo.users，不能只写 users）
  (4) 是创建索引视图的前提条件

设计分析:
  这是一种"防御性设计"——防止 DBA 修改表时意外破坏依赖的视图。
  其他数据库没有这个机制:
    PostgreSQL: ALTER TABLE 时不检查视图依赖，可能导致视图失效
    MySQL:      同上
    Oracle:     修改表会使依赖视图变为 INVALID 状态（懒编译，首次访问时重新编译）

对引擎开发者的启示:
  对象依赖追踪是数据库元数据管理的核心挑战。
  SQL Server 的 SCHEMABINDING 是"主动防御"（建视图时绑定），
  Oracle 的 INVALID 状态是"被动发现"（访问时重新编译）。
  主动防御更安全但限制更多，被动发现更灵活但可能运行时报错。

## WITH ENCRYPTION: 加密视图定义

```sql
CREATE VIEW secret_view WITH ENCRYPTION AS
SELECT id, username FROM users;
```

加密后 sp_helptext 和 sys.sql_modules 不返回视图文本
这是一个安全特性，但有争议——实际上可以被逆向工程
其他数据库没有等价功能（PostgreSQL 的视图定义总是可见的）

## 索引视图: SQL Server 的"物化视图"

SQL Server 没有 CREATE MATERIALIZED VIEW 语法。
物化视图通过"在视图上创建索引"实现——第一个索引必须是唯一聚集索引。

```sql
CREATE VIEW dbo.mv_order_summary
WITH SCHEMABINDING                         -- 必须
AS
SELECT user_id,
       COUNT_BIG(*) AS order_count,         -- 必须用 COUNT_BIG（不是 COUNT）
       SUM(amount)  AS total_amount
FROM dbo.orders
GROUP BY user_id;
GO

CREATE UNIQUE CLUSTERED INDEX ix_mv_order
ON dbo.mv_order_summary (user_id);          -- 此刻数据被"物化"
```

索引视图的独特行为:
  (1) 数据自动同步维护（DML 时引擎自动更新物化数据）
  (2) Enterprise Edition: 优化器自动匹配（查询不引用视图也能用）
  (3) Standard Edition: 必须显式使用 WITH (NOEXPAND) 提示
```sql
SELECT * FROM mv_order_summary WITH (NOEXPAND) WHERE user_id = 42;
```

索引视图的严格限制:
  不支持: OUTER JOIN, UNION, 子查询, DISTINCT, TOP, ORDER BY,
          HAVING, CASE, 非确定性函数（GETDATE 等）, FLOAT 聚合
  必须: SCHEMABINDING, 两部分表名, COUNT_BIG(*), 确定性表达式

设计分析（对引擎开发者）:
  SQL Server 的索引视图 vs PostgreSQL 的 MATERIALIZED VIEW:
    SQL Server: 自动增量维护（DML 时同步更新），但限制极多
    PostgreSQL: 手动刷新（REFRESH MATERIALIZED VIEW），但几乎无限制
    Oracle:     支持自动刷新（ON COMMIT/ON DEMAND），限制介于两者之间

  自动维护的代价: 每次 INSERT/UPDATE/DELETE 都要额外更新索引视图，
  限制多是因为引擎需要能推导出增量更新逻辑（只有简单聚合能做到）。

对引擎开发者的启示:
  增量物化视图维护是一个非常困难的问题（尤其是涉及 JOIN 和复杂聚合时）。
  SQL Server 选择了"限制多但全自动"的路线。
  现代方案（如 Materialize, RisingWave）尝试通过流式计算实现更通用的增量维护。

## 可更新视图与 INSTEAD OF 触发器

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age FROM users WHERE age >= 18
WITH CHECK OPTION;  -- INSERT/UPDATE 必须满足 WHERE 条件

-- 通过视图进行 DML
INSERT INTO adult_users (username, email, age) VALUES ('alice', 'a@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
```

INSTEAD OF 触发器: 使多表 JOIN 视图也能"更新"
SQL Server 独有: INSTEAD OF 可以用在表上（其他数据库只能用在视图上）
```sql
CREATE VIEW order_detail AS
SELECT o.id, o.amount, u.username
FROM orders o JOIN users u ON o.user_id = u.id;

CREATE TRIGGER trg_order_detail_insert
ON order_detail INSTEAD OF INSERT AS
BEGIN
    INSERT INTO orders (id, amount)
    SELECT id, amount FROM inserted;
END;
```

## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;  -- 2016+
```

版本演进:
2005+ : SCHEMABINDING, INSTEAD OF 触发器, 索引视图
2016+ : CREATE OR ALTER VIEW, DROP VIEW IF EXISTS
> **注意**: SQL Server 不支持 CREATE OR REPLACE（使用 CREATE OR ALTER）
