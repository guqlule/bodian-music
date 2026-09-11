# 波点音乐

一款基于 Flutter 的 Android 音乐播放器，仿 lx-music-mobile 风格。支持手机使用，也可通过 joviincar 投屏到车机使用。

## 功能特性

- 多源音乐搜索与播放
- 用户自定义 API（JS 脚本扩展音源）
- 逐字歌词 + KTV 扫字特效
- 全屏 PV 歌词（流星极光背景）
- 音频频谱可视化
- 本地音乐扫描播放
- 歌单管理（收藏、历史、下载）
- 均衡器调节
- 睡眠定时
- 蓝牙歌词显示
- 隐私政策页面

## 车机使用

支持通过 **joviincar** 投屏到车机，手机端播放音乐，车机端同步显示歌词和操控。

## 项目结构

```
├── android/          # Android 原生代码
├── assets/           # 资源文件
├── lib/              # Flutter 源码
│   ├── core/         # 主题、路由、存储
│   ├── models/       # 数据模型
│   ├── providers/    # 状态管理（Riverpod）
│   ├── screens/      # 页面
│   ├── services/     # 服务层（API、播放器、下载）
│   └── widgets/      # 通用组件
├── test/             # 单元测试
├── pubspec.yaml      # 依赖配置
└── analysis_options.yaml
```

## 环境要求

- Flutter 3.35+
- Dart SDK ^3.9.2
- Android SDK 21+
- Android Studio / VS Code

## 构建

```bash
# 获取依赖
flutter pub get

# 调试运行
flutter run

# 构建 Release APK
flutter build apk --release --split-per-abi
```

## 下载安装

前往 [Releases](https://github.com/guqlule/bodian-music/releases) 下载最新 APK：

| 架构 | 说明 |
|------|------|
| armeabi-v7a | 大部分手机 |
| arm64-v8a | 新款手机（推荐） |
| x86_64 | 模拟器/平板 |

## 主要依赖

| 包名 | 用途 |
|------|------|
| just_audio | 音频播放 |
| audio_session | 音频会话管理 |
| flutter_riverpod | 状态管理 |
| flutter_js | JS 脚本运行时（用户 API） |
| cached_network_image | 网络图片缓存 |
| shared_preferences | 本地存储 |
| sqflite | 数据库 |
| permission_handler | 权限管理 |
| lottie | 动画 |
| shimmer | 加载效果 |

## 音源说明

支持两种音源模式：

1. **内置 API** — 默认提供基础音源
2. **用户自定义 API** — 通过导入 JS 脚本扩展音源，兼容 lx-music 格式

## 注意事项

- 仅供学习交流使用
- 请支持正版音乐
- 网络请求可能受服务器限制
