-- Oracle: UPSERT
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - MERGE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/MERGE.html
--   [2] Oracle PL/SQL Language Reference - DML Error Logging
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/dml-error-logging.html
--   [3] Oracle SQL Language Reference - INSERT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html

-- ============================================================
-- MERGE: 标准 UPSERT (9i+)
-- ============================================================
-- Oracle 的 MERGE 是所有数据库中功能最完整的 MERGE 实现之一
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM dual) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- ============================================================
-- MERGE 核心坑: ON 子句必须是确定性的
-- ============================================================
-- ON 子句的匹配条件必须保证 USING 中的每一行最多匹配 target 中的一行
-- 如果一行源数据匹配多行目标数据，Oracle 报错: ORA-30926
--
-- 错误示例:
--   MERGE INTO orders t
--   USING new_orders s
--   ON (t.customer_id = s.customer_id)   -- 一个客户可能有多个订单!
--   WHEN MATCHED THEN UPDATE ...          -- ORA-30926!
--
-- 修复方法:
--   1. 改用唯一键: ON (t.order_id = s.order_id)
--   2. 在 USING 中去重:
--      USING (SELECT customer_id, MAX(email) AS email
--             FROM new_orders GROUP BY customer_id) s

-- ============================================================
-- MERGE 批量操作: USING 子查询/表
-- ============================================================
-- 实际生产中，MERGE 的 USING 通常是一张表或子查询，而不是 FROM dual
MERGE INTO products t
USING staging_products s
ON (t.product_code = s.product_code)
WHEN MATCHED THEN
    UPDATE SET t.name = s.name,
               t.price = s.price,
               t.updated_at = CURRENT_TIMESTAMP
    -- 只更新有变化的行（避免不必要的触发器触发和 redo 生成）
    WHERE t.name != s.name OR t.price != s.price
WHEN NOT MATCHED THEN
    INSERT (product_code, name, price, created_at)
    VALUES (s.product_code, s.name, s.price, CURRENT_TIMESTAMP);

-- ============================================================
-- 10g+: MERGE 中的 DELETE 子句
-- ============================================================
-- MERGE 可以在 UPDATE 之后删除满足条件的行（Oracle 独有扩展）
-- 注意: DELETE 只能删除被 UPDATE 过的行，不能删除未匹配的行
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, -1 AS age FROM dual) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    DELETE WHERE t.age < 0          -- 更新后如果 age < 0 则删除该行
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- ============================================================
-- 10g+: MERGE 中的 WHERE 条件
-- ============================================================
-- 在 UPDATE 和 INSERT 上分别加 WHERE，精细控制执行条件
MERGE INTO users t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age FROM dual) s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
    WHERE t.age < s.age             -- 只在新数据更"新"时才更新
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age)
    WHERE s.age > 0;                -- 只在 age 合法时才插入

-- ============================================================
-- MERGE + RETURNING: 只在 PL/SQL 中可用
-- ============================================================
-- SQL 层面的 MERGE 不支持 RETURNING 子句（这是一个经常被问到的限制）
-- 如果需要知道 MERGE 影响了哪些行，必须用 PL/SQL:
--
-- DECLARE
--     TYPE id_list IS TABLE OF NUMBER;
--     v_ids id_list;
-- BEGIN
--     -- 注意: 即使在 PL/SQL 中，MERGE 也不支持 RETURNING
--     -- 只能通过间接方式获取:
--     MERGE INTO users t
--     USING (SELECT 'alice' AS username, 'alice@example.com' AS email FROM dual) s
--     ON (t.username = s.username)
--     WHEN MATCHED THEN UPDATE SET t.email = s.email
--     WHEN NOT MATCHED THEN INSERT (username, email) VALUES (s.username, s.email);
--
--     -- 方法: 用 SQL%ROWCOUNT 获取影响行数
--     DBMS_OUTPUT.PUT_LINE('Rows affected: ' || SQL%ROWCOUNT);
--
--     -- 或者使用触发器 + 集合变量来收集受影响的 ID
-- END;
-- /
--
-- 23c 新增: INSERT ... RETURNING 和 UPDATE ... RETURNING 增强，但 MERGE 仍不支持

