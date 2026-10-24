# 命令行

两类命令：`watchd` 的离线命令（不启动服务，直接采集或分析），开发用的 `cargo xtask`。

## watchd

不带参数运行 `watchd.exe` 启动本机服务，见 [本机接口](http-api.md)。带子命令时不启动服务：

```powershell
# 竞技和快速，每个模式最多读 5 页对局列表，读 20 场详情，查参与者段位
.\watchd.exe dataset "Player#12345" --modes competitive,quick --pages 5 --details 20 --lobby

# 每个职责取最近 5 场，只看重装
.\watchd.exe dataset "Player#12345" --modes quick --per-role 5 --roles tank --lobby

# 分析一份已有的数据集
.\watchd.exe analyze path\to\dataset.json
```

### `dataset`

输出 `{dataset, analysis}`：数据集结构见 [数据结构](data-model.md)。

| 选项 | 含义 | 默认 |
|---|---|---|
| `--modes a,b` | 模式：`competitive`、`quick`、`stadium` | `competitive,quick` |
| `--season N` | 对局列表和生涯只读这个赛季 | 当前赛季 |
| `--career-seasons 20,21` | 另外读这些赛季的生涯，最多 11 个 | 无 |
| `--pages N` | 每个模式最多读几页对局列表，1–20 | 5 |
| `--details N` | 读最新多少场的详情，最多 5000 | 20 |
| `--per-role N` | 改为每个职责取最新 N 场读详情，1–50；`--details` 不再生效 | 不设 |
| `--roles tank,damage,support` | 只分析这些职责 | 全部 |
| `--no-hero-board` | 不读英雄榜 | 读 |
| `--lobby` | 给详情里的参与者取段位快照（对局强度要用） | 不取 |
| `--max-rated N` | 最多查多少名参与者的段位，最多 5000 | 60 |
| `--no-cache` | 不用本机对局库 `matches.db`（默认读写：已存的详情和段位快照直接复用） | 用 |
| `--out PATH` | 输出文件 | 数据文件夹的 `exports\` |

### `analyze`

`analyze <dataset.json> [--utc-offset 分钟] [--out PATH]`：对数据集做全部分析（汇总、分时段、分职责、分英雄、对局强度等）。不带 `--out` 时输出到标准输出。输入可以是 `dataset` 的输出，也可以是单独的数据集。

### 其他子命令

| 命令 | 作用 |
|---|---|
| `import-catalog <query_tool.json>` | 导入新版目录（英雄、地图名称和当前赛季），写到数据文件夹的 `catalog.json`；不导入时用内置快照 `crates/watch-core/data/query_tool.min.json` |
| `import-legacy <config.py>` | 从旧版配置导入大神账号到 `secrets.json`；已有 `secrets.json` 时拒绝 |
| `apply-update <新文件夹> <程序文件夹>` | 应用内更新用的安装步骤，由 `/api/update/apply` 调起，不手动运行 |

### 数据文件夹

默认 `%LOCALAPPDATA%\Watch Overwatch\`；设了环境变量 `WATCH_DATA_DIR` 时改用它（服务和应用都认）。凭据在 `secrets.json`，对局库在 `cache\matches.db`，玩家库在 `players.json`。

## cargo xtask

在仓库任意位置运行，只需要 Rust 工具链，任务有自己的测试：

| 命令 | 作用 |
|---|---|
| `cargo xtask sync-assets` | 把 `resources/game/`（解包游戏得到，见 [游戏数据](game-data.md)）复制进 `app/assets/game/`，并登记到 `app/pubspec.yaml` |
| `cargo xtask slim-catalog <完整文件> <输出文件>` | 把完整的 `query_tool.json` 精简成程序读取的快照 |
| `cargo xtask update-catalog <目录>` | 用下载到 `<目录>` 的大神线上配置重建内置快照（见下） |
| `cargo xtask package` | 把 `target\release\watchd.exe` 和 `flutter build windows --release` 的产物打成 `dist\watch-overwatch-v<版本>-windows-x64.zip`，并写出 `.sha256`；不自己构建，先跑这两个 release 构建 |
| `cargo xtask release-notes <版本>` | 打印 `CHANGELOG.md` 里这个版本的一节，用作 GitHub 发布说明（应用的“更新内容”显示的就是它） |

### 更新内置目录

内置快照 `crates/watch-core/data/query_tool.min.json` 来自大神公开的配置文件，含英雄、地图、段位名称和图标、角斗领域的异能与装备。大神有新英雄、新地图、改名或换图时：

```powershell
$dir = "$env:TEMP\ds_ow"; New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($f in 'ow_record_query_tool','ow_hero_config','ow_map_config','ow_record_query_tool_mod_trait','ow_hero_attr','ow_perk_list') {
  Invoke-WebRequest "https://s.166.net/config/ds_ow/$f.json" -OutFile "$dir\$f.json"
}
cargo xtask update-catalog $dir
```

`update-catalog` 不联网，合并规则和大神自己的查询工具一致：

- 取 `ow_record_query_tool.json`，去掉由其他文件提供的部分。
- 合并另外五个文件：英雄、地图、异能与装备、英雄属性、威能。
- `seasonList` 没有线上文件，沿用现有快照里的。

合并后精简，覆盖快照。之后运行 `cargo test`，再看 `git diff`。

## 示例玩家

示例玩家（`watch_core::demo`，按固定规则生成对局，不请求大神）只编进开发构建：`cargo build`、`flutter run` 带，`cargo build --release`、`flutter build windows --release` 默认不带，发布包没有。发布构建要带上时两边一起打开：

```powershell
cargo build --release -p watchd --features demo
flutter build windows --release --dart-define=WATCH_DEMO=true
```

服务端开关：`watch_core::DEMO_AVAILABLE`（`/api/state` 的 `demo`）；应用开关：`app/lib/core/build.dart` 的 `demoBuild`。两边都有才显示“打开示例玩家”。不带示例的构建读玩家库时跳过开发构建留下的 `示例玩家#0000`，文件本身不改。

