-- MaxCompute (ODPS): 数据库、模式与用户管理
--
-- 参考资料:
--   [1] MaxCompute Documentation - 项目管理
--       https://help.aliyun.com/zh/maxcompute/user-guide/project-management
--   [2] MaxCompute Documentation - 安全与权限
--       https://help.aliyun.com/zh/maxcompute/user-guide/security-overview

-- ============================================================
-- 1. MaxCompute 命名层级: Project → Schema → Table
-- ============================================================

-- 设计演进:
--   1.0/2.0: 两级命名 Project.Table（Project 类似 Database）
--   3.0+:    三级命名 Project.Schema.Table（引入 Schema 层）
--
-- 对比其他引擎的命名层级:
--   MaxCompute 3.0: Project.Schema.Table  (3级)
--   PostgreSQL:     Database.Schema.Table (3级，但不能跨 Database 查询)
--   MySQL:          Database.Table        (2级，无 Schema 概念)
--   SQL Server:     Server.Database.Schema.Table (4级)
--   Oracle:         User/Schema.Table     (2级，User=Schema)
--   BigQuery:       Project.Dataset.Table (3级，Dataset≈Schema)
--   Snowflake:      Account.Database.Schema.Table (4级)
--   Hive:           Database.Table        (2级，与 MaxCompute 1.0 相同)
--
-- 设计决策分析:
--   为什么 MaxCompute 后来引入 Schema?
--     一个 Project 可能有数万张表，两级命名导致表管理混乱
--     Schema 提供了逻辑分组（如 raw/ods/dwd/dws/ads 数据分层）
--     BigQuery 的 Dataset 解决了相同问题

-- ============================================================
-- 2. 项目（Project）管理
-- ============================================================

-- Project 通过阿里云控制台或 CLI 创建，不通过 SQL
-- Project 是 MaxCompute 的基本资源隔离和计费单元

-- 项目属性设置（odpscmd 中执行）:
-- setproject odps.sql.type.system.odps2 = true;    -- 启用 2.0 类型系统
-- setproject odps.schema.model.enabled = true;     -- 启用 Schema 模式
-- setproject odps.sql.allow.cartesian = true;      -- 允许笛卡尔积

-- Project vs Database:
--   Project 不仅是命名空间，还是:
--     计费单元: 按 Project 统计 CU 消耗和存储量
--     安全边界: ProjectProtection 防止数据流出
--     资源隔离: Quota Group 分配计算资源
--   对比 MySQL Database: 仅是命名空间，无计费和安全隔离语义

-- ============================================================
-- 3. Schema 管理（3.0+）
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;

-- 完整三级引用
SELECT * FROM myproject.myschema.users;

-- 切换默认 Schema
USE myschema;

-- 查看和删除
SHOW SCHEMAS;
DROP SCHEMA myschema;
DROP SCHEMA IF EXISTS myschema;

-- 典型的 Schema 分层设计（数据仓库最佳实践）:
-- CREATE SCHEMA raw;    -- 原始数据层（贴源层）
-- CREATE SCHEMA ods;    -- 操作数据层（清洗后）
-- CREATE SCHEMA dwd;    -- 明细数据层（标准化）
-- CREATE SCHEMA dws;    -- 汇总数据层（宽表）
-- CREATE SCHEMA ads;    -- 应用数据层（报表）

-- ============================================================
-- 4. 用户管理 —— 与阿里云 RAM 深度集成
-- ============================================================

-- 添加用户（必须是阿里云账号或 RAM 子账号）
ADD USER ALIYUN$alice@example.com;          -- 阿里云主账号
ADD USER RAM$alice;                         -- RAM 子账号

-- 删除用户
REMOVE USER ALIYUN$alice@example.com;

-- 查看用户
LIST USERS;

-- 设计决策: 用户不在 MaxCompute 内部创建
--   MaxCompute 依赖阿里云 RAM 做身份认证
--   ADD USER 只是将已有的 RAM 账号关联到 Project
--   对比:
--     MySQL:      CREATE USER 在数据库内部创建用户
--     PostgreSQL: CREATE ROLE 在数据库内部创建
--     BigQuery:   依赖 GCP IAM（与 MaxCompute 类似）
--     Snowflake:  CREATE USER 在 Snowflake 内部创建（但支持 SSO 集成）

