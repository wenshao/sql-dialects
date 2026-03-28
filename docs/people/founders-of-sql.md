# SQL 语言的创始人

> 信息来源：
> - [Wikipedia: Edgar F. Codd](https://en.wikipedia.org/wiki/Edgar_F._Codd)
> - [Wikipedia: SQL](https://en.wikipedia.org/wiki/SQL)
> - [A Relational Model of Data for Large Shared Data Banks (1970)](https://dl.acm.org/doi/10.1145/362384.362685)
> - [SEQUEL: A Structured English Query Language (1974)](https://dl.acm.org/doi/10.1145/800296.811515)
> - [ACM Turing Award 1981: Edgar F. Codd](https://amturing.acm.org/award_winners/codd_1000892.cfm)

---

SQL 语言的诞生可以追溯到三位 IBM 研究员的工作。Edgar F. Codd 提出了关系模型的理论基础，
Donald Chamberlin 和 Raymond Boyce 在此基础上设计了 SEQUEL 语言，即 SQL 的前身。

## Edgar F. Codd (1923-2003)

### 生平与职业背景

Edgar Frank Codd 出生于英格兰多塞特郡，二战期间曾在英国皇家空军服役。
战后他移居美国，在密歇根大学获得数学与通信学博士学位。
1949 年加入 IBM，此后在 IBM 研究院工作了数十年。

### 关系模型

1970 年，Codd 在 Communications of the ACM 上发表了划时代的论文：
"A Relational Model of Data for Large Shared Data Banks"。
这篇论文提出了用数学上的关系（即表）来组织数据的思想，
奠定了现代关系数据库的理论基础。

论文的核心贡献包括：
- 将数据组织与物理存储分离（数据独立性）
- 用关系代数和关系演算作为查询的数学基础
- 提出了规范化理论，减少数据冗余

### 图灵奖

1981 年，Codd 因关系模型的贡献获得 ACM 图灵奖。
颁奖词称他"为数据库系统的理论和实践做出了根本性贡献"。

### 12 条准则

1985 年，Codd 提出了 12 条关系数据库准则（Codd's 12 Rules），
用于衡量一个数据库系统是否真正符合关系模型。
这些准则至今仍被用来评估数据库系统的关系性。

Codd 于 2003 年在美国佛罗里达州去世，享年 79 岁。

---

## Donald Chamberlin

### 从 System R 到 SQL

Donald D. Chamberlin 是 IBM 圣何塞研究实验室（现 Almaden 研究中心）的研究员。
1972 年，他在听完 Codd 关于关系模型的演讲后深受启发，
决定设计一种非程序员也能使用的关系数据查询语言。

1974 年，Chamberlin 与 Raymond Boyce 共同发表论文
"SEQUEL: A Structured English Query Language"，
提出了 SEQUEL 语言——SQL 的直接前身。

SEQUEL 后来因商标问题更名为 SQL（Structured Query Language）。

### System R 项目

Chamberlin 是 IBM System R 项目的核心成员。System R 是第一个
实现 SQL 的关系数据库原型系统，于 1974-1979 年间开发。
System R 证明了关系模型在实际系统中是可行的，
其优化器架构影响了后续几乎所有商业数据库。

### 荣誉

Chamberlin 是 ACM Fellow，获得过多项 IBM 内部奖项。
他在 XQuery 和 XML 数据库领域也有重要贡献，
是 XQuery 语言规范的联合编辑。

---

## Raymond Boyce (1947-1974)

### SEQUEL 联合设计者

Raymond F. Boyce 是 Chamberlin 在 IBM 的同事，
两人共同设计了 SEQUEL 语言。

### Boyce-Codd 范式

Boyce 与 Codd 共同提出了 Boyce-Codd 范式（BCNF），
这是数据库规范化理论中的一个重要概念，
比第三范式更严格，解决了某些第三范式无法处理的异常情况。

### 英年早逝

令人惋惜的是，Boyce 于 1974 年因脑动脉瘤去世，年仅 26 岁。
当时 SEQUEL 论文刚刚发表不久。
他未能看到自己参与设计的语言成为全球最广泛使用的数据库语言。

---

## 历史影响

这三位的工作构成了 SQL 的理论和实践基础：

- **Codd** 提供了数学理论——关系模型
- **Chamberlin 和 Boyce** 将理论转化为可用的查询语言——SQL
- **System R** 证明了这一切在工程上是可行的

SQL 于 1986 年被 ANSI 采纳为标准（SQL-86），
此后经历了 SQL-89、SQL-92、SQL:1999、SQL:2003、SQL:2008、
SQL:2011、SQL:2016、SQL:2023 等多个版本的演进。

从三位 IBM 研究员的工作到今天，SQL 已经成为数据领域的通用语言，
几乎每一个现代数据库系统都支持某种形式的 SQL。

---

*注：本页信息均来自公开渠道。如有不准确之处欢迎指正。*
