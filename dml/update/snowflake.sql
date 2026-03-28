-- Snowflake: UPDATE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - UPDATE
--       https://docs.snowflake.com/en/sql-reference/sql/update

-- ============================================================
-- 1. 基本语法
-- ============================================================

UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 UPDATE 的微分区实现
-- 与 DELETE 类似，UPDATE 在 Snowflake 中不是原地修改:
--   (a) 扫描包含目标行的微分区
--   (b) 读取整个微分区数据
--   (c) 应用 SET 子句修改
--   (d) 将修改后的数据写入新微分区
--   (e) 原子替换元数据
--
-- 性能特征:
--   UPDATE 1 行（涉及 1 个微分区）: 重写 ~500MB 数据
--   UPDATE 分散在 N 个微分区的行: 重写 N × ~500MB 数据
--   这使得 Snowflake 不适合高频单行 UPDATE（OLTP 场景）
--
-- 对比:
--   MySQL InnoDB: 原地更新（in-place update），只修改页面中的行
--   PostgreSQL:   追加新版本（HOT update 优化减少索引更新）
--   Oracle:       原地更新 + UNDO 日志
--   BigQuery:     类似 Snowflake（重写受影响的分区）
--   Redshift:     DELETE + INSERT 模式（类似 Snowflake 但更显式）
--   Databricks:   Delta Lake 写新文件 + 标记旧文件删除
--
-- 对引擎开发者的启示:
--   不可变文件存储的 UPDATE 成本 = O(affected_partitions × partition_size)
--   传统行存的 UPDATE 成本 = O(affected_rows × row_size)
--   当 UPDATE 影响少量行但分散在多个分区时，不可变存储的代价很大。
--   优化方向: 聚簇键让相关行集中在少数分区中。

-- 2.2 FROM 子句多表 UPDATE
-- Snowflake 支持 FROM 子句（非 SQL 标准）:
UPDATE users u
SET u.status = 1
FROM orders o
WHERE u.id = o.user_id AND o.amount > 1000;

-- 多表 JOIN 更新:
UPDATE users u
SET u.status = 1
FROM orders o, payments p
WHERE u.id = o.user_id AND o.id = p.order_id AND p.amount > 1000;

-- 对比:
--   PostgreSQL: 也支持 FROM 子句（语法一致）
--   MySQL:      UPDATE t1 JOIN t2 ON ... SET t1.col = t2.col
--   Oracle:     不支持 FROM/JOIN，只能用子查询:
--               UPDATE t SET col = (SELECT val FROM s WHERE s.id = t.id)
--   SQL Server: UPDATE t SET col = s.val FROM t JOIN s ON t.id = s.id
--
-- 对引擎开发者的启示:
--   FROM 子句 vs 子查询 UPDATE 的执行计划差异:
--   FROM 子句: 优化器可以选择 Hash Join 等高效算法
--   子查询:    可能退化为每行执行一次子查询（嵌套循环）
--   支持 FROM 子句通常能产生更好的执行计划。

-- ============================================================
-- 3. CTE + UPDATE
-- ============================================================

WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u
SET u.status = 2
FROM vip v
WHERE u.id = v.user_id;

-- ============================================================
-- 4. 半结构化数据 (VARIANT) 的更新
-- ============================================================

-- 更新 VARIANT 中的字段（需要使用函数，无法直接修改路径）:
UPDATE events SET data = OBJECT_INSERT(data, 'source', 'web', TRUE)
WHERE event_name = 'login';
-- OBJECT_INSERT(object, key, value, TRUE) 的第 4 个参数表示允许覆盖已有 key

-- 删除 VARIANT 中的字段:
UPDATE events SET data = OBJECT_DELETE(data, 'temp_field');

-- 更新 ARRAY:
UPDATE users SET tags = ARRAY_APPEND(tags, 'premium') WHERE username = 'alice';

-- 嵌套路径更新: 不支持直接修改（需要重构整个 VARIANT）
-- data:address.city := 'Shanghai'  -- 不支持!
-- 需要: SET data = OBJECT_INSERT(data, 'address',
--        OBJECT_INSERT(data:address, 'city', 'Shanghai', TRUE), TRUE)
--
-- 对比:
--   PostgreSQL JSONB: jsonb_set(data, '{address,city}', '"Shanghai"') — 更简洁
--   MySQL JSON:       JSON_SET(data, '$.address.city', 'Shanghai') — 最简洁
--   Snowflake:        OBJECT_INSERT 嵌套调用 — 最繁琐
--
-- 对引擎开发者的启示:
--   VARIANT 的嵌套更新是 Snowflake 的明显短板。
--   PostgreSQL 的 jsonb_set 和 MySQL 的 JSON_SET 提供了更好的 API。
--   如果引擎支持半结构化类型，路径级别的原地更新 API 是必要的。

-- ============================================================
-- 5. 基于子查询的批量更新
-- ============================================================

UPDATE users u SET
    email = t.new_email
FROM (SELECT 'alice' AS username, 'alice_new@example.com' AS new_email
      UNION ALL
      SELECT 'bob', 'bob_new@example.com') t
WHERE u.username = t.username;

-- ============================================================
-- 横向对比: UPDATE 能力矩阵
-- ============================================================
-- 能力            | Snowflake      | BigQuery     | PostgreSQL  | MySQL
-- 基本 UPDATE     | 支持           | 支持         | 支持        | 支持
-- FROM/JOIN 更新  | FROM           | FROM         | FROM        | JOIN
-- CTE + UPDATE    | 支持           | 支持         | 支持        | 支持(8.0+)
-- VARIANT 更新    | OBJECT_INSERT  | N/A          | jsonb_set   | JSON_SET
-- RETURNING       | 不支持         | 不支持       | 支持        | 不支持
-- LIMIT UPDATE    | 不支持         | 不支持       | 不支持      | 支持
-- ON UPDATE       | 不支持         | 不支持       | 触发器      | 触发器/列属性
