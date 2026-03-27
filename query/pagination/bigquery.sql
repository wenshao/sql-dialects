-- BigQuery: 分页
--
-- 参考资料:
--   [1] BigQuery SQL Reference - LIMIT and OFFSET
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#limit_and_offset_clause

-- ============================================================
-- 1. LIMIT / OFFSET
-- ============================================================

SELECT * FROM myproject.mydataset.users ORDER BY id LIMIT 10;
SELECT * FROM myproject.mydataset.users ORDER BY id LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. QUALIFY: BigQuery 独有的分组过滤
-- ============================================================

-- Top-N per group（不需要子查询）
SELECT user_id, order_date, amount
FROM myproject.mydataset.orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_date DESC) <= 3;
-- → 每个用户最近的 3 个订单

-- 设计分析:
--   QUALIFY 是 BigQuery/Snowflake 独有的子句。
--   作用: 在窗口函数计算后过滤（类似 HAVING 对聚合函数）。
--   替代了: 外层 SELECT + WHERE rn <= 3 的子查询模式。
--   对比 ClickHouse 的 LIMIT BY: 功能相似但 QUALIFY 更通用（支持任意窗口函数）。

-- ============================================================
-- 3. BigQuery 分页的特殊考虑
-- ============================================================

-- BigQuery 不适合传统的 Web 应用分页:
-- (a) 每次查询都是独立的 slot 调度 → 无法保持"游标"状态
-- (b) 查询结果不能"跨请求复用" → OFFSET 分页每次都全量计算
-- (c) 按扫描量计费 → 每次分页都扫描全表 → 成本高
--
-- 推荐做法:
-- (1) 一次查询获取所有需要的数据 → 前端分页
-- (2) 导出到 GCS → 分段下载
-- (3) BigQuery Storage Read API → 流式读取大结果集
-- (4) 使用物化视图/预聚合 → 减少每次查询的数据量

-- LIMIT 不节省成本!
-- SELECT * FROM huge_table LIMIT 10;
-- → BigQuery 仍然扫描全表（按全量计费），然后返回 10 行
-- → 只有 WHERE + 分区裁剪 才能减少扫描量

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 分页的设计:
--   (1) QUALIFY → 窗口函数后过滤（替代子查询）
--   (2) LIMIT 不减少扫描量 → 成本模型的重要差异
--   (3) 无状态查询 → 不适合传统 OFFSET 分页
--
-- 对引擎开发者的启示:
--   QUALIFY 是优秀的语法设计:
--   WHERE/HAVING/QUALIFY 三层过滤 = 行过滤/聚合过滤/窗口过滤。
--   按扫描量计费的引擎中，LIMIT 不等于"少花钱":
--   用户需要理解 LIMIT 只是截断结果，不是减少扫描。
