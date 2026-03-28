-- MaxCompute (ODPS): 动态 SQL
--
-- 参考资料:
--   [1] MaxCompute SQL - Script Mode
--       https://help.aliyun.com/zh/maxcompute/user-guide/script-mode

-- ============================================================
-- 1. MaxCompute 不支持服务端动态 SQL —— 设计决策
-- ============================================================

-- 不支持:
--   PREPARE / EXECUTE（参数化查询）
--   EXECUTE IMMEDIATE（动态执行字符串）
--   存储过程中的动态 SQL
--
-- 为什么?
--   MaxCompute 没有"会话"概念: 每个 SQL 是独立的分布式作业
--   没有服务端游标: 不能逐步执行 SQL 片段
--   安全考虑: 动态拼接 SQL 有注入风险（云服务更敏感）
--
-- 对比:
--   MySQL:      PREPARE stmt FROM @sql; EXECUTE stmt;
--   PostgreSQL: EXECUTE format('SELECT * FROM %I', tbl);
--   Oracle:     EXECUTE IMMEDIATE sql_string;
--   BigQuery:   EXECUTE IMMEDIATE sql_string;（支持!）
--   Snowflake:  EXECUTE IMMEDIATE sql_string;（存储过程中）
--   Hive:       不支持（与 MaxCompute 相同）

-- ============================================================
-- 2. Script Mode 中的变量替换
-- ============================================================

-- Script Mode 支持变量，但有重要限制
SET @today = TO_CHAR(GETDATE(), 'yyyyMMdd');
SET @yesterday = TO_CHAR(DATEADD(GETDATE(), -1, 'dd'), 'yyyyMMdd');

-- 变量用于 WHERE 条件（可以）
SELECT * FROM orders WHERE dt = @yesterday;

-- 变量用于 PARTITION 值（可以）
INSERT OVERWRITE TABLE daily_summary PARTITION (dt = @yesterday)
SELECT user_id, SUM(amount)
FROM orders WHERE dt = @yesterday
GROUP BY user_id;

-- 限制: 变量不能用于表名替换
-- SET @table_name = 'users';
-- SELECT * FROM @table_name;  -- 语法错误!

-- 限制: 变量不能用于列名
-- SET @col = 'age';
-- SELECT @col FROM users;    -- 返回字符串 'age'，不是列值!

-- ============================================================
-- 3. DataWorks 调度中的变量替换
-- ============================================================

-- DataWorks 是 MaxCompute 的调度平台
-- 支持在 SQL 提交前做文本替换（宏展开）

-- ${bizdate}: 业务日期（通常是 T-1）
-- ${yyyymmdd}: 当前日期
-- ${table_name}: 自定义参数

-- 示例（在 DataWorks SQL 节点中）:
-- SELECT * FROM ${table_name} WHERE dt = '${bizdate}';
-- DataWorks 在提交前将 ${bizdate} 替换为实际日期字符串

-- 这是文本替换，不是参数化查询:
--   优点: 可以替换表名、列名、任意 SQL 片段
--   缺点: 有 SQL 注入风险（但 DataWorks 环境受控，风险可控）

-- ============================================================
-- 4. 应用层动态 SQL: PyODPS
-- ============================================================

-- PyODPS 是 MaxCompute 的 Python SDK
-- 动态 SQL 在应用层拼接:

-- from odps import ODPS
-- o = ODPS(access_id, access_key, project, endpoint)
--
-- # 动态表名
-- table_name = 'users'
-- result = o.execute_sql(f'SELECT COUNT(*) FROM {table_name}')
--
-- # 动态分区
-- partitions = ['20240101', '20240102', '20240103']
-- for dt in partitions:
--     sql = f"INSERT OVERWRITE TABLE summary PARTITION (dt='{dt}') "
--     sql += f"SELECT user_id, SUM(amount) FROM orders WHERE dt='{dt}' GROUP BY user_id"
--     o.execute_sql(sql)
--
-- # 动态列名
-- columns = ['age', 'balance', 'score']
-- select_clause = ', '.join(columns)
-- result = o.execute_sql(f'SELECT {select_clause} FROM users')

-- 安全注意: PyODPS 拼接 SQL 需要防止注入
-- 最佳实践: 验证输入值（白名单表名/列名）

-- ============================================================
-- 5. Java SDK 动态 SQL
-- ============================================================

-- import com.aliyun.odps.Odps;
-- import com.aliyun.odps.task.SQLTask;
--
-- String tableName = "users";  // 从配置或参数获取
-- String sql = String.format("SELECT COUNT(*) FROM %s", tableName);
-- Instance instance = SQLTask.run(odps, sql);
-- instance.waitForSuccess();

-- ============================================================
-- 6. 横向对比: 动态 SQL 能力
-- ============================================================

-- 服务端动态 SQL:
--   MaxCompute: 不支持             | BigQuery: EXECUTE IMMEDIATE
--   Snowflake:  EXECUTE IMMEDIATE  | PostgreSQL: EXECUTE / DO $$
--   Oracle:     EXECUTE IMMEDIATE  | MySQL: PREPARE/EXECUTE
--   Hive:       不支持

-- 变量系统:
--   MaxCompute: SET @var（常量赋值）  | BigQuery: DECLARE var（查询赋值）
--   Snowflake:  SET var（查询赋值）   | PostgreSQL: DO $$ DECLARE
--   MySQL:      SET @var             | Hive: SET hivevar:var

-- 调度层变量:
--   MaxCompute: DataWorks ${var}     | BigQuery: Scheduled Queries 参数
--   Snowflake:  Snowflake Tasks      | Hive: Oozie/Airflow 参数

-- ============================================================
-- 7. 常见动态 SQL 场景及 MaxCompute 解决方案
-- ============================================================

-- 场景 1: 按日期循环处理多个分区
-- 解决: DataWorks 调度 + ${bizdate} 变量 + 定时任务

-- 场景 2: 根据配置表动态生成 SQL
-- 解决: PyODPS 读取配置表 → 拼接 SQL → execute_sql

-- 场景 3: 动态 PIVOT（事先不知道列名）
-- 解决: PyODPS 查询 DISTINCT 值 → 拼接 CASE WHEN 语句

-- 场景 4: 多表合并（表名从配置获取）
-- 解决: PyODPS 循环拼接 UNION ALL

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- 1. BigQuery 的 EXECUTE IMMEDIATE 证明了批处理引擎可以支持动态 SQL
-- 2. 变量系统应支持查询赋值（SET var = SELECT ...） — 否则价值有限
-- 3. 调度层变量替换（文本宏展开）是简单但有效的动态 SQL 方案
-- 4. 应用层 SDK 拼接是最灵活的方案 — 但需要防注入机制
-- 5. 参数化查询（PREPARE/EXECUTE）可以防止注入 — 应优先支持
-- 6. 控制流（IF/WHILE）+ 动态 SQL = 完整的脚本能力（BigQuery 的方案）
