# SQLite: UPSERT

> 参考资料:
> - [SQLite Documentation - UPSERT](https://www.sqlite.org/lang_upsert.html)
> - [SQLite Documentation - INSERT (conflict resolution)](https://www.sqlite.org/lang_insert.html)

## ON CONFLICT ... DO UPDATE（3.24.0+，2018年）

基本 UPSERT: 冲突时更新
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;
```

EXCLUDED: 引用被拒绝的行（尝试插入的值）
这是 SQLite/PostgreSQL 的语法，MySQL 用 VALUES() 函数

冲突时什么都不做（INSERT IF NOT EXISTS）
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING;
```

条件更新（只在满足条件时更新）
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 30)
ON CONFLICT (username)
DO UPDATE SET age = EXCLUDED.age
WHERE EXCLUDED.age > users.age;    -- 只更新更大的年龄值
```

## 旧语法: INSERT OR REPLACE / INSERT OR IGNORE

INSERT OR REPLACE（所有版本支持，但有陷阱!）
```sql
INSERT OR REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
```

REPLACE 的陷阱（对引擎开发者重要!）:
  REPLACE = DELETE 旧行 + INSERT 新行
  后果:
  (a) rowid 改变（因为是新行）
  (b) 未指定的列重置为默认值（不是保留原值!）
  (c) 触发 BEFORE DELETE + AFTER DELETE + BEFORE INSERT + AFTER INSERT
  (d) 外键的 ON DELETE 动作会被触发

对比 ON CONFLICT DO UPDATE:
  DO UPDATE 是原地修改（rowid 不变，触发 UPDATE 触发器）
  REPLACE 是删除+插入（rowid 改变，触发 DELETE+INSERT 触发器）

> **结论**: ON CONFLICT DO UPDATE 几乎总是优于 REPLACE

INSERT OR IGNORE（跳过冲突行）
```sql
INSERT OR IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
```

## 多列冲突和多冲突子句

复合唯一约束冲突
```sql
INSERT INTO order_items (order_id, item_id, quantity)
VALUES (1, 42, 3)
ON CONFLICT (order_id, item_id)
DO UPDATE SET quantity = quantity + EXCLUDED.quantity;
```

多个 ON CONFLICT 子句（3.35.0+）
```sql
INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'alice@e.com')
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username
ON CONFLICT (email) DO NOTHING;
```

## UPSERT 的批量操作

批量 UPSERT
```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@e.com', 25),
    ('bob', 'bob@e.com', 30),
    ('charlie', 'charlie@e.com', 35)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;
```

UPSERT + RETURNING（3.35.0+）
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@e.com', 26)
ON CONFLICT (username)
DO UPDATE SET age = EXCLUDED.age
RETURNING id, username, age;
```

## 对比与引擎开发者启示

SQLite UPSERT 的设计演进:
- **阶段 1 (2000)**: INSERT OR REPLACE（有 DELETE+INSERT 陷阱）
- **阶段 2 (2018)**: ON CONFLICT DO UPDATE（真正的 UPSERT）
  - 等了 18 年才有真正的 UPSERT!

EXCLUDED 伪表:
  - SQLite 和 PostgreSQL 都使用 EXCLUDED 引用冲突行
  - MySQL 使用 VALUES()（在 INSERT ... ON DUPLICATE KEY UPDATE 中）
  - MySQL 8.0.19+ 也支持别名方式（AS new_row）

对引擎开发者的启示:
- (1) REPLACE (DELETE+INSERT) 不是真正的 UPSERT（语义不同）
- (2) ON CONFLICT DO UPDATE 是更好的设计（原地修改，rowid 不变）
- (3) EXCLUDED 伪表比 VALUES() 函数更清晰
- (4) 支持多 ON CONFLICT 子句增加了灵活性但也增加了复杂度
