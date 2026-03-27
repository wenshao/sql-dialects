-- MySQL: 存储过程（5.0+）
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE PROCEDURE
--       https://dev.mysql.com/doc/refman/8.0/en/create-procedure.html
--   [2] MySQL 8.0 Reference Manual - CREATE FUNCTION
--       https://dev.mysql.com/doc/refman/8.0/en/create-function.html
--   [3] MySQL 8.0 Reference Manual - Stored Program Syntax
--       https://dev.mysql.com/doc/refman/8.0/en/sql-compound-statements.html
--   [4] MySQL 8.0 Reference Manual - Cursor
--       https://dev.mysql.com/doc/refman/8.0/en/cursors.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 创建存储过程
DELIMITER //
CREATE PROCEDURE get_user(IN p_username VARCHAR(64))
BEGIN
    SELECT * FROM users WHERE username = p_username;
END //
DELIMITER ;

-- 调用
CALL get_user('alice');

-- 带输出参数
DELIMITER //
CREATE PROCEDURE get_user_count(OUT p_count INT)
BEGIN
    SELECT COUNT(*) INTO p_count FROM users;
END //
DELIMITER ;

CALL get_user_count(@cnt);
SELECT @cnt;

-- INOUT 参数
DELIMITER //
CREATE PROCEDURE increment(INOUT p_val INT, IN p_step INT)
BEGIN
    SET p_val = p_val + p_step;
END //
DELIMITER ;

SET @v = 10;
CALL increment(@v, 5);
SELECT @v;  -- 15

