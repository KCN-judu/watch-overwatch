# 数据结构

应用和导出都不直接读大神的原始 JSON，而是读统一的数据结构 IR（intermediate representation）。定义在 `crates/watch-core/src/ir.rs`，由 `dashen::normalize` 从大神的原始数据转换；应用里的镜像是 `app/lib/core/models.dart`。

> 大神原始 JSON → `dashen::normalize` → IR → `analysis` / `strength` / `growth` … → 应用或导出

## 约定

- 字段名用 snake_case；枚举的取值也是 snake_case（`win`、`loss`、`support`……）。
- **缺失用 `null`，不用 0。** 大神没给的数字不当成 0；应用里显示为 `—`。
- 英雄、地图、统计项、威能都用 `EntityRef` 引用，名称可能缺失，**不能靠名称连接**，要用 `guid` 或 `official_id`。
- 官方 ID 在 JSON 里是字符串，避免 JavaScript 大整数丢精度。
- 部分请求失败不会让整个采集失败：`Coverage` 记录每个请求是否成功。
- 版本 `IR_VERSION`（当前 2.0.0）：删除或改动字段升主版本，只新增可选字段升次版本。2.0.0（应用 1.4.0）：`Participant` 去掉 `career_rank`、`career_other_roles`，换成三个职责的段位快照 `career`；单独的段位缓存 `ratings.db` 取消，段位只取本赛季。

## 主要类型

| 类型 | 内容 |
|---|---|
| `PlayerDataset` | 一名玩家的完整数据集：`ir_version`、资料、生涯、对局、对局详情（按对局编号）、英雄榜、`player_ratings`、采集覆盖情况 |
| `PlayerProfile` | 昵称、战网编号、头像、称号、荣誉等级、游戏时长（小时）、总场次、封禁状态 |
| `CareerSnapshot` | 某模式某赛季的生涯：各职责数据、英雄使用统计、省榜、行为与荣誉、近期对局 |
| `MatchSummary` | 列表里的一场：地图、结果、比分、英雄、职责、统计、本场段位 |
| `MatchDetail` | 一场的详情：时长、比分、禁用、本人用过的英雄（`subject_heroes`）、双方各 5 人；角斗领域另有回合 |
| `Participant` | 一名参与者：英雄、职责、统计、对局报告的段位 `rank`、段位快照 `career`、威能、组队成员、点赞者；`is_subject` 标出本人 |
| `RoleRanks` | 段位快照：`{tank, damage, support}`，每个职责一个 `RankState` |
| `RankState` | `{state: "ranked", rank}`；`{state: "unranked"}`：查到了，这个职责本赛季没有段位；`{state: "querying"}`：还不知道（没查，或请求失败） |
| `StatLine` | 一场的统计：消灭、助攻、阵亡、伤害、治疗、阻挡（`mitigation`）、最后一击、单独消灭、承受伤害、承受治疗、目标时间 |
| `HeroUsage` | 一个英雄的赛季统计：场次、胜率、时长、熟练度、每场平均、每 10 分钟 |
| `EntityRef` | 英雄、地图、统计项、威能的引用：大神 `guid`、官方 `official_id`（`0x…`）、名称 |
| `Rank` | 段位名 `tier`、小段 `division`（1 最高）、大神原始分 `score`、段位分 `skill_rating`（500–5000） |
| `PlayerRating` | 数据集的 `player_ratings`：一名参与者本赛季有段位的职责，由段位快照整理，只在 `lobby_ratings` 时有 |
| `Coverage` | 每个请求是否成功、每个模式的列表读了几页、是否已读到最早一场（`exhausted`）、新增了几场、命中本机的次数 |

### 段位快照

`Participant.career` 是读入这场对局时查到的参与者本赛季三个职责的竞技段位，和对局一起存在本机对局库里。查到的职责（`ranked` 或 `unranked`）不再改，同一场对局以后打开显示同样的段位；`querying` 的职责由段位同步补上。查询时间、失败次数记在后台任务的状态里，不在值上。

### 显示段位

`detail` 视图给每名参与者另带 `shown_rank` 和 `fleta`。`shown_rank` 由 `watch_core::rank_view` 算出，对局强度和同分段基准用同一个结果：

| `shown_rank` | 条件 |
|---|---|
| `{state: "ranked", rank, basis: "match"}` | 对局报告了段位 |
| `{state: "ranked", rank, basis: "role"}` | 段位快照里所打职责有段位 |
| `{state: "querying"}` | 所打职责还在查；或所打职责没有段位，其他职责还有在查的 |
| `{state: "ranked", rank, basis: "other_roles"}` | 所打职责没有段位，取其他职责里最高的 |
| `{state: "unranked"}` | 三个职责都没有段位；角斗领域和没有战网编号的玩家在对局没报告段位时也是 |

分析结果（`PlayerAnalysis`）由 `analysis::analyze` 生成：总体和分窗口的汇总，按模式 / 队列 / 职责 / 英雄 / 地图的拆分，连续对局，按小时，段位时间线，队内占比，同队玩家，赛季走势，对局强度。成长面板来自单独的 `growth` 模块（`POST /api/player/growth`），不在数据集里。

## 从哪里取

| 想要 | 用什么 |
|---|---|
| 一名玩家的全部数据 | `POST /api/player/dataset`，或命令行 `watchd dataset` |
| 一个视图 | `POST /api/player/view`，见 [本机接口](http-api.md) |
| 匿名化的版本 | 导出，见 [导出协议](export.md) |
| 逐局的成长指标 | `POST /api/player/growth` |

## 大神接口

IR 的数据来自这些大神接口（`dashen/endpoint.rs`）：

| 接口 | 用途 |
|---|---|
| `searchBnetAccount` | 按战网昵称查玩家，拿到 token（POST，其余为 GET） |
| `customer/queryCard` | 玩家资料卡 |
| `customer/queryCountInfo` | 竞技、快速的生涯：各职责、英雄使用统计、近期对局、省榜、荣誉；也用来取参与者的段位快照 |
| `customer/queryMatchList`、`queryMatchInfo` | 对局列表、对局详情 |
| `customer/fight/queryCount`、`queryMatchList`、`queryMatchInfo` | 角斗领域的对应接口 |
| `queryProvinceRank`、`billboard/*` | 省榜、英雄榜 |

`customer/fight/getLeisureFightRoleCard` 也在白名单里，只能经 `/api/request` 调用。

英雄统计、段位、近期对局来自同一个 `queryCountInfo`：一次请求返回本赛季打过的全部英雄，与应用是否显示无关。大神**不提供**每次阵亡的时间点，存活时长只能按对局时长和阵亡数估计，见 [指标口径](metrics.md#life)。
