# DesktopPet · 小狗桌宠

一只安静、傻乎乎、喜欢陪你忙的小狗，待在屏幕边缘，打字时轻轻摇尾巴

[官网与下载](https://desktop-pet-dog.pages.dev/) · [Mac 安装与更新](https://desktop-pet-dog.pages.dev/install.html) · [Windows 试用版](https://desktop-pet-dog.pages.dev/windows.html)

## Mac build 53 / Windows build 11：悬停摸摸，按住拖动

1. 鼠标在小狗头部或尾巴上停留片刻后，轻轻来回移动即可摸摸；鼠标停着不持续触发
2. 按住直接拖动，不再需要双击；原有手动锁定选择仍保留，可从右键 → 外观与摆放 → 锁定位置取消
3. 普通单击保留原来的表情、弹性和互动特效，鼠标移动不增加计数
4. 操作提示与Mac互动预览同步更新；关闭只收起本次提示，不再提示会记住选择

## 下载与使用

1. Apple 芯片 Mac，macOS 14 或以上：[下载 Mac build 53](https://desktop-pet-dog.pages.dev/updates/DesktopPet-0.1.0-b53-arm64.zip)
2. Windows 10（1809 或更新）/11，64 位 x64：[下载 Windows build 11 安装程序](https://desktop-pet-dog.pages.dev/updates/DesktopPet-Windows-0.1.0-b11-x64-Setup.exe)
3. 已安装的小狗可右键 → 更多 → 检查更新，确认后下载安装，保留原计数和设置
4. Mac 当前为开发签名测试版，尚未完成 Developer ID 签名与公证；Windows 安装包尚无 Authenticode 代码签名，首次打开可能出现系统安全提示，请核对下载来源并自行决定是否运行，无需关闭系统保护
5. 本次 Windows 悬停摸摸、单次拖动和提示气泡尚未完成真实 Windows 设备验收，欢迎小范围试用反馈

## 小狗能做什么

1. 呼吸、眨眼、柔性摇尾巴、打盹与平滑醒来
2. 自选爱心、小花、小爪子和小星星，搭配随机上浮互动特效
3. 多档体型、两种尾巴大小、四向平滑旋转，选中小狗后按 R 转身；Windows 在英文输入法下使用 R
4. 可选键盘、鼠标与触控板统一计数，数字默认悬停显示，也可常驻
5. 透明空白处点击穿透，隐藏或系统睡眠时停止动画，尊重系统减少动态设置
6. Mac 支持拖到顶栏自动对齐，左右摆放或向下拖回桌面；Windows 暂无对应顶栏模式

![小狗待在 Mac 顶栏里的实际效果](https://desktop-pet-dog.pages.dev/assets/topbar-mac-b46.png)

## 隐私与更新

1. 日常陪伴和计数在本机运行，无账号、遥测或广告
2. 计数默认关闭。Mac 主动启用后由用户授予输入监控；Windows 在应用内确认启用后接收 Raw Input，不需要 macOS 式的输入监控开关
3. 只保存今日、累计及必要偏好，不保存输入文字、按键顺序或应用信息；Windows 仅为排除长按重复，临时在内存标记按下状态，松开或停止监听时清除
4. 摸摸仅使用小狗本窗口收到的临时位置与距离，不保存鼠标轨迹
5. 只有主动选择检查更新和确认下载时联网，不进行后台更新轮询；官方更新包校验独立更新签名，该签名不等同于系统发行者签名
6. 详见 [Mac 隐私说明](docs/PRIVACY.md)和 [Windows 构建与隐私说明](windows/README.md)

## 源码构建

本仓库现同时包含 Mac 与 Windows 小狗源码

1. Mac：macOS 14+、Swift 6 / Xcode 工具链，Sparkle 版本已锁定

~~~sh
swift build -c release
bash scripts/test.sh
~~~

2. Mac 应用打包与自己的本地开发签名见[构建说明](docs/BUILDING.md)
3. Windows：Python 3、Zig 0.16.0 与固定版本 WinSparkle，见 [Windows 构建说明](windows/README.md)
4. 本仓库包含代码、资源、公开更新验签公钥和第三方许可证，不包含发布私钥；修改版应使用自己的应用标识、更新源和签名密钥，不应沿用官方更新通道发布

## 建议与反馈

哪里让你觉得可爱，哪里有点打扰，或者希望小狗学会什么？欢迎[给我发邮件](mailto:zichen904@gmail.com?subject=DesktopPet%20%E5%B0%8F%E7%8B%97%E5%BB%BA%E8%AE%AE)：[zichen904@gmail.com](mailto:zichen904@gmail.com)

也可以到[官网写点建议](https://desktop-pet-dog.pages.dev/#contact)，填写后打开自己的邮件应用并确认发送。反馈问题时，可附上系统版本、小狗 build 号和复现步骤，请避免发送输入内容等私人信息

## 仓库与许可

本仓库由维护者管理，外部账号没有直接推送修改的权限。公开仓库允许查看、下载和 Fork，Fork 是其他账号自己的副本，不会自动改变本仓库

项目代码与原创美术的许可证尚未确定，当前未附加开源许可证。第三方依赖遵循其各自的许可证
