# 波点音乐 Bodian Music

> **⚠️ 重要声明：本项目仅供个人学习、研究和交流使用，严禁用于商业及非法用途。请在下载后 24 小时内删除。**

一款基于 Flutter 开发的 Android 音乐播放器。

## 项目简介

**波点音乐（Bodian Music）** 是一款采用 Flutter 框架开发的开源 Android 音乐播放器，旨在为开发者提供一个完整、可学习、可二次开发的移动音乐应用范例。

类似于 **洛雪音乐（LX Music / lx-music）**、**QQ音乐**、**网易云音乐** 等优秀产品，波点音乐在 **蓝牙/车机歌词同步**、**全屏 KTV 歌词**、**频谱可视化**、**NAS 音乐库** 等核心功能上做了完整的实现，适合作为 Flutter 实战项目的参考。

> 💡 **学习价值**：如果你正在学习 Flutter，本项目涵盖了音频播放、后台服务（audio_service）、蓝牙 AVRCP、JavaScript 引擎、自定义渲染、WebDAV 协议等众多实战技术点。

## 核心功能

### 🎵 播放相关
- 🎤 在线音乐搜索与试听
- 🎚️ 多音质切换（标准 / 高品 / 无损 / Hi-Res）
- 📃 用户自定义 API 脚本（JavaScript，支持扩展音源）
- 📁 本地音乐扫描与管理
- ☁️ **WebDAV NAS 音乐库**（支持群晖 Synology、威联通 QNAP、Nextcloud、Alist、Rclone 等）
- 🎚️ 均衡器调节

### 🎬 视觉与歌词
- 📝 同步滚动歌词（支持逐字 / 逐行两种模式）
- 🎤 **PV 全屏 KTV 歌词**（卡拉OK 动态扫字效果）
- 🌈 频谱可视化动画（8 种特效：柱状/波浪/圆环/脉冲/粒子/火焰/极光/水波）
- ✨ 沉浸式播放器 UI（新拟态风格）
- 🎨 多套主题色板（深色 / 浅色模式）

### 🚗 车载 / 蓝牙
- 📱 **蓝牙歌词同步**（AVRCP 协议，与 QQ音乐、洛雪音乐一致）
- 🎵 **灵动岛歌词显示**（Android Dynamic Island）
- 🔄 车机自动同步媒体控制

### 📚 其他
- ❤️ 收藏、历史、播放列表管理
- ⏰ 定时关闭
- 📊 排行榜浏览
- 🎛️ 搜索歌单导入

## 与同类项目的对比

| 功能 | 波点音乐 | 洛雪音乐 (LX) | QQ音乐 | 网易云音乐 |
| |---------|---------|---------|----------|
| Flutter 实现 | ✅ | ❌ (Electron) | ❌ (原生) | ❌ (原生) |
| 蓝牙歌词 | ✅ | ✅ | ✅ | ✅ |
| PV KTV 歌词 | ✅ | ❌ | ✅ | ✅ |
| WebDAV NAS | ✅ | ✅ | ❌ | ❌ |
| 用户自定义脚本 | ✅ | ✅ | ❌ | ❌ |
| 频谱可视化 | ✅ | ✅ | ✅ | ✅ |
| 开源可学习 | ✅ | ✅ | ❌ | ❌ |

## 适用人群

- 🎓 **Flutter 初学者 / 中级开发者**：本项目涵盖了完整的音频应用开发流程
- 🔧 **音频应用开发者**：蓝牙 AVRCP、后台播放、歌词同步等技术的完整实现
- 🎨 **UI 设计师**：新拟态风格、多种可视化特效的实现参考
- 📱 **移动开发者**：了解如何实现音乐类应用的核心功能

## 环境要求

- Flutter SDK >= 3.9.2
- Dart SDK >= 3.9.2
- Android SDK (API 36)
- Android 7.0+ (API 24+)

## 构建

```bash
# 1. 克隆项目
git clone https://github.com/guqlule/bodian-music.git
cd bodian-music

# 2. 安装依赖
flutter pub get

# 3. 构建 Debug APK
flutter build apk --debug

# 4. 构建 Release APK
flutter build apk --release

# 5. 指定架构构建（减小包体积）
flutter build apk --release --split-per-abi

# 6. 运行到连接的设备
flutter run
```

构建产物路径：`build/app/outputs/flutter-apk/`

| 架构 | 大小（约） |
|------|-----------|
| armeabi-v7a | 19.9 MB |
| arm64-v8a | 22.2 MB |
| x86_64 | 23.5 MB |
| 通用版 (含全部架构) | ~62 MB |

## 项目结构

