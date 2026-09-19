# 同步讲记（Flutter Android MVP · 1.2.0）

一款面向课堂、专题讲座和实地参观的本地优先多模态记录工具。持续录音时可以低干扰拍照、标重点、记录疑问和切换章节；结束后，照片与标记会按可播放音频时间轴对齐。

## 当前实现

### 2026-09 可靠性更新

- 本地 ASR 在独立 Dart isolate 中运行，录音 PCM 先写文件，再异步交给字幕线程；模型异常不再阻止开始录音。
- 字幕队列限制为 8 秒音频，单条消息确认后才发送下一条；积压或解码超时会停用本地字幕并提示，不丢弃原始音频。
- 字幕使用 PCM 采样位置标记起止时间，暂停时通过 FIFO 屏障收尾，避免异步结果错配恢复后的时间。
- 结束时先完成音频分片落盘，再限时收尾字幕。恢复清单串行原子替换，避免并发覆盖及先删除旧清单造成的空窗。
- 注意：isolate 隔离计算阻塞和 Dart 异常，不隔离进程级 native crash；仍需真机长录音验收。

### 基础功能

- 现场相机支持最高分辨率请求、连续拍摄、点按对焦与双指/滑杆缩放；照片先保存再确认，备注可在回顾页补写，不再每张强制弹框。Android 缩略图用原生后台降采样并校正 EXIF 方向，其他平台使用独立 isolate。
- Android 新增“PPT / 文档扫描”，通过 ML Kit 扫描界面直接拍照、裁边及矫正透视，结果自动回到当前记录。一次扫描一页；取消或扫描不可用不改变录音状态。
- 扫描返回结果先写入应用私有目录和恢复日志；Activity 重建后可在再次进入对应现场页时导入，使用固定事件 ID 避免重复节点。
- 扫描边界：依赖 Google Play 服务，首次使用可能联网下载组件；SDK 仅返回处理图、不返回未裁剪原图或精确快门时间。节点明确标为扫描入口时间，并保留设备时间范围供校准。需要原图和精确同步请选普通相机。

- 默认使用随包中英双语 INT8 模型，设置 → 实时字幕中可切回轻量中文；两种模式均在手机运行，无需 API 密钥、Mac 或联网下载模型。
- 支持最多 80 个会议术语、人名和英文缩写热词；使用匹配模型的 CJK/BPE 分词和 beam search，不是对结果强制替换。设置在下次录音生效。
- 设置页提供离线模型自检，使用内置公开测试音频，不启用麦克风、不上传；录音期间禁止自检以避免争用资源。
- 模型缓存使用独立版本目录和 SHA-256 校验，损坏后从安装包修复；模型包来源、校验清单和许可随仓库提供。

