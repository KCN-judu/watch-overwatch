# resources/game

从本机国服守望先锋 2.25.0.0.154461 解包得到的资源（简体中文）。说明与重新解包方法见 `docs/game-data.md`。

| 文件 | 内容 |
|---|---|
| `heroes.json` | 54 个英雄：`name`、`class`（Tank/Damage/Support）、`subrole`（名称+被动）、`abilities`（名称、类别、说明、图标路径）、`perks`（名称、说明、图标路径） |
| `hero_subrole.json` | 英雄中文名 → 子职责中文名（奇袭、医疗、神准、专业、铁壁、侦察、先锋、战术、斗士、生存） |
| `maps.json` | 地图：官方 GUID、名称、变体名、类型（OffenseDefenseMap / MirroredMap / PVE） |
| `icons/heroes/<英雄>/abilities/*.png` | 技能、终极技能、被动技能图标，按中文名命名 |
| `icons/heroes/<英雄>/perks/*.png` | 威能图标 |
| `icons/ui/role-*.svg` | 官方职责图标（矢量，单色，用时按主题着色） |

这个目录不会被打进应用。需要用到哪类资源，再复制到 `app/assets/` 并在 `pubspec.yaml` 里登记。
