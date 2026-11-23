# CheckLet ☑︎

Mac 桌面上的半透明悬浮待办小球。鼠标移上去显示今日 / 本周待办和重要日期，按快捷键固定显示；可以连接 Claude、Codex 等 AI 工具，直接说一句话就能管理待办。

## 功能

| | |
|---|---|
| **悬浮球** | 显示今日剩余数量和完成进度环；今天或明天有重要日期时会有小红点。可拖动，靠边自动吸附 |
| **悬停显示** | 鼠标移到球上 → 弹出面板，移开自动收起；在面板里点过（比如正在输入）就会保持打开，点别处才收起 |
| **固定显示** | 点击小球、按 **⌃⌥T** 或点面板上的 📌 → 一直显示。快捷键还会直接聚焦输入框，可以马上输入。Esc 隐藏 |
| **今日待办** | 没做完的会自动顺延到第二天（标注"从 X 月 X 日顺延"），右键可"推迟到明天" |
| **本周待办** | 按周一到周日计；没做完的顺延到下周 |
| **重要日期** | 生日、截止日等，显示"明天 / 还有 8 天"倒计时，可以打勾 |
| **自动分类** | 工作 / 学习 / 生活 / 健康 / 财务 / 人情，不选也会自动识别，还会学习你的修正习惯 |
| **AI 连接** | 内置 MCP 服务，Claude Desktop / Claude Code / Codex 一键连接；其他支持 MCP 的工具粘贴配置即可 |
| **外观** | 磨砂玻璃 / 液态玻璃（macOS 26+）/ 高透明，不透明度可调，跟随系统深浅色 |

## 安装

**系统要求**：macOS 13 Ventura 及以上，Apple 芯片和 Intel 芯片的 Mac 都支持。

### 方式一：下载安装包

