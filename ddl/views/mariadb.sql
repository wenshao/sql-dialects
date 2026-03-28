-- MariaDB: 视图 (Views)
-- 语法与 MySQL 基本一致, 差异在于与独有特性的交互
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - CREATE VIEW
--       https://mariadb.com/kb/en/create-view/

-- ============================================================
-- 1. 基本语法
-- ============================================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE (比 MySQL 更早支持)
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at, age
FROM users
WHERE age >= 18;

-- ============================================================
-- 2. 可更新视图
-- ============================================================
CREATE VIEW young_users AS
SELECT id, username, email, age FROM users WHERE age < 30
WITH CHECK OPTION;
-- WITH CHECK OPTION: INSERT/UPDATE 必须满足 WHERE 条件
-- WITH LOCAL CHECK OPTION: 只检查当前视图条件
-- WITH CASCADED CHECK OPTION: 检查所有嵌套视图条件 (默认)

-- ============================================================
-- 3. 视图算法
-- ============================================================
CREATE ALGORITHM=MERGE VIEW v_users AS SELECT * FROM users WHERE age > 18;
-- MERGE: 视图定义合并到外部查询 (性能最佳, 等价于内联展开)
-- TEMPTABLE: 先物化视图结果到临时表 (不可更新, 但避免锁竞争)
-- UNDEFINED: 优化器自动选择 (默认)
--
-- MariaDB 与 MySQL 的 ALGORITHM 选择逻辑相同:
--   包含聚合/DISTINCT/GROUP BY/UNION 的视图强制使用 TEMPTABLE

-- ============================================================
-- 4. 与系统版本表交互 (MariaDB 独有)
-- ============================================================
-- 可以在视图中使用 FOR SYSTEM_TIME
CREATE VIEW products_history AS
SELECT * FROM products FOR SYSTEM_TIME ALL;
-- 但不能在视图定义中使用时间参数 (只能查询时指定)
-- SELECT * FROM products FOR SYSTEM_TIME AS OF '2024-01-01';

-- ============================================================
-- 5. 对引擎开发者: 视图的实现策略
-- ============================================================
-- MERGE 策略实现:
--   解析视图 SQL → 将 WHERE/SELECT 合并到外部查询的 AST → 统一优化
--   难点: 列名冲突解析, 子查询展开, 表达式替换
-- TEMPTABLE 策略实现:
--   执行视图查询 → 结果存入内部临时表 → 外部查询读取临时表
--   难点: 临时表大小控制, 内存/磁盘切换, 统计信息缺失
-- 优化器选择依据: 视图是否可合并 (无聚合/DISTINCT/LIMIT等)
