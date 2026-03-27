-- Materialize: 日期函数

-- Materialize 兼容 PostgreSQL 日期函数

-- 当前时间
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURRENT_DATE;
SELECT mz_now();                             -- Materialize 特有

-- 日期加减
SELECT NOW() + INTERVAL '1 day';
SELECT NOW() - INTERVAL '3 hours';
SELECT INTERVAL '1 year 2 months';

-- 日期差
SELECT AGE(NOW(), '2024-01-01'::TIMESTAMPTZ);

-- 提取
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DOW FROM NOW());
SELECT DATE_PART('hour', NOW());

-- 截断
SELECT DATE_TRUNC('hour', NOW());
SELECT DATE_TRUNC('day', NOW());
SELECT DATE_TRUNC('month', NOW());

-- 格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');

-- 解析
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 时区转换
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';

-- EPOCH 转换
SELECT EXTRACT(EPOCH FROM NOW());
SELECT TO_TIMESTAMP(1705286400);

-- 生成时间序列
SELECT generate_series(
    '2024-01-01'::TIMESTAMPTZ,
    '2024-01-07'::TIMESTAMPTZ,
    INTERVAL '1 day'
);

-- 注意：兼容 PostgreSQL 的日期函数
-- 注意：mz_now() 返回 Materialize 系统时钟
-- 注意：NOW() 在物化视图中有特殊行为