- 原创的安静、专业视觉系统，统一颜色、字号、间距、圆角与状态组件，跟随系统深色/浅色模式；
- “记录 / 搜索 / 资料包 / 设置”四入口信息架构；首页包含欢迎信息、正在录音、异常恢复、场景筛选、代表照片与字幕/导出状态；
- 创建记录：标题可空并自动命名，支持课堂、讲座、实地参观、会议、访谈和其他场景，以及活动名称、地点和简介；
- 应用内全文搜索标题、场景、地点、简介、标签、字幕、章节、重点、疑问和图片说明，并可筛选场景、照片、重点和疑问；
- Android 麦克风前台服务、持久通知、CPU wake lock；
- 单一麦克风 PCM 流同时写入 16 kHz/16-bit/mono WAV 分片并送入本地 ASR，避免录音与字幕争抢麦克风；
- 使用 `sherpa_onnx` 和随包中文 / 中英双语流式模型实时显示离线字幕初稿，不需要网络或 API 密钥；
- 可选接入腾讯云实时 ASR 大模型 2.0：PCM 按40ms帧发送，显示云端中间结果，稳定句带起止时间并替换重叠的本地初稿；
- 云端连接失败时录音不停止，自动切换本地字幕并按2～30秒退避重连；暂停/继续会正常结束并重建云端会话；
- 设置页只保存安全代理地址和代理令牌；腾讯云 AppID、SecretID、SecretKey 只存在于独立代理服务；
- 服务 isolate 约每 5 分钟安全结束并创建新 WAV 分片，文件头每秒同步，异常退出后可恢复已落盘内容；
- 暂停/继续不把暂停时长计入可播放时间轴，同时保留每个节点的设备实际时间，并把暂停、继续和中断状态写入时间轴；
- Android `SystemClock.elapsedRealtime()` 单调时钟通道，锁屏和修改系统时间不影响 offset；
- 现场“照片”入口可选择 App 内 CameraX 相机拍照或从系统相册导入，期间录音服务独立继续；
- Android 13+ 相册导入使用系统 Photo Picker，不申请广泛存储权限；Activity 被回收时可恢复待处理照片及原 offset；
- 原始照片和 480px 缩略图写入应用私有持久目录；
- 重点、疑问、章节、照片和中断事件时间轴；
- 现场页新增独立备注、大点击区域、轻震动反馈、最近事件预览和非阻塞字幕状态；返回首页不会停止录音；
- 内置相机支持闪光灯、前后镜头切换和点按对焦，并在权限申请前解释用途；
- 多分片连续播放、±10 秒、拖动、点击事件 seek、附近节点高亮；
- 记录详情使用“回顾 / 字幕 / 时间轴 / 资料包”四个内容 Tab；支持 0.75–2.0 倍速、字幕编辑、照片时间点调整、照片大图和节点编辑删除；
- 可编辑记录标题、场景、地点、简介和标签；可明确确认后删除整条记录及本地媒体；
- 异常恢复卡片可查看已保存音频/照片，并从既有连续时间和下一个 WAV 分片继续录制；
- SQLite 四表、外键、索引和 Repository 层；schema v2 新增活动、标签和照片来源，v3 新增导出历史字段，自动迁移并保留旧记录；
- App 启动时恢复未完成记录：同步服务清单、字幕和时间节点，并尝试读取未登记 WAV/旧版 m4a 分片时长；
- `AiProcessingService` 接口、完整 AI 输入结构、离线 `MockAiProcessingService`；
- 记录整理稿明确标注“老师明确讲过 / 照片直接可见 / AI推测 / 需要核实”；
- 整理稿按时间合并转写、照片、章节、重点、疑问和备注，照片插入邻近讲解位置；
- “整理与导出”页面渲染 Markdown 与本地图片，支持复制全文、分享 Markdown；
- 不在手机端生成最终结论；按课堂、讲座、实地参观或自定义场景生成可直接交给 Codex 的整理提示词；
- 导出 Codex 图文 ZIP：包含 `CODEX_PROMPT.md`、`note.md`、schema v3 `manifest.json`、`audio/segment_XXXX.wav` 原始音频分片和按稳定相对路径整理的 `images/photo_NNN.ext` 原图；manifest 记录 Session、音频分片元数据、字幕、双时间轴事件、图片来源和导出元数据；
- Android 与 iOS 工程骨架；MVP 的后台可靠性实现优先针对 Android。

## 未实现 / 已知限制

