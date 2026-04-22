# 蓝牙控制界面项目说明

## 一、项目概述

本项目是一个基于 Flutter 开发的 BLE 控制 App，用于替代通用蓝牙调试助手中“手动输入数字并发送”的操作方式。

原本的控制流程是：先连接蓝牙设备，再手动输入数值，例如 `20`、`21`、`28` 等，最后发送给硬件。为了让操作更直观，也便于演示和后续使用，本项目将这些数字指令封装成了可点击的界面按钮，例如频率按钮、开关按钮和直流模式按钮。

目前项目已经完成了安卓端的基本功能实现，可以用于 BLE 设备联调和演示。

## 二、主要完成内容

目前已经完成的内容如下：

- 完成了安卓端 BLE 控制界面的搭建
- 可以扫描附近的 BLE 设备，并由用户手动选择连接
- 连接成功后可以自动发现服务和特征
- 支持自动匹配可写特征（TX）和可通知特征（RX）
- 支持手动进入特征设置页面，自行选择 TX 和 RX
- 将原本需要手动输入的指令改成了界面按钮操作
- 点击按钮后可以直接向硬件发送对应的控制值
- 页面会根据当前指令状态切换 `Alternate Current` 与 `Direct Current` 的显示效果

## 三、技术方案

本项目主要使用了以下技术：

- `Flutter`
  用于完成整个 App 的界面开发和交互逻辑。

- `flutter_reactive_ble`
  用于实现 BLE 的扫描、连接、服务发现、特征读写以及通知订阅。

- `MethodChannel`
  用于 Flutter 与 Android 原生层之间通信，处理蓝牙和定位权限申请。

- `Kotlin`
  用于编写 Android 原生权限申请部分。

## 四、当前界面功能

当前页面大致分为三部分：

### 1. 状态区

用于显示当前设备连接状态和模式状态，包括：

- `Connected / Disconnected`
- 扫描中或连接中的状态提示
- 当前频率显示
- 当前设备名称
- `Alternate Current / Direct Current` 模式状态

### 2. 功能入口区

包含两个主要按钮：

- `Bluetooth`
  用于扫描并连接 BLE 设备

- `Code`
  用于进入特征设置页面，手动选择 TX / RX 特征

### 3. 控制区

包含频率控制按钮和直流控制按钮。

频率按钮包括：

- `0.5Hz`
- `1Hz`
- `2Hz`
- `5Hz`
- `8Hz`
- `10Hz`
- `16Hz`
- `20Hz`
- `ON/OFF`

另有单独的：

- `Direct Current`

## 五、指令映射关系

当前界面中的按钮与硬件发送值对应关系如下：

| 界面按钮 | 发送值 |
| --- | --- |
| 0.5Hz | 20 |
| 1Hz | 21 |
| 2Hz | 22 |
| 5Hz | 23 |
| 8Hz | 24 |
| 10Hz | 25 |
| 16Hz | 26 |
| 20Hz | 27 |
| ON/OFF | 00 |
| Direct Current | 28 |

发送方式为 UTF-8 文本发送。例如点击 `0.5Hz` 时，实际写入的内容是字符串 `"20"`。

## 六、BLE 参数设置

代码中当前优先使用的 UUID 如下：

- Service UUID
  - `BCE9EBFB-BFEE-03A1-B7D7-E587C728441E`

- 写特征 UUID（TX）
  - `5E400002-B5A3-F393-E0A9-E50E24DCCA9E`

- 读特征 / 通知特征 UUID（RX）
  - `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`

说明：

- 扫描设备时不按 Service UUID 过滤
- 连接成功后优先尝试匹配以上 UUID
- 如果没有匹配到，则自动选择当前设备中可用的写特征和通知特征

## 七、项目主要文件说明

项目中当前最重要的几个文件如下：

- [lib/main.dart](C:/Users/took1/Desktop/flutter_ble_ui/lib/main.dart)
  主要界面、BLE 连接逻辑、控制按钮逻辑都在这个文件中。

- [pubspec.yaml](C:/Users/took1/Desktop/flutter_ble_ui/pubspec.yaml)
  项目依赖配置文件。

- [android/app/src/main/AndroidManifest.xml](C:/Users/took1/Desktop/flutter_ble_ui/android/app/src/main/AndroidManifest.xml)
  安卓权限声明文件。

- [android/app/src/main/kotlin/com/example/flutter_ble_ui/MainActivity.kt](C:/Users/took1/Desktop/flutter_ble_ui/android/app/src/main/kotlin/com/example/flutter_ble_ui/MainActivity.kt)
  安卓端权限申请逻辑。

## 八、运行方法

### 1. 安装依赖

在项目根目录执行：

```bash
flutter pub get
```

### 2. 连接安卓手机

- 打开手机开发者选项
- 开启 `USB 调试`
- 使用数据线连接电脑

检查设备是否连接成功：

```bash
adb devices
flutter devices
```

### 3. 运行项目

```bash
flutter run
```

如果需要指定设备，可使用：

```bash
flutter run -d <device_id>
```

### 4. 构建安装包

```bash
flutter build apk --debug
```

生成后的安装包路径通常为：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 十、目前存在的不足

目前项目仍然属于原型性质，主要还有以下不足：

- 代码还比较集中，主要逻辑都写在 `main.dart` 中，后续可以继续拆分模块
- 当前更适合安卓真机调试和演示，尚未做正式发布版本
- 页面样式已经完成基础优化，但还可以继续精细调整

## 十一、后续可继续完善的方向

后续如果继续优化，可以从以下几个方向展开：

- 将 BLE 逻辑、UI 组件、指令映射拆分成独立文件
- 增加设备记忆功能，保存上一次使用的特征配置
- 增加更完整的异常提示和连接失败反馈
- 优化界面细节和整体视觉风格
- 输出正式的 release 安装包

## 十二、总结

本项目已经完成了从 BLE 扫描、连接、特征配置到控制指令发送的基本闭环，也将原本依赖手动输入数字的调试流程改成了可视化按钮操作。当前版本已经可以作为硬件联调、功能演示和后续继续开发的基础版本。
