# BigQuery: 权限管理

> 参考资料:
> - [1] BigQuery Documentation - IAM & Access Control
>   https://cloud.google.com/bigquery/docs/access-control
> - [2] BigQuery - Row Level Security
>   https://cloud.google.com/bigquery/docs/row-level-security-intro


## 1. IAM 模型: 与传统数据库权限的根本区别


 BigQuery 使用 GCP IAM，不使用 SQL CREATE USER:
   身份 = Google Account / Service Account
   权限 = IAM Role
 无服务器 → 无数据库连接 → 无数据库用户

 预定义角色:
   roles/bigquery.dataViewer     → SELECT
   roles/bigquery.dataEditor     → SELECT + DML
   roles/bigquery.dataOwner      → 完全数据控制
   roles/bigquery.jobUser        → 运行查询
   roles/bigquery.admin          → 全部权限

## 2. SQL GRANT（映射到 IAM）


```sql
GRANT `roles/bigquery.dataViewer`
ON SCHEMA myproject.mydataset
TO 'user:alice@example.com';

GRANT `roles/bigquery.dataEditor`
ON SCHEMA myproject.mydataset
TO 'serviceAccount:etl@myproject.iam.gserviceaccount.com';

REVOKE `roles/bigquery.dataViewer`
ON SCHEMA myproject.mydataset
FROM 'user:alice@example.com';

```

## 3. 行级安全（Row Access Policy）


```sql
CREATE ROW ACCESS POLICY region_filter
ON myproject.mydataset.sales
GRANT TO ('user:alice@example.com', 'group:analysts@example.com')
FILTER USING (region = 'APAC');

DROP ROW ACCESS POLICY region_filter ON myproject.mydataset.sales;

```

## 4. 列级安全（Data Catalog Policy Tag）


 通过 Data Catalog 的 Policy Tag 标记敏感列:
 SSN 列标记为 "PII-Restricted"
 只有拥有 datacatalog.categoryFineGrainedReader 的用户才能查询
 比 SQL GRANT SELECT(col) 更强大: 跨表统一、集中管理、可审计

## 5. 成本控制（BigQuery 独有的"权限"维度）


查询成本历史

```sql
SELECT user_email, SUM(total_bytes_billed) / POWER(1024, 4) AS tb_billed
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY user_email ORDER BY tb_billed DESC;

```

 项目级配额防止意外大查询（通过 GCP Console 设置）

## 6. 对比与引擎开发者启示

BigQuery 权限模型的核心:
(1) 身份由云平台管理（不存储密码 → 更安全）
(2) IAM 角色替代 SQL GRANT
(3) Data Catalog 列级安全（跨表统一）
(4) 成本控制作为权限的一等公民

对引擎开发者的启示:
云原生引擎应集成云 IAM，而非自建用户系统。
成本控制应该是云数仓权限的核心组件。

