-- Apache Doris: 分页
--
-- 参考资料:
--   [1] Doris Documentation - SELECT
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. LIMIT / OFFSET (MySQL 兼容)
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
SELECT * FROM users ORDER BY id LIMIT 20, 10;  -- MySQL 简写
SELECT * FROM users ORDER BY id LIMIT 10;

-- 带总行数
SELECT *, COUNT(*) OVER() AS total_count FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. OFFSET 性能问题 (MPP 架构放大)
-- ============================================================
-- OFFSET 100000, LIMIT 10:
--   单机: 扫描 100010 行，丢弃 100000 行
--   MPP(3 BE): 每个 BE 返回 100010 行到 FE → 3×100010 行网络传输
-- 结论: 大 OFFSET 在 MPP 架构下代价极高。

-- ============================================================
-- 3. 键集分页 (Keyset Pagination，推荐)
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10;              -- 第一页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10; -- 后续页

-- 多列排序
SELECT * FROM users
WHERE (created_at, id) < ('2025-01-15', 42)
ORDER BY created_at DESC, id DESC LIMIT 10;

-- ============================================================
-- 4. Top-N 优化
-- ============================================================
-- ORDER BY + LIMIT 自动使用堆排序(Heap Sort):
-- 复杂度从 O(M*logM) 降到 O(M*logN)
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;

-- 分组 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- 对比:
--   Doris:      LIMIT/OFFSET(MySQL 兼容)
--   StarRocks:  完全相同(同源)
--   ClickHouse: LIMIT OFFSET + LIMIT BY(分组取前 N，独有)
--   BigQuery:   LIMIT OFFSET + QUALIFY(窗口过滤)
