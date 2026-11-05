# 构建与开发签名

## 编译和测试

在仓库根目录执行：

```sh
swift build -c release
bash scripts/test.sh
```

## 打包应用

构建脚本要求固定的代码签名身份。可使用自己已有的有效代码签名证书，并指定其 SHA-1 指纹：

```sh
DESKTOP_PET_SIGNING_IDENTITY=YOUR_CERTIFICATE_SHA1 bash scripts/build-app.sh
open build/DesktopPet.app
```

脚本在签名和完整性校验成功后替换应用，保留上一构建；没有固定身份时停止，不回退到临时签名。

也可为自己的开发机器创建本地身份：

```sh
bash scripts/setup-local-signing.sh --prepare
bash scripts/setup-local-signing.sh --install
bash scripts/build-app.sh
```

`--prepare` 只生成本机材料；`--install` 将身份导入登录钥匙串，并设置仅代码签名用途的用户域信任，需要自行完成系统确认。签名材料存放在忽略的 `.local-signing/`，不要加入仓库或随应用分发。

首次启用计数时仍需在系统设置授予输入监控。固定签名用于保持开发版本的身份；更换身份仍可能需要重新授权。首次运行的权限行为应在目标机器上验证。

本地开发签名与公开分发身份不同。正式分发应单独准备 Developer ID 签名和 Apple 公证。

## 离屏预览

下列命令只绘制程序内的小狗和效果，不读取桌面：

```sh
build/DesktopPet.app/Contents/MacOS/DesktopPet --render-dog-previews build/dog-previews
build/DesktopPet.app/Contents/MacOS/DesktopPet --render-yawn-previews build/yawn-previews
build/DesktopPet.app/Contents/MacOS/DesktopPet --render-tail-loop build/tail-frames
build/DesktopPet.app/Contents/MacOS/DesktopPet --render-click-heart-previews build/heart-previews
```

哈欠使用随包分发的 `Sources/DesktopPet/Resources/DogYawn.json` 矢量数据，Swift Package 负责生成资源包，打包脚本将其复制到应用内。离屏渲染与正常运行使用同一份资源，不需要额外下载。
