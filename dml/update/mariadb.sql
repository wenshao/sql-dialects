-- MariaDB: UPDATE
-- 核心差异: RETURNING 子句, 历史版本跟踪
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - UPDATE
--       https://mariadb.com/kb/en/update/

-- ============================================================
-- 1. 基本语法 (与 MySQL 相同)
-- ============================================================
UPDATE users SET age = 26 WHERE username = 'alice';
UPDATE users SET age = age + 1, updated_at = NOW() WHERE age < 30;
UPDATE users SET balance = balance * 1.1 ORDER BY balance ASC LIMIT 100;

-- 多表更新
UPDATE users u JOIN orders o ON u.id = o.user_id
SET u.balance = u.balance + o.amount
WHERE o.status = 'completed';

-- ============================================================
-- 2. UPDATE ... RETURNING (10.5+) -- MariaDB 独有
-- ============================================================
UPDATE users SET age = age + 1 WHERE username = 'alice'
RETURNING id, username, age AS new_age;
-- 返回更新后的值, 避免额外的 SELECT 查询
-- 对比 PostgreSQL: UPDATE ... RETURNING (8.2+)
-- 对比 MySQL: 不支持, 需要 UPDATE + SELECT 两步

-- ============================================================
-- 3. 系统版本表的 UPDATE 行为
-- ============================================================
-- 对启用了 SYSTEM VERSIONING 的表:
-- UPDATE 不会覆盖旧行, 而是插入新版本, 旧版本移入历史
UPDATE products SET price = 29.99 WHERE id = 1;
-- 之后可以查询更新前的数据:
-- SELECT * FROM products FOR SYSTEM_TIME ALL WHERE id = 1;

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- UPDATE + RETURNING 的实现需要在更新操作完成后读取新值
-- 与 INSERT RETURNING 不同, UPDATE RETURNING 还需要处理:
--   - 部分列更新: 未被 SET 的列从原行继承
--   - 触发器修改: AFTER UPDATE 触发器可能修改了值
--   - MVCC 版本: 返回的必须是事务内最新版本
