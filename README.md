# 波点音乐

> **声明：本项目仅供个人学习和研究使用，严禁用于商业用途。请在下载后 24 小时内删除。**

## 关于项目

波点音乐是一款基于 Flutter 开发的 Android 音乐播放器应用，用于学习和研究 Flutter 移动应用开发技术。

本项目**不提供任何音乐资源**，所有音乐内容均来自用户自行导入或通过合法渠道获取。

## 功能特性

- 音乐在线搜索与播放
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

## 环境要求

- Flutter SDK >= 3.9.2
- Dart SDK >= 3.9.2
- Android SDK (API 36)

## 构建

```bash
# 安装依赖
flutter pub get

# 构建 Debug APK
flutter build apk --debug

# 构建 Release APK（需配置签名）
flutter build apk --release

# 指定架构构建
flutter build apk --release --target-platform android-arm64

# 运行
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

---

## 免责声明

**本项目仅供个人学习和研究使用，严禁用于商业及非法用途。**

1. 本项目不提供任何音乐资源，所有音乐内容均由用户自行导入或通过合法渠道获取。
2. 使用本项目时，您必须遵守所在国家/地区的相关法律法规。
3. 您必须通过合法渠道获取音乐资源，尊重音乐版权。
4. 本项目开发者不对因使用本项目而产生的任何直接或间接损失承担责任。
5. 本项目开发者保留随时删除本项目的权利，恕不另行通知。
6. 如有任何疑问或侵权问题，请联系删除。
7. 下载、安装或使用本项目，即表示您已阅读并同意上述声明。

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
