-- Oracle: UPDATE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - UPDATE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/UPDATE.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新（标量子查询）
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- ============================================================
-- 2. Oracle 独有的 UPDATE 语法
-- ============================================================

-- 2.1 多列子查询更新（Oracle 独有的元组赋值语法）
UPDATE users SET (email, age) = (
    SELECT email, age FROM temp_users t WHERE t.username = users.username
)
WHERE username IN (SELECT username FROM temp_users);

-- 设计分析:
--   Oracle 允许 SET (col1, col2) = (subquery) 的元组赋值语法。
--   子查询必须返回恰好一行，否则报错 ORA-01427。
--
-- 横向对比:
--   Oracle:     SET (c1, c2) = (SELECT ...) -- 元组赋值
--   PostgreSQL: UPDATE t SET (c1, c2) = (SELECT ...) -- 相同语法 (9.5+)
--   MySQL:      不支持元组赋值，需要拆成多个标量子查询
--   SQL Server: 不支持元组赋值，需要 FROM 子句 JOIN

-- 2.2 关联子查询更新
UPDATE users u SET status = 1
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.amount > 1000);

-- 2.3 更新内联视图（通过可更新视图间接更新，Oracle 独有）
UPDATE (
    SELECT u.status, o.amount
    FROM users u JOIN orders o ON u.id = o.user_id
) SET status = 1 WHERE amount > 1000;
-- 注意: 需要"键保留表"（key-preserved table），否则报 ORA-01779

-- 设计分析:
--   Oracle 允许更新 FROM 子句中的 JOIN 结果，只要目标表是键保留的。
--   键保留 = 目标表的主键/唯一键在 JOIN 结果中仍然唯一。
--
-- 横向对比:
--   Oracle:     UPDATE (SELECT ... FROM t1 JOIN t2 ...) SET ...
--   MySQL:      UPDATE t1 JOIN t2 ON ... SET t1.col = ...（多表 UPDATE 语法）
--   PostgreSQL: UPDATE t1 SET ... FROM t2 WHERE t1.id = t2.id
--   SQL Server: UPDATE t1 SET ... FROM t1 JOIN t2 ON ...

-- 2.4 ROWNUM 限制更新行数
UPDATE users SET status = 0 WHERE status = 1 AND ROWNUM <= 100;

-- ROWNUM 陷阱同 DELETE: 不保证更新"哪 100 行"
-- 12c+ 可以用 FETCH FIRST:
UPDATE (
    SELECT * FROM users WHERE status = 1
    ORDER BY created_at FETCH FIRST 100 ROWS ONLY
) SET status = 0;

-- ============================================================
-- 3. RETURNING 子句
-- ============================================================

DECLARE v_id NUMBER;
BEGIN
    UPDATE users SET age = 26 WHERE username = 'alice'
    RETURNING id INTO v_id;
    DBMS_OUTPUT.PUT_LINE('Updated user id: ' || v_id);
END;
/

-- BULK COLLECT 批量返回
DECLARE
    TYPE id_tab IS TABLE OF NUMBER;
    v_ids id_tab;
BEGIN
    UPDATE users SET status = 0 WHERE age > 90
    RETURNING id BULK COLLECT INTO v_ids;
    DBMS_OUTPUT.PUT_LINE('Updated ' || v_ids.COUNT || ' rows');
END;
/

-- ============================================================
-- 4. '' = NULL 对 UPDATE 的影响
-- ============================================================

-- 更新为空字符串:
UPDATE users SET bio = '' WHERE id = 1;
-- 实际效果: bio 被设为 NULL（因为 '' = NULL）

-- 条件中的空字符串:
UPDATE users SET status = 0 WHERE bio = '';
-- 不会更新任何行! 因为 bio = '' 等于 bio = NULL，结果是 UNKNOWN

-- 正确写法:
UPDATE users SET status = 0 WHERE bio IS NULL;

-- ============================================================
-- 5. 批量更新优化（PL/SQL FORALL）
-- ============================================================

-- FORALL 是 Oracle PL/SQL 的批量 DML 引擎
DECLARE
    TYPE id_array IS TABLE OF NUMBER;
    TYPE status_array IS TABLE OF NUMBER;
    v_ids id_array := id_array(1, 2, 3, 4, 5);
    v_statuses status_array := status_array(1, 1, 0, 1, 0);
BEGIN
    FORALL i IN 1..v_ids.COUNT
        UPDATE users SET status = v_statuses(i) WHERE id = v_ids(i);
    COMMIT;
END;
/

-- FORALL 的实现原理:
--   将多个 DML 打包成一次上下文切换发送给 SQL 引擎（减少 PL/SQL ↔ SQL 切换开销）。
--   比逐行 UPDATE 快 10-50 倍。
--
-- 对比:
--   PostgreSQL: unnest() + UPDATE ... FROM 实现批量更新
--   MySQL:      CASE WHEN + IN 实现批量更新（或 INSERT ON DUPLICATE KEY UPDATE）
--   SQL Server: 表值参数 + MERGE

-- ============================================================
-- 6. 乐观锁更新模式
-- ============================================================

-- 使用版本号
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
-- 检查 SQL%ROWCOUNT 是否为 1

-- 使用 ORA_ROWSCN（Oracle 独有的行变更 SCN）
UPDATE orders SET status = 'shipped'
WHERE id = 100 AND ORA_ROWSCN = 123456789;

-- ============================================================
-- 7. 对引擎开发者的总结
-- ============================================================
-- 1. Oracle 的元组赋值 SET (c1,c2) = (subquery) 和内联视图更新是独特的语法设计。
-- 2. 键保留表的概念决定了 JOIN UPDATE 的可行性，优化器需要推导这个属性。
-- 3. FORALL 批量 DML 通过减少上下文切换大幅提升性能，值得在引擎层面原生支持。
-- 4. '' = NULL 导致 UPDATE SET col = '' 和 WHERE col = '' 都有反直觉行为。
-- 5. ORA_ROWSCN 是 MVCC 的副产品，提供了优雅的乐观锁实现。