## 文档截图

`docs/images/` 里的截图由脚本拍，不用手动截：

```powershell
powershell -File tools/docs-screenshots.ps1                 # 构建带示例玩家的版本，再拍全部
powershell -File tools/docs-screenshots.ps1 -NoBuild        # 用上次的构建
powershell -File tools/docs-screenshots.ps1 -NoBuild -Only overview,maps
```

| 步骤 | 做法 |
|---|---|
| 构建 | `watchd` 带 `--features demo`（目标目录 `target/demo`，不碰正在运行的那份），应用带 `--dart-define=WATCH_DEMO=true`，复制到 `target/screenshots/app` |
| 启动 | 数据目录 `target/screenshots/data`（`WATCH_DATA_DIR`），端口 18380（`WATCHD_PORT`），服务程序用 `WATCHD_PATH` 指定；可以和平时用的那份同时开。预先写好 `ui-state.json`（主题、竞技模式、不检查更新）和 `players.json`（示例玩家），启动即打开示例玩家的概览 |
| 拍摄 | 每张图重新启动一次，按 `$Shots` 里的步骤点击；窗口固定 1360 × 860，按窗口可见边框截取 |
| 加工 | ImageMagick：去掉最外 1 像素、8 像素圆角、阴影、纯色底（`-Background`，默认 `#D9E0EA`）。原始截图留在 `target/screenshots/raw` |

参数：`-Theme light` 拍浅色主题，`-Out` 换输出目录。

- 需要 ImageMagick 7（`magick`）在 PATH 上。
- 运行时不要动鼠标：脚本在应用窗口里点击。应用不在最前时脚本会停下，不会点到别的窗口。
- 页面靠点击固定坐标进入，不用快捷键（中文输入法会截走模拟的按键）。界面布局变了以后，先跑一次、看 `target/screenshots/raw`，再改脚本里的坐标。
- 图片来自大神和暴雪的图片地址，第一次运行会先把每页走一遍，等图片缓存好再拍。

## 文档站

文档站在 `site/` 下，是一个 Astro 项目；内容来自 `docs/` 和 `CHANGELOG.md`，构建前由 `site/scripts/prepare.mjs` 整理。本地预览：

```powershell
cd site
npm ci
npm run dev
```

推送到 `main` 后，GitHub Actions 会构建并发布到 GitHub Pages。