1. 到 [Releases](https://github.com/Cha1ron/CheckLet/releases) 页面下载最新的 `CheckLet-x.y.z.dmg`
2. 双击打开 DMG，把 **CheckLet** 拖进「应用程序」文件夹
3. 从「应用程序」里打开 CheckLet

> **第一次打开提示"无法验证开发者"？**
> 目前安装包还没有经过 Apple 公证，macOS 会拦截一次。任选一种方式放行：
> - 打开「系统设置 → 隐私与安全性」，往下翻，点 CheckLet 旁边的「仍要打开」
> - 或者在终端运行：`xattr -cr /Applications/CheckLet.app`，然后正常打开

### 方式二：从源码构建

需要 Xcode 或 Command Line Tools（Swift 5.9+）：

```bash
git clone https://github.com/Cha1ron/CheckLet.git
cd CheckLet
./scripts/package.sh            # 产物在 dist/ 目录
cp -R dist/CheckLet.app /Applications/
```

### 开始使用

打开后屏幕右侧会出现一个半透明小球，菜单栏也会出现 ☑︎ 图标：

- 鼠标移到小球上 → 显示待办；点击小球 → 固定显示
- **⌃⌥T** → 固定显示并直接输入，再按一次隐藏（可在设置里更换快捷键）
- 拖动小球换位置；右键小球或点菜单栏图标 → 设置、连接 AI 工具、开机启动

### 卸载

退出 CheckLet（菜单栏图标 → 退出），删除「应用程序」里的 CheckLet.app。如需同时删除数据：

```bash
rm -rf ~/Library/Application\ Support/CheckLet
```

## 分类

每条待办都有一个分类：💼 工作 · 📚 学习 · 🏠 生活 · 💪 健康 · 💰 财务 · 💝 人情 · 📌 其他。面板里可以按分类筛选。

**不用手动选，会自动识别**，比如「给我家猫换猫砂」→ 🏠 生活，「交房租」→ 💰 财务，「给妈妈买生日礼物」→ 💝 人情。识别方式按优先级：

1. **你指定的**：添加时点输入框左边的 ✨ 选分类，或在内容里写 `#生活`、`#工作`
2. **AI 工具指定的**：通过 Claude / Codex 添加时，由 AI 根据语义直接选择
3. **你的习惯**：点击待办上的分类标签修改后，CheckLet 会记住。比如把「带团子洗澡」改成生活后，以后跟「团子」有关的都会归到生活
4. **Apple Intelligence**：在支持的 Mac（macOS 26+，开启了 Apple Intelligence）上，用端侧模型复核自动分类，不联网
5. **关键词规则**：内置中英文关键词，离线即时生效

## 连接 AI 工具

打开 设置 → **AI 连接**（菜单栏图标 / 右键小球 / 面板上的齿轮），然后：

- **Claude Desktop**：点「一键连接」，然后完全退出并重开 Claude Desktop
- **Claude Code**：点「一键连接」（会调用 `claude mcp add --scope user …`），新开一个会话生效
- **Codex**：点「一键连接」（写入 `~/.codex/config.toml`），重启 Codex 生效
- **Muse 或其他工具**：如果它支持 MCP，在它的 MCP 设置里粘贴页面上的 JSON 配置；只能执行命令的话，用页面上的命令行写法

连接前请先把 App 放进「应用程序」文件夹，因为 AI 工具记住的是 App 所在的路径。修改配置文件前会自动备份为 `*.checklet-backup`。

连接之后可以这样说：

- 「把明天下午 3 点交周报加到我的待办」→ 明天出现在今日待办
- 「这周要做：健身三次、整理照片、给房东打电话」→ 批量加到本周
- 「12 月 10 日项目上线，记到重要日期」
- 「我今天还有什么没做？」「把买牛奶打勾」「把整理照片挪到下周」
- 「帮我把待办重新分类一下」「这周工作类的还剩几件？」

AI 加的待办会带一个来源小标签（Claude / Codex）。

### MCP 工具一览

| 工具 | 说明 |
|---|---|
| `list_todos` | 查看待办（可按清单筛选，可包含未来的） |
| `add_todo` / `add_todos` | 添加一条 / 多条（`list`: today / week / date，`date`: YYYY-MM-DD，`category`: 分类） |
| `complete_todo` | 打勾 / 取消打勾（id 或标题关键字） |
| `update_todo` | 改内容、清单、日期、备注、分类 |
| `delete_todo` | 删除 |

## 命令行

```bash
C=/Applications/CheckLet.app/Contents/MacOS/CheckLet
$C list                      # 查看
$C add 写周报                 # 今日
$C add 健身 --week            # 本周
$C add 妈妈生日 -d 12-01      # 重要日期
$C add 取快递 --on 明天        # 明天的今日待办
$C add 买猫粮 -c 生活          # 指定分类（不指定会自动识别）
$C list -c 工作               # 只看某个分类
$C done 周报                  # 打勾（id 或标题关键字）
$C rm 3fa2c1                 # 删除
```

## 开发

需要 Xcode 或 Command Line Tools（Swift 5.9+），不需要完整的 Xcode。

```bash
swift build && .build/debug/CheckLet    # 直接运行调试版
./scripts/package.sh                    # 打包 → dist/（通用二进制 .app、.dmg、.zip）
```

### 发布签名版本

有 Apple 开发者账号（Developer ID 证书）时，可以签名并公证，用户下载后直接双击即可打开：

```bash
xcrun notarytool store-credentials checklet   # 只需一次，按提示填 Apple ID / 团队 ID / App 专用密码
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" NOTARY_PROFILE=checklet VERSION=1.1.0 ./scripts/package.sh
```

| 路径 | 内容 |
|---|---|
| `Sources/CheckLet/Core/` | 数据模型、文件存储（flock 加锁，多进程安全）、业务逻辑 |
| `Sources/CheckLet/MCP/` | MCP 服务（JSON-RPC over stdio）和命令行 |
| `Sources/CheckLet/App/` | 悬浮球、面板、设置界面、快捷键、AI 连接 |
| `scripts/` | 打包脚本、图标生成 |

数据保存在 `~/Library/Application Support/CheckLet/todos.json`。App、AI 工具、命令行都读写这个文件，App 每秒检查一次变化，所以 AI 加的待办会马上出现在面板里。设置环境变量 `CHECKLET_DATA_DIR` 可以改用别的目录（方便测试）。