```
lib/
├── core/                    # 核心工具
│   ├── theme/              # 主题配置、颜色、阴影
│   ├── router/             # GoRouter 路由管理
│   └── utils/              # 工具类（日志、存储）
├── models/                 # 数据模型 (MusicInfo, Playlist)
├── providers/              # 状态管理 (Riverpod)
├── screens/                # 页面
│   ├── home/              # 首页（播放器、抽屉菜单）
│   ├── player/            # 播放页
│   ├── search/            # 搜索
│   ├── local/             # 本地音乐
│   ├── webdav/            # WebDAV 音乐库
│   ├── playlist_detail/   # 歌单详情
│   ├── settings/          # 设置
│   ├── user_api/          # 用户脚本 API 编辑
│   └── about/             # 关于
├── services/                # 服务层
│   ├── api/               # API 接口、用户脚本引擎
│   ├── audio/             # 音频分析（频谱、FFT）
│   ├── player/            # 播放器 (just_audio + audio_service)
│   ├── lyric/             # 歌词解析（KRC、LRC）
│   ├── local/             # 本地音乐扫描
│   ├── webdav/            # WebDAV 服务
│   └── sync/              # 同步服务
└── widgets/                # 通用组件
    ├── audio_visualizer.dart   # 频谱可视化（8 种特效）
    ├── large_ktv_overlay.dart  # 全屏 KTV 歌词
    ├── mini_ktv_lyric_bar.dart # 迷你歌词条
    └── mini_player.dart        # 底部迷你播放器
```

## 技术栈

| 类别 | 技术 |
|------|------|
| **UI 框架** | Flutter 3.x |
| **状态管理** | Riverpod |
| **路由** | GoRouter |
| **音频播放** | just_audio + audio_service |
| **JavaScript 引擎** | flutter_js |
| **网络** | http / Cronet |
| **本地存储** | Hive |
| **WebDAV** | webdav_client |
| **频谱分析** | Android 原生 Visualizer API (FFT) |
| **后台服务** | MediaSession (AVRCP) |

## 关键技术实现

### 1. 蓝牙/车机歌词同步

参考 `androidx/media` Issue #430 的解决方案：
- 通过 `audio_service` 的 `mediaItem` 更新 `title` 字段
- 同时推 `playbackState`（position 微调）触发车机重新读取 metadata
- 仅在歌词行变化时推送（与 QQ音乐、洛雪音乐 一致的行为）

### 2. PV KTV 歌词扫字

使用自定义 `LerpScanText` 组件（见 `lib/widgets/large_ktv_overlay.dart`），逐字符 `Color.lerp` 实现无 ShaderMask / ClipRect 的扫字效果，零伪影。

### 3. 频谱可视化

通过 Android 原生 Visualizer API 直接抓取 FFT 数据，使用 Dart Canvas + 自定义 Painter 渲染8种特效。详细实现见 `lib/widgets/audio_visualizer.dart`。

### 4. WebDAV NAS 音乐库

支持标准的 WebDAV 协议，兼容主流 NAS 系统。可在设置中配置服务器地址、端口、用户名、密码、路径，支持测试连接、扫描远程目录、播放远程音频。

### 5. 用户自定义 API 脚本

使用 `flutter_js` 在 Dart 中嵌入 JavaScript 引擎，允许用户编写自定义脚本扩展音源。脚本可读取全局变量（如 `__lx_init_data__`、`__lx_request_queue__`）与原生层通信。

---

## ⚠️ 免责声明

**本项目仅供个人学习和研究使用，严禁用于商业及非法用途。**

1. 本项目**不提供任何音乐资源**，所有音乐内容均由用户自行导入或通过合法渠道获取。
2. 使用本项目时，您必须遵守所在国家/地区的相关法律法规。
3. 您必须通过合法渠道获取音乐资源，尊重音乐版权。
4. 本项目开发者不对因使用本项目而产生的任何直接或间接损失承担责任。
5. 本项目开发者保留随时删除本项目的权利，恕不另行通知。
6. 如有任何疑问或侵权问题，请联系删除。
7. 下载、安装或使用本项目，即表示您已阅读并同意上述声明。

**项目内涉及的"洛雪音乐""LX Music""QQ音乐""网易云音乐"等名称仅为功能对比说明，不代表本项目与上述产品有任何官方关联或合作关系。**

## 相关项目

如果你对本项目感兴趣，也可以看看以下优秀的开源音乐项目：

- [洛雪音乐 (lx-music-mobile)](https://github.com/lyswhut/lx-music-mobile) - 洛雪音乐移动版（Electron + Vue）
- [lx-music-source](https://github.com/lyswhut/lx-music-source) - 洛雪音乐音源脚本仓库
- [YesPlayMusic](https://github.com/qier222/YesPlayMusic) - 高颜值的第三方网易云播放器
- [BlackHole](https://github.com/Sangwan5688/BlackHole) - Flutter 实现的音乐播放器
- [SPlayer](https://github.com/jayjd/SPlayer) - Vue 实现的简约音乐播放器

## 开源许可

本项目采用 MIT 许可证。

```
MIT License

Copyright (c) 2026 guqlule

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

⭐ 如果这个项目对你有帮助，欢迎 Star！