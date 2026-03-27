-- SQL Server: UPDATE
--
-- 参考资料:
--   [1] SQL Server T-SQL - UPDATE
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/update-transact-sql
--   [2] SQL Server T-SQL - OUTPUT Clause
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/output-clause-transact-sql

-- ============================================================
-- 1. 基本语法
-- ============================================================

UPDATE users SET age = 26 WHERE username = 'alice';
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- TOP: 限制更新行数（SQL Server 独有 DML TOP）
UPDATE TOP (100) users SET status = 0 WHERE status = 1;
-- 注意: UPDATE TOP 不保证顺序，更新哪 100 行是不确定的

-- ============================================================
-- 2. OUTPUT 子句: 同时获取更新前后的值
-- ============================================================

-- deleted = 旧值, inserted = 新值（UPDATE 中两者都可用）
UPDATE users SET age = 26
OUTPUT deleted.age AS old_age, inserted.age AS new_age, inserted.id
WHERE username = 'alice';

-- OUTPUT INTO: 将变更捕获到表变量
DECLARE @changes TABLE (id BIGINT, old_age INT, new_age INT);
UPDATE users SET age = age + 1
OUTPUT inserted.id, deleted.age, inserted.age INTO @changes
WHERE city = 'Beijing';
SELECT * FROM @changes;

-- 设计分析（对引擎开发者）:
--   UPDATE 的 OUTPUT 是最有价值的场景——它同时提供旧值和新值。
--   PostgreSQL 的 RETURNING 只能返回新值（没有等价于 deleted 的旧值访问方式）。
--   这使得 SQL Server 的 OUTPUT 在审计场景中比 RETURNING 更强大:
--     UPDATE t SET status = 'shipped'
--     OUTPUT deleted.status AS from_status, inserted.status AS to_status
--     WHERE id = 100;
--
-- 对引擎开发者的启示:
--   要支持 UPDATE 中的旧值访问，引擎需要在更新前保留行的副本。
--   这与 MVCC 的实现自然契合——旧版本本来就需要保留。
--   PostgreSQL 的 RETURNING 不支持旧值是一个设计遗憾。

-- ============================================================
-- 3. FROM 子句 JOIN 更新（T-SQL 扩展语法）
-- ============================================================

-- SQL Server 的 UPDATE ... FROM ... JOIN 是 T-SQL 独有语法:
UPDATE u SET u.status = 1
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE o.amount > 1000;

-- 多表 JOIN 更新:
UPDATE u SET u.tier = 'gold'
FROM users u
JOIN (SELECT user_id, SUM(amount) AS total
      FROM orders GROUP BY user_id) o ON u.id = o.user_id
WHERE o.total > 50000;

-- 设计分析:
--   UPDATE ... FROM 的歧义问题: 如果 JOIN 导致一行被多次匹配，
--   SQL Server 会随机选择其中一个匹配行的值——这是不确定行为。
--   PostgreSQL 也有同样的问题（UPDATE ... FROM），但文档中有明确警告。
--
-- 横向对比:
--   PostgreSQL: UPDATE t SET ... FROM other WHERE t.id = other.id（FROM 子句，类似）
--   MySQL:      UPDATE t JOIN other ON ... SET t.col = other.col（JOIN 语法，类似）
--   Oracle:     UPDATE (SELECT ... FROM t JOIN other) SET ...（需要 key-preserved 表）
--               或 MERGE INTO（更安全）

-- ============================================================
-- 4. 变量赋值 + 更新（T-SQL 独有能力）
-- ============================================================

-- SQL Server 允许在 UPDATE 中同时更新列和赋值变量
DECLARE @old_age INT;
UPDATE users SET @old_age = age, age = 26 WHERE username = 'alice';
-- @old_age 得到更新前的值

-- 累加变量（经典的"编号"模式，2012 之前替代 ROW_NUMBER）
DECLARE @seq INT = 0;
UPDATE users SET @seq = @seq + 1, seq_num = @seq WHERE city = 'Beijing';

-- 设计分析:
--   变量赋值 + 更新在一条语句中完成，是原子操作。
--   但更新顺序是不确定的——@seq 赋值的结果取决于 SQL Server 选择的访问路径。
--   这个特性没有标准 SQL 等价，其他数据库不支持。
--
-- 对引擎开发者的启示:
--   将 DML 和变量赋值混合是 T-SQL 的独特设计。
--   它简化了某些场景但引入了不确定性——引擎内部的行访问顺序影响结果。
--   现代引擎应通过窗口函数（ROW_NUMBER）替代这种模式。

-- ============================================================
-- 5. CTE + UPDATE
-- ============================================================

;WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE u SET status = 2
FROM users u JOIN vip v ON u.id = v.user_id;

-- 直接在 CTE 上 UPDATE（SQL Server 特色）
;WITH ranked AS (
    SELECT id, status, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
)
UPDATE ranked SET status = 1 WHERE rn = 1;

-- ============================================================
-- 6. CASE 表达式（条件更新）
-- ============================================================

UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- ============================================================
-- 7. 更新锁与并发安全
-- ============================================================

-- 经典的"读后更新"模式需要 UPDLOCK 防止并发问题:
BEGIN TRANSACTION;
    DECLARE @balance DECIMAL(10,2);
    SELECT @balance = balance FROM accounts WITH (UPDLOCK) WHERE id = 1;
    IF @balance >= 100
        UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- 不使用 UPDLOCK 的风险:
--   两个事务同时 SELECT 余额 1000，都认为足够，各减 100，最终余额 900 而非 800。
--   UPDLOCK 使第二个事务等待第一个完成。
--
-- 横向对比:
--   PostgreSQL: SELECT ... FOR UPDATE（SQL 标准语法）
--   MySQL:      SELECT ... FOR UPDATE
--   Oracle:     SELECT ... FOR UPDATE
--   SQL Server: 不支持 FOR UPDATE（使用 WITH (UPDLOCK) 表提示替代）
--
-- 对引擎开发者的启示:
--   SQL Server 的锁提示系统（WITH (UPDLOCK, ROWLOCK, HOLDLOCK)）比 FOR UPDATE 更灵活，
--   但学习曲线更陡。FOR UPDATE 是 SQL 标准，SQL Server 是唯一不支持它的主流数据库。
--   这是 T-SQL 方言偏离标准的一个典型例子。

-- ============================================================
-- 8. 自更新限制
-- ============================================================

-- SQL Server 不支持在 UPDATE 中引用被更新的表的子查询（某些情况下）:
-- 正确方式: 使用 CTE 或 FROM 子句代替相关子查询
;WITH avg_by_city AS (
    SELECT city, AVG(age) AS avg_age FROM users GROUP BY city
)
UPDATE u SET age = a.avg_age
FROM users u JOIN avg_by_city a ON u.city = a.city
WHERE u.age IS NULL;

-- 版本说明:
-- SQL Server 2005+ : CTE + UPDATE, OUTPUT 子句
-- SQL Server 2008+ : MERGE（见 upsert 章节）
-- SQL Server 2012+ : OFFSET-FETCH（不适用于 UPDATE）
