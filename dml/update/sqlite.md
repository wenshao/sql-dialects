# SQLite: UPDATE

> 参考资料:
> - [SQLite Documentation - UPDATE](https://www.sqlite.org/lang_update.html)
> - [SQLite Documentation - Conflict Resolution](https://www.sqlite.org/lang_conflict.html)

## 基本语法

基本更新
```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

多列更新
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

CASE 表达式
```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

子查询更新
```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```

3.33.0+: FROM 子句（多表 UPDATE）
```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```

3.35.0+: RETURNING
```sql
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;
```

## 冲突处理（UPDATE OR ...）

与 INSERT OR ... 相同的 5 种策略:
```sql
UPDATE OR REPLACE users SET username = 'bob' WHERE username = 'alice';
-- 如果 'bob' 已存在且 username 有 UNIQUE 约束:
-- → 删除已有的 'bob' 行，然后将 'alice' 改名为 'bob'

UPDATE OR IGNORE users SET username = 'bob' WHERE username = 'alice';
-- 如果冲突 → 跳过该行的更新，不报错

UPDATE OR ABORT users SET username = 'bob' WHERE username = 'alice';
UPDATE OR ROLLBACK users SET username = 'bob' WHERE username = 'alice';
UPDATE OR FAIL users SET username = 'bob' WHERE username = 'alice';
```

设计分析:
  UPDATE OR ... 是 SQLite 独有的语法。
  其他数据库（MySQL/PostgreSQL）的 UPDATE 在冲突时只会报错。
  这在批量 UPDATE 时很有用: 如果某行冲突，是跳过还是回滚全部?

## LIMIT / ORDER BY（条件编译）

需要编译时启用 SQLITE_ENABLE_UPDATE_DELETE_LIMIT
```sql
UPDATE users SET status = 0
WHERE status = 1
ORDER BY created_at
LIMIT 100;
```

为什么需要编译选项?
SQLite 官方认为 UPDATE + LIMIT 不是标准 SQL，
只在明确需要时启用，避免用户误用。
对比: MySQL 原生支持 UPDATE ... LIMIT N

## 单文件写入的 UPDATE 性能

UPDATE 的 I/O 模式:
  (1) 读取满足 WHERE 的行（使用索引或全表扫描）
  (2) 在 journal/WAL 中记录旧值（用于 ROLLBACK）
  (3) 原地修改 B-Tree 页中的数据
  (4) fsync（PRAGMA synchronous 控制）

```sql
UPDATE vs DELETE + INSERT:
```

  UPDATE 是原地修改（in-place），rowid 不变
  REPLACE 是 DELETE + INSERT，rowid 改变
  对于有 rowid 依赖的场景（外键、应用缓存），UPDATE 更安全

批量 UPDATE 也应该在事务中:
```sql
BEGIN;
UPDATE users SET status = 0 WHERE last_login < '2023-01-01';
UPDATE users SET status = 1 WHERE last_login >= '2023-01-01';
COMMIT;
```

## 动态类型对 UPDATE 的影响

与 INSERT 一样，UPDATE 不做类型检查:
UPDATE users SET age = 'twenty-six' WHERE username = 'alice';  -- 成功!
列声明的类型只是"亲和性"提示，不是约束。
只有 CHECK 约束或 STRICT 模式表才会拒绝类型不匹配的更新。

## 对比与引擎开发者启示

SQLite UPDATE 的设计特征:
  (1) UPDATE OR ... → 5 种冲突策略（独有）
  (2) FROM 子句 → 3.33.0 才支持（比 MySQL 晚但比 SQL 标准早）
  (3) RETURNING → 3.35.0 才支持
  (4) LIMIT → 需要编译选项（保守设计）
  (5) 原地修改 → rowid 不变（与 REPLACE 的区别）

对引擎开发者的启示:
  UPDATE 的原子性保证是 ACID 的核心。
  SQLite 的 WAL + 原地修改设计使 UPDATE 高效且安全。
  冲突处理策略（5 种）是过度设计还是精细控制，取决于目标用户。
  嵌入式场景倾向于更多策略选择（因为没有 DBA 来处理冲突），
  服务端场景倾向于简单（冲突就报错，应用层重试）。
