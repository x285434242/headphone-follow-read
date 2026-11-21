# 耳机跟读训练器（Flutter + sherpa-onnx）

端侧 ASR / TTS / 声纹 / 降噪的蓝牙耳机跟读训练 App。

- ASR: SenseVoice（离线）
- TTS: Matcha（中文，多音字/语气语调处理）
- 声纹: 3D-Speaker 注册/验证
- 降噪: GTCRN + VoxLock（保留本人声、剔除他人声）

APK 由 GitHub Actions 自动编译，见 `.github/workflows/build-apk.yml`。
模型需首次从 GitHub Releases 下载后放到手机 `models/` 目录，详见 README.md。
