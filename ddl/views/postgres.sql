-- PostgreSQL: Views (视图)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE VIEW
--       https://www.postgresql.org/docs/current/sql-createview.html
--   [2] PostgreSQL Documentation - CREATE MATERIALIZED VIEW
--       https://www.postgresql.org/docs/current/sql-creatematerializedview.html
--   [3] PostgreSQL Documentation - Rules System (视图底层机制)
--       https://www.postgresql.org/docs/current/rules.html

-- ============================================================
-- 1. 基本视图
-- ============================================================

CREATE VIEW active_users AS
SELECT id, username, email, created_at FROM users WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at FROM users WHERE age >= 18;

CREATE TEMPORARY VIEW temp_view AS SELECT id, username FROM users;

-- 递归视图（9.3+，语法糖——展开为 WITH RECURSIVE CTE）
CREATE RECURSIVE VIEW employee_hierarchy (id, name, manager_id, level) AS
    SELECT id, name, manager_id, 1 FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, eh.level + 1
    FROM employees e JOIN employee_hierarchy eh ON e.manager_id = eh.id;

-- ============================================================
-- 2. 视图的内部实现: 规则系统 (Rule System)
-- ============================================================

-- PostgreSQL 视图不是"存储的查询"，而是通过规则系统实现的:
--   CREATE VIEW 实际上创建了一个空表 + 一条 _RETURN 规则。
--   查询视图时，规则系统将 SELECT 重写为视图定义的查询。
--
-- 可以在 pg_rewrite 中看到:
-- SELECT ev_type, ev_action FROM pg_rewrite
-- WHERE ev_class = 'active_users'::regclass;
--
-- 设计 trade-off:
--   优点: 视图展开发生在查询重写阶段（优化器之前），
--         可以与外部查询合并优化
--   缺点: 规则系统本身复杂度高，INSTEAD 规则的语义晦涩
--         （社区曾讨论用 INSTEAD OF 触发器完全替代规则系统）

-- ============================================================
-- 3. 可更新视图 + WITH CHECK OPTION
-- ============================================================

-- PostgreSQL 自动支持简单单表视图的 DML（无需触发器）
-- 条件: 只有一个 FROM 项，无聚合/分组/DISTINCT/LIMIT/UNION
CREATE VIEW adult_users AS
SELECT id, username, email, age FROM users WHERE age >= 18
WITH CHECK OPTION;                -- 9.4+: INSERT/UPDATE 必须满足 WHERE 条件

-- 嵌套视图的检查行为
CREATE VIEW premium_users AS
SELECT id, username, email, age FROM adult_users WHERE balance > 1000
WITH CASCADED CHECK OPTION;       -- CASCADED: 检查所有层级的 WHERE 条件
-- WITH LOCAL CHECK OPTION;       -- LOCAL: 只检查当前视图的 WHERE 条件

-- 复杂视图的 DML: 使用 INSTEAD OF 触发器
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON complex_view
    FOR EACH ROW EXECUTE FUNCTION handle_view_insert();

-- ============================================================
-- 4. Security Barrier 视图（9.2+）
-- ============================================================

CREATE VIEW secure_users WITH (security_barrier = true) AS
SELECT id, username, email FROM users
WHERE department = current_setting('app.department');

-- 为什么需要 security_barrier:
--   普通视图的 WHERE 条件可能被优化器"下推"到用户函数之后执行。
--   恶意用户定义的函数可以在 WHERE 过滤之前看到不该看的行。
--   security_barrier 强制视图 WHERE 先于用户条件执行（防止信息泄露）。
--
-- 代价: security_barrier 会阻止一些优化（如谓词下推），性能可能下降。
-- 结合 RLS（行级安全）使用效果更好。

-- ============================================================
-- 5. 物化视图 (Materialized View, 9.3+)
-- ============================================================

CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders GROUP BY user_id;

-- 不填充数据创建
CREATE MATERIALIZED VIEW mv_empty AS
SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id
WITH NO DATA;

