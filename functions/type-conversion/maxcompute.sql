-- MaxCompute: Type Conversion
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - Type Conversion
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/type-conversions

SELECT CAST(42 AS STRING); SELECT CAST('42' AS BIGINT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('3.14' AS DECIMAL(10,2));

-- 日期转换
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT TO_CHAR(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800);
SELECT UNIX_TIMESTAMP('2024-01-15 00:00:00');

-- 隐式转换
SELECT '42' + 0;

-- 更多数值转换
SELECT CAST('100' AS INT);                           -- 100
SELECT CAST(3.14 AS BIGINT);                         -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(42 AS FLOAT);                            -- 42.0
SELECT CAST(TRUE AS BIGINT);                         -- 1
SELECT CAST(0 AS BOOLEAN);                           -- false

-- 日期/时间格式化
SELECT TO_CHAR(GETDATE(), 'yyyy-MM-dd HH:mm:ss');
SELECT TO_CHAR(GETDATE(), 'yyyy年MM月dd日');
SELECT TO_CHAR(GETDATE(), 'yyyyMMdd');
SELECT TO_DATE('20240115', 'yyyyMMdd');
SELECT TO_DATE('2024/01/15', 'yyyy/MM/dd');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP(GETDATE());

-- 日期部分提取
SELECT YEAR(GETDATE());                              -- 2024
SELECT MONTH(GETDATE());                             -- 1
SELECT DAY(GETDATE());                               -- 15
SELECT HOUR(GETDATE());                              -- 10

-- 数值格式化
-- MaxCompute 无内置数值格式化函数
-- 使用 CONCAT + CAST 手动格式化

-- JSON 转换 (MaxCompute 2.0)
SELECT GET_JSON_OBJECT('{"a":1}', '$.a');

-- 复合类型转换
SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<STRING>);
-- SELECT CAST(MAP('k1', 'v1') AS MAP<STRING, STRING>);

-- 隐式转换
SELECT '42' + 0;                                     -- 42
SELECT CONCAT('val: ', 42);                          -- 隐式转字符串
SELECT 1 + 1.5;                                     -- DOUBLE

-- 错误处理（无 TRY_CAST）
-- CAST 转换失败直接报错并中止任务
-- 建议在上游数据处理阶段清洗数据

-- 注意：MaxCompute 类型转换与 Hive 类似
-- 注意：日期模式使用 Java SimpleDateFormat (yyyy, MM, dd, HH, mm, ss)
-- 注意：MaxCompute 2.0 增加了 DATE, TIMESTAMP, DECIMAL 类型
-- 限制：无 TRY_CAST, ::, CONVERT