-- 变量和流程控制
DELIMITER //
CREATE PROCEDURE transfer(
    IN p_from BIGINT, IN p_to BIGINT, IN p_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_balance DECIMAL(10,2);

    START TRANSACTION;

    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
    ELSE
        UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
        COMMIT;
    END IF;
END //
DELIMITER ;

-- 创建函数
DELIMITER //
CREATE FUNCTION full_name(first VARCHAR(50), last VARCHAR(50))
RETURNS VARCHAR(101)
DETERMINISTIC
BEGIN
    RETURN CONCAT(first, ' ', last);
END //
DELIMITER ;

SELECT full_name('Alice', 'Smith');

-- 删除存储过程 / 函数
DROP PROCEDURE IF EXISTS get_user;
DROP FUNCTION IF EXISTS full_name;

-- ============================================================
-- 2. MySQL 存储过程的局限性（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 DELIMITER: MySQL 最大的语法尴尬
-- MySQL 的客户端协议以 ; 作为语句结束符，存储过程体内也有 ;
-- 解决方案: DELIMITER // 临时更改分隔符
-- 这不是 SQL 语法层面的概念，而是客户端协议的 workaround
--
-- 对比:
--   PostgreSQL: $$ ... $$ (dollar-quoting) 作为过程体边界，语言无关
--               CREATE FUNCTION ... AS $$ BEGIN ... END $$;
--   Oracle:     / (斜杠) 作为块终止符，在 SQL*Plus 中
--   SQL Server: GO 作为批处理分隔符（不是 SQL 语句，是客户端指令）
--
-- 对引擎开发者的启示:
--   如果引擎支持过程式语言，需要在协议层面解决 "过程体包含分号" 的问题
--   PostgreSQL 的 dollar-quoting 是最优雅的方案（协议层无需改动）

-- 2.2 语言能力对比: MySQL SP vs Oracle PL/SQL vs PG PL/pgSQL
--
-- MySQL 存储过程的缺失特性:
--   a. 没有包（Package）概念:
--      Oracle PL/SQL 有 PACKAGE: 将相关过程/函数/类型/变量打包为模块
--      MySQL: 所有过程平铺在 schema 中，无法模块化管理
--      PG: 没有 Package，但 SCHEMA + Extension 提供了组织能力
--
--   b. 没有 %TYPE / %ROWTYPE:
--      Oracle: v_name users.username%TYPE（变量类型自动跟随列类型）
--      PG:     v_rec users%ROWTYPE（变量为表的行类型）
--      MySQL:  必须手动声明类型，列类型改变后存储过程可能出错
--
--   c. 没有匿名块:
--      Oracle: BEGIN ... END; 可以直接执行，无需创建命名过程
--      PG:     DO $$ BEGIN ... END $$; 匿名块
--      MySQL:  必须先 CREATE PROCEDURE 再 CALL，无法即兴执行过程式代码
--
--   d. 没有集合类型 / 表类型:
--      Oracle: TYPE t IS TABLE OF NUMBER; 可以在过程中操作集合
--      PG:     支持数组参数、复合类型参数
--      MySQL:  不支持数组/集合类型参数，需要用临时表或字符串拼接模拟
--
--   e. 异常处理较弱:
--      Oracle: EXCEPTION WHEN ... THEN（命名异常、自定义异常类型）
--      PG:     EXCEPTION WHEN ... THEN（类似 Oracle）
--      MySQL:  DECLARE HANDLER（条件处理器），功能更有限，只有 CONTINUE/EXIT 两种
--
--   f. 没有 BULK COLLECT / FORALL:
--      Oracle: BULK COLLECT INTO + FORALL 批量操作，避免逐行上下文切换
--      MySQL: 只能逐行游标处理，没有批量操作原语

-- ============================================================
-- 3. 游标的性能问题（对 SQL 引擎开发者）
-- ============================================================

DELIMITER //
CREATE PROCEDURE process_users()
BEGIN
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_username VARCHAR(64);
    DECLARE cur CURSOR FOR SELECT username FROM users;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_username;
        IF v_done THEN LEAVE read_loop; END IF;
        -- 逐行处理
    END LOOP;
    CLOSE cur;
END //
DELIMITER ;

-- 3.1 游标的性能陷阱
-- MySQL 游标是只读的、不可滚动的、只能单向遍历（ASENSITIVE）
--
-- 主要性能问题:
--   a. 逐行处理 vs 集合操作: SQL 引擎优化集合操作，游标强制退化为逐行模式
--   b. 上下文切换: 每次 FETCH 在 SQL 引擎和过程式解释器之间切换
--   c. 事务持续时间: 游标遍历期间长时间持有锁或 MVCC 快照

-- 3.2 游标能力对比:
--   MySQL:      只读、单向、不可滚动（最弱的游标实现）
--   PostgreSQL: 可滚动、可通过 DECLARE CURSOR 定义、支持 MOVE/FETCH NEXT/PRIOR/FIRST/LAST
--   Oracle:     显式游标 + 隐式游标，支持 REF CURSOR（游标变量），可作为输出参数传递
--   SQL Server: 支持 STATIC/DYNAMIC/KEYSET/FAST_FORWARD 游标类型（最丰富的游标分类）

-- 3.3 替代游标的方案:
--   a. 集合操作: 大多数游标逻辑可以用 UPDATE ... JOIN / INSERT ... SELECT 替代
--   b. 窗口函数: LAG/LEAD/ROW_NUMBER 替代 "与前一行比较" 的游标模式
--   c. 递归 CTE: 替代树遍历 / 累计计算的游标
--   d. 应用层批处理: 分批 SELECT + 应用层处理（可控性更好）

-- ============================================================
-- 4. 横向对比: 存储过程 vs 应用层逻辑 vs UDF（对 SQL 引擎开发者）
-- ============================================================

-- 4.1 存储过程的适用场景:
--   a. 减少网络往返: 复杂业务逻辑在数据库端一次执行，避免多次 round-trip
--   b. 数据密集型操作: 大量数据处理不需要传输到应用层
--   c. 安全控制: 只授权用户 EXECUTE 权限，不直接暴露表
--   d. 代码复用: 多个应用共享同一数据库逻辑

-- 4.2 存储过程的问题（现代架构的反对理由）:
--   a. 可测试性差: 不能用标准测试框架（JUnit/pytest）测试
--   b. 版本控制困难: 代码存在数据库中，不在 Git 仓库中
--   c. 调试困难: MySQL 没有原生的过程调试器
--   d. 水平扩展困难: 存储过程绑定在数据库上，增加实例不能分担计算
--   e. 微服务冲突: 存储过程创建 "隐藏的服务"，违反服务边界

-- 4.3 UDF（User-Defined Function）的设计选择:
--   MySQL:      DETERMINISTIC / NOT DETERMINISTIC 声明（影响缓存和复制），不支持表值函数
--   PostgreSQL: 多语言 UDF（PL/pgSQL / PL/Python / PL/V8），RETURNS TABLE / SETOF
--   Oracle:     PL/SQL 函数，PIPELINED 函数（流式返回行）
--   SQL Server: CLR 集成（C# 编写 UDF），Table-Valued Function
--   分析引擎:   ClickHouse（外部程序/Lambda）、BigQuery（SQL/JS 沙箱）、DuckDB（C++ 扩展）

-- 4.4 现代趋势:
--   "胖数据库" 时代（2000s）: 业务逻辑尽可能在数据库中（Oracle PL/SQL 生态繁荣）
--   "薄数据库" 时代（2010s+）: 数据库只做存储和查询，业务逻辑在应用层
--   当前平衡点:
--     - OLTP: 简单过程仍有价值（减少 round-trip），复杂逻辑放应用层
--     - OLAP: UDF 用于自定义聚合/转换（如 BigQuery JS UDF、ClickHouse Lambda）
--     - 分布式: 大多数分布式引擎的存储过程支持较弱或不支持
--       TiDB: 不支持存储过程（MySQL 兼容层不含过程式语言）
--       CockroachDB: 24.1+ 支持 PL/pgSQL（PostgreSQL 兼容需求驱动）

-- 对引擎开发者的总结:
--   1) 存储过程对 MySQL/PG/Oracle 兼容性很重要，但实现成本高（需要过程式解释器）
--   2) 优先级: UDF（标量函数）> 存储过程 > 包/匿名块
--   3) 如果要支持过程式语言，PL/pgSQL 的语法比 MySQL SP 更值得参考（更清晰、功能更全）
--   4) 现代引擎的替代方案: 支持多语言 UDF（Python/JS/Wasm）而不是发明自己的过程式语言
