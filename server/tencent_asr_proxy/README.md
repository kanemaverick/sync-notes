# 腾讯云实时 ASR 安全代理

这个服务替移动 App 保存腾讯云 `AppID`、`SecretID` 和 `SecretKey`，生成 HMAC-SHA1 签名，并在 App 与腾讯云实时 ASR V2 WebSocket 之间中继 PCM 和识别结果。腾讯云密钥绝不能填写到 Flutter 设置页。

## 本地启动

```bash
cd server/tencent_asr_proxy
dart pub get
export TENCENT_APP_ID="..."
export TENCENT_SECRET_ID="..."
export TENCENT_SECRET_KEY="..."
export PROXY_AUTH_TOKEN="$(openssl rand -hex 32)"
dart run bin/server.dart
```

健康检查：`GET /health`。App 中填写的地址为：

```text
wss://你的域名/v1/asr/tencent/realtime
```

生产环境必须使用 HTTPS/WSS、限流、日志脱敏和可撤销的 App 访问令牌。反向代理需要允许 WebSocket Upgrade，并把空闲超时设置到课堂录音长度以上。

## 不依赖 Mac 的推荐部署：腾讯云 SCF Web 函数

腾讯云 Web 函数已支持原生 WebSocket，并会提供公网 `wss://` 函数 URL，因此不必单独购买域名。

1. 从仓库根目录运行 `python3 tool/package_asr_proxy.py`（需要 pip 与网络）；产物为 `build/tencent_asr_proxy_scf.zip`。脚本仅打包指定源文件与纯 Python 依赖，根目录包含 `app.py`、`aliyun_asr.py`、可执行的 `scf_bootstrap` 和 `websockets/`，不会包含 `.env` 或 App 配置。
2. 在腾讯云“云函数 SCF”新建 **Web 函数**，运行环境选择 **Python 3.9**，代码提交方式选择“本地上传 ZIP”。
3. 启动命令填写 `/var/user/scf_bootstrap`，监听端口填写 `9000`。
4. 在高级配置中勾选 **WebSocket 支持**，执行超时和 WebSocket 空闲超时设置为允许的较大值（官方当前允许空闲超时 10–7200 秒）。
5. 添加四个加密环境变量：`TENCENT_APP_ID`、`TENCENT_SECRET_ID`、`TENCENT_SECRET_KEY`、`PROXY_AUTH_TOKEN`。
6. 开启公网函数 URL，将其中的 `https://` 改为 `wss://`，并追加 `/v1/asr/tencent/realtime`。
7. 先访问 `https://函数域名/health`，确认返回 `providerConfigured: true`，再把 WSS 地址配置到 App 或内置到 APK。

一次实时转写会占用一个 Web 函数实例直到连接结束，会同时产生 SCF 运行费用和腾讯云 ASR 费用。发布前设置预算告警、并发上限和日志脱敏。

Python 代码包使用纯 Python WebSocket 中继，避免 SCF Python 3.9 基础镜像的旧 glibc 无法运行当前 Dart AOT 二进制的问题。`websockets` 依赖需要以纯 Python 文件随包上传，不要把 macOS 的原生 `.so` 文件打进 ZIP。

## 腾讯云配置

在腾讯云控制台开通语音识别大模型 2.0，创建 API 密钥。代理固定使用：

- 引擎：`16k_zh_en_2.0`
- PCM：16 kHz、16-bit、单声道
- VAD：开启
- 数学数字转换：开启

部署后只把代理地址与 `PROXY_AUTH_TOKEN` 填入 App。不要把 `.env`、云密钥或真实代理令牌提交到 Git。

## 阿里 Fun-ASR（Python 代理新增，真实云端待验证）

新增 `/v1/asr/aliyun/realtime` 路由，腾讯路由保持不变。配置 `DASHSCOPE_API_KEY`
与同一 `PROXY_AUTH_TOKEN`；可选 `ALIYUN_WORKSPACE_ID`（北京地域）、
`ALIYUN_VOCABULARY_ID`（预编译热词）。密钥、业务空间与开通的模型必须属于同一地域。
默认 `fun-asr-realtime`，音频为 16kHz 单声道 PCM。示例见 `scf_python/.env.example`。
程序读取进程环境变量，不自动加载 .env。

`/health` 保留旧 `providerConfigured`（腾讯配置存在），新增 `providers.tencent`
与 `providers.aliyun` 布尔值。它们只检查配置是否存在，**不证明密钥有效、额度足够或识别可用**。

在 `scf_python` 目录安装 requirements 后执行：
`python3 -m unittest -v test_aliyun_asr test_proxy_routes`。
测试使用本地模拟服务，不上传录音，不产生云 ASR 费用。
当前 Dart 代理仍仅支持腾讯；多服务商部署请使用 Python ZIP。
