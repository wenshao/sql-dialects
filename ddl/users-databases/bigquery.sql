-- BigQuery: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] BigQuery Documentation - CREATE SCHEMA (Dataset)
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_schema
--   [2] BigQuery Documentation - IAM & Access Control
--       https://cloud.google.com/bigquery/docs/access-control
--   [3] BigQuery Architecture - Slot-based Execution
--       https://cloud.google.com/bigquery/docs/slots

-- ============================================================
-- 1. BigQuery 命名层级: project > dataset > table
-- ============================================================

-- BigQuery 没有 CREATE DATABASE 和 CREATE USER。
-- 命名层级与传统数据库完全不同:
--
--   传统:    server → database → schema → table
--   BigQuery: organization → project → dataset → table
--
-- 映射关系:
--   project ≈ database（GCP 项目，计费单位，通过 GCP Console 创建）
--   dataset ≈ schema（访问控制边界，通过 SQL 创建）
--   table   ≈ table
--
-- 为什么没有 CREATE DATABASE?
-- BigQuery 的"数据库"是 GCP project，它不仅包含 BigQuery，
-- 还包含 Cloud Storage、Compute Engine 等所有 GCP 服务。
-- project 的生命周期由组织管理员控制，不适合用 SQL DDL 管理。

-- ============================================================
-- 2. Dataset 管理（BigQuery 的 "schema"）
-- ============================================================

CREATE SCHEMA myproject.mydataset;
CREATE SCHEMA IF NOT EXISTS myproject.mydataset;

-- 完整选项
CREATE SCHEMA myproject.mydataset
OPTIONS (
    location = 'US',                            -- 数据物理位置
    default_table_expiration_days = 90,          -- 表默认过期
    description = 'Main application dataset',
    labels = [('env', 'prod'), ('team', 'data')]
);

-- location 选项的重要性:
--   (a) 一旦设置不能更改（数据物理存储在指定区域）
--   (b) 跨区域 JOIN 不被允许（US 的 dataset 不能 JOIN EU 的 dataset）
--   (c) 影响合规性（GDPR 要求欧洲数据留在欧洲）
--   (d) 影响性能（就近访问更快）
--   对比: 传统数据库的 CREATE DATABASE 没有 location 概念（单机部署）

-- 修改 dataset
ALTER SCHEMA myproject.mydataset
SET OPTIONS (
    default_table_expiration_days = 180,
    description = 'Updated description'
);

-- 删除 dataset
DROP SCHEMA myproject.mydataset;
DROP SCHEMA IF EXISTS myproject.mydataset CASCADE;   -- 级联删除所有表

-- ============================================================
-- 3. 权限管理: IAM 模型（非 SQL GRANT）
-- ============================================================

-- BigQuery 使用 GCP IAM（Identity and Access Management），不用 SQL 的 CREATE USER。
-- 这是无服务器架构的核心设计:
--   没有数据库服务器 → 没有数据库连接 → 没有数据库用户
--   身份验证由 Google Cloud 统一管理（SSO、Service Account、OAuth）
--
-- 预定义角色层级:
--   roles/bigquery.dataViewer    → SELECT
--   roles/bigquery.dataEditor    → SELECT + INSERT/UPDATE/DELETE
--   roles/bigquery.dataOwner     → 完全数据控制
--   roles/bigquery.jobUser       → 运行查询（消耗 slot）
--   roles/bigquery.admin         → 全部权限
--
-- gcloud CLI 授权:
-- $ gcloud projects add-iam-policy-binding myproject \
--     --member="user:alice@example.com" \
--     --role="roles/bigquery.dataViewer"

-- SQL GRANT（BigQuery 特有语法，映射到 IAM）
GRANT `roles/bigquery.dataViewer`
ON SCHEMA myproject.mydataset
TO 'user:alice@example.com';

GRANT `roles/bigquery.dataEditor`
ON SCHEMA myproject.mydataset
TO 'serviceAccount:etl@myproject.iam.gserviceaccount.com';

REVOKE `roles/bigquery.dataViewer`
ON SCHEMA myproject.mydataset
FROM 'user:alice@example.com';

