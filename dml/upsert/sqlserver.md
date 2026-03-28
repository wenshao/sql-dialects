# SQL Server: UPSERT

> 参考资料:
> - [SQL Server T-SQL - MERGE](https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql)
> - [Aaron Bertrand - Use Caution with SQL Server's MERGE Statement](https://www.mssqltips.com/sqlservertip/3074/use-caution-with-sql-servers-merge-statement/)
> - [Microsoft - Known MERGE Issues](https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql#remarks)

## MERGE (2008+): 功能强大但有争议

```sql
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```

> **注意**: MERGE 语句必须以分号结尾（这不是可选的）

## 为什么很多 SQL Server 专家建议避免 MERGE

MERGE 在 SQL Server 中有一个臭名昭著的历史:

1. 已知 Bug 列表很长
   微软文档页面专门列出了一系列 MERGE 相关的 bug (KB 文章)
   包括: 错误的行计数、触发器不按预期触发、外键约束违反等
   虽然大部分已在后续 CU 中修复，但社区信心已受损

2. 线程安全问题
   MERGE 不是原子操作！在高并发下:
   - 两个会话同时 MERGE 相同的键
   - 都走 WHEN NOT MATCHED 分支
   - 结果: 主键/唯一约束违反
   即使加了唯一索引也只是变成报错而非静默重复

3. 锁行为不可预测
   MERGE 的执行计划复杂，锁的获取顺序不一定符合预期
   在某些场景下比等价的 INSERT/UPDATE 更容易死锁

4. 调试困难
   MERGE 的执行计划比分开的 INSERT + UPDATE 更难分析
   出问题时不容易定位是 MATCHED 还是 NOT MATCHED 分支的问题

Paul White, Aaron Bertrand 等 SQL Server MVP 的建议:
"除非你真的需要 MERGE 的多分支能力，否则用 INSERT + UPDATE"

## MERGE + OUTPUT: 审计与结果追踪

OUTPUT 是 MERGE 的一个真正亮点（其他方式很难做到等价效果）
```sql
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25),
              ('bob', 'bob@example.com', 30)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age)
OUTPUT
    $action AS merge_action,               -- 'INSERT', 'UPDATE', 或 'DELETE'
    inserted.id,
    inserted.username,
    COALESCE(deleted.email, '(new)') AS old_email,
    inserted.email AS new_email;
```

OUTPUT INTO: 把结果写入审计表
```sql
DECLARE @merge_log TABLE (
    action     NVARCHAR(10),
    id         BIGINT,
    username   NVARCHAR(64),
    old_email  NVARCHAR(255),
    new_email  NVARCHAR(255)
);

MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email
WHEN NOT MATCHED THEN
    INSERT (username, email) VALUES (s.username, s.email)
OUTPUT $action, inserted.id, inserted.username,
       deleted.email, inserted.email
INTO @merge_log;
```

查看操作结果
```sql
SELECT * FROM @merge_log;
```

## 推荐方案: IF EXISTS + UPDATE ELSE INSERT (带正确锁定)

方案 A: 简单版（有并发问题，只适合低并发场景）
```sql
IF EXISTS (SELECT 1 FROM users WHERE username = 'alice')
    UPDATE users SET email = 'alice@example.com', age = 25 WHERE username = 'alice';
ELSE
    INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```

> **问题**: SELECT 和 INSERT 之间的窗口允许另一个线程插入相同的行

方案 B: 先 UPDATE 后 INSERT（推荐，大多数行已存在的场景）
```sql
BEGIN TRAN;
    UPDATE users WITH (UPDLOCK, SERIALIZABLE)
    SET email = 'alice@example.com', age = 25
    WHERE username = 'alice';

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO users (username, email, age)
        VALUES ('alice', 'alice@example.com', 25);
    END
COMMIT;
```

为什么 UPDLOCK + SERIALIZABLE:
  UPDLOCK:      防止死锁（两个会话不会同时持有 S 锁再升级到 X 锁）
  SERIALIZABLE: 防止幻读（锁住"不存在的行"的范围，阻止另一个会话插入）
  没有 SERIALIZABLE: 两个会话都 UPDATE 返回 0 行，都执行 INSERT → 重复
  没有 UPDLOCK:      两个会话都拿 S 锁，都想升级 X 锁 → 死锁

方案 C: 先 INSERT 后 UPDATE（推荐，大多数行是新的场景）
```sql
BEGIN TRAN;
    BEGIN TRY
        INSERT INTO users (username, email, age)
        VALUES ('alice', 'alice@example.com', 25);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 2627 OR ERROR_NUMBER() = 2601  -- 唯一约束违反
        BEGIN
            UPDATE users SET email = 'alice@example.com', age = 25
            WHERE username = 'alice';
        END
        ELSE
            THROW;  -- 其他错误重新抛出
    END CATCH
COMMIT;
```

## 批量 UPSERT: 性能优化

批量操作时，方案 B 的变体最高效:
```sql
BEGIN TRAN;
    -- 先更新已存在的行
    UPDATE t WITH (UPDLOCK, SERIALIZABLE)
    SET t.email = s.email, t.age = s.age
    FROM users t
    INNER JOIN staging_users s ON t.username = s.username;
```

再插入不存在的行
```sql
    INSERT INTO users (username, email, age)
    SELECT s.username, s.email, s.age
    FROM staging_users s
    WHERE NOT EXISTS (
        SELECT 1 FROM users t WHERE t.username = s.username
    );
COMMIT;
```

为什么比 MERGE 更好:
  1. 执行计划更简单，优化器更容易生成好的计划
  2. 锁行为更可预测
  3. 出问题时更容易调试（可以单独运行 UPDATE 或 INSERT）
  4. 没有 MERGE 的已知 bug 风险

## +: INSERT ... ON CONFLICT 风格？

SQL Server 至今（2022）没有 PostgreSQL 风格的 INSERT ... ON CONFLICT
也没有 MySQL 风格的 INSERT ... ON DUPLICATE KEY UPDATE
MERGE 是唯一的"单语句 upsert"，这也是为什么即便有争议它仍被广泛使用

如果你从 PostgreSQL/MySQL 迁移过来，适应一下:
  PostgreSQL:  INSERT ... ON CONFLICT DO UPDATE
  MySQL:       INSERT ... ON DUPLICATE KEY UPDATE
  SQL Server:  MERGE 或 UPDATE+INSERT 模式

## UPSERT 与 IDENTITY / SEQUENCE 的交互

> **注意**: MERGE 的 NOT MATCHED 分支会消耗 IDENTITY 值
即使另一个会话的 MERGE 最终走了 MATCHED 分支
这会导致 IDENTITY 值出现间隙（gap）

如果业务要求 ID 连续（罕见但存在），考虑:
  1. 使用 SEQUENCE + sp_sequence_get_range 预分配
  2. 或接受现实: 大多数系统不需要连续 ID
