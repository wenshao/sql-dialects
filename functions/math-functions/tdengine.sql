-- TDengine: Math Functions
--
-- 参考资料:
--   [1] TDengine Documentation - Functions
--       https://docs.tdengine.com/reference/sql/function/

SELECT ABS(-42); SELECT CEIL(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159);
SELECT MOD(17, 5);
SELECT SQRT(144);
SELECT LOG(EXP(1));

-- TDengine 特有时序计算函数
-- SELECT DERIVATIVE(value, 1s, 0) FROM meters;     -- 导数
-- SELECT DIFF(value) FROM meters;                   -- 差值
-- SELECT SPREAD(value) FROM meters;                 -- 极差

-- 注意：TDengine 面向时序数据，数学函数有限
-- 注意：提供时序计算特有函数（DERIVATIVE, DIFF, SPREAD）
-- 限制：无三角函数
-- 限制：无 POWER, EXP, PI 等
