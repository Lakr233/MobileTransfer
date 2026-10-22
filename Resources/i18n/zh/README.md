# iTM

作者：@Sunbelife · 新浪微博：[https://weibo.com/x1nyang](https://weibo.com/x1nyang)

iTM（iOS TimeMachine）是一款用于备份和恢复 iOS 设备的 macOS 应用，基于 Lakr Aream 的 [MobileTransfer](https://github.com/Lakr233/MobileTransfer) 开发。

## 功能

- 备份和恢复 iOS 设备数据。
- 选择备份位置并设置备份密码。
- 加载检查点以进行增量备份。
- 验证备份并转换 BBackupp 归档。

由于 API 变化，实验性的应用备份与恢复功能目前无法使用。降级恢复可能损坏设备；请先确认归档和目标设备，再使用该功能。

现有的 `.mobiletransfer` 归档仍受支持。为避免影响已有备份，文件扩展名保持不变。

## 许可

MobileTransfer 应用代码采用 MIT 许可证。原作者的版权声明和许可证保留在 [LICENSE](../../../LICENSE) 中。第三方许可声明随应用收录于 `MobileTransfer/Resources/License.txt`。

随应用打包的 `MobileInstall` 命令行辅助程序包含 GPL-2.0-or-later 代码，`MobileBackup` 包含 LGPL-2.1-or-later 代码。仅在组织内部进行私有开发无需公开源码。在向组织外分发应用程序包前，请核查相应的源码提供义务和许可证要求。

为保持构建兼容性，Xcode 项目和 Scheme 沿用上游名称；macOS 产品名称、图标和 Bundle Identifier 已改为 iTM。
