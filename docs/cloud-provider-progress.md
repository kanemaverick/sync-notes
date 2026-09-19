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
