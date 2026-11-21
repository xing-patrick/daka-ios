# 打卡提醒 · iOS 版

「打卡提醒」的 SwiftUI 移植版。到点提醒你做某件事，点一下就打卡，支持重复规则、法定节假日、批量导入。

数据格式与 Android 版完全一致，同一份 JSON 两边能互读。

## 现在能做什么

- **清单**：按天翻看，点圆点打卡（记录实际打卡时间，提前/延后都会显示「原定 07:00」），左滑移除
- **任务库**：模板增删改；重复规则六种（每天 / 工作日 / 周末 / 法定上班日 / 休息日 / 自定义星期）
- **到点提醒**：横幅 + 「完成 / 稍后 10 分钟」两个按钮，不用打开 App 就能操作；推迟满 3 次判打卡失败
- **批量导入**：一行一条「名称 时间 规则」，边打字边预览，看不懂的行单独列出来
- **节假日**：粘贴导入法定放假和调休补班，「法定上班日 / 休息日」规则靠它才准

## 已知限制

| 限制 | 说明 |
|---|---|
| 没接入 AlarmKit | 静音或专注模式下通知可能不出声。需要 iOS 26 SDK + Apple 审核的 entitlement，当前环境两样都没有 |
| 不理会不判失败 | iOS 不给 App 感知「通知被划掉」，所以「推迟 3 次判失败」只在主动点「稍后」时才会触发 |
| 不能单独关震动 | iOS 没有对第三方 App 开放的震动控制接口，编辑页只保留「到点出声」 |
| 待发提醒有上限 | 系统最多保留 64 条，这里只排 60 条；App 每次启动/回前台会自动往后补排，长期不打开可能排不满 |

## 装到手机上

构建产物是**未签名**的 ipa，不能直接安装，必须用你自己的 Apple ID 重签。有两种方式：

### 方式一：直接下载现成的包（不需要 Mac）

1. 打开 https://github.com/xing-patrick/daka-ios/releases/download/latest/Daka-unsigned.ipa 下载

   （这个仓库只维护一个滚动更新的 Release，tag 固定为 `latest`，每次 main 构建成功就覆盖里面的 ipa。）
2. 电脑上装 [Sideloadly](https://sideloadly.io/)（Windows / macOS 都行），Windows 还需要装 iTunes 或 Apple Devices 以提供驱动
3. iPhone 用数据线连电脑，在「设置 → 隐私与安全性 → 开发者模式」里打开开发者模式并重启
4. Sideloadly 里把 ipa 拖进去，Apple ID 填自己的，点 Start；按提示在手机上输入密码
5. 装好后去「设置 → 通用 → VPN 与设备管理」信任自己的开发者证书
6. 打开 App，允许通知

> 免费 Apple ID 签的包 **7 天过期**，过期后重签一次即可；同一账号最多同时装 3 个自签 App。

### 方式二：自己编译（需要 Mac + Xcode）

```bash
brew install xcodegen
xcodegen generate          # 从 project.yml 生成 Daka.xcodeproj
open Daka.xcodeproj
```

然后在 Xcode 里选中 Daka target → Signing & Capabilities → Team 选自己的账号。
如果提示 bundle id 冲突，把 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 改成你自己的（比如 `com.你的名字.daka`），重新 `xcodegen generate`。

命令行出未签名包（CI 里跑的就是这套）：

```bash
xcodebuild -project Daka.xcodeproj -scheme Daka -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

mkdir -p out/Payload && cp -R build/Build/Products/Release-iphoneos/Daka.app out/Payload/
cd out && zip -qry ../Daka-unsigned.ipa Payload
```

## 目录结构

```
project.yml                  XcodeGen 工程定义（改这个，不要手改 .xcodeproj）
App/                         SwiftUI 界面与系统集成
  DakaApp.swift              入口，监听前后台切换重排提醒
  AppModel.swift             界面与数据层之间的封装
  DayListView.swift          主界面清单 + 底部三按钮
  LibraryView.swift          任务库
  TemplateEditorView.swift   模板编辑
  ImportView.swift           批量导入
  HolidayView.swift          节假日
  SettingsView.swift         设置
  ReminderScheduler.swift    本地通知排期与通知按钮回调
Sources/DakaCore/            数据层，纯逻辑，不依赖 UIKit/SwiftUI
  Dates.swift                天序号 / 星期 / 文案换算
  Models.swift               TaskTemplate / DayTask，JSON 字段与 Android 对齐
  StoreFile.swift            单个 JSON 文件的读写（原子写）
  TaskStore.swift            模板展开、打卡、推迟、模板传导
  HolidayStore.swift         节假日判定，合并与优先级
  ImportParser.swift         批量导入解析
  HolidayParser.swift        节假日导入解析
  ReminderPlan.swift         提醒排期计算（纯函数）
Tests/DakaCoreTests/         50 个单测，`swift test` 直接跑，不需要 Xcode
```

## 数据存在哪

`Application Support/Daka/store.json`，一个文件装全部状态。结构和 Android 版的 SharedPreferences 一致：

```json
{
  "templates": [{ "id": "...", "name": "早起", "min": 420, "kind": "REPEAT", "mode": "WEEKDAY", "days": 31, "created": 20700, "s": true, "v": true }],
  "days": { "20700": [{ "id": "...", "tpl": "...", "name": "早起", "min": 420, "done": false, "auto": true }] },
  "holidays": [20730],
  "workdays": [20736],
  "seeded": true,
  "version": 3
}
```

## CI

每次 push 到 main 会跑两个 job：

- **数据层单测**：`swift test --parallel`，50 个用例
- **编译未签名 ipa**：`xcodegen` 生成工程 → `xcodebuild` 关签名编译 → 校验 bundle id → 打包 ipa → 上传工件 → 发布到 tag 为 `latest` 的 Release

编译失败时，错误行会以 Actions 注解的形式输出（`::error::`），因为这个仓库的 job 日志需要登录才能下载，注解是匿名可读的。
