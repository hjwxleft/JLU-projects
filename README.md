# flutter_ble_ui

一个基于 Flutter 开发的 BLE 控制 App，用来替代通用蓝牙调试助手中的“手动输入数字发送指令”流程，把常用控制命令封装成可视化按钮，方便演示、测试和后续二次开发。

## 1. 项目简介

本项目的目标是连接 BLE 硬件设备，并通过手机界面直接发送预设控制指令。

当前界面已经完成了基础交互闭环：

- 扫描附近 BLE 设备
- 手动选择设备连接
- 自动发现服务和特征
- 自动匹配可写 TX / 可通知 RX 特征
- 支持手动进入 `Code` 页面配置特征
- 通过按钮发送频率控制指令
- 根据发送或设备回传状态更新界面显示

适用场景：

- BLE 硬件联调
- 给客户或老师演示控制效果
- 作为后续正式 App 的原型版本

## 2. 技术栈

- `Flutter`
  负责整个 App 的界面、状态更新和页面交互。
- `flutter_reactive_ble`
  负责 BLE 扫描、连接、服务发现、特征读写和通知订阅。
- `MethodChannel`
  用于 Flutter 与 Android 原生层通信，申请蓝牙和定位权限。
- `Kotlin`
  Android 原生权限处理写在 `MainActivity.kt` 中。

## 3. 当前已实现的功能

### 3.1 BLE 连接功能

- 点击 `Bluetooth` 按钮后扫描附近所有 BLE 设备
- 扫描结果弹出设备列表，由用户手动选择连接
- 连接成功后自动执行服务发现
- 自动寻找可写特征和可通知特征
- 支持优先匹配预设 UUID，也支持退化为通用可用特征

### 3.2 特征手动配置

- 点击 `Code` 按钮后弹出特征设置窗口
- 可手动选择：
  - TX（写特征）
  - RX（通知/指示特征）
- 保存后立即生效

### 3.3 控制指令封装

UI 中已经把原始数值命令封装成按钮，不需要手动输入数字。

当前映射关系如下：

| 显示按钮 | 实际发送值 |
|---|---|
| `0.5Hz` | `20` |
| `1Hz` | `21` |
| `2Hz` | `22` |
| `5Hz` | `23` |
| `8Hz` | `24` |
| `10Hz` | `25` |
| `16Hz` | `26` |
| `20Hz` | `27` |
| `ON/OFF` | `00` |
| `Direct Current` | `28` |

发送格式为 UTF-8 文本，例如发送 `20` 时，实际写入的是字符串 `"20"` 的字节数据。

### 3.4 状态显示

界面目前包含以下状态信息：

- `Connected / Disconnected`
- `Scanning... / Connecting...`
- 当前频率显示，例如 `0.0 Hz`、`10.0 Hz`
- 当前模式显示：
  - `Alternate Current`
  - `Direct Current`

当发送或接收到以下值时，界面会自动更新模式：

- `20` 到 `27`：高亮 `Alternate Current`
- `28`：高亮 `Direct Current`
- `00`：两种模式都不作为激活态显示

## 4. BLE 相关参数

当前代码里内置了以下优先匹配 UUID：

- Service UUID
  - `BCE9EBFB-BFEE-03A1-B7D7-E587C728441E`
- 写特征 UUID（TX）
  - `5E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- 读/通知特征 UUID（RX）
  - `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`

说明：

- 扫描阶段不会按 Service UUID 过滤
- 连接后会优先尝试匹配以上 UUID
- 如果匹配不到，会自动选择当前设备中可用的写特征和通知特征

## 5. 项目结构

重点文件如下：

- [lib/main.dart](C:/Users/took1/Desktop/flutter_ble_ui/lib/main.dart)
  主界面、BLE 逻辑、指令发送逻辑都集中在这里。
- [pubspec.yaml](C:/Users/took1/Desktop/flutter_ble_ui/pubspec.yaml)
  Flutter 项目依赖配置文件。
- [android/app/src/main/AndroidManifest.xml](C:/Users/took1/Desktop/flutter_ble_ui/android/app/src/main/AndroidManifest.xml)
  Android 蓝牙和定位权限声明。
- [android/app/src/main/kotlin/com/example/flutter_ble_ui/MainActivity.kt](C:/Users/took1/Desktop/flutter_ble_ui/android/app/src/main/kotlin/com/example/flutter_ble_ui/MainActivity.kt)
  Android 原生权限申请逻辑。

## 6. 运行环境要求

建议环境：

- Flutter 3.x
- Dart 3.x
- Android Studio 或 VS Code
- Android SDK
- JDK 17
- 一台开启 USB 调试的安卓手机

本项目开发过程中实际使用过：

- Flutter SDK
- Android 平台真机调试
- JDK 17

## 7. 如何运行项目

### 7.1 安装依赖

在项目根目录执行：

```bash
flutter pub get
```

### 7.2 连接安卓真机

- 打开开发者选项
- 开启 `USB 调试`
- 用数据线连接电脑

检查设备是否识别：

```bash
adb devices
flutter devices
```

### 7.3 运行项目

```bash
flutter run
```

如果指定设备：

```bash
flutter run -d <device_id>
```

### 7.4 构建调试安装包

```bash
flutter build apk --debug
```

生成路径通常为：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 8. Android 权限说明

本项目已经声明并处理以下权限：

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_FINE_LOCATION`

注意：

- Android 12 及以上，对蓝牙扫描和连接权限要求更严格
- 部分手机即使授权成功，也需要用户手动打开系统定位服务，否则可能无法扫描到 BLE 设备

## 9. 当前界面说明

当前页面大致分为三块：

### 第一块：状态区

- 连接状态胶囊
- 扫描/连接过程提示
- 当前频率显示
- 当前设备名称
- 当前模式状态：
  - `Alternate Current`
  - `Direct Current`

### 第二块：功能入口区

- `Bluetooth`
  扫描并连接 BLE 设备
- `Code`
  打开特征配置面板

### 第三块：控制区

- `Voltage Regulation`
  九宫格频率控制按钮
- `Direct Current`
  独立的大按钮控制项

## 10. 交付别人时建议发什么

如果只是给别人安装试用，发这个文件即可：

- `build/app/outputs/flutter-apk/app-debug.apk`

如果是给别人继续开发，建议直接把整个项目文件夹打包发送：

- `flutter_ble_ui/`

打包源码时可以不带以下目录，以减小体积：

- `.dart_tool/`
- `build/`
- `.idea/`

## 11. 当前已知限制

- 目前主要面向 Android 真机调试
- 代码暂时集中在 `main.dart` 中，便于快速原型开发，但后续如果继续扩展，建议拆分模块
- 当前是调试版 App，更适合测试、演示和继续开发，不是最终正式发布版
- iOS 端尚未针对真实设备做完整联调验证

## 12. 后续可优化方向

- 将 BLE 逻辑、UI 组件、指令映射拆分为独立文件
- 增加设备记忆功能，下次自动恢复上次使用的特征配置
- 增加更完整的错误提示和连接失败反馈
- 增加更正式的图标、启动页和发布配置
- 输出 release 包，便于正式交付

## 13. 备注

本项目是一个可运行的 BLE 控制原型，已经具备“扫描设备、连接设备、配置特征、发送控制指令、根据状态更新 UI”的完整链路，可作为后续产品化开发的基础版本。
