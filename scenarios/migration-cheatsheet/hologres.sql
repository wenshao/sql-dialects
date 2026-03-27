-- Hologres: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Hologres Documentation
--       https://help.aliyun.com/document_detail/130408.html

-- 一、与 PostgreSQL 兼容性: 兼容PostgreSQL 11协议和语法
--   差异: 列存+行存混合引擎, 实时分析场景, 与MaxCompute互通
-- 二、数据类型: 与PostgreSQL基本相同
--   差异: 不支持部分PG类型(如自定义类型/域), JSONB支持, ARRAY支持
-- 三、陷阱: OLAP实时数仓(不适合OLTP), 建表需要选择列存/行存/行列混存,
--   Distribution Key(分布键)影响查询性能, Segment Key(分段键)用于数据裁剪,
--   Clustering Key(聚簇键)优化排序, 与MaxCompute外表互通
-- 四、自增: SERIAL（但建议使用应用层生成ID）
-- 五、日期/字符串: 与 PostgreSQL 相同
--   NOW(); CURRENT_TIMESTAMP; CURRENT_DATE;
--   TO_CHAR(ts, 'YYYY-MM-DD HH24:MI:SS'); TO_DATE('2024-01-15', 'YYYY-MM-DD');
-- 六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, POSITION, ||

-- ============================================================
-- 七、数据类型映射（从 PostgreSQL/MySQL 到 Hologres）
-- ============================================================
-- PostgreSQL → Hologres: 基本兼容
--   INT → INT, TEXT → TEXT, JSONB → JSONB,
--   TIMESTAMPTZ → TIMESTAMPTZ, BOOLEAN → BOOLEAN,
--   SERIAL → SERIAL, ARRAY → ARRAY (部分支持)
-- MySQL → Hologres:
--   INT → INT, VARCHAR(n) → VARCHAR(n)/TEXT,
--   DATETIME → TIMESTAMP, TINYINT(1) → BOOLEAN,
--   JSON → JSONB, AUTO_INCREMENT → SERIAL
-- MaxCompute → Hologres:
--   STRING → TEXT, BIGINT → BIGINT, DOUBLE → FLOAT8,
--   DECIMAL → DECIMAL, DATETIME → TIMESTAMP

-- 八、函数等价映射
-- MySQL → Hologres:
--   IFNULL → COALESCE, NOW() → NOW(),
--   DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_DATE,
--   CONCAT(a,b) → a || b, GROUP_CONCAT → STRING_AGG,
--   LIMIT → LIMIT

-- 九、常见陷阱补充
--   建表选择存储模式: 列存(分析)、行存(点查)、行列混存
--   Distribution Key 选择影响数据分布和查询效率
--   Segment Key 用于时间裁剪（时序数据推荐）
--   Clustering Key 优化排序扫描
--   与 MaxCompute 可通过外表互通
--   不支持 UPDATE/DELETE（行存表除外）
--   OLAP 实时数仓，不适合高并发 OLTP

-- 十、NULL 处理
-- COALESCE(a, b, c)                                  -- 返回第一个非 NULL
-- NULLIF(a, b)                                       -- a=b 时返回 NULL

-- 十一、分页语法
-- SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- 十二、MaxCompute 外表查询
-- CREATE FOREIGN TABLE mc_table (id int, name text)
--   SERVER odps_server OPTIONS (project 'prj', table 'tbl');
