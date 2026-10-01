# 波点音乐 Bodian Music

> **重要声明：本项目仅供个人学习、研究和交流使用，严禁用于商业及非法用途。请在下载后 24 小时内删除。**

一款基于 Flutter 开发的 Android 音乐播放器。

<p align="center">
  <b>关键词</b>：Flutter 音乐播放器 · 洛雪音源脚本 · KRC 逐字歌词 · QRC 歌词 · 卡拉OK 扫字 · JIZURA 歌词特效 · 蓝牙 AVRCP 歌词 · Jovi InCar · HiCar 车机歌词 · MediaSession · WebDAV 音乐库 · 频谱可视化
</p>

## 项目简介

**波点音乐（Bodian Music）** 是一款采用 Flutter 框架开发的开源 Android 音乐播放器。

项目在三个方向上做了比较深的实现：

1. **歌词** —— 兼容洛雪支持的 KRC / QRC / ELRC 逐字歌词格式，并内置酷狗 KRC 跨源兜底：即使歌曲来自 QQ 音乐、网易云等只提供行级歌词的音源，也会**后台异步补取酷狗 KRC**，把整首歌升级为逐字，从而在全屏歌词页得到真正的卡拉OK 扫字。
2. **全屏特效歌词** —— 一屏一句巨幅歌词，围绕它做了 6 种版式 × 7 种入场 × 8 种文本特效 × 6 套配色 × 7 种句间转场的可自由组合系统。
3. **车机 / 蓝牙歌词** —— 通过 MediaSession 把歌词推给车机，含 Jovi InCar / HiCar 专用歌词协议。

**学习价值**：涵盖音频播放、后台服务（audio_service）、蓝牙 AVRCP、JavaScript 引擎、CustomPainter 自定义渲染、WebDAV 协议等实战技术点。

## 核心功能

### 播放相关

- 在线音乐搜索与试听
- 多音质切换（标准 / 高品 / 无损 / Hi-Res）
- **用户自定义 API 脚本**（JavaScript，可直接导入 `.js` 音源脚本，兼容洛雪音乐音源格式）
- 本地音乐扫描与管理
- **WebDAV NAS 音乐库**（群晖 Synology、威联通 QNAP、Nextcloud、Alist、Rclone 等）
- 均衡器调节
- 音源失败自动跨源兜底

### 歌词

- 同步滚动歌词，逐字 / 逐行自动识别
- **KRC 逐字歌词**（酷狗）：base64 解码 → 跳 4 字节 → 16 字节 XOR → zlib 解压 → 逐字时间轴解析
- **QRC 逐字歌词**（QQ）：作为备用解析路径接入
- **ELRC / LRC 行级歌词**（网易云等）
- **酷狗 KRC 跨源兜底** —— 本源只有行级歌词时，后台异步补取逐字版本再覆盖（先秒出行级歌词，不阻塞显示；切歌后自动丢弃过期结果，防串词）
- 翻译行支持

### 全屏特效歌词

点右上角 ✨ 打开特效面板，配置自动保存，重进页面恢复。

| 维度 | 可选 |
|------|------|
| **版式**（6） | 巨号铺满 / 居中 / 残像堆叠 / 跑马灯 / 满屏铺贴 / 竖排 |
| **入场**（7） | 弹跳 / 旋转 / 落下 / 打字 / 缩放 / 虚化 / 擦除 |
| **保持** | 抖动 |
| **出场**（5） | 无 / 缩小 / 炸裂 / 虚化 / 擦除 |
| **转场**（7） | 沿用入场出场 / 熄灯 / 闪白 / 拉焦 / 推移 / 溶入 / 擦除 |
| **文本特效**（8） | 素色 / 描边 / 粗描边 / 辉光 / 霓虹 / 渐变 / 重色差 / 高亮 |
| **配色**（6） | 夜黑 / 绯红 / 薄荷 / 警示 / HUD / 蓝图 |

- **扫字高亮** —— 播放头左侧转强调色、右侧压暗，中间一段按字号缩放的软边
- **镜头追踪（Z 轴穿越）** —— 当前句从纵深逼近焦点再掠过镜头，上一句上浮消失、下一句从深处浮现
- **随机特效** —— 从 8 套手工调校的成套方案里逐句抽取，自动避开与上一句重复
- **动效强度** 滑杆（0~150%）

### 车载 / 蓝牙

- **蓝牙歌词同步**（AVRCP，经 MediaSession 推送歌词到车机 / 蓝牙耳机）
- **Jovi InCar / HiCar 歌词协议** —— 除播放卡片外，写入车机歌词专用 metadata 与 session extras
- **灵动岛歌词显示**（Android Dynamic Island / 通知栏歌词）
- **车机模式手动开关** —— 设置 → 播放 → 车机模式：自动 / 强制车机 / 强制蓝牙
- 播放队列同步（仅推当前歌曲，不塞整个播放列表，避免车机卡顿）

### 视觉

