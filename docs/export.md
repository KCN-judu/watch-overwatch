# 导出协议

两种导出，结构不同：

| | 应用的“导出数据集” | `POST /api/player/export` |
|---|---|---|
| 内容 | 完整数据集和分析 `{dataset, analysis}`，结构见 [数据结构](data-model.md) | 匿名化的协议文档，版本 1.1.0，见下 |
| 标识 | 含战网编号、对局编号、大神 GUID | 只有显示名 |
| 来源 | `POST /api/player/dataset`（命令行 `watchd dataset` 输出同样的结构） | 一个视图（`/api/player/view` 的同一组参数） |
| 用在 | 应用 | 旧网页界面、脚本 |

两种都不含凭据。

## 导出数据集

应用里选模式、每个模式的场数（最近 1–5000 场或全部）、是否带玩家段位。先把对局列表读到够数，再分小批准备详情（和段位快照）；本机已存的不再读。最后用这些对局请求 `/api/player/dataset`（`match_limit` 为场数，`lobby_ratings` 为是否带段位），把返回原样写成 JSON 文件。

## 协议文档（1.1.0）

JSON Schema：[`watch-overwatch.schema.json`](watch-overwatch.schema.json)。删除或改动字段升主版本，只新增可选字段升次版本。

请求体与 `/api/player/view`（见 [本机接口](http-api.md)）相同（`session`、`view`、`mode`、`season`、`page`、`scope`、`start_season`、`second_session`），另有：

| 字段 | 默认 | 含义 |
|---|---|---|
| `technical` | `false` | 为真时 `provider_data` 带脱敏后的大神原始数据 |
| `include_teammates` | `true` | 向大神读视图里前 20 场的详情，填 `teammates`、`enemies` |

### 顶层字段

| 字段 | 内容 |
|---|---|
| `schema_version` | `"1.1.0"` |
| `generated_at_unix_ms` | 生成时间 |
| `source` | `provider`（`netease_dashen`）、`client`、`client_version` |
| `query` | `view`、`mode`、`season`、`page`、`scope`、`timezone`；没传 `season` 时填目录里的当前赛季，不是大神确认的赛季 |
| `completeness` | `status`、`page_limit`、`cached`、`season_errors`（往期赛季里读取失败的个数），见下 |
| `units` | 时间戳为 Unix 毫秒，时长为秒，胜率为 0–100，缺失为 `null`，汇总胜率的分母为胜 + 负；`identifier_policy`、`provider_fields` 说明是否带了大神标识和原始数据 |
| `entities` | 出现过的英雄和地图：`{kind, name}`，`kind` 为 `hero` 或 `map`；没有名称时为 `未知` |
| `records` | `player_name`、`matches`、`summary` |
| `provider_data` | 默认 `null` |

### `completeness.status`

| 值 | 含义 |
|---|---|
| `complete` | `summary`、`sameplay` 视图读到了对局列表的最早一场 |
| `partial` | `summary` 视图到了 5 页的上限 |
| `page` | `matches` 视图，只有一页 |
| `provider_snapshot` | 其余视图：大神这一次返回的内容 |

`complete` 只表示读完了大神可提供的对局列表，不等于玩家的全部历史。

### `records`

`records.matches` 每场：

| 字段 | 内容 |
|---|---|
| `match_index` | 在本次导出里的序号，从 0 起 |
| `player_name` | 本人显示名 |
| `outcome` | `win`、`loss`、`draw`、`unknown` |
| `started_at_unix_ms` | 开始时间 |
| `hero_name`、`hero_role` | 英雄名（缺失为 `未知英雄`）、职责中文名 |
| `map_name` | 地图名（缺失为 `未知地图`） |
| `score` | `[己方, 对方]` |
| `stats` | `kills`、`assists`、`deaths`、`damage`、`healing`、`blocked_damage`、`mitigation` |
| `teammates`、`enemies` | 己方（含本人）、对方每人的 `player_name`（缺失为 `未知玩家`）、`hero_name`、`hero_role`、`stats`；没读详情时为空 |

`blocked_damage` 与 `mitigation` 同值，都是大神的 `resistDamage`：阻挡、减免的伤害量，不是次数。

`records.summary`：`matches`、`wins`、`losses`、`draws`、`unknown`、`win_rate`、`kills`、`assists`、`deaths`、`damage`、`healing`（合计）、`kda`、`best_streak`。

不输出对局编号、官方 UID、大神 GUID。`records` 只覆盖对局：`profile`、`card`、`heroes`、`history` 视图的内容只在 `technical` 导出的 `provider_data` 里。

### 脱敏

`query` 和 `provider_data` 递归去掉键名含 `token`、`apikey`、`cookie`、`authorization`、`password`、`traceid`（忽略大小写、`_` 和 `-`）的字段，以及 `session` 字段。`technical` 导出适合调试，不适合作为第三方分析的输入。
