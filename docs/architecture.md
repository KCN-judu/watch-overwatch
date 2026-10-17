# 说明文档

## 总体结构

```
Flutter 界面 (app/)  ──HTTP, 仅本机──▶  watchd (Rust)  ──HTTPS──▶  网易大神接口
                                         │
                                         ├─ watch-core：调度、转换、采集、分析
                                         └─ 目录：英雄、地图、统计项、段位图标
```

- 界面启动时自己拉起同目录的 `watchd.exe`（端口 18280，环境变量 `WATCHD_PORT`），并设置 `WATCHD_EXIT_ON_STDIN_EOF`，窗口关闭时服务一并退出。
- 服务只接受 `127.0.0.1` 或 `localhost` 的请求；非 GET 请求必须带头 `x-watch-client: watch-overwatch`，且来源（如有）必须是本机，防止网页对它发请求。
- 界面和导出都不直接读上游的原始 JSON，而是读统一的数据结构（IR）。

## 数据流

> 大神原始 JSON → `dashen::normalize` → IR → `analysis` / `strength` → 界面或导出

### IR（`crates/watch-core/src/ir.rs`）

字段名用 snake_case；缺失用 `null`，不用 0。主要类型：

| 类型 | 内容 |
|---|---|
| `PlayerDataset` | 一个玩家的完整数据集：资料、生涯、对局、对局详情、英雄榜、参与者段位、采集覆盖情况 |
| `PlayerProfile` | 昵称、玩家编号、头像、称号、荣誉等级、游戏时长、总场次、封禁状态 |
| `CareerSnapshot` | 某模式某赛季的生涯：各职责数据、英雄使用统计、省榜、行为与荣誉 |
| `MatchSummary` | 列表里的一场：地图、结果、比分、英雄、职责、统计 |
| `MatchDetail`、`Participant` | 一场的详情：双方各 5 人，每人的英雄、职责、统计、段位、威能 |
| `HeroUsage` | 一个英雄的赛季统计：场次、胜率、时长、熟练度、每场平均、每 10 分钟 |
| `EntityRef` | 英雄、地图、统计项、威能的引用：大神 `guid`、官方 `official_id`（`0x…`）、名称。名称可能缺失，不能靠名称做连接 |
| `Rank` | 段位名、小段、分数、段位分 |

`Coverage` 记录每个请求是否成功，部分失败不会让整个采集失败，会在覆盖情况里写明。

### 请求的上游接口（`dashen/endpoint.rs`）

| 接口 | 用途 |
|---|---|
| `searchBnetAccount` | 按战网昵称查玩家，拿到 token（POST，其余为 GET） |
| `customer/queryCard` | 玩家资料卡 |
| `customer/queryCountInfo` | 竞技、快速的生涯：各职责、英雄使用统计、近期对局、省榜、荣誉 |
| `customer/queryMatchList`、`queryMatchInfo` | 对局列表、对局详情 |
| `customer/fight/queryCount`、`queryMatchList`、`queryMatchInfo` | 角斗领域的对应接口 |
| `queryProvinceRank`、`billboard/*` | 省榜、英雄榜 |

英雄统计和段位、近期对局来自同一个 `queryCountInfo`：一次请求返回你本赛季打过的全部英雄，与界面是否显示无关。

### 目录

内置快照 `crates/watch-core/data/query_tool.min.json`，包含英雄（图标、立绘、横幅、职责）、地图（图、玩法）、统计项清单（每个英雄有哪些统计）、威能、段位和荣誉图标。可用 `watchd import-catalog` 导入新版，也可用同目录的 `slim_catalog.py` 重新精简。目录通过 `/api/catalog` 提供给界面。

## 本机接口（`watchd`）

| 路径 | 作用 |
|---|---|
| `GET /healthz` | 存活检查 |
| `GET /api/state` | 服务状态、账号状态、请求记录 |
| `GET/POST /api/players` | 玩家库 |
| `POST /api/accounts` | 添加、更新、移除大神账号 |
| `POST /api/player/search` | 查玩家，返回会话编号 |
| `POST /api/player/view` | 某个视图（资料、对局、详情等），返回 IR |
| `POST /api/player/dataset` | 完整数据集和分析；可带 `progress_id` |
| `GET /api/progress?id=…` | 上面那次采集的实时进度 |
| `GET /api/cache`、`POST /api/cache/clear` | 查看、清除对局强度缓存 |
| `POST /api/player/export`、`/api/export/file` | 导出数据集 |
| `GET /api/catalog` | 目录 |
| `POST /api/request` | 白名单内的原始接口转发（调试用） |

会话只存在内存里，约一小时过期，过期后界面会自动重新查找。

## 界面（`app/lib`）

| 目录 | 内容 |
|---|---|
| `core/` | 数据模型（IR 的镜像）、接口调用、目录、英雄数据补全（`hero_stats.dart`）、游戏资料（`gamedata.dart`）、图片仓库（`image_store.dart`） |
| `design/` | 设计令牌（颜色、字体、间距）、表格、卡片列表、图表、图标和图片组件 |
| `state/` | 应用状态（每个玩家一个工作区，保存当前页、筛选、滚动位置和打开的对局或英雄）、命令注册表（菜单、快捷键、命令面板共用） |
| `ui/` | 外壳、玩家库、各页面 |

## 存放位置

| 内容 | 位置 |
|---|---|
| 账号凭据 | `%LOCALAPPDATA%\Watch Overwatch\secrets.json` |
| 界面状态（主题、行高、布局、上次的玩家和页面） | `%LOCALAPPDATA%\Watch Overwatch\ui-state.json` |
| 玩家库 | 同目录，由 `watchd` 维护 |
| 导出文件 | 同目录的 `exports\` |
| 图片缓存 | 同目录的 `img-cache\` |
| 对局强度缓存 | 同目录的 `cache\strength.db`（SQLite） |

## 对局强度缓存

`strength.db` 里有两张表：对局详情（按模式、对局编号、被查询的玩家）和玩家各赛季的竞技段位。里面有其他玩家的昵称和编号（对局详情里本来就有），但没有任何令牌。规则和保留时间见 [algorithms.md](algorithms.md) 的 4.6。设置页可以查看大小和清除。

采集计划（`CollectPlan`）里有四个相关字段：`roles`（只分析哪些职责，空表示全部）、`known_matches`（调用方已读取的对局记录，不空时服务不再翻列表）、`refresh_ratings`（跳过当前赛季段位的缓存）、`cache`（缓存本身，不序列化）。

## 图片

所有网络图片都经过同一个仓库（`image_store.dart`）：

- **磁盘**：下载一次就保存，文件名由地址的哈希生成，之后启动直接读磁盘，不再联网。
- **同时请求**：同一地址同一时间只发一个请求，其余等待同一结果。
- **内存**：解码后的图片放在框架的图片缓存里，上限 4000 张、600 MB；两个地方用同一张图，只解码一次，切换页面不会重新加载。
- **占位**：图片到达前显示同样大小的灰色占位块，带缓慢移动的高光；失败时显示文字或留空，不影响数据。
- **预加载**：目录到达后，后台预加载全部英雄的小图标和肖像、段位和荣誉图标；加载超过约 0.35 秒时，状态栏显示进度。

## 英雄资料和图标

英雄简介、技能、威能的名称和说明、技能和威能图标，来自本机安装的游戏，用 OWLib 的 DataTool 解包。解包方法和已整理的资源见 [game-data.md](game-data.md)；`resources/game/` 是整理后的资料，`app/assets/game/` 是打进应用的副本，用 `tools/sync_game_assets.py` 同步。