- 频谱可视化动画（8 种特效：频谱 / 地形 / 脉冲 / 雷达 / 镜像 / 线条 / 粒子 / 螺旋）
- 沉浸式播放器 UI（新拟态风格）
- 多套主题色板（深色 / 浅色）

### 其他

- 收藏、历史、播放列表管理
- 定时关闭
- 排行榜浏览
- 搜索歌单导入

## 适用人群

- **Flutter 初学者 / 中级开发者** —— 完整的音频应用开发流程
- **音频应用开发者** —— 蓝牙 AVRCP、后台播放、车机歌词同步
- **对歌词渲染感兴趣的开发者** —— KRC/QRC 解密解析、卡拉OK 扫字、Z 轴景深转场、自定义 Painter 动效
- **UI 设计师** —— 歌词动效与可视化特效的实现参考

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

# 5. 按架构分包（显著减小单包体积）
flutter build apk --release --split-per-abi

# 6. 运行到连接的设备
flutter run
```

构建产物路径：`build/app/outputs/flutter-apk/`

通用版 APK 约 63 MB；使用 `--split-per-abi` 分包后单个架构的包体可明显减小。

## 项目结构

```
lib/
├── core/                       # 核心工具
│   ├── theme/                  # 主题配置、颜色、阴影
│   ├── router/                 # GoRouter 路由管理
│   └── utils/                  # 工具类（日志、存储）
├── models/                     # 数据模型 (MusicInfo, Playlist)
├── providers/                  # 状态管理 (Riverpod)
├── screens/
│   ├── home/                   # 首页（播放器、抽屉菜单）
│   ├── player/                 # 播放页
│   ├── search/                 # 搜索
│   ├── local/                  # 本地音乐
│   ├── webdav/                 # WebDAV 音乐库
│   ├── playlist_detail/        # 歌单详情
│   ├── settings/               # 设置
│   ├── user_api/               # 用户脚本 API 编辑
│   ├── about/                  # 关于
│   └── pv_lyrics/              # 全屏特效歌词
│       ├── pv_lyrics_screen.dart      # 页面容器 + 随机方案调度
│       ├── lyric_effect_config.dart   # 特效枚举 / 成套方案 / 持久化 / 特效面板
│       └── jizura_lyrics_view.dart    # 自定义 Painter 动效渲染
├── services/
│   ├── api/                    # API 接口、用户脚本引擎、歌词获取
│   ├── audio/                  # 音频分析（频谱、FFT）
│   ├── player/                 # 播放器 (just_audio + audio_service)
│   ├── lyric/                  # 歌词解析
│   │   ├── lyric_parser.dart         # LRC / ELRC 逐字时间轴
│   │   ├── krc_decoder.dart          # 酷狗 KRC 解密
│   │   ├── krc_parser.dart           # 酷狗逐字解析
│   │   ├── qrc_parser.dart           # QQ QRC 解析
│   │   └── car_lyric_formatter.dart  # 车机全文歌词清洗
│   ├── local/                  # 本地音乐扫描
│   ├── webdav/                 # WebDAV 服务
│   └── sync/                   # 同步服务
└── widgets/
    ├── audio_visualizer.dart        # 频谱可视化（8 种特效）
    ├── large_ktv_overlay.dart       # 大屏 KTV 歌词 overlay
    ├── mini_ktv_lyric_bar.dart      # 迷你歌词条
    └── mini_player.dart             # 底部迷你播放器

android/app/src/main/kotlin/.../
├── MediaSessionHelper.kt            # MediaSession、车机歌词 metadata
└── CarModeDetector.kt               # 车机模式检测
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
| **本地存储** | Hive + SharedPreferences |
| **WebDAV** | webdav_client |
| **歌词渲染** | CustomPainter + Canvas Shader |
| **频谱分析** | Android 原生 Visualizer API (FFT) |
| **后台服务** | MediaSession (AVRCP) |

## 关键技术实现

### 1. 逐字歌词与跨源兜底

网易云、QQ、酷我的公开歌词接口只返回**行级**歌词（`[mm:ss]text`），没有字级时间戳，因此无法做卡拉OK 扫字。

- **KRC 解密**：酷狗 KRC 为 `base64 → 跳 4 字节 → 16 字节 XOR → zlib`。XOR 密钥为固定常量，解密后 zlib 头为 `78 9c`。
- **跨源兜底**：本源只有行级歌词时，先立即显示行级版本，再在后台检索酷狗按「歌名 + 歌手」匹配（校验歌手，避免同名歌拿错词），拿到真逐字才覆盖。**不在主流程同步等待** —— 酷狗搜索+下载需 1~3 秒，串行等待会让本来秒出的歌词卡住。
- 逐字判定同时识别两种标记：ELRC 的 `<mm:ss.xxx>` 与 KRC/QRC 的 `<offset,dur>`。

### 2. 全屏特效歌词的扫字渲染

扫字不是逐字 `Color.lerp` —— 那样软边只能落在单个字内部，字与字之间仍是硬边，看起来像色块跳变而非光扫过。

