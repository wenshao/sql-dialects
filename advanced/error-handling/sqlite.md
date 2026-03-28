# SQLite: 错误处理

> 参考资料:
> - [SQLite Documentation - Result Codes](https://www.sqlite.org/rescode.html)
> - [SQLite Documentation - C API Error Handling](https://www.sqlite.org/c3ref/errcode.html)

## 为什么 SQLite 没有服务端错误处理

SQLite 没有 TRY/CATCH、EXCEPTION WHEN、DECLARE HANDLER。
原因与不支持存储过程相同: 嵌入式数据库没有服务端执行环境。
错误处理完全在宿主语言（C/Python/Java）中实现。

这实际上是一个优势: 宿主语言的错误处理比 SQL 更强大:
  Python: try/except + logging + retry logic
  Java: try/catch + CompletableFuture + circuit breaker
  C: 返回码检查 + errno
SQL 的 TRY/CATCH 是这些机制的简化版本。

## SQLite 错误码体系（对引擎开发者）

主要错误码（通过 C API sqlite3_errcode() 返回）:
SQLITE_OK         (0)   → 成功
SQLITE_ERROR      (1)   → SQL 错误或缺少的数据库
SQLITE_BUSY       (5)   → 数据库被锁定（另一个连接持有锁）
SQLITE_LOCKED     (6)   → 表被锁定（同一连接内的死锁）
SQLITE_READONLY   (8)   → 数据库是只读的
SQLITE_CONSTRAINT (19)  → 约束违反（UNIQUE/NOT NULL/CHECK/FOREIGN KEY）
SQLITE_MISMATCH   (20)  → 数据类型不匹配（如 STRICT 表）
SQLITE_FULL       (13)  → 磁盘空间不足
SQLITE_CORRUPT    (11)  → 数据库文件损坏

扩展错误码（更精确的诊断）:
SQLITE_CONSTRAINT_UNIQUE    (2067) → 唯一约束违反
SQLITE_CONSTRAINT_PRIMARYKEY(1555) → 主键约束违反
SQLITE_CONSTRAINT_FOREIGNKEY(787)  → 外键约束违反
SQLITE_CONSTRAINT_CHECK     (275)  → CHECK 约束违反
SQLITE_CONSTRAINT_NOTNULL   (1299) → NOT NULL 约束违反
SQLITE_BUSY_RECOVERY        (261)  → WAL 恢复期间的 BUSY
SQLITE_BUSY_SNAPSHOT         (517) → WAL 快照冲突

## SQL 层面的错误避免策略

INSERT OR ... 系列: 处理约束冲突而不抛出错误
```sql
INSERT OR IGNORE INTO users (id, username) VALUES (1, 'test');
INSERT OR REPLACE INTO users (id, username) VALUES (1, 'updated');
INSERT INTO users (id, username) VALUES (1, 'test')
    ON CONFLICT(id) DO UPDATE SET username = excluded.username;
```

IF EXISTS / IF NOT EXISTS: 避免 DDL 错误
```sql
CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT);
DROP TABLE IF EXISTS temp_table;
CREATE INDEX IF NOT EXISTS idx_email ON users(email);
```

RAISE（在触发器中抛出错误）:
```sql
CREATE TRIGGER trg_check
```

BEFORE INSERT ON users
BEGIN
```sql
    SELECT RAISE(ABORT, 'Invalid data') WHERE NEW.age < 0;
```

END;

COALESCE / NULLIF / IFNULL: 避免 NULL 导致的逻辑错误
```sql
SELECT COALESCE(age, 0) FROM users;
SELECT IFNULL(email, 'unknown') FROM users;
```

## SQLITE_BUSY 处理（嵌入式最常见的错误）

SQLITE_BUSY 是嵌入式数据库最典型的错误:
多个连接/线程同时写入时发生。
```sql
PRAGMA busy_timeout = 5000;    -- 等待最多 5 秒（而非立即返回错误）

-- 应用层重试模式:
-- max_retries = 3
-- for attempt in range(max_retries):
--     try:
--         conn.execute(sql)
--         break
--     except sqlite3.OperationalError as e:
--         if 'database is locked' in str(e):
--             time.sleep(0.1 * (attempt + 1))
--         else:
--             raise
```

## 对比与引擎开发者启示

SQLite 的错误处理模型:
  (1) 无服务端错误处理 → 宿主语言更强大
  (2) 精细的错误码体系 → 扩展错误码区分约束类型
  (3) INSERT OR ... → SQL 层面的冲突处理
  (4) SQLITE_BUSY → 嵌入式特有的锁冲突模型

对引擎开发者的启示:
  嵌入式引擎的错误码设计很重要:
  (a) 主错误码 + 扩展错误码的分层设计便于诊断
  (b) BUSY vs LOCKED 的区分（跨连接 vs 同连接）很有用
  (c) INSERT OR ... 让用户在 SQL 层面控制错误行为，减少应用层代码
