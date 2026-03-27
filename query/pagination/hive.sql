-- Hive: 分页
--
-- 参考资料:
--   [1] Apache Hive Language Manual - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select
--   [2] Apache Hive - Sort/Distribute By
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+SortBy

-- LIMIT（所有版本）
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT / OFFSET（2.0+）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 窗口函数分页（0.11+）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE t.rn BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- SORT BY + LIMIT（局部排序，每个 Reducer 内排序）
SELECT * FROM users SORT BY id LIMIT 10;

-- ORDER BY + LIMIT（全局排序，所有数据汇聚到一个 Reducer）
SELECT * FROM users ORDER BY id LIMIT 10;

-- 注意：Hive 2.0 之前不支持 OFFSET，只能使用窗口函数实现分页
-- 注意：Hive 不支持 FETCH FIRST ... ROWS ONLY 标准语法
-- 注意：ORDER BY 在 Hive 中会将所有数据发送到一个 Reducer，大数据量下非常慢
-- 注意：建议使用 SORT BY（局部排序）+ LIMIT 替代 ORDER BY 全局排序
-- 注意：DISTRIBUTE BY + SORT BY 可实现分区内排序