实现方式是**整句一遍绘制 + 横向渐变**：

```
stops  = [0, (maskX - edge)/W, (maskX + edge)/W, 1]
colors = [bright, bright, dim, dim]
```

播放头位置优先用逐字时间戳算出（`已完成字累计宽度 + 当前字内进度 × 当前字宽`），无逐字数据时退化为行级进度。软边宽度取 `clamp(字号 × 0.42, 8, 16)` —— 大字号有足够过渡，小字号又不会糊成一片。

### 3. 句间转场

转场的核心约定是**出场与进场走同一条流向向量**，使跨越交接点的屏幕运动方向始终不变，读起来是一段连续的移动，而不是「退回去再推进去」。

另外两条硬约束：

- **不许空屏** —— 交接时两句同场（旧句定格在出场末态、新句定格在进场初态），淡出留 alpha 地板
- **一个转场只做一件事** —— 熄灯/闪白只动透明度，拉焦只动模糊，推移/擦除只动位移，溶入只动缩放

镜头追踪（Z 轴穿越）用 `w = 1/(1+z)` 作为透视因子：远处缩小并向消失点收拢，越过镜头则放大冲出画面，缩放与纵向偏移共用同一个 `w`。

### 4. 渲染性能

歌词页每帧重绘，交接时最多同场 3 句，每句需逐字排版。已做的优化：

- **版式排版跨帧缓存** —— 排版是纯函数（只依赖文本 / 版式 / 尺寸），缓存后命中率接近 100%
- **扫字一遍绘制** —— 渐变右端直接用未唱暗色，省掉参考实现里必须的「暗底 + 遮罩亮层」两遍结构
- **装饰性重影按行排版** —— 色差重影、残像不参与逐字抖动，N 次排版降到「行数次」
- **背景墙录成 `Picture`** —— 静态内容录一次，之后每帧一次 `drawPicture`
- **邻句降级为单层** —— 交接窗口里的邻句跳过扫字亮层、色差重影、背景墙、翻译行

综合下来，默认配置单句每帧排版次数从约 `5N + 22` 降至约 `2N + 4`。

### 5. 蓝牙 / 车机歌词同步

- **灵动岛 / 通知栏**：`mediaItem.add()` 更新 audio_service 内部 metadata
- **车机蓝牙**：MethodChannel 直接写 `MediaSessionCompat.setMetadata()`，走 AVRCP
- 定时广播 `playbackState`（每 500ms），触发车机重新读取 metadata
- 仅在歌词行变化时推送，避免高频更新
- 播放队列只推当前歌曲（早期版本推整个播放列表，实测导致系统队列约 600 项、车机响应异常）

### 6. Jovi InCar / HiCar 车机集成

除常规播放卡片外，写入车机歌词专用通道：

| Key | 值 |
|-----|-----|
| `ucar.media.metadata.LYRICS_WHOLE` | 整首歌词全文 LRC |
| `ucar.media.metadata.LYRICS_STATUS` | `0L`（必须与全文成对下发） |
| `vivomusicmix.media.metadata.support_event` | `31L` |

并在 session extras 中写入 `action = vivomusicmix.extra.lrc_change`、媒体 id 与歌词正文。

> 下发全文前会先剥除 ELRC 的字级 `<mm:ss.xxx>` 标签并按时间戳去重，避免车机解析异常。

### 7. 频谱可视化

通过 Android 原生 Visualizer API 直接抓取 FFT 数据，使用 Dart Canvas + 自定义 Painter 渲染 8 种特效。

### 8. WebDAV NAS 音乐库

支持标准 WebDAV 协议，兼容主流 NAS 系统。可配置服务器地址、端口、用户名、密码、路径，支持测试连接、扫描远程目录、播放远程音频。

### 9. 用户自定义 API 脚本

使用 `flutter_js` 在 Dart 中嵌入 JavaScript 引擎，允许用户编写脚本扩展音源。支持直接导入 `.js` 音源脚本文件，兼容洛雪音乐音源格式，无需手动适配即可使用社区共享的音源。

---

## 免责声明

**本项目仅供个人学习和研究使用，严禁用于商业及非法用途。**

1. 本项目**不提供任何音乐资源**，所有音乐内容均由用户自行导入或通过合法渠道获取。
2. 使用本项目时，您必须遵守所在国家/地区的相关法律法规。
3. 您必须通过合法渠道获取音乐资源，尊重音乐版权。
4. 本项目与洛雪音乐（及其任何衍生版本）无隶属关系，仅在音源脚本格式与歌词文件格式上保持兼容。
5. 本项目开发者不对因使用本项目而产生的任何直接或间接损失承担责任。
6. 本项目开发者保留随时删除本项目的权利，恕不另行通知。
7. 如有任何疑问或侵权问题，请联系删除。
8. 下载、安装或使用本项目，即表示您已阅读并同意上述声明。

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

如果这个项目对你有帮助，欢迎 Star！