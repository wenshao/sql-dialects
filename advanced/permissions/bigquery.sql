-- BigQuery: 权限管理
--
-- 参考资料:
--   [1] BigQuery - Access Control
--       https://cloud.google.com/bigquery/docs/access-control
--   [2] BigQuery SQL Reference - GRANT / REVOKE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#grant_statement

-- BigQuery 使用 Google Cloud IAM（Identity and Access Management）
-- 不使用传统的 GRANT/REVOKE SQL 语法

-- ============================================================
-- IAM 角色层级
-- ============================================================

-- 组织级别 (Organization)
-- └── 文件夹级别 (Folder)
--     └── 项目级别 (Project)
--         └── 数据集级别 (Dataset)
--             └── 表/视图级别 (Table/View)

-- ============================================================
-- 预定义角色
-- ============================================================

-- BigQuery Admin: 完全控制
-- roles/bigquery.admin

-- BigQuery Data Owner: 数据集和表的完全控制
-- roles/bigquery.dataOwner

-- BigQuery Data Editor: 读写数据
-- roles/bigquery.dataEditor

-- BigQuery Data Viewer: 只读
-- roles/bigquery.dataViewer

-- BigQuery User: 运行查询
-- roles/bigquery.user

-- BigQuery Job User: 创建和运行作业
-- roles/bigquery.jobUser

-- ============================================================
-- 通过 gcloud CLI 管理权限
-- ============================================================

-- 项目级别授权
-- gcloud projects add-iam-policy-binding myproject \
--     --member="user:alice@example.com" \
--     --role="roles/bigquery.dataViewer"

-- 数据集级别授权
-- bq show --format=prettyjson mydataset > policy.json
-- 编辑 policy.json 添加 access 条目
-- bq update --source policy.json mydataset

-- ============================================================
-- SQL 数据集权限管理（DCL 语法）
-- ============================================================

-- 授予数据集权限
GRANT `roles/bigquery.dataViewer` ON SCHEMA mydataset
TO "user:alice@example.com";

GRANT `roles/bigquery.dataEditor` ON SCHEMA mydataset
TO "group:data-team@example.com";

-- 撤销数据集权限
REVOKE `roles/bigquery.dataViewer` ON SCHEMA mydataset
FROM "user:alice@example.com";

-- ============================================================
-- SQL 表级权限管理
-- ============================================================

-- 授予表权限
GRANT `roles/bigquery.dataViewer` ON TABLE myproject.mydataset.users
TO "user:alice@example.com";

GRANT `roles/bigquery.dataEditor` ON TABLE myproject.mydataset.users
TO "serviceAccount:my-sa@myproject.iam.gserviceaccount.com";

-- 撤销表权限
REVOKE `roles/bigquery.dataViewer` ON TABLE myproject.mydataset.users
FROM "user:alice@example.com";

-- ============================================================
-- 列级安全（Column-Level Security）
-- ============================================================

-- 使用 Policy Tag 控制列级访问
-- 1. 在 Data Catalog 中创建 Policy Tag
-- 2. 将 Policy Tag 关联到列
-- 3. 设置 IAM 策略控制谁可以看到受保护的列

ALTER TABLE users ALTER COLUMN email
SET OPTIONS (policy_tags = ['projects/myproject/locations/us/taxonomies/123/policyTags/456']);

-- ============================================================
-- 行级安全（Row-Level Security）
-- ============================================================

-- 创建行级访问策略
CREATE ROW ACCESS POLICY region_filter ON orders
GRANT TO ("user:alice@example.com", "group:us-team@example.com")
FILTER USING (region = 'US');

-- 多个策略（取并集，任意策略通过即可访问）
CREATE ROW ACCESS POLICY admin_access ON orders
GRANT TO ("group:admin@example.com")
FILTER USING (TRUE);  -- 管理员可以看到所有行

-- 删除行级策略
DROP ROW ACCESS POLICY region_filter ON orders;
DROP ALL ROW ACCESS POLICIES ON orders;

-- ============================================================
-- 数据掩码（Dynamic Data Masking）
-- ============================================================

-- 通过 Data Catalog Policy Tag + Masking Rule 实现
-- 不同用户看到不同程度的数据掩码

-- ============================================================
-- 授权视图（Authorized View）
-- ============================================================

-- 授权视图可以访问底层数据集的数据
-- 即使用户没有底层数据集的直接权限

CREATE VIEW mydataset.safe_users AS
SELECT id, username, REGEXP_REPLACE(email, r'(.).*@', r'\1***@') AS masked_email
FROM mydataset.users;

-- 在数据集设置中添加授权视图

-- ============================================================
-- 服务账户
-- ============================================================

-- 推荐使用服务账户进行应用程序访问
-- gcloud iam service-accounts create my-app-sa
-- gcloud projects add-iam-policy-binding myproject \
--     --member="serviceAccount:my-app-sa@myproject.iam.gserviceaccount.com" \
--     --role="roles/bigquery.dataViewer"

-- 注意：BigQuery 使用 IAM，不使用传统的 CREATE USER / GRANT
-- 注意：权限继承：组织 -> 文件夹 -> 项目 -> 数据集 -> 表
-- 注意：列级安全通过 Policy Tag 实现
-- 注意：行级安全通过 Row Access Policy 实现
-- 注意：推荐使用最小权限原则