-- ============================================================
-- MERGE + Error Logging (10gR2+): 容错批量加载
-- ============================================================
-- DML Error Logging 让 MERGE 在遇到错误（约束违反、类型错误）时不中断
-- 错误行被写入日志表，其他行继续处理

-- 先创建错误日志表（自动生成结构）
BEGIN
    DBMS_ERRLOG.CREATE_ERROR_LOG(
        dml_table_name => 'USERS',
        err_log_table_name => 'ERR$_USERS'
    );
END;
/

-- 然后在 MERGE 中使用
MERGE INTO users t
USING staging_users s
ON (t.username = s.username)
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age)
LOG ERRORS INTO err$_users ('BATCH_20240101')  -- 标签用于识别批次
    REJECT LIMIT 100;                          -- 最多容忍 100 个错误

-- 查看哪些行出错了:
-- SELECT ora_err_number$, ora_err_mesg$, ora_err_tag$, username, email
-- FROM err$_users WHERE ora_err_tag$ = 'BATCH_20240101';
--
-- 这在 ETL 场景中极其实用:
--   1. 百万行 MERGE 不会因为 1 行脏数据而全部回滚
--   2. 错误行可以事后修复重跑
--   3. LOG ERRORS 也支持 INSERT、UPDATE、DELETE（不只是 MERGE）

-- ============================================================
-- PL/SQL: 异常处理方式的 UPSERT
-- ============================================================
-- 传统方式，所有 Oracle 版本都支持
BEGIN
    INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        UPDATE users SET email = 'alice@example.com', age = 25 WHERE username = 'alice';
END;
/

-- ============================================================
-- PL/SQL 方式 vs MERGE: 性能对比
-- ============================================================
-- 单行操作:
--   PL/SQL 异常方式: 如果大部分是 INSERT（命中率低），比 MERGE 略快
--                    因为 MERGE 总需要先查一次
--   MERGE:           如果大部分是 UPDATE（命中率高），性能相近
--
-- 批量操作（推荐 MERGE）:
--   MERGE 是单条 SQL，可以利用并行执行（PARALLEL hint）
--   PL/SQL 循环逐行处理的性能远不如单条 MERGE
--
-- 推荐策略:
--   单行: 用 PL/SQL，代码更清晰
--   批量: 永远用 MERGE，配合 LOG ERRORS 处理异常

-- ============================================================
-- 23c: INSERT ... ON CONFLICT (简化语法)
-- ============================================================
-- 23c 引入了更接近 PostgreSQL 风格的简化 upsert 语法:
-- INSERT INTO users (username, email, age)
-- VALUES ('alice', 'alice@example.com', 25)
-- ON CONFLICT (username)
-- DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age;
--
-- 这比 MERGE ... USING (SELECT ... FROM dual) 简洁得多
-- 但截至 23c 发布初期，文档和支持仍在完善中

-- ============================================================
-- 并发安全注意事项
-- ============================================================
-- Oracle 的 MERGE 不自动加排他锁
-- 并发 MERGE 相同的 ON 条件可能导致:
--   1. 两个会话都走 NOT MATCHED 分支 → 唯一约束违反
--   2. 一个 INSERT 一个 UPDATE → 其中一个等待另一个提交
--
-- 高并发场景的解决方案:
--   1. 使用 UNIQUE 约束 + 重试逻辑（最简单）
--   2. 先 SELECT FOR UPDATE，再决定 INSERT 或 UPDATE
--   3. 使用 DBMS_LOCK 或应用层分布式锁
--
-- 对比: PostgreSQL 的 INSERT ... ON CONFLICT 是原子的，不需要额外锁
--       Oracle 的 MERGE 在并发场景下需要更多关注