-- ============================================================
-- 5. 角色管理
-- ============================================================

-- 系统内置角色:
--   ProjectOwner: 项目所有者，最高权限
--   Admin:        项目管理员
--   Super:        超级管理员

CREATE ROLE analyst;
CREATE ROLE data_engineer;

GRANT analyst TO ALIYUN$alice@example.com;
REVOKE analyst FROM ALIYUN$alice@example.com;

LIST ROLES;
SHOW GRANTS FOR ALIYUN$alice@example.com;
DROP ROLE analyst;

-- ============================================================
-- 6. 权限管理 —— 四层安全模型
-- ============================================================

-- 第一层: RAM（阿里云资源访问管理）
--   控制"谁能访问 MaxCompute 服务"
--   JSON 策略: {"Action": ["odps:*"], "Resource": ["acs:odps:*:*:projects/myproject"]}

-- 第二层: ACL（访问控制列表）
GRANT SELECT ON TABLE users TO USER ALIYUN$alice@example.com;
GRANT ALL ON TABLE users TO ROLE analyst;
GRANT CREATETABLE ON PROJECT myproject TO USER ALIYUN$alice@example.com;
GRANT SELECT ON SCHEMA myschema TO ROLE analyst;        -- 3.0+
REVOKE SELECT ON TABLE users FROM USER ALIYUN$alice@example.com;

-- 查看权限
SHOW GRANTS FOR USER ALIYUN$alice@example.com;
SHOW GRANTS ON TABLE users;
WHOAMI;                                     -- 查看当前身份

-- 第三层: Policy（策略授权，类似 AWS IAM Policy）
--   更灵活的条件授权（基于时间、IP、标签等条件）
--   在控制台或 CLI 中配置 JSON 策略

-- 第四层: Label Security（列级安全标签）
SET LABEL 2 TO TABLE users(email, phone);   -- 设置列敏感级别 (0-4)
GRANT LABEL 2 TO USER ALIYUN$alice@example.com;  -- 授予访问级别

-- Label Security 设计:
--   级别 0: 公开
--   级别 1: 内部
--   级别 2: 秘密
--   级别 3: 机密
--   级别 4: 最高机密
--   用户只能访问 <= 自己级别的列
--   对比:
--     BigQuery:   列级安全通过 Policy Tags（类似标签机制）
--     Snowflake:  列级安全通过 Row Access Policy + Dynamic Data Masking
--     Oracle:     Label Security（Oracle Label Security 模块，最早的实现）

-- ============================================================
-- 7. 跨项目数据共享 —— Package 机制
-- ============================================================

-- 项目 A 中:
CREATE PACKAGE my_package;
ADD TABLE users TO PACKAGE my_package;
ALLOW PROJECT project_b TO INSTALL PACKAGE my_package;

-- 项目 B 中:
INSTALL PACKAGE project_a.my_package;
-- 访问: SELECT * FROM project_a.my_package.users;

-- ProjectProtection: 防止数据流出
SET ProjectProtection = true;
ADD TRUSTED PROJECT project_b;              -- 例外: 允许向 project_b 流出

SHOW SecurityConfiguration;

-- ============================================================
-- 8. 元数据查询
-- ============================================================

LIST TABLES;
LIST SCHEMAS;
LIST USERS;
LIST ROLES;
DESC TABLE users;
SHOW PARTITIONS orders;

-- INFORMATION_SCHEMA（较新版本支持）:
SELECT table_name, data_length, table_rows
FROM INFORMATION_SCHEMA.TABLES;

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- 1. 命名层级: 三级命名（Project/Database.Schema.Table）是数据仓库的最佳实践
-- 2. 外部身份集成: 云数仓不应自建用户系统，应与云平台 IAM 集成
-- 3. Label Security: 列级安全标签是 PII 数据保护的简洁方案
-- 4. Package 跨项目共享: 解决了多租户间的安全数据共享问题
-- 5. ProjectProtection: 数据不出项目的安全边界是云数仓的刚需
-- 6. Project 作为计费单元: 命名空间 + 计费 + 安全的三合一设计值得参考
