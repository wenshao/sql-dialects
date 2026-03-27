-- Greenplum: 索引
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- Greenplum 基于 PostgreSQL，支持大部分 PG 索引类型
-- 但在 MPP 架构下，索引策略需要额外考虑

-- ============================================================
-- B-tree 索引（默认）
-- ============================================================

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_age ON users (age);

-- 唯一索引（必须包含分布键）
CREATE UNIQUE INDEX idx_users_email_id ON users (email, id);

-- 多列索引
CREATE INDEX idx_users_city_age ON users (city, age);

-- 降序索引
CREATE INDEX idx_users_age_desc ON users (age DESC);

-- 条件索引（部分索引）
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

-- 并发创建（不锁表）
CREATE INDEX CONCURRENTLY idx_users_created ON users (created_at);

-- ============================================================
-- GiST 索引（通用搜索树）
-- ============================================================

-- 范围查询、几何类型
CREATE INDEX idx_events_range ON events USING GIST (tsrange(start_time, end_time));

-- ============================================================
-- GIN 索引（倒排索引，全文搜索）
-- ============================================================

CREATE INDEX idx_articles_search ON articles USING GIN (to_tsvector('english', content));

-- JSON / JSONB 索引
CREATE INDEX idx_data_gin ON events USING GIN (data jsonb_path_ops);

-- 数组索引
CREATE INDEX idx_tags ON articles USING GIN (tags);

-- ============================================================
-- Bitmap 索引（Greenplum 特有，低基数列优化）
-- ============================================================

-- Greenplum 特有，适合 AO 表上的低基数列
CREATE INDEX idx_status_bmp ON users USING BITMAP (status);
CREATE INDEX idx_region_bmp ON orders USING BITMAP (region);

-- ============================================================
-- BRIN 索引（Block Range Index，大表顺序数据）
-- ============================================================

CREATE INDEX idx_orders_date_brin ON orders USING BRIN (order_date);

-- ============================================================
-- 索引管理
-- ============================================================

-- 删除索引
DROP INDEX idx_users_email;
DROP INDEX IF EXISTS idx_users_email;
DROP INDEX CONCURRENTLY idx_users_email;

-- 重建索引
REINDEX INDEX idx_users_email;
REINDEX TABLE users;

-- 查看索引
SELECT * FROM pg_indexes WHERE tablename = 'users';

-- ============================================================
-- 索引使用建议
-- ============================================================

-- 在分布式环境下索引的效果取决于查询模式
-- AO 表推荐 Bitmap 索引
-- Heap 表推荐 B-tree 索引
-- 大表的时间列推荐 BRIN 索引
-- 全文搜索推荐 GIN 索引

-- 注意：索引在每个 Segment 上独立创建
-- 注意：UNIQUE 索引必须包含分布键
-- 注意：AO 表不支持 UNIQUE 索引
-- 注意：索引在分析型负载中不一定有效（全表扫描可能更快）
