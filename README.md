# Ruyio Plugins

A plugin market for [Ruyio](https://github.com/h025/Ruyio). In Ruyio, open **Plugin Market → +** and add:

```
https://github.com/h025/ruyio-market
```

由 h025 维护的 Ruyio 插件市场。在 Ruyio 的“插件市场”里点“+”，添加上面的地址即可浏览和安装。

> The plugins are signed with the publisher's self-signed certificate instead of being notarized by Apple.
> Ruyio 0.0.1 and later installs them as ordinary plugins, no developer mode needed. 插件用发布者的自签名证书
> 签名，未经 Apple 公证；Ruyio 0.0.1 起无需开发者模式即可安装。

## Plugins

| Plugin | What it does | Permissions |
|---|---|---|
| [Screenshot / 截图](plugins/screenshot) | Select part of the screen with the system screenshot UI, copy it, or pin it above other windows; keeps the last 50 captures. 框选截图，复制或钉在屏幕最上层，保留最近 50 张。 | `screen.capture`, `windows.pin`, `clipboard.write` |

Screenshot shortcuts (change them in Ruyio → Shortcuts): **⌃⇧A** capture to clipboard, **⌃⇧P** capture and
pin. On a pinned image: drag to move, scroll or pinch to zoom, hover and click the close button to close it,
right-click for copy / save / zoom / opacity / close all. **Esc** does not close a pin. 钉图可拖动、滚动或捏合缩放，
悬停显示关闭按钮，右键可复制、存储、调整透明度；按 Esc 不会关闭。The first capture asks to allow **Ruyio Capture Helper** under Screen & System Audio Recording;
neither Ruyio itself nor any plugin receives that permission.

## Writing a plugin / 编写插件

See **[WRITING_PLUGINS.md](WRITING_PLUGINS.md)** (中文): how a Ruyio plugin works, the manifest, the SDK, and
how to add, build and publish a plugin in this repository. The full reference is in the
[Ruyio Wiki](https://github.com/h025/Ruyio/wiki).

## Layout

| Path | Contents |
|---|---|
| `ruyio-market.json` | Market index |
| `plugins/<name>/ruyio-plugin.json` | Plugin descriptor: releases with SHA-256 |
| `plugins/<name>/releases/<version>/` | Published packages (never changed once pushed) |
| `plugins/<name>/Plugin/` | Plugin source, manifest and XcodeGen project |

## Building a release

Requires Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and a Ruyio checkout next to this repository
(or `RUYIO_ROOT=/path/to/Ruyio`) for the plugin SDK:

```sh
Scripts/build-plugin.sh screenshot
```

It builds the plugin, signs it with the publisher certificate (a self-signed one, created on first use in
`~/Library/Keychains/ruyio-plugin-publisher.keychain-db`; back it up, updates need the same certificate),
packages `releases/<version>/<Name>.ruyioplugin.zip` and records the release and its SHA-256 in
`ruyio-plugin.json`. Bump `version` in the plugin's `manifest.json` for every published change.

## License

MIT. See [LICENSE](LICENSE).