- 已有内置中英双语/轻量中文两套本地模型及热词配置，但字幕仍是初稿；远场、噪声、口音、英文缩写和专业词仍可能错漏，原始音频是最终依据；
- 腾讯云接入代码已完成，但仓库不含用户的腾讯云凭证和已部署域名；未配置代理时会保持纯离线模式，真实云端效果和账单需在用户账号下验收；
- 没有真实 OCR、录后校正模型或云端多模态模型；Mock 不读取 API 密钥，也不把演示文字冒充真实内容；
- 没有账号、云同步、多人协作、视频、音频剪辑、PDF/Word 导出；
- Android 用户在系统设置中“强行停止”App 后，系统不允许服务继续或自行重启；这是平台限制；
- 电话或其他 App 抢占麦克风时，`record` 的状态回调会写中断节点。不同厂商对音频焦点的行为不同，必须真机验证；
- 5 分钟分片依赖前台任务的周期回调，受严重厂商节电限制时切分点可能延后，但正在写入的文件不是内存缓冲；
- 当前播放器以分片实际/清单时长映射。长时间真机测试后应进一步用媒体容器时长校准服务时钟；
- PCM WAV 约占 115 MB/小时；换取了单路采集、可恢复文件头和本地流式识别，长期使用前需要增加存储空间预警和结束后归档压缩；
- `flutter_foreground_task` 10.0.0 仍会应用旧式 Kotlin Gradle Plugin；当前 Flutter 3.44.8 可成功构建，但 Flutter 已提示未来版本需升级插件的 Built-in Kotlin 支持；
- iOS 已配置相机、麦克风说明和 `audio` background mode，但尚未进行 Xcode 真机签名与后台策略验证；
- 图文 ZIP 已包含原始 WAV 分片；如果录音分片缺失，manifest 会将 `audioComplete` 标记为 `false`。私有媒体会在卸载 App 时被 Android 删除，重要录音仍需及时导出备份。

## 技术结构

Android 缩略图采用原生后台降采样与 EXIF 方向修正，不改写原图；原生单元测试可在
`android/` 目录执行 `./gradlew :app:testDebugUnitTest -Ptarget-platform=android-arm64`。
真机问题与复测情况见 [2026-09 优化记录](docs/optimization-2026-09.md)。

```text
lib/
  core/       单调时钟、暂停映射、分片 seek 映射、主题和通用状态组件
  data/       SQLite schema 与 AppRepository
  models/     Session、AudioSegment、TimelineEvent、TranscriptSegment
  services/   前台 PCM/WAV、离线/腾讯云 ASR、恢复、媒体/ZIP、连续播放器、Mock AI
  screens/    首页导航、搜索、导出中心、设置、创建、现场、内置相机、详情和整理包
  widgets/    记录卡片、快捷操作、时间轴和输入组件
test/
  data/       数据库与重启持久化
  services/   offset、暂停、分片、seek、Mock AI
  widgets/    首页导航、创建流程、详情 Tab、录音快捷操作与输入弹窗
server/
  tencent_asr_proxy/  腾讯签名、凭证隔离和 WebSocket 中继服务
```

媒体目录为 `ApplicationSupport/sessions/<sessionId>/`，包含 `audio/`、`photos/`、`thumbnails/`、`exports/`、`recording_manifest.json` 和 `ai_note.md`。结构化数据存入 `sync_notes.sqlite`。每个事件同时保留 `offsetMs` 和设备实际时间 `createdAt/deviceTime`；前者用于播放跳转，后者用于区分暂停间隔。UI 不直接访问 SQLite，数据读写经过 `AppRepository`，媒体删除与导出经过 `MediaStorage`。

## 数据库迁移

1.1 将数据库从 v1 依次升级至 v3。v2 仅添加活动名称、标签和照片来源；v3 仅添加上次导出时间、路径和大小。迁移均使用 `ALTER TABLE ... ADD COLUMN`，原有 Session、AudioSegment、TimelineEvent 与 TranscriptSegment 的主键、外键和媒体路径不改变。迁移测试会先创建真实 v1 表并写入旧记录，再用当前代码升级和读回。

## 关键依赖

