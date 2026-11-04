# Windows 小狗桌宠

Windows 10（1809 或更新）/11 x64 的原生 Win32 / GDI+ 实现，当前源码版本为 build 11。日常使用请从[官网](https://desktop-pet-dog.pages.dev/windows.html)下载安装程序；以下说明供本地构建使用。

## 构建环境

1. Python 3，仅使用标准库
2. [Zig 0.16.0](https://ziglang.org/download/)，构建脚本会核对版本，不会自动安装或下载工具链
3. [WinSparkle 0.9.4 官方归档](https://github.com/vslavik/winsparkle/releases/download/v0.9.4/WinSparkle-0.9.4.zip)，头文件、依赖信息及许可证在 vendor/winsparkle；DLL 从该官方归档取得
4. 不需要额外安装 .NET 等应用运行时，Windows 系统提供 GDI+ 与 UCRT

## 在 Windows 构建

在仓库根目录打开 PowerShell。先下载上面的 WinSparkle ZIP，核对 SHA256：

~~~powershell
Get-FileHash .\WinSparkle-0.9.4.zip -Algorithm SHA256
~~~

期望值：6037df37fc263bd1650a1c4949681a9d40ffe991d01f35892a406cb5d103c976

核对一致后解压并运行构建脚本，将 Zig 路径替换为自己的安装位置：

~~~powershell
Expand-Archive .\WinSparkle-0.9.4.zip -DestinationPath .\build\windows-deps\WinSparkle-0.9.4
py windows/build.py --zig C:\tools\zig\zig.exe
~~~

默认 DLL 路径为 build/windows-deps/WinSparkle-0.9.4/WinSparkle-0.9.4/x64/Release/WinSparkle.dll。如果解压到其他位置，使用 --winsparkle-dir 指定包含 x64 文件夹的目录；脚本还会验证 DLL 的固定 SHA256。

~~~powershell
py windows/build.py --zig C:\tools\zig\zig.exe --winsparkle-dir C:\deps\WinSparkle-0.9.4
~~~

在 macOS 或 Linux 上可使用相应平台的 Zig 0.16.0 交叉构建：

~~~sh
python3 windows/build.py --zig /path/to/zig --winsparkle-dir /path/to/WinSparkle-0.9.4
~~~

输出在仓库的 build/windows：

1. DesktopPet-Windows：应用、WinSparkle DLL 和随包说明
2. DesktopPet-Windows-0.1.0-b11-x64.zip：免安装文件归档
3. DesktopPet-Windows-0.1.0-b11-x64-Setup.exe：当前账户安装程序
4. compile.log：构建日志

构建出的安装程序不带 Authenticode 代码签名，也没有官方更新私钥的签名；本地构建成功不代表可直接作为官方在线更新发布。程序包含公开验签公钥，不包含任何私钥。修改版应配置自己的版本、应用身份、更新源及密钥。

## 校验与测试

1. 构建后可静态检查 PE、图标、权限声明、DLL、归档白名单及安装器嵌入载荷：

~~~sh
python3 windows/audit.py build/windows/DesktopPet-Windows-0.1.0-b11-x64.zip
~~~

2. tests/CoreTests.cpp、HeldKeysTests.cpp、MenuModelTests.cpp、OperationHintModelTests.cpp、PetExpressionTests.cpp、SqueezeEyesTests.cpp、StrokeGestureTests.cpp 和 HoverStrokeGestureTests.cpp 是无需 Windows UI 的 C++17 测试，可用 Clang 或 Zig 在主机编译运行。例如：

~~~sh
mkdir -p build/windows-tests
clang++ -std=c++17 -Wall -Wextra -Werror windows/tests/CoreTests.cpp -o build/windows-tests/core-tests
build/windows-tests/core-tests
~~~

3. InputCountingTests.cpp、InstallFilesTests.cpp、InteractionControlsTests.cpp、OperationHintControlsTests.cpp 和 PettingControlsTests.cpp 需要 Windows API。它们使用独立测试窗口或临时目录，应在 Windows 测试环境编译和执行，不能把交叉编译通过当作运行验收。
4. 本次悬停摸摸、直接拖动和提示气泡仍需真实 Windows 设备验证，尤其是透明命中、鼠标捕获、触控板、中文输入法、DPI、多屏与系统减少动态设置。静态检查不等于安全认证、性能保证或完整兼容性验收。

## 数据与更新

1. 计数默认关闭。应用内确认开启后才注册 Raw Input，只统计键盘与鼠标按钮按下；移动、滚轮和抬起不计，双击按两次物理按下计算。
2. 长按去重仅在内存用物理按键编号和扩展标记维护临时按下状态，松开清除，暂停、锁屏、系统睡眠和退出时全清。不转换文字，不保存按键编号、顺序、逐次时间、应用或设备身份。单独修饰键仍计入，与 Mac 不同。
3. 今日、累计与设置保存在 %LOCALAPPDATA%\DesktopPet\settings.ini。程序安装在 %LOCALAPPDATA%\Programs\DesktopPetDog，更新替换程序时保留计数目录。
4. 光标在头尾轮廓内停留约 0.35 秒后，来回移动即可摸摸，不需要按住。默认单次按住直接拖动；已有明确保存的锁定选择保持，可右键解锁。静止、透明区和数字框不触发，只临时使用本窗口位置与距离，不保存轨迹或增加计数。提示的“关闭”只影响本次启动，“不再提示”保存在本机。
5. 只有主动选择“检查更新”及确认下载时访问 HTTPS 更新源，使用 WinSparkle 的 Ed25519 验签，日常无后台检查或遥测。服务器仍能看到普通连接信息；更新组件另存跳过版本等偏好，不包含计数或输入内容。
6. Windows 关闭动画时，小狗尊重系统设置，摇尾、弹性与特效位移会减少或停止，计数和静态反馈仍可工作。

WinSparkle 与其依赖的许可证位于 vendor/winsparkle/COPYING*。项目代码和原创美术尚未选择许可证。
