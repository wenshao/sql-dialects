# TDengine: 数据库、模式与用户管理

> 参考资料:
> - [TDengine Documentation - CREATE DATABASE](https://docs.taosdata.com/reference/sql/database/)
> - [TDengine Documentation - User Management](https://docs.taosdata.com/reference/sql/user/)
> - ============================================================
> - TDengine 是时序数据库
> - 命名层级: cluster > database > stable(超级表) > table(子表)
> - 没有 schema 概念
> - 数据库是最基本的数据组织单元
> - ============================================================
> - ============================================================
> - 1. 数据库管理
> - ============================================================

```sql
CREATE DATABASE myapp;
CREATE DATABASE IF NOT EXISTS myapp;

CREATE DATABASE myapp
    BUFFER 256                                  -- 写入缓存 MB
    CACHEMODEL 'both'                           -- 缓存最新行和最后值
    COMP 2                                      -- 压缩级别 0-2
    DURATION 14d                                -- 数据文件时间跨度
    KEEP 365d                                   -- 数据保留天数
    MAXROWS 4096                                -- 每个数据块最大行数
    MINROWS 100                                 -- 每个数据块最小行数
    PAGES 256                                   -- 缓存页数
    PRECISION 'ms'                              -- 时间精度: ms, us, ns
    REPLICA 3                                   -- 副本数
    WAL_LEVEL 2                                 -- WAL 级别
    VGROUPS 6                                   -- 虚拟节点组数
    SINGLE_STABLE 0                             -- 是否只包含一个超级表
    STT_TRIGGER 1;                              -- SST 触发值
```

## 修改数据库

```sql
ALTER DATABASE myapp KEEP 730d;                 -- 修改保留天数
ALTER DATABASE myapp CACHEMODEL 'last_value';
ALTER DATABASE myapp WAL_LEVEL 1;
ALTER DATABASE myapp BUFFER 512;
```

## 删除数据库

```sql
DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;
```

## 切换数据库

```sql
USE myapp;
```

## 查看数据库

```sql
SHOW DATABASES;
SELECT * FROM information_schema.ins_databases;
```

## 用户管理


```sql
CREATE USER myuser PASS 'secret123';

CREATE USER myuser PASS 'secret123'
    SYSINFO 1;                                  -- 允许查看系统信息
```

## 修改用户

```sql
ALTER USER myuser PASS 'newsecret';
ALTER USER myuser ENABLE 0;                     -- 禁用
ALTER USER myuser ENABLE 1;                     -- 启用
ALTER USER myuser SYSINFO 0;                    -- 禁止查看系统信息
```

## 删除用户

```sql
DROP USER myuser;
```

## 默认用户: root（密码: taosdata）

## 权限管理


## TDengine 3.0+ 权限管理

数据库权限

```sql
GRANT ALL ON myapp.* TO myuser;
GRANT READ ON myapp.* TO myuser;
GRANT WRITE ON myapp.* TO myuser;
```

## 收回权限

```sql
REVOKE ALL ON myapp.* FROM myuser;
REVOKE WRITE ON myapp.* FROM myuser;
```

## 查看权限

```sql
SHOW USER PRIVILEGES;
```

注意：TDengine 的权限模型较简单
只有 ALL, READ, WRITE 三种
没有角色（ROLE）概念

## 查询元数据


```sql
SHOW DATABASES;
SHOW USERS;
SHOW STABLES;                                   -- 超级表
SHOW TABLES;                                    -- 子表
SHOW USER PRIVILEGES;

SELECT * FROM information_schema.ins_databases;
SELECT * FROM information_schema.ins_users;
SELECT * FROM information_schema.ins_stables WHERE db_name = 'myapp';

SELECT DATABASE();
SELECT USER();
```

## 集群管理


```sql
SHOW DNODES;                                    -- 数据节点
SHOW MNODES;                                    -- 管理节点
SHOW VNODES;                                    -- 虚拟节点
SHOW QNODES;                                   -- 查询节点
```

添加/删除节点
CREATE DNODE 'host:port';
DROP DNODE dnode_id;
注意：TDengine 针对时序数据优化
数据库配置直接影响存储和查询性能
KEEP, DURATION, PRECISION 是最重要的配置项
