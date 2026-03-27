-- Teradata: Error Handling
--
-- 参考资料:
--   [1] Teradata SQL Reference - SPL Error Handling
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Stored-Procedures-and-Embedded-SQL/

-- ============================================================
-- DECLARE HANDLER (SPL)
-- ============================================================
CREATE PROCEDURE safe_insert(IN p_id INTEGER, IN p_name VARCHAR(100))
BEGIN
    DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
    BEGIN
        -- 约束违反，跳过
    END;

    INSERT INTO users(id, username) VALUES(p_id, p_name);
END;

-- ============================================================
-- SIGNAL (抛出异常)
-- ============================================================
CREATE PROCEDURE validate_amount(IN p_amount DECIMAL(10,2))
BEGIN
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Amount must be positive';
    END IF;
END;

-- ============================================================
-- DECLARE CONDITION
-- ============================================================
CREATE PROCEDURE condition_demo()
BEGIN
    DECLARE duplicate_key CONDITION FOR SQLSTATE '23505';
    DECLARE EXIT HANDLER FOR duplicate_key
    BEGIN
        -- 处理重复键
    END;

    INSERT INTO users(id, username) VALUES(1, 'test');
END;

-- ============================================================
-- 活动类型 (Activity Type) 检查
-- ============================================================
-- Teradata 特有的 ACTIVITY_COUNT 变量
-- INSERT INTO users(id, username) VALUES(1, 'test');
-- IF ACTIVITY_COUNT = 0 THEN
--     -- 无行受影响
-- END IF;

-- 版本说明：
--   Teradata 全版本 : DECLARE HANDLER, SIGNAL
-- 注意：Teradata 使用 SPL (Stored Procedure Language)
-- 注意：支持 CONTINUE 和 EXIT 处理器
-- 注意：ACTIVITY_COUNT 检查受影响行数
-- 限制：不支持 TRY/CATCH 或 EXCEPTION WHEN