-- 刷新
REFRESH MATERIALIZED VIEW mv_order_summary;               -- 全量刷新（阻塞读取）
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary;   -- 并发刷新（不阻塞读取，9.4+）
-- CONCURRENTLY 要求物化视图有 UNIQUE 索引

-- 在物化视图上创建索引
CREATE UNIQUE INDEX idx_mv_user ON mv_order_summary (user_id);

-- 设计分析: 为什么 PostgreSQL 不支持自动刷新
--   PostgreSQL 物化视图是"手动刷新"模型:
--   (a) 自动增量刷新（如 Oracle）需要物化视图日志，实现复杂
--   (b) 全量 REFRESH 语义清晰，CONCURRENTLY 解决了读阻塞问题
--   (c) 可通过 pg_cron 扩展定时刷新:
--       SELECT cron.schedule('*/30 * * * *',
--           'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary');
--
-- 对比:
--   Oracle:     REFRESH ON COMMIT / ON DEMAND + 物化视图日志（增量刷新，最完善）
--   SQL Server: Indexed View（自动维护，但限制极多——不能 GROUP BY 多表等）
--   MySQL:      无物化视图
--   BigQuery:   物化视图自动增量刷新（底层 Google 基础设施支持）

-- ============================================================
-- 6. CONCURRENTLY 刷新的内部机制
-- ============================================================

-- REFRESH MATERIALIZED VIEW CONCURRENTLY 的实现:
--   (1) 将新查询结果写入临时表
--   (2) 与旧数据做 diff（通过 UNIQUE 索引比较）
--   (3) 删除旧数据中不存在的行，插入新增的行，更新变化的行
--   (4) 全程只持 ExclusiveLock（允许 SELECT，阻塞其他 REFRESH）
--
-- 为什么需要 UNIQUE 索引:
--   diff 算法需要唯一键来匹配新旧行。没有 UNIQUE 索引，
--   PostgreSQL 无法确定哪些行"相同"（新增 vs 不变 vs 变化）。

-- ============================================================
-- 7. 横向对比: 视图能力
-- ============================================================

-- 1. 可更新视图:
--   PostgreSQL: 简单视图自动可更新（9.3+），复杂视图用 INSTEAD OF 触发器
--   MySQL:      简单视图可更新（WITH CHECK OPTION 支持）
--   Oracle:     INSTEAD OF 触发器（最灵活），也支持简单视图自动更新
--   SQL Server: 简单视图可更新，INSTEAD OF 触发器
--
-- 2. 物化视图:
--   PostgreSQL: 9.3+ 手动刷新，无增量刷新
--   Oracle:     最完善（ON COMMIT/ON DEMAND + MV Log 增量刷新）
--   SQL Server: Indexed View（自动维护，限制多）
--   MySQL:      不支持
--   BigQuery:   自动增量刷新
--
-- 3. Security Barrier:
--   PostgreSQL: security_barrier 选项（9.2+）
--   其他:       无等价功能（需要应用层处理）

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) 视图通过规则系统（query rewrite）而非"存储查询"实现:
--     这使得视图 WHERE 条件可以与外部查询合并优化。
--     但规则系统的复杂性是 PostgreSQL 的历史包袱。
--
-- (2) 物化视图的增量刷新是一个开放难题:
--     PostgreSQL 选择不实现增量刷新（全量 REFRESH + CONCURRENTLY），
--     而 Oracle 的 MV Log 方案虽然完善但实现极其复杂。
--     对新引擎，可以考虑 Change Data Capture (CDC) 驱动的增量刷新。
--
-- (3) security_barrier 是安全视图的关键:
--     没有 security_barrier，视图作为安全边界是不可靠的
--     （优化器可能让用户函数在行过滤之前执行）。

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- PostgreSQL 9.2:  security_barrier 视图选项
-- PostgreSQL 9.3:  物化视图, 自动可更新视图, 递归视图
-- PostgreSQL 9.4:  REFRESH CONCURRENTLY, WITH CHECK OPTION
-- PostgreSQL 12:   物化视图支持 CREATE OR REPLACE（部分场景）
-- PostgreSQL 15:   物化视图支持 CLUSTER 命令
