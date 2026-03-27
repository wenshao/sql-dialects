-- MaxCompute (ODPS): 权限管理
--
-- 参考资料:
--   [1] MaxCompute - Authorization
--       https://help.aliyun.com/zh/maxcompute/user-guide/authorization
--   [2] MaxCompute - Security Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/security-overview

-- MaxCompute 使用阿里云 RAM（Resource Access Management）+ 项目级权限

-- ============================================================
-- 阿里云 RAM（外部权限管理）
-- ============================================================

-- RAM 提供用户、角色和策略管理
-- 通过阿里云控制台或 CLI 管理

-- RAM 用户: 对应一个阿里云子账号
-- RAM 角色: 可以被 RAM 用户扮演
-- RAM 策略: 定义权限范围

-- 示例 RAM 策略（JSON）：
-- {
--     "Statement": [{
--         "Action": ["odps:*"],
--         "Effect": "Allow",
--         "Resource": ["acs:odps:*:*:projects/myproject"]
--     }],
--     "Version": "1"
-- }

-- ============================================================
-- 项目级角色
-- ============================================================

-- 内置角色：
-- ProjectOwner: 项目所有者，最高权限
-- Admin: 项目管理员
-- SuperAdmin: 超级管理员

-- 查看角色
LIST ROLES;

-- 创建角色
CREATE ROLE analyst;
CREATE ROLE data_engineer;

-- 删除角色
DROP ROLE analyst;

-- ============================================================
-- 授权操作（ACL 模式）
-- ============================================================

-- 授予表权限
GRANT SELECT ON TABLE users TO USER alice;
GRANT SELECT, INSERT ON TABLE users TO USER alice;
GRANT ALL ON TABLE users TO USER alice;

-- 授予项目权限
GRANT CreateTable ON PROJECT myproject TO USER alice;
GRANT CreateInstance ON PROJECT myproject TO USER alice;

-- 授予角色权限
GRANT SELECT ON TABLE users TO ROLE analyst;
GRANT ALL ON TABLE users TO ROLE data_engineer;

-- 将角色授予用户
GRANT analyst TO USER alice;
GRANT data_engineer TO USER bob;

-- ============================================================
-- 撤销权限
-- ============================================================

REVOKE SELECT ON TABLE users FROM USER alice;
REVOKE ALL ON TABLE users FROM ROLE analyst;
REVOKE analyst FROM USER alice;

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANTS FOR USER alice;
SHOW GRANTS ON TABLE users;
WHOAMI;  -- 查看当前用户身份

-- ============================================================
-- 标签（Label）安全
-- ============================================================

-- MaxCompute 支持基于标签的列级安全
-- 标签级别从 0（公开）到 4（最高机密）

-- 设置表/列的标签级别
SET LABEL 2 TO TABLE users;                     -- 整表设为级别 2
SET LABEL 3 TO TABLE users (email, phone);      -- 特定列设为级别 3
SET LABEL 4 TO TABLE users (id_card);           -- 身份证设为级别 4

-- 授予用户标签权限
GRANT LABEL 2 TO USER alice;                    -- alice 可以访问级别 2 及以下
GRANT LABEL 3 TO USER bob;                      -- bob 可以访问级别 3 及以下

-- 查看标签
SHOW LABEL GRANTS ON TABLE users;
SHOW LABEL GRANTS FOR USER alice;

-- 清除标签
SET LABEL 0 TO TABLE users (email);

-- ============================================================
-- 包（Package）权限共享
-- ============================================================

-- 跨项目共享数据的权限管理
-- 项目 A 创建包并授权给项目 B

-- 在项目 A 中
CREATE PACKAGE mypackage;
ADD TABLE users TO PACKAGE mypackage;
ALLOW PROJECT project_b TO INSTALL PACKAGE mypackage;

-- 在项目 B 中
INSTALL PACKAGE project_a.mypackage;
-- 之后可以访问 project_a.mypackage.users

-- ============================================================
-- 安全策略
-- ============================================================

-- ProjectProtection: 防止数据流出项目
SET ProjectProtection=true;

-- 例外：允许特定数据流出
ADD TRUSTED PROJECT project_b;

-- 查看安全配置
SHOW SecurityConfiguration;

-- ============================================================
-- IP 白名单
-- ============================================================

-- 通过阿里云控制台设置项目级 IP 白名单
-- 限制只有特定 IP 才能访问项目

-- 注意：MaxCompute 结合 RAM 和项目级权限两层管理
-- 注意：标签安全提供列级别的细粒度访问控制
-- 注意：Package 机制实现跨项目的安全数据共享
-- 注意：ProjectProtection 防止数据泄露到项目外
-- 注意：权限管理同时涉及阿里云 RAM 和 MaxCompute ACL
