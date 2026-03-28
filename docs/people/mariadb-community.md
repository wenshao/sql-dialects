# MariaDB 社区关键人物

本文作为 [monty-widenius.md](monty-widenius.md) 的补充，
介绍 MariaDB 项目中除 Michael "Monty" Widenius 之外的核心贡献者。
MariaDB 的成功不仅源于其创始人的远见，
也离不开一批资深数据库工程师的长期投入。

## Sergei Golubchik - 首席架构师

### MySQL 时代

Sergei Golubchik 是 MariaDB Server 的首席架构师（Chief Architect），
也是 MariaDB 基金会的关键技术决策者之一。

他最早在 MySQL AB 公司工作，是 MySQL 数据库的核心开发者之一。
在 MySQL 时期，Golubchik 参与了多个关键模块的开发，
包括全文搜索引擎（FULLTEXT search）和可插拔认证框架等功能。

### 在 MariaDB 的角色

当 Widenius 在 2009 年发起 MariaDB 分叉时，
Golubchik 是跟随 Widenius 从 MySQL 转向 MariaDB 的核心开发者之一。
在 MariaDB 中，他担任首席架构师，负责：
- MariaDB Server 的整体技术方向和架构决策
- 代码审查和核心模块的设计
- 社区贡献的技术评估和合并决策

Golubchik 的工作风格以技术严谨著称，
他在 MariaDB 的邮件列表和 JIRA 中非常活跃，
是 MariaDB 技术讨论中最权威的声音之一。

## 其他核心贡献者

### Vicentiu Ciorbaru

Vicentiu Ciorbaru 是 MariaDB 基金会的工程副总裁
（Vice President of Engineering），
负责协调 MariaDB Server 的开发工作和发布流程。
他在 MariaDB 社区中长期活跃，参与了多个版本的开发和发布管理。

### Daniel Bartholomew

Daniel Bartholomew 长期负责 MariaDB 的文档和发布工程工作。
高质量的文档对于开源数据库项目的采用至关重要，
MariaDB 的知识库（Knowledge Base）在社区中获得了良好的口碑。

## MariaDB 基金会

### 治理结构

MariaDB 基金会（MariaDB Foundation）是一个非营利组织，
负责 MariaDB Server 的治理和社区协调。
基金会确保 MariaDB Server 保持开源和社区驱动的开发模式。

基金会与 MariaDB Corporation（商业公司）是独立的实体。
基金会关注开源项目本身的健康发展，
而商业公司负责企业版产品和云服务的开发与销售。

### 社区贡献

MariaDB 基金会鼓励和协调来自全球的社区贡献：
- 通过 Google Summer of Code 吸引学生参与
- 举办 MariaDB Server Fest 等社区活动
- 维护公开的路线图和开发流程

## 技术贡献

MariaDB 社区在 MySQL 基础上引入了多项独有的技术特性：

| 特性 | 贡献者/团队 | 说明 |
|------|------------|------|
| Aria 存储引擎 | Monty Widenius | MyISAM 的改进版本 |
| Galera Cluster | Codership (Seppo Jaakola) | 同步多主复制 |
| ColumnStore | MariaDB Corporation | 列式存储引擎 |
| Spider 引擎 | Kentoku Shiba | 分布式分片引擎 |
| 序列引擎 | 社区 | 生成序列值的虚拟引擎 |

### Galera Cluster

值得特别提及的是 Galera Cluster，
由芬兰公司 Codership 的 Seppo Jaakola 开发。
Galera 为 MariaDB 提供了同步多主复制能力，
这是 MariaDB 区别于 MySQL 的重要特性之一。

## 影响

MariaDB 社区的核心贡献者们共同确保了项目的健康发展：
- Golubchik 作为首席架构师维护了代码质量和技术一致性
- 基金会的治理结构保障了项目的独立性和开放性
- 来自不同公司和个人的贡献者丰富了 MariaDB 的功能生态
- 社区驱动的开发模式使 MariaDB 成为 MySQL 之外最重要的分支
