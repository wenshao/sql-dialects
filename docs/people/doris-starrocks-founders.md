# Doris/StarRocks 创始人 - 从百度 Palo 到开源分叉

> 信息来源：
> - [Apache Doris 官网](https://doris.apache.org/)
> - [Apache Doris Incubator Proposal (2018)](https://cwiki.apache.org/confluence/display/INCUBATOR/DorisProposal)
> - [StarRocks GitHub](https://github.com/StarRocks/starrocks)
> - [StarRocks 官网](https://www.starrocks.io/)
> - [Apache Doris Wikipedia](https://en.wikipedia.org/wiki/Apache_Doris)
> - [SelectDB 官网](https://www.selectdb.com/)

---

Apache Doris 和 StarRocks 是两个同源的开源分析数据库，
都源自百度内部的 Palo 项目。
两者的分叉历程是中国开源数据库领域的一个典型案例。

## 百度 Palo 项目的起源

### 背景

Palo 最初是百度内部的一个 OLAP 分析引擎项目，
用于支持百度的广告分析、用户行为分析等业务场景。
项目大约在 2013-2014 年间启动，由百度大数据团队开发。

Palo 的设计目标是构建一个兼容 MySQL 协议的 MPP 分析数据库，
能够在数百亿行数据上实现秒级查询响应。

### 核心架构

Palo/Doris 的架构设计相对简洁：
- **FE（Frontend）**：Java 编写，负责 SQL 解析、查询规划和元数据管理
- **BE（Backend）**：C++ 编写，负责数据存储和查询执行
- 兼容 MySQL 协议，用户可以直接使用 MySQL 客户端连接
- 不依赖外部组件（如 HDFS、ZooKeeper）

## Apache Doris

### 进入 Apache 基金会

2018 年 7 月，百度将 Palo 项目捐赠给 Apache 软件基金会，
进入孵化器，更名为 Apache Doris。
2022 年 6 月，Doris 从 Apache 孵化器毕业，成为 Apache 顶级项目（TLP）。

> 来源：[Apache Doris Incubator Proposal](https://cwiki.apache.org/confluence/display/INCUBATOR/DorisProposal)、[Apache Doris 官网](https://doris.apache.org/)

### 社区发展

Apache Doris 在进入 Apache 后获得了更广泛的社区参与。
百度之外的公司和个人开发者也开始参与贡献，
项目的功能和稳定性持续提升。SelectDB 公司（成立于 2022 年）基于 Apache Doris
提供商业化支持和云服务。

> 来源：[SelectDB 官网](https://www.selectdb.com/)

## StarRocks 的分叉 (2020)

### 分叉背景

2020 年，部分 Doris 核心开发者从百度离开，
创立了鼎石科技（后更名为 StarRocks），
基于 Doris 的代码进行分叉开发。

创始团队包括原 Doris 项目的核心贡献者。
他们选择独立发展，以更快的节奏推进技术演进。

### 技术路线差异

StarRocks 在 Doris 的基础上进行了大量重构和创新：

| 特性 | Apache Doris | StarRocks |
|------|-------------|-----------|
| 向量化引擎 | 后续版本引入 | 早期即全面向量化 |
| CBO 优化器 | 逐步完善 | 基于 Cascades 框架重写 |
| 物化视图 | 基础支持 | 多表物化视图，智能路由 |
| 数据湖分析 | 支持外表查询 | 深度集成 Hudi/Iceberg/Delta |
| 存算分离 | 后续版本支持 | 3.0 版本原生支持 |

### 开源许可

StarRocks 最初使用 Elastic License 2.0，
后于 2023 年 3 月切换为 Apache 2.0 许可证，
并于 2023 年 9 月加入 Linux 基金会。

> 来源：[StarRocks GitHub](https://github.com/StarRocks/starrocks)、[StarRocks 官网](https://www.starrocks.io/)

## 同源分叉的启示

Doris 和 StarRocks 的分叉故事在开源世界并不罕见，
类似的案例包括 MySQL/MariaDB、Elasticsearch/OpenSearch 等。

两个项目的竞争也带来了积极效果：
- 技术迭代速度加快，两个项目互相借鉴和竞争
- 用户有了更多选择
- 推动了国产 OLAP 数据库的整体技术水平提升

从百度内部工具到两个活跃的开源项目，
Palo/Doris/StarRocks 的发展历程反映了
中国大数据分析引擎从内部自研走向全球开源的趋势。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
