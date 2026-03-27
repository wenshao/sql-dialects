-- TDengine: Type Conversion
--
-- 参考资料:
--   [1] TDengine Documentation
--       https://docs.tdengine.com/reference/sql/function/

SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INT);
SELECT CAST('42' AS BIGINT); SELECT CAST(42 AS FLOAT);

-- 时间戳转换
-- SELECT CAST(ts AS BIGINT) FROM meters;        -- 时间戳 → 毫秒数
-- SELECT CAST(1705276800000 AS TIMESTAMP);       -- 毫秒数 → 时间戳

-- 注意：TDengine CAST 类型有限
-- 注意：时间戳以毫秒为单位
-- 限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER, TO_CHAR, TO_DATE
