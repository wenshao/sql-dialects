-- MariaDB: 存储过程
-- 语法与 MySQL 一致, 新增 Oracle 兼容模式
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Stored Procedures
--       https://mariadb.com/kb/en/stored-procedures/

-- ============================================================
-- 1. 基本存储过程
-- ============================================================
DELIMITER //
CREATE PROCEDURE get_user_orders(IN p_user_id BIGINT)
BEGIN
    SELECT o.id, o.amount, o.created_at
    FROM orders o
    WHERE o.user_id = p_user_id
    ORDER BY o.created_at DESC;
END //
DELIMITER ;

CALL get_user_orders(1);

-- ============================================================
-- 2. 带 OUT 参数
-- ============================================================
DELIMITER //
CREATE PROCEDURE get_user_stats(
    IN p_user_id BIGINT,
    OUT p_order_count INT,
    OUT p_total_amount DECIMAL(15,2)
)
BEGIN
    SELECT COUNT(*), COALESCE(SUM(amount), 0)
    INTO p_order_count, p_total_amount
    FROM orders WHERE user_id = p_user_id;
END //
DELIMITER ;

CALL get_user_stats(1, @cnt, @total);
SELECT @cnt, @total;

-- ============================================================
-- 3. Oracle 兼容模式 (sql_mode=ORACLE, 10.3+)
-- ============================================================
-- MariaDB 独有: 可以切换到 Oracle PL/SQL 兼容模式
SET sql_mode=ORACLE;
CREATE OR REPLACE PROCEDURE oracle_style_proc(p_id IN NUMBER)
AS
    v_name VARCHAR2(100);
BEGIN
    SELECT name INTO v_name FROM employees WHERE id = p_id;
    DBMS_OUTPUT.PUT_LINE('Name: ' || v_name);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Not found');
END;
/
-- 支持: %TYPE, %ROWTYPE, EXCEPTION, PL/SQL 语法
-- 对比 MySQL: 无 Oracle 兼容模式
-- 设计动机: 降低 Oracle → MariaDB 迁移成本

-- ============================================================
-- 4. 存储函数
-- ============================================================
DELIMITER //
CREATE FUNCTION calc_tax(amount DECIMAL(10,2)) RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    RETURN amount * 0.13;
END //
DELIMITER ;

SELECT calc_tax(100.00);

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- Oracle 兼容模式是 MariaDB 的差异化战略:
--   瞄准 Oracle 迁移市场 (去 IOE 浪潮)
--   实现复杂度极高: 需要在 parser 中支持两套语法
--   权衡: 兼容层越厚, 维护成本越高, 但市场价值越大
-- 对比: TiDB 选择 MySQL 兼容, OceanBase 选择 MySQL + Oracle 双模
-- 存储过程的执行模型:
--   解释执行 (MariaDB/MySQL): 每次调用解析 AST 并逐语句执行
--   编译执行 (Oracle PL/SQL): 编译为字节码, 缓存复用
--   编译模式性能更好, 但实现复杂度高一个数量级