- Flutter 3.44.8 / Dart 3.12.2；
- `camera` 0.12.0+2（Flutter 官方，Android 使用 CameraX）；
- Android 原生 `play-services-mlkit-document-scanner` 16.0.0（通过 Kotlin MethodChannel，首次组件下载可能需要联网）；
- `image_picker` 1.2.3（Flutter 官方，仅用于系统相册/Photo Picker）；
- `record` 7.1.1；
- `flutter_foreground_task` 10.0.0；
- `just_audio` 0.10.6；
- `sqflite` 2.4.3；
- `permission_handler` 12.0.3、`path_provider` 2.1.6、`image` 4.9.1、`share_plus` 13.3.0；
- `sherpa_onnx` 1.13.8（本地流式 ASR，固定版本以便复现）；
- `shared_preferences` 2.5.5（非敏感的云转写开关、代理地址和代理令牌）；
- `flutter_markdown_plus` 1.0.12、`archive` 4.0.9（图文渲染与 ZIP）。

依赖选择与 Android 配置参考了当前的 [Flutter 相机文档](https://docs.flutter.dev/cookbook/plugins/picture-using-camera)、[Android 麦克风前台服务类型](https://developer.android.com/about/versions/14/changes/fgs-types-required#microphone)、[Android 音频输入共享限制](https://developer.android.com/media/platform/sharing-audio-input?hl=zh-CN)、[SpeechRecognizer 连续识别限制](https://developer.android.com/reference/android/speech/SpeechRecognizer.html)、[后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)、[应用私有存储](https://developer.android.com/training/data-storage/app-specific) 与 [sherpa-onnx 流式模型文档](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html)。

## 权限

Android 声明：`CAMERA`、`RECORD_AUDIO`、`POST_NOTIFICATIONS`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MICROPHONE`、`WAKE_LOCK`、`INTERNET`。相册通过系统 Photo Picker 选择，不申请存储广泛访问权限；导入后照片和录音只进入应用私有目录。

Android 14+ 必须在 App 可见时启动 microphone 前台服务。本项目只从“开始记录”按钮启动服务，不能从后台静默启动。

## 本地运行

本机安装的 Flutter 位于：

```bash
export PATH="/Users/a1-6/.local/share/flutter/bin:$PATH"
cd "/Users/a1-6/Documents/产品设计/sync_notes"
flutter pub get
flutter run
```

若系统设置了代理，需要让 Flutter 测试访问本机回环端口：

```bash
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1
```

连接 Android 真机后：

```bash
adb devices
flutter run -d <device-id>
```

## 检查与测试

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

本环境的 Flutter 3.44.8 分析器在包含中文的绝对路径上偶发 LSP JSON 截断；可复制到 ASCII 临时目录检查，不改动源码：

```bash
tmp_dir=$(mktemp -d /tmp/sync_notes_check.XXXXXX)
cp -R . "$tmp_dir/project"
(cd "$tmp_dir/project" && flutter analyze)
```

构建 APK：

```bash
flutter build apk --debug
# 输出：build/app/outputs/flutter-apk/app-debug.apk
```

Debug APK 会包含离线模型、三种 Android ABI 和调试符号，体积较大。发布/试装优先使用 arm64 拆分包：

```bash
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

发布前必须配置自己的 applicationId、release keystore 和隐私政策，不能使用当前 debug 签名。

## 腾讯云实时转写

移动端不能保存腾讯云长期密钥。本项目提供可运行的安全代理，部署说明见 [`server/tencent_asr_proxy/README.md`](server/tencent_asr_proxy/README.md)。代理固定使用腾讯云实时 ASR V2 的 `16k_zh_en_2.0` 引擎。

```bash
cd server/tencent_asr_proxy
dart pub get
export TENCENT_APP_ID="..."
export TENCENT_SECRET_ID="..."
export TENCENT_SECRET_KEY="..."
export PROXY_AUTH_TOKEN="$(openssl rand -hex 32)"
dart run bin/server.dart
```

生产环境通过 HTTPS 反向代理暴露：

```text
wss://你的域名/v1/asr/tencent/realtime
```

随后进入 App 底部“设置”→“实时转写”，打开腾讯云转写并填写 WSS 地址与 `PROXY_AUTH_TOKEN`。不要把腾讯云密钥填写到 App。协议选择参考腾讯云当前的[实时语音识别 V2 WebSocket 文档](https://cloud.tencent.com/document/product/1093/131127)。

### 构建“安装后即用”的 APK

公网代理部署完成后，复制配置模板（真实文件已被 Git 忽略）：

```bash
cp deploy/app_config.example.json deploy/app_config.json
```

将 `deploy/app_config.json` 中的地址换成公网 `wss://` 地址，令牌填写代理服务的 `PROXY_AUTH_TOKEN`，然后构建：

```bash
flutter build apk --release --split-per-abi \
  --dart-define-from-file=deploy/app_config.json
```

新设备安装 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 后，默认开启腾讯云实时转写，不需要 Mac、ADB 或手工填写配置。运行时仍需要可访问腾讯云的网络。

APK 中的代理访问令牌可被高级用户提取，因此它必须是可撤销、可轮换的服务令牌，代理端应限流和监控用量。腾讯云 `SecretKey` 仍只能留在服务器。

## AI 服务替换

`AiProcessingService.process(AiProcessingInput)` 已提供边界。输入包含带起止时间的转写、照片文件与 offset、OCR 字段、照片前后约 45 秒转写、章节/重点/疑问/备注。真实密钥不得放入 Flutter 客户端，推荐由后端持有。

`.env.example` 仅作配置说明，`.env`、keystore 和 `key.properties` 已加入 `.gitignore`。Flutter App 不加载云厂商密钥；代理通过服务端环境变量读取腾讯凭证。

## 真机验收清单

每次测试前确认授权提示、前台通知和剩余存储空间，测试后在回顾页抽查照片节点与讲解位置，目标误差 ≤2 秒。

- [ ] 连续录音 60 分钟：产生约 12 个分片，列表与播放器显示为连续音频；
- [ ] 锁屏 15 分钟：通知持续存在，解锁后 offset 连续，音频无明显缺口；
- [ ] 录音中拍摄 20 张以上照片：相机预览时通知仍在，逐张抽查时间点；
- [ ] 来电/语音 App 抢占麦克风：出现明确中断节点和提示，返回后可继续；
- [ ] 飞行模式：创建、录音、实时字幕、拍照、标记、结束、回放、Mock AI 和图文 ZIP 导出均可用；
- [ ] 近场普通话、远场课堂、多人和噪声环境分别抽查实时字幕；字幕错误不得影响 WAV 原始录音；
- [ ] 腾讯云代理启用：现场页状态显示“腾讯云”，稳定句写入 SQLite，并替换同时间范围的“本地初稿”；
- [ ] 录音中断开网络再恢复：状态切换“本地兜底”后自动重连，WAV 与时间轴连续且不会出现重复云端句；
- [ ] 从最近任务划掉 App：服务与通知按厂商策略继续；重新打开可回到进行中记录；
- [ ] 在调试场景强制终止进程后重开：未完成 Session 被标为中断，已落盘分片和节点可回放；
- [ ] 手动暂停 2 分钟再继续：暂停时间不进入播放器时间轴，照片/标记仍对齐；
- [ ] 修改系统时间：offset 不跳变；
- [ ] 分别测试 Pixel/Android 原生、三星、小米/澎湃OS、OPPO/ColorOS、vivo/OriginOS、华为/HarmonyOS 兼容设备；
- [ ] 按厂商提示将 App 设为允许后台活动/不受电池优化限制后重复锁屏测试；
- [ ] 存储不足、拒绝权限、只允许一次权限、相机被占用时显示可理解错误且已有数据不丢失。

## 后续最优先

1. 使用同一批真实课堂录音对腾讯云实时结果进行字错率与延迟验收，并接入录后大模型2.0校正；
2. 60–120 分钟真机压力测试和厂商后台适配，用音频容器时间戳做自动漂移校准；
3. 完整数据恢复导入、存储空间预警和导出包分片校验，并完善失败后的重试与续传。