-- 设计对比:
--   MySQL:      CREATE USER 'alice'@'%' IDENTIFIED BY 'pass'; GRANT SELECT ON db.* TO 'alice';
--   PostgreSQL: CREATE USER alice WITH PASSWORD 'pass'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO alice;
--   ClickHouse: CREATE USER alice IDENTIFIED BY 'pass'; GRANT SELECT ON db.* TO alice;
--   BigQuery:   不创建用户，直接给 Google 身份授权

-- ============================================================
-- 4. 行级安全与列级安全
-- ============================================================

-- 行级安全策略
CREATE ROW ACCESS POLICY region_filter
ON myproject.mydataset.sales
GRANT TO ('user:alice@example.com', 'group:analysts@example.com')
FILTER USING (region = 'APAC');

-- 多个策略可以叠加（OR 逻辑）
CREATE ROW ACCESS POLICY us_filter
ON myproject.mydataset.sales
GRANT TO ('user:bob@example.com')
FILTER USING (region = 'US');

DROP ROW ACCESS POLICY region_filter ON myproject.mydataset.sales;

-- 列级安全通过 Data Catalog Policy Tag 实现（不在 SQL 中定义）
-- 可以标记 PII 列（如 SSN、email），只有授权用户才能查询这些列

-- 设计对比:
--   PostgreSQL: CREATE POLICY ... FOR SELECT USING (region = 'APAC') TO alice;
--   ClickHouse: CREATE ROW POLICY ... USING region = 'APAC' TO analyst;
--   BigQuery:   语法类似但基于 Google 身份（email/group），不是数据库用户

-- ============================================================
-- 5. Slot 模型: BigQuery 独有的计算资源管理
-- ============================================================

-- BigQuery 的计算资源是 "slot"（虚拟 CPU + 内存单位）。
-- 两种计费模式:
--   (a) On-demand: 按扫描数据量计费，slot 自动分配（默认）
--       → 适合低频、不可预测的查询负载
--   (b) Capacity: 购买固定 slot 数量（每月/每年）
--       → 适合高频、可预测的查询负载
--
-- Reservation（slot 预留）:
-- 通过 BigQuery Reservation API 管理，不通过 SQL:
--   Organization → Reservation（slot 池） → Assignment（分配给 project/folder）
--
-- 这与传统数据库的资源管理根本不同:
--   MySQL/PostgreSQL: max_connections, work_mem, shared_buffers
--   ClickHouse:       max_memory_usage, max_threads（用户级设置）
--   BigQuery:         slot 是全局共享的，不绑定到连接或用户

-- ============================================================
-- 6. 元数据查询
-- ============================================================

-- 数据集信息
SELECT schema_name, location, creation_time
FROM INFORMATION_SCHEMA.SCHEMATA;

-- 表信息
SELECT table_name, table_type, row_count, size_bytes
FROM myproject.mydataset.INFORMATION_SCHEMA.TABLES;

-- 列信息
SELECT table_name, column_name, data_type, is_nullable
FROM myproject.mydataset.INFORMATION_SCHEMA.COLUMNS;

-- 查询历史（成本分析）
SELECT user_email, query, total_bytes_processed, total_slot_ms
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY total_bytes_processed DESC
LIMIT 20;

-- ============================================================
-- 7. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 的身份和资源管理特点:
--   (1) 没有数据库用户 → 身份由云平台统一管理（IAM）
--   (2) Dataset = 访问控制边界 → location 不可变
--   (3) Slot 模型 → 计算资源与数据完全分离
--   (4) 行级/列级安全 → 集成到云治理体系（Data Catalog）
--
-- 对引擎开发者的启示:
--   云原生引擎不应该自建用户管理系统:
--   - 集成云 IAM（如 AWS IAM、GCP IAM）更安全、更标准
--   - 数据库用户名/密码是安全漏洞的主要来源
--   - Service Account（服务账号）比数据库密码更适合自动化场景
--   Slot 模型的启示:
--   - 计算资源应该是弹性可伸缩的，不绑定到数据库实例
--   - 这是 Snowflake（Virtual Warehouse）和 BigQuery（Slot）的共同设计
