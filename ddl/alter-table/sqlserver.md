# SQL Server: ALTER TABLE

> 参考资料:
> - [SQL Server T-SQL - ALTER TABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql)
> - [SQL Server - Online Index Operations](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/perform-index-operations-online)

## 基本语法

添加列
```sql
ALTER TABLE users ADD phone NVARCHAR(20);
ALTER TABLE users ADD status INT NOT NULL DEFAULT 1;
```

添加多列（单语句，其他方言通常需要多条）
```sql
ALTER TABLE users ADD
    city    NVARCHAR(64),
    country NVARCHAR(64) DEFAULT N'CN';
```

修改列类型（T-SQL 使用 ALTER COLUMN，不是 MODIFY）
```sql
ALTER TABLE users ALTER COLUMN phone NVARCHAR(32) NOT NULL;
```

重命名列/表: 必须使用系统存储过程 sp_rename
设计分析: 这是 SQL Server 独有的做法——DDL 操作通过存储过程完成
其他方言都用 ALTER TABLE ... RENAME COLUMN 语法
```sql
EXEC sp_rename 'users.phone', 'mobile', 'COLUMN';
EXEC sp_rename 'users', 'members';
```

删除列
```sql
ALTER TABLE users DROP COLUMN phone;
```

2016+: IF EXISTS 语法（避免先查元数据再执行）
```sql
ALTER TABLE users DROP COLUMN IF EXISTS phone, city;
```

## 默认值约束的独特设计（对引擎开发者）

SQL Server 的 DEFAULT 是一个命名约束对象，不是列的属性。
这是核心设计差异：修改默认值需要先删除旧约束，再创建新约束。
```sql
ALTER TABLE users ADD CONSTRAINT DF_users_status DEFAULT 0 FOR status;
ALTER TABLE users DROP CONSTRAINT DF_users_status;
```

设计 trade-off:
  优点: 约束有名字，方便元数据管理、脚本生成
  缺点: 用户体验差——删列前必须先删约束，否则报错
        如果建表时用了匿名默认值，约束名是系统生成的随机名，
        删除需要先查 sys.default_constraints 获取约束名

匿名默认值的删除困境（SQL Server 经典坑）:
```sql
DECLARE @constraint_name NVARCHAR(256);
SELECT @constraint_name = name
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID('users')
  AND parent_column_id = (SELECT column_id FROM sys.columns
                          WHERE object_id = OBJECT_ID('users')
                            AND name = 'status');
EXEC('ALTER TABLE users DROP CONSTRAINT ' + @constraint_name);
```

横向对比:
  MySQL:      ALTER TABLE t ALTER COLUMN c SET DEFAULT v（直接改，无需名字）
  PostgreSQL: ALTER TABLE t ALTER COLUMN c SET DEFAULT v（同 MySQL）
  Oracle:     ALTER TABLE t MODIFY c DEFAULT v（也是直接改）
  SQL Server: 必须 DROP + ADD 命名约束（唯一要求如此的主流数据库）

对引擎开发者的启示:
  默认值作为独立约束对象增加了元数据一致性，但严重影响了 DDL 易用性。
  现代引擎应考虑同时支持两种模式：匿名列级默认值 + 可选的命名约束。

## ALTER COLUMN 的限制（对引擎开发者）

SQL Server 的 ALTER COLUMN 每次只能修改类型或 NULL 性中的一个属性。
修改类型时必须同时声明 NULL/NOT NULL，否则列会变回 NULL。
```sql
ALTER TABLE users ALTER COLUMN email NVARCHAR(500) NOT NULL;
```

不能通过 ALTER COLUMN 修改:
  - 默认值（需要 DROP/ADD CONSTRAINT）
  - IDENTITY 属性（无法添加或删除）
  - 计算列表达式
要修改 IDENTITY 列，只能: 新建列 → 迁移数据 → 删旧列 → 重命名

