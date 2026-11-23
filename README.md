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
| **AI 连接** | 内置 MCP 服务，Claude Desktop / Claude Code / Codex 一键连接；其他支持 MCP 的工具粘贴配置即可 |
| **外观** | 磨砂玻璃 / 液态玻璃（macOS 26+）/ 高透明，不透明度可调，跟随系统深浅色 |

## 给朋友安装

把 `dist/CheckLet-1.0.0.dmg` 发给朋友，附带 [docs/安装说明.txt](docs/安装说明.txt)（DMG 里已经放了一份）。

支持 macOS 13 及以上，Apple 芯片和 Intel Mac 都可以（通用二进制）。

> 因为没有用 Apple 开发者证书签名，朋友第一次打开时 macOS 会拦截，需要到「系统设置 → 隐私与安全性」点「仍要打开」，或者在终端运行 `xattr -cr /Applications/CheckLet.app`。
> 如果你有 Apple 开发者账号（$99/年），可以签名 + 公证，朋友就能直接双击打开：
>
> ```bash
> xcrun notarytool store-credentials checklet   # 只需一次，按提示填 Apple ID / 团队 ID / App 专用密码
> SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" NOTARY_PROFILE=checklet ./scripts/package.sh
> ```

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

AI 加的待办会带一个来源小标签（Claude / Codex）。

### MCP 工具一览

| 工具 | 说明 |
|---|---|
| `list_todos` | 查看待办（可按清单筛选，可包含未来的） |
| `add_todo` / `add_todos` | 添加一条 / 多条（`list`: today / week / date，`date`: YYYY-MM-DD） |
| `complete_todo` | 打勾 / 取消打勾（id 或标题关键字） |
| `update_todo` | 改内容、清单、日期、备注 |
| `delete_todo` | 删除 |

## 命令行

```bash
C=/Applications/CheckLet.app/Contents/MacOS/CheckLet
$C list                      # 查看
$C add 写周报                 # 今日
$C add 健身 --week            # 本周
$C add 妈妈生日 -d 12-01      # 重要日期
$C add 取快递 --on 明天        # 明天的今日待办
$C done 周报                  # 打勾（id 或标题关键字）
$C rm 3fa2c1                 # 删除
```

## 开发

需要 Xcode 或 Command Line Tools（Swift 5.9+），不需要完整的 Xcode。

```bash
swift build && .build/debug/CheckLet    # 直接运行调试版
./scripts/package.sh                    # 打包 → dist/
```

| 路径 | 内容 |
|---|---|
| `Sources/CheckLet/Core/` | 数据模型、文件存储（flock 加锁，多进程安全）、业务逻辑 |
| `Sources/CheckLet/MCP/` | MCP 服务（JSON-RPC over stdio）和命令行 |
| `Sources/CheckLet/App/` | 悬浮球、面板、设置界面、快捷键、AI 连接 |
| `scripts/` | 打包脚本、图标生成 |

数据保存在 `~/Library/Application Support/CheckLet/todos.json`。App、AI 工具、命令行都读写这个文件，App 每秒检查一次变化，所以 AI 加的待办会马上出现在面板里。设置环境变量 `CHECKLET_DATA_DIR` 可以改用别的目录（方便测试）。
