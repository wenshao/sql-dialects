-- SQLite: 存储过程
--
-- 参考资料:
--   [1] SQLite Documentation - SQL Language Reference
--       https://www.sqlite.org/lang.html
--   [2] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html

-- SQLite 不支持存储过程和函数！

-- 替代方案:

-- 1. 在应用层实现（最常用）
-- 用 Python/Java/C 等编写逻辑

-- 2. 用 CTE + 复杂查询实现部分逻辑
WITH transfer AS (
    SELECT 1 AS from_id, 2 AS to_id, 100.00 AS amount
)
UPDATE accounts SET balance = CASE
    WHEN id = (SELECT from_id FROM transfer) THEN balance - (SELECT amount FROM transfer)
    WHEN id = (SELECT to_id FROM transfer)   THEN balance + (SELECT amount FROM transfer)
END
WHERE id IN (SELECT from_id FROM transfer UNION SELECT to_id FROM transfer);

-- 3. 自定义函数（通过 C API 或 Python 接口注册）
-- Python 示例:
-- conn.create_function("my_func", 1, lambda x: x.upper())
-- SELECT my_func(username) FROM users;

-- 4. 触发器可以实现部分自动化逻辑（见 triggers/sqlite.sql）

-- 注意：没有 PL/SQL、PL/pgSQL 等过程式语言
-- 注意：没有游标
-- 注意：没有变量声明
-- 注意：没有流程控制（IF/WHILE/LOOP）
