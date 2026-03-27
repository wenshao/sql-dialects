-- BigQuery: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] BigQuery Documentation - CREATE SCHEMA (Dataset)
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_schema
--   [2] BigQuery Documentation - IAM & Access Control
--       https://cloud.google.com/bigquery/docs/access-control

-- ============================================================
-- BigQuery 命名层级: project > dataset > table
-- - project ≈ database（GCP 项目，不通过 SQL 创建）
-- - dataset ≈ schema（通过 SQL 或 API 创建）
-- - 没有 CREATE DATABASE / CREATE USER
-- - 权限通过 IAM 管理
-- ============================================================

-- ============================================================
-- 1. Dataset（数据集）管理
-- ============================================================

-- 创建数据集（相当于 schema）
CREATE SCHEMA myproject.mydataset;
CREATE SCHEMA IF NOT EXISTS myproject.mydataset;

CREATE SCHEMA myproject.mydataset
OPTIONS (
    location = 'US',                            -- 数据位置（US, EU, asia-east1 等）
    default_table_expiration_days = 90,          -- 表默认过期天数
    description = 'Main application dataset',
    labels = [('env', 'prod'), ('team', 'data')]
);

-- 修改数据集
ALTER SCHEMA myproject.mydataset
SET OPTIONS (
    default_table_expiration_days = 180,
    description = 'Updated description'
);

-- 删除数据集
DROP SCHEMA myproject.mydataset;
DROP SCHEMA IF EXISTS myproject.mydataset CASCADE;  -- 级联删除所有表

-- ============================================================
-- 2. 项目（Project）管理
-- ============================================================

-- BigQuery 项目通过 GCP Console / gcloud CLI 管理，不通过 SQL
-- $ gcloud projects create my-project-id --name="My Project"
-- $ gcloud projects delete my-project-id

-- 默认项目设置（bq CLI）
-- $ bq --project_id=myproject query 'SELECT 1'

-- ============================================================
-- 3. 用户与权限（IAM，非 SQL）
-- ============================================================

-- BigQuery 使用 GCP IAM 进行权限管理，不使用 SQL 的 CREATE USER / GRANT
-- 常用角色：
-- - roles/bigquery.dataViewer    -- 读取数据
-- - roles/bigquery.dataEditor    -- 读写数据
-- - roles/bigquery.dataOwner     -- 完全控制数据
-- - roles/bigquery.jobUser       -- 运行查询
-- - roles/bigquery.admin         -- 完全管理权限

-- gcloud CLI 授权示例：
-- $ gcloud projects add-iam-policy-binding myproject \
--     --member="user:alice@example.com" \
--     --role="roles/bigquery.dataViewer"

-- 数据集级别权限（SQL）
GRANT `roles/bigquery.dataViewer`
ON SCHEMA myproject.mydataset
TO 'user:alice@example.com';                    -- BigQuery 特有语法

REVOKE `roles/bigquery.dataViewer`
ON SCHEMA myproject.mydataset
FROM 'user:alice@example.com';

-- ============================================================
-- 4. 行级安全与列级安全
-- ============================================================

-- 行级安全策略
CREATE ROW ACCESS POLICY region_filter
ON myproject.mydataset.sales
GRANT TO ('user:alice@example.com', 'group:analysts@example.com')
FILTER USING (region = 'APAC');

DROP ROW ACCESS POLICY region_filter
ON myproject.mydataset.sales;

-- 列级安全（通过 Policy Tag）
-- 需要在 Data Catalog 中创建 Policy Tag，然后关联到列
-- ALTER TABLE myproject.mydataset.users
-- ALTER COLUMN ssn SET POLICY TAG `projects/myproject/locations/us/taxonomies/123/policyTags/456`;

-- ============================================================
-- 5. 查询元数据
-- ============================================================

-- 列出数据集
SELECT schema_name, location, creation_time
FROM INFORMATION_SCHEMA.SCHEMATA;

-- 列出表（指定数据集）
SELECT table_name, table_type, row_count, size_bytes
FROM myproject.mydataset.INFORMATION_SCHEMA.TABLES;

-- 列出列
SELECT table_name, column_name, data_type, is_nullable
FROM myproject.mydataset.INFORMATION_SCHEMA.COLUMNS;

-- 查看作业历史
SELECT user_email, query, total_bytes_processed, creation_time
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY creation_time DESC
LIMIT 20;

-- ============================================================
-- 6. 数据集选项与设置
-- ============================================================

-- 默认排序规则（BigQuery 不支持数据库级别设置）
-- 每个查询可以设置：
-- SET @@dataset_id = 'mydataset';              -- 设置默认数据集

-- 数据传输服务（跨项目复制数据集）
-- 通过 BigQuery Data Transfer Service API 管理

-- 注意：BigQuery 是无服务器架构
-- - 不需要管理服务器、连接数
-- - 计费按扫描数据量或预留 slot
-- - 权限完全通过 IAM 管理
-- - 没有传统数据库的 CREATE USER