横向对比:
  MySQL:      ALTER TABLE t MODIFY col type NOT NULL DEFAULT v（一条搞定）
  PostgreSQL: ALTER TABLE t ALTER col TYPE type, ALTER col SET NOT NULL（分步但灵活）
  Oracle:     ALTER TABLE t MODIFY col type DEFAULT v NOT NULL（一条搞定）

对引擎开发者的启示:
  ALTER COLUMN 的原子性设计是个权衡：每次只改一个属性更安全，
  但用户需要多条语句。现代引擎应支持在单条 ALTER 中修改多个属性。

## Online DDL（Enterprise Edition 专属）

2014+: ONLINE = ON（部分 ALTER TABLE 操作不阻塞 DML）
```sql
ALTER TABLE users ALTER COLUMN bio NVARCHAR(MAX) NOT NULL WITH (ONLINE = ON);
```

关键限制: ONLINE DDL 只在 Enterprise Edition 中可用。
Standard/Express/Developer 版本执行 ALTER TABLE 时会获取 Sch-M 锁，
完全阻塞所有并发查询和 DML。

横向对比:
  MySQL:      5.6+ Online DDL 所有版本可用；8.0.12+ ALGORITHM=INSTANT
  PostgreSQL: 大部分 ALTER TABLE 都是在线的（不需要特殊语法）
              11+ ADD COLUMN + DEFAULT 是 INSTANT（不重写表）
  Oracle:     ONLINE DDL 需要 Enterprise Edition（同 SQL Server）

对引擎开发者的启示:
  将 Online DDL 锁定在付费版本是一个商业策略，但技术上不应该如此。
  现代引擎应在所有版本中支持无锁 DDL（至少对简单操作如 ADD COLUMN）。

## 事务性 DDL（SQL Server 独特优势）

SQL Server 的 DDL 是完全事务性的：可以在事务中执行并回滚。
```sql
BEGIN TRANSACTION;
    ALTER TABLE users ADD temp_col INT;
    -- 验证是否正确...
ROLLBACK;  -- temp_col 消失了
```

这是 SQL Server 和 PostgreSQL 共有的重要能力。
横向对比:
  MySQL:  DDL 会隐式提交事务，无法回滚
  Oracle: DDL 会隐式提交事务，无法回滚

对引擎开发者的启示:
  事务性 DDL 是 Schema Migration 工具（如 Flyway、Liquibase）的关键依赖。
  缺少事务性 DDL 意味着迁移失败后需要人工修复——这是 MySQL/Oracle 用户的痛点。
  实现事务性 DDL 需要在系统表（元数据表）上支持 MVCC，复杂度较高。

## 计算列（Computed Columns）

SQL Server 支持持久化和非持久化计算列
```sql
ALTER TABLE users ADD full_name AS (first_name + N' ' + last_name);           -- 虚拟
ALTER TABLE users ADD full_name AS (first_name + N' ' + last_name) PERSISTED; -- 持久化

-- PERSISTED 计算列可以创建索引（虚拟计算列不能）
-- 横向对比:
--   MySQL:      5.7+ 支持 VIRTUAL/STORED 生成列
--   PostgreSQL: 12+ 支持 STORED 生成列（无 VIRTUAL）
--   Oracle:     11g+ 支持 VIRTUAL 列
--
-- 对引擎开发者的启示:
--   计算列的核心价值是在 JSON 字段上创建索引（SQL Server 的 JSON 索引方案）。
--   ALTER TABLE t ADD city AS JSON_VALUE(data, '$.city'); CREATE INDEX ... ON t(city);
```

## 版本演进与 DROP IF EXISTS

SQL Server 2016+ 引入 IF EXISTS，之前必须先查元数据:
```sql
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('users') AND name = 'phone')
    ALTER TABLE users DROP COLUMN phone;
```

2016+ 简化为:
```sql
ALTER TABLE users DROP COLUMN IF EXISTS phone;
```

查看表元数据
```sql
SELECT c.name, t.name AS type, c.max_length, c.is_nullable, dc.definition AS default_value
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
WHERE c.object_id = OBJECT_ID('users');
```
