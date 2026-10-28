# 编写插件

这份文档说明怎样为 [Ruyio](https://github.com/h025/Ruyio) 编写插件，以及怎样把它加进这个插件市场。完整的字段和接口说明在 Ruyio Wiki：

- [编写第一个插件](https://github.com/h025/Ruyio/wiki/编写第一个插件)（手把手教程）
- [插件清单参考](https://github.com/h025/Ruyio/wiki/插件清单参考)
- [SDK 与界面参考](https://github.com/h025/Ruyio/wiki/SDK-与界面参考)
- [打包、签名与发布](https://github.com/h025/Ruyio/wiki/打包签名与发布)

## 插件是什么

- 一个独立的 macOS App，运行在 **App 沙盒**里，没有 Dock 图标（`LSUIElement`）。
- 由 Ruyio 按需启动（空闲 30 秒自动退出），通过标准输入输出与 Ruyio 交换消息，SDK 已经封装好。
- **不自己画界面**：返回一份界面描述（列表、表单、预览……），由 Ruyio 用原生控件绘制。
- 需要的系统操作（写剪贴板、在用户右键的文件夹里写文件、打开 App、框选截图、钉图……）都通过 SDK **请 Ruyio 代办**，并在清单里声明权限。
- 一个插件可以提供多个**动作**，每个动作可以出现在命令面板、全局快捷键、菜单栏、Finder 右键菜单中。

## 准备

- Apple Silicon Mac，macOS 15+，Xcode 26+，[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- 把 Ruyio 源码克隆到这个仓库旁边（插件 SDK 在其中的 `Packages/RuyioKit`）：

```sh
cd ~/Developer
git clone https://github.com/h025/Ruyio.git
git clone https://github.com/h025/ruyio-market.git
```

构建脚本默认在 `../Ruyio` 找 SDK；放在别处时用环境变量 `RUYIO_ROOT=/path/to/Ruyio` 指定。

## 仓库结构

```
ruyio-market/
├── ruyio-market.json                      # 市场索引
├── Scripts/build-plugin.sh                # 构建、打包、记录版本
└── plugins/<名字>/
    ├── ruyio-plugin.json                  # 插件描述：所有发布过的版本及 SHA-256
    ├── releases/<版本>/<Name>.ruyioplugin.zip   # 已发布的安装包（推送后不再改动）
    └── Plugin/                            # 插件源码
        ├── project.yml
        ├── manifest.json
        └── Sources/
```

## 在这个仓库里新增一个插件

### 1. 从截图插件复制一份

```sh
cp -R plugins/screenshot/Plugin plugins/hello/Plugin
rm -rf plugins/hello/Plugin/build plugins/hello/Plugin/*.xcodeproj
```

### 2. 改工程定义 `plugins/hello/Plugin/project.yml`

把 `name`、target 名、scheme 名、`PRODUCT_NAME` 都改成 `Hello`，`bundleIdPrefix` 和 `PRODUCT_BUNDLE_IDENTIFIER` 改成你的前缀和 ID（例如 `io.github.yourname`、`io.github.yourname.hello`，ID 要与清单里的 `id` 一致），`entitlements.path` 改成 `build/Hello.entitlements`，`CFBundleShortVersionString` 与清单 `version` 保持一致。保持这几项不变：

- `packages.RuyioKit.path: ${RUYIO_ROOT}/Packages/RuyioKit`，依赖 `RuyioPluginSDK`；
- `ENABLE_HARDENED_RUNTIME: YES`、`ARCHS: arm64`，`CODE_SIGN_IDENTITY: "-"`（临时签名，见下文“关于签名和公证”）；
- 签名权限只有 `com.apple.security.app-sandbox: true`；
- **`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`**：否则 Xcode 会加上调试用的 `get-task-allow`，Ruyio 会以“签名权限不在白名单”拒绝安装；
- `manifest.json` 作为资源打进 App；`LSUIElement: true`。

### 3. 写清单 `plugins/hello/Plugin/manifest.json`

```json
{
  "schemaVersion": 1,
  "id": "io.github.yourname.hello",
  "name": "Hello",
  "version": "1.0.0",
  "description": "A first Ruyio plugin.",
  "author": "yourname",
  "license": "MIT",
  "source": "https://github.com/h025/ruyio-market",
  "runtime": "native-isolated",
  "bundlePath": "Hello.app",
  "executable": "Hello.app/Contents/MacOS/Hello",
  "architectures": ["arm64"],
  "minimumHostVersion": "1.1.0",
  "minimumMacOSVersion": "15.0",
  "permissions": ["clipboard.write"],
  "actions": [
    {
      "id": "say-hello",
      "title": "Say Hello",
      "symbol": "hand.wave",
      "keywords": ["hello", "你好"],
      "presentations": [
        {"type": "commandPalette"},
        {"type": "globalHotkey", "defaultShortcut": "control+option+h"}
      ]
    }
  ],
  "defaultLocale": "en",
  "localizations": {
    "zh-Hans": {
      "name": "你好",
      "description": "第一个 Ruyio 插件。",
      "action.say-hello.title": "打个招呼"
    }
  }
}
```

清单速查：

- `id`：反向域名，小写字母、数字、`-`；`app.ruyio.` 前缀保留给官方插件。这个市场里的插件用 `io.github.<你的 GitHub 名>.<插件名>`。
- `version`：语义化版本；**每次发布都要升**。
- `bundlePath` / `executable` 必须与 App 实际的名字一致。
- 入口 `presentations[].type`：`commandPalette`、`globalHotkey`（`defaultShortcut` 如 `control+shift+a`，必须带 ⌘/⌃/⌥）、`menuBar`、`finderContextMenu`（需要 `contexts`）。
- 有副作用（写剪贴板、写文件、截图）的动作标 `"hasSideEffects": true`，超时从 10 秒放宽到 120 秒。
- 打开界面的动作用 `"opensView": "<视图 id>"`，并在 `views` 里声明 `{"id", "title", "placement": "overlay"}`；设置界面用 `"placement": "settings"`。
- 本地化键：`name`、`description`、`action.<id>.title`、`action.<id>.palette` / `.menu` / `.finder`（对应入口设置了 `title` 时）。

权限一览：

| 权限 | 用途 |
|---|---|
| `clipboard.write` | 写剪贴板 |
| `clipboard.read` | 读剪贴板（只是声明，无法强制） |
| `files.write` | 在用户右键的文件夹里创建文件 |
| `files.read.selected` | 读取用户在 Finder 中选中的文件 |
| `apps.open` | 打开网页、终端、编辑器，在 Finder 中显示文件 |
| `paste.automatic` | 界面关闭后由 Ruyio 自动粘贴回原 App |
| `screen.capture` | 框选截图（Ruyio 1.1+） |
| `windows.pin` | 钉图窗口（Ruyio 1.1+） |
| `background` | 常驻运行 |
| `network.client` | 联网（签名里还要加 `com.apple.security.network.client`） |

### 4. 写代码

`Sources/main.swift`：

```swift
import RuyioPluginSDK

PluginRuntime.run(HelloPlugin.self)
```

`Sources/HelloPlugin.swift`：

```swift
import Foundation
import RuyioPluginSDK

final class HelloPlugin: RuyioPlugin {
    let context: PluginContext

    init(context: PluginContext) {
        self.context = context
    }

    func perform(_ invocation: ActionInvocation, execution: ExecutionID, operation: OperationID?) async throws -> ActionResult {
        switch invocation.actionID.rawValue {
        case "say-hello":
            return .succeeded(.notice(context.isChinese ? "你好，Ruyio！" : "Hello, Ruyio!"))
        default:
            throw RuyioError(.actionNotFound, objectID: invocation.actionID.rawValue)
        }
    }
}
```

SDK 速查：

| 需要 | 用法 |
|---|---|
| 显示提示 / 打开界面 / 先让用户填表 | `return .succeeded(.notice("…"))` / `.openView("id")` / `.requestInput(FormSpec(...))` |
| 写剪贴板 | `try await context.capabilities.writeClipboard(ClipboardWriteRequest(items:originToken:))` |
| 在 Finder 右键的文件夹里写文件 | `try await context.capabilities.writeFiles(FileWriteRequest(directory: invocation.finder!.targetDirectory!, items: [...]), operation: operation!)` |
| 打开网页 / 终端 / 编辑器 | `openWebLink(_:)` / `openTerminal(directories:)` / `openInConfiguredApplication(role: "editor", targets:)` |
| 框选截图 | `try await context.capabilities.captureScreen(execution: execution)`，返回存进本插件存储的 PNG `blobID` |
| 钉图 | `try await context.capabilities.pinImage(blobID:scale:)` |
| 存数据 | `context.storage.put(StoredDocument(collection:id:body:fields:searchText:sortKey:blobIDs:))`、`get`、`delete`、`query(StorageQuery(...))`、`batch` |
| 存二进制 | `context.storage.putBlob(data)` → `blobID`；记得写进某个文档的 `blobIDs`，否则 10 分钟后会被清理 |
| 界面 | `openView` / `handleViewEvent` 返回 `ViewDocument(viewID:revision:title:root:)`，`root` 常用 `.collection(CollectionSpec(...))`；`revision` 每次都要增大 |
| 本地化 | `context.isChinese`、`context.localized(key, fallback)` |

几条规则：

- 动作超时：普通 10 秒，`hasSideEffects` 120 秒；超时后任务会被取消。
- `print` 不会显示（标准输出是通信通道），请用 `os.Logger` 并在“控制台”App 里看。
- 插件在沙盒里：不能直接读写用户文件、不能启动其他程序、默认不能联网。
- 单个存储文档不超过 512 KiB；每次查询最多 200 条；界面文档最多 500 个节点。
- 数据格式变化时升 `storageSchemaVersion`，并实现 `migrateData` / `checkHealth`。

### 5. 编译、打包、本地试装

```sh
Scripts/build-plugin.sh hello
```

脚本会编译 Release 版，打包成 `plugins/hello/releases/<版本>/Hello.ruyioplugin.zip`（包内是 `Hello.ruyioplugin/` 目录，含 App 和一份与 App 内完全相同的 `manifest.json`），计算 SHA-256，并在 `plugins/hello/ruyio-plugin.json` 里记录这个版本（文件不存在时自动创建）。

试装：Ruyio › 通用设置 › 高级 › 打开**开发者模式** › 开发插件 › **选择本地开发插件…**，选刚生成的 zip。按 ⇧⌘Space 打开命令面板试用。改代码后要重新试装：先在插件详情中卸载（默认保留数据），再选新的安装包。

同一个版本号在**推送前**可以用 `Scripts/build-plugin.sh hello --replace` 重新生成；推送后就不能再替换，必须升版本号。

### 6. 登记到市场

在 `ruyio-market.json` 的 `plugins` 里加一项：

```json
{
  "id": "io.github.yourname.hello",
  "manifest": "plugins/hello/ruyio-plugin.json",
  "name": "Hello / 你好",
  "summary": "A first Ruyio plugin. 第一个 Ruyio 插件。"
}
```

### 7. 提交

```sh
git add plugins/hello ruyio-market.json
git commit -m "Add the Hello plugin 1.0.0"
git push
```

推送后，已添加这个市场的用户在 Ruyio 里刷新（插件市场 › 来源 › ⋯ › 刷新）就能看到。

### 发布新版本

1. 改代码，把 `manifest.json` 的 `version` 升一级；
2. `Scripts/build-plugin.sh hello`：生成新的 `releases/<新版本>/` 并在 `ruyio-plugin.json` 里追加一项（旧版本保留）；
3. 提交推送。用户的 Ruyio 检查更新时会提示“可更新”。

新版本必须由同一个签名者签名；新增的权限会在用户更新时列出来请他确认。

## 关于签名和公证

这个市场里的插件目前是**临时签名**、没有经过 Apple 公证，所以用户需要打开开发者模式才能安装，Ruyio 会把它们作为“开发者插件”安装。

要让用户在普通模式下安装，需要 Apple Developer Program 账号：用 Developer ID 签名、开启 Hardened Runtime、提交公证并 staple，再打包。具体命令见 Wiki 的[打包、签名与发布](https://github.com/h025/Ruyio/wiki/打包签名与发布)。

无论哪种方式，Ruyio 安装时都会检查：必须开启 App 沙盒；签名权限只允许 `app-sandbox`（以及与 `network.client` 对应的 `network.client`）；签名标识等于 Bundle ID；`LSUIElement` 为真；不能内嵌其他可启动的程序（`.app`、`.xpc`、`.appex`、登录项等）；安装包内外的 `manifest.json` 完全一致；SHA-256 与描述文件一致。

## 实例：截图插件

`plugins/screenshot/Plugin/Sources/ScreenshotPlugin.swift` 演示了：

- **截图并钉住**（`capture-pin`，`hasSideEffects`）：`captureScreen(execution:)` 让用户框选，返回的 PNG 已存进插件存储；插件把它记成一条历史文档（`blobIDs` 引用这张图），再用 `pinImage(blobID:scale:)` 钉到屏幕上。用户按 Esc 取消时 SDK 抛出 `action.cancelled`，插件捕获它（`catch let error as RuyioError where error.code == .cancelled`）并返回 `ActionResult(state: .cancelled)`，Ruyio 就不会把它当成失败提示。
- **截图到剪贴板**（`capture`）：用 `writeClipboard` 写入 `public.png`，表示里直接引用 `blobID`。
- **截图历史**（`opensView`）：`collection` 界面，带搜索、预览图（`.image`）、条目操作（钉住 ↩、复制 ⌘C、删除 ⌘⌫）和“清空历史…”确认框（`.confirm`）。
- 只保留最近 50 张：每次新增后把多余的旧文档批量删除，被删文档引用的图片会被自动清理。
