# Windows 平台运行说明

## 问题
在 Windows 上运行 Flutter 应用时，如果遇到以下错误：
```
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

## 解决方案

### 方法 1：启用开发者模式（推荐）

1. 按 `Win + I` 打开 Windows 设置
2. 进入 **更新和安全** > **开发者选项**（或直接搜索"开发者模式"）
3. 启用 **开发者模式**
4. 重启命令行窗口
5. 重新运行 `flutter run`

或者直接运行以下命令打开设置：
```powershell
start ms-settings:developers
```

### 方法 2：使用 Android 设备/模拟器（推荐用于实际开发）

根据项目计划，本应用主要针对 Android 平台开发。建议使用以下方式测试：

1. **Android 模拟器**：
   - 在 Android Studio 中创建并启动 Android 模拟器
   - 运行 `flutter run` 并选择 Android 设备

2. **真实 Android 设备**：
   - 启用 USB 调试
   - 连接设备后运行 `flutter run`

### 方法 3：临时禁用 Windows 平台（如果不需要在 Windows 上测试）

如果不需要在 Windows 上测试，可以删除 `windows` 文件夹，Flutter 将不会尝试构建 Windows 版本。

## 注意事项

- 开发者模式是 Windows 10/11 的内置功能，启用后可以支持符号链接，这是 Flutter 插件系统所必需的
- 如果启用了开发者模式后仍有问题，请确保以管理员权限运行命令行
- 本应用的核心功能（语音录制）在 Android 平台上测试效果最佳

