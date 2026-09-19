# 多服务商接入状态

## 阿里 Fun-ASR（开发中，未真实云端验收）

Python 代理新增 `/v1/asr/aliyun/realtime`。手机通用协议已兼容；旧腾讯路径不变。
服务端设置 `DASHSCOPE_API_KEY`、`PROXY_AUTH_TOKEN`，可选北京地域
`ALIYUN_WORKSPACE_ID` 和预编译 `ALIYUN_VOCABULARY_ID`。示例在代理的
`scf_python/.env.example`，程序读取环境变量，不自动读取 .env。

部署时必须同时包含 `app.py`、`aliyun_asr.py` 和 requirements.txt。
使用公网 TLS WebSocket 地址；不可依赖 Mac 本地代理。
当前默认模型 fun-asr-realtime，PCM 16kHz 单声道 int16。
App 已新增腾讯/阿里/自定义代理选择器，选择会切换服务器路由并标注真实字幕来源。
尚未部署或使用真实密钥验证，不能宣称已经可用。
云端时间零点已改为实际送出的第一帧 PCM，避免连接等待时间造成字幕提前。

本地协议测试：在 scf_python 目录运行 `python3 -m unittest -v test_aliyun_asr`。
覆盖握手、音频顺序、结束后稳定句、时间戳和错误消息脱敏；不衡量识别准确率。

官方协议参考（2026-09-20核对）：
- https://help.aliyun.com/zh/model-studio/fun-asr-realtime-websocket-api
- https://help.aliyun.com/zh/model-studio/fun-asr-client-events
- https://help.aliyun.com/zh/model-studio/fun-asr-server-events

下一步：阿里端到端联调、豆包适配、服务商选择与就绪状态、真机录音/恢复/连续拍照回归。

## 1.2.1+4010 客户端检查

- 服务商下拉已实现腾讯、阿里与自定义路由；阿里明确标注未真实验证。
- 云端时间基准从实际第一帧 PCM 开始，修复握手等待造成字幕提前。
- WebSocket 建立后 10 秒未收到就绪信号会回退，不再永久显示连接中。
- 正常结束后服务器断开不会误报连接失败；连接异常不再原样显示内部错误。
- 73 项 Flutter 测试通过，静态检查通过。包含本地 WebSocket 超时回归。
- 豆包官方详细协议页本次读取失败，尚未实现；不能把其他产品的协议套用过来。
- 当前阶段仍需真实云账号配置与真机回归，以上测试不等于识别准确率验收。

## 部署包验证

新增 allowlist 打包脚本 `tool/package_asr_proxy.py`，成功生成
`build/tencent_asr_proxy_scf.zip`，使用 websockets 12.0 的 py3-none-any wheel。
通过 ZIP 直接导入 app、aliyun_asr、websockets 的冒烟检查。
10 项 Python 测试通过，其中 4 项实际启动本地 TCP/WebSocket 检查鉴权与路由。
尚未上传云端：当前环境未发现部署 CLI，浏览器控制两次超时。
手机已确认覆盖安装 1.2.1+4010，但锁屏仍阻止 UI 验收。

## 豆包适配进展（未真实云端验收）

通过火山引擎官方 GitHub 示例确认 SAUC 报文结构后新增
`doubao_asr.py`、`/v1/asr/doubao/realtime` 和 App 选择项。
服务端需 `DOUBAO_APP_ID`、`DOUBAO_ACCESS_TOKEN`，可选 `DOUBAO_VOCABULARY_ID`。
使用双向流式 bigmodel 路径及 `volc.bigasr.sauc.duration` 资源。
当前实现旧版应用ID/访问令牌鉴权；新版单 API Key 控制台尚未适配验证。
15 项 Python 测试通过，包括握手前不发音频、末包标记、最后稳定句、去重、
压缩响应上限和三条路由鉴权。未上传真实录音、未开通付费资源、未部署线上。
App 选择项尚未包含在手机的 4010 安装包内，需下一次构建安装。

官方参考：
- https://github.com/volcengine/ai-app-lab/blob/main/arkitect/core/component/asr/asr_client.py
- https://github.com/volcengine/ai-app-lab/blob/main/arkitect/utils/binary_protocol.py
- https://github.com/volcengine/ai-app-lab/blob/main/arkitect/core/component/asr/model.py

## 4011 安装与完成度核对

已构建并使用 `adb install -r` 覆盖安装 1.2.1+4011；手机包信息确认 versionCode=4011。
APK：`build/app/outputs/flutter-apk/sync-notes-1.2.1-4011-arm64.apk`。
SHA256：`a8a9df9de12aa6491e0209203f127427dd7e3dab313efaffb24b898d937471d5`。
74 项 Flutter 测试、15 项 Python 测试和 Flutter 静态检查通过。
部署 ZIP 实际导入 app/aliyun_asr/doubao_asr 成功，包含三条路由。

完成目标仍未成立：
- USB 供电保持亮屏设置值为 2，但安全锁屏仍 showing=true；未绕过锁屏。
- 新版未完成真机 UI、连续20张照片、两次异常续录、60分钟后台录音验收。
- 环境未设置阿里/豆包密钥，两个已知项目 .env 文件不存在；未搜索其他应用的凭据。
- 新云服务代理未部署，未测真实识别准确率、延迟、热词收益。
- 市面上其他 ASR 服务未接入；不能把三条接口称为所有主流服务均可用。
- 安装未执行卸载或清除数据；锁屏下尚未在 UI 复核原有记录。
