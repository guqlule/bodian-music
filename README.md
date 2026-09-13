# 波点音乐 (Bodian Music)

一款基于 Flutter 的 Android 音乐播放器，仿 lx-music-mobile 风格。

## 功能特性

- 音乐在线搜索、播放
- 歌词同步显示（逐字/逐行）
- PV 全屏歌词（KTV 动态效果）
- 频谱动画
- 蓝牙/车机歌词同步（AVRCP）
- 灵动岛歌词显示
- 多音质切换（标准/高/无损）
- 用户自定义 API 脚本（JavaScript）
- 深色模式
- 本地音乐扫描
- WebDAV NAS 音乐库（支持群晖、威联通、Nextcloud、Alist 等）
- 歌曲收藏/历史
- 播放列表管理
- 定时关闭

## 构建

### 环境要求
- Flutter SDK >= 3.9.2
- Dart SDK >= 3.9.2
- Android SDK (API 36)

### 安装依赖
```bash
flutter pub get
```

### 构建 APK
```bash
# Debug
flutter build apk --debug

# Release (需签名配置)
flutter build apk --release

# 指定架构
flutter build apk --release --target-platform android-arm64
```

### 运行
```bash
flutter run
```

## 项目结构

```
lib/
├── core/                    # 核心工具
│   ├── theme/              # 主题配置
│   ├── router/             # 路由管理
│   └── utils/              # 工具类
├── models/                 # 数据模型
├── providers/              # 状态管理 (Riverpod)
├── screens/                # 页面
│   ├── home/              # 首页
│   ├── player/            # 播放页
│   ├── setting/           # 设置
│   ├── local/             # 本地音乐
│   └── webdav/            # WebDAV 音乐库
├── services/               # 服务层
│   ├── api/               # API 接口
│   ├── player/            # 播放器
│   └── webdav/            # WebDAV 服务
└── widgets/                # 通用组件
```

## 技术栈

- **UI 框架**: Flutter
- **状态管理**: Riverpod
- **路由**: GoRouter
- **音频播放**: just_audio + audio_service
- **网络**: http / Cronet
- **数据库**: Hive
- **WebDAV**: webdav_client

## 致谢

- [lx-music-mobile](https://github.com/lyswhut/lx-music-mobile) - 原版参考
- [flutter_audio_service](https://github.com/ryanheise/audio_service) - 音频后台服务
- [just_audio](https://github.com/ryanheise/just_audio) - 音频播放引擎

## 许可证

MIT License
