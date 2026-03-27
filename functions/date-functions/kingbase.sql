-- KingbaseES (人大金仓): 日期函数
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 当前日期时间
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CLOCK_TIMESTAMP();
SELECT CURRENT_DATE;
SELECT LOCALTIME;
SELECT LOCALTIMESTAMP;

-- 构造日期
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIME(10, 30, 0);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 日期加减
SELECT '2024-01-15'::DATE + INTERVAL '1 day';
SELECT '2024-01-15'::DATE + INTERVAL '3 months';
SELECT '2024-01-15'::DATE + 7;
SELECT NOW() - INTERVAL '2 hours 30 minutes';

-- 日期差
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;
SELECT AGE('2024-12-31', '2024-01-01');

-- 提取
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DOW FROM NOW());
SELECT DATE_PART('year', NOW());

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');

-- 截断
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('year', NOW());

-- 时区转换
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';

-- 生成日期序列
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);

-- 注意事项：
-- 日期函数与 PostgreSQL 完全兼容
-- Oracle 兼容模式下也支持 SYSDATE、ADD_MONTHS 等
