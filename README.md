# Typer ⌨️

> 极简、原生的 macOS 拟真打字与自动化演示小工具。  
> 录课录屏、产品演示、现场汇报防翻车的效率神器。

[![macOS](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/qgpuerr/Typer?color=green)](https://github.com/qgpuerr/Typer/releases)

---

## ✨ 功能亮点

- ⚡️ **纯原生极速体验**：纯 Swift 6 + SwiftUI + AppKit 打造，零外部第三方依赖，安装包仅 **1MB** 出头，内存占用极小。
- 🔤 **多输入法方案支持**：默认支持标准**全拼输入法**，并全新支持**小鹤双拼**与**自然码/微软双拼**，一键切换，词卡与按键精准智能映射。
- 🎯 **拟真人手打字手感**：内置拼音/双拼输入过程引擎，支持打字速度调节、微小随机间隔与标点自然停顿，告别生硬机械的瞬间粘贴。
- 🖥️ **现代悬浮控制面板**：半透明毛玻璃质感，置顶浮动，随用随调。
- 📌 **常驻顶部菜单栏**：不占用 Dock 栏空间，点击右上角键盘图标随时展开/收起面板。
- ⌨️ **全局全局快捷键**：按下 <kbd>⌥ Option</kbd> + <kbd>T</kbd> 随时启动或暂停模拟打字。

---

## 🚀 快速开始

### 方式 1：直接下载安装（推荐）

1. 前往 [Releases 页面](https://github.com/qgpuerr/Typer/releases) 下载最新的 **`Typer.dmg`**。
2. 双击打开并将 **Typer** 拖入「应用程序（Applications）」文件夹。
3. 双击打开即可使用。

> **首次打开提示拦截？**
> 个人开源作品未购买苹果企业证书公证，若 macOS 提示「无法打开」或「来自未知开发者」：
> 打开 **「系统设置」→「隐私与安全性」**，滑到底部点击 **「仍要打开」** 即可。

### 方式 2：从源码本地构建

环境要求：macOS 13.0+，Xcode 15+ / Swift 6.0 工具链。

```bash
# 克隆仓库
git clone https://github.com/qgpuerr/Typer.git
cd Typer

# 一键编译并生成 .app 与 .dmg 安装包
./build_app.sh
```
执行完毕后，应用程序将自动安装至 `~/Applications/Typer.app`，并在桌面生成 `Typer.dmg` 安装包。

---

## ⚙️ 必要系统权限

为了能够向当前光标所在的输入框模拟真实键盘事件，`Typer` 需要授予 macOS **辅助功能权限（Accessibility）**：

1. 启动 `Typer`，系统将自动弹出权限申请。
2. 或手动打开 **「系统设置」→「隐私与安全性」→「辅助功能」**。
3. 将 **Typer** 右侧的开关开启即可。

---

## 🛠️ 技术架构

```text
Typer
├── Sources
│   ├── main.swift              # 程序主入口点 (NSApplication)
│   ├── AppDelegate.swift       # 菜单栏图标与悬浮窗生命周期管理
│   ├── ContentView.swift       # 核心交互控制面板 UI (SwiftUI)
│   ├── WordCardView.swift      # 词卡展示组件
│   ├── PinyinEngine.swift      # 拼音与文本输入解析引擎
│   ├── KeyDriver.swift         # 基于 CoreGraphics 的底层键盘模拟驱动
│   ├── HotKeyManager.swift     # 全局 Carbon 快捷键注册器
│   ├── PermissionManager.swift # 辅助功能权限检测与动态监听
│   ├── Models.swift            # 状态模型与数据管理
│   └── Theme.swift             # 设计系统与配色方案
├── build_app.sh                # 独立打包与图标生成脚本
└── Package.swift               # Swift Package 配置文件
```

---

## 📄 开源许可

本项目遵循 [MIT License](LICENSE) 开源许可。欢迎 Star、Issue 与 Pull Request！
