# STATUS — 黑猫拦截 Pro · iOS

## 当前版本

**v1.2.8 build 127**（2026-11-21 · 修 iOS 14 进设置闪退 + 卡密永久卡）

### 客户端

| 问题 | 处置 |
|---|---|
| iOS 14 进设置 / 激活卡密页闪退 | **根因**：1.2.7 的「端口段拦截」用了 `SwitchToggleStyle(tint:)`，这个初始化器 iOS 15.0 起才有。对比两版包的动态符号，1.2.7 新增了 `SwiftUI.SwitchToggleStyle.init(tint:)`，1.2.6 没有 —— iOS 14 渲染规则库卡片时懒绑定找不到符号，当场崩。 |
| 处置 | 改成自绘开关 `HMInlineSwitch`（Capsule + Circle + offset，全是 iOS 13 API），不再引用 Toggle / SwitchToggleStyle / `Binding(get:set:)` |
| 设置页自动聚焦 | 去掉 `ScrollViewReader` + `scrollTo`（iOS 14 在 sheet 转场里会拿到已释放的滚动容器）；只保留一次 `focus()`，且 `CardCodeFocus.focus()` 先确认字段已进 window |
| 永久卡支持 | `LicenseState` 新增 `permanent`；`expireText` 显示「永久有效」、`remainText` 显示「永久」；`isUsable` / `isHardInvalid` 对永久卡不看 `expireAt`；本地合并时不会把永久标记降级 |
| 版本 | 1.2.8 / 127 |

### 服务端

| 项 | 处置 |
|---|---|
| 永久卡生成 | 后台「生成卡密 → 卡密类型」新增「永久卡 · 永久有效」；`cards.duration_sec = 0` 表示永久，兑换后 `expire_at` 写 `PERMANENT_UNTIL = 4102444800`（2100-01-01） |
| 接口 | `card/redeem`、`session/state`、`session/beat`、`payload` 都带 `permanent`；老客户端拿到远期 `card_expire_at` 照常能用 |
| 时长上限 | 顺手修了个老 bug：`createBatch` 以前把时长卡在 30 天，季卡/年卡生成出来只有 30 天；现在上限 3650 天 |
| 后台展示 | `dur()` 对 0 显示「永久」；延期按钮对永久卡不再改动 |
| 实测 | 生成 1 张永久卡 → 兑换 → `expire_at=4102444800`、`permanent=true`；30 天卡 2592000、365 天卡 31536000（不再被截）；测试数据已清理 |
| 备份 | `~/bak-1.2.8-20261121-234720/`（4 个文件原样） |

### 待真机验证

- iOS 14：设置页能正常打开、不再闪退；点卡密框能起键盘、能粘
- iOS 14：永久卡激活后「剩余」显示「永久」、不显示两万多天
- 端口段拦截开关（默认关）打开后自动重连、核心端口仍放行

---

**v1.2.7 build 126**（2026-11-21 · 恢复「端口段拦截」开关：独立于拦截模式，默认关闭）

### 客户端

| 项 | 处置 |
|---|---|
| 设置里没有「端口段拦截」开关 | **已恢复**。1.2.4 曾把它跟模式绑死（全局开、规则关）并从界面移除；1.2.7 按站长要求加回**独立开关**，存 `hm.portblock.v1`，**默认关闭**，用户自己打开才按 `#PORT` 段拦 |
| 打开后会不会把授权通道一起封掉 | 不会。`AppConfig.corePorts`（22/53/80/123/443/853/8080/8443）永远放行，与 1.2.3 口径一致 |
| 隧道侧读取 | `ConfigStore.tunnelConfiguration()` 把 `portBlock` 带进扩展；`PacketTunnelProvider` 缺省 `false`，`TunnelEngine` 只在开关打开时查 `#PORT` 段 |
| 切换生效方式 | 与拦截模式一致：落盘 → 隧道在跑就重连一次（约 2 秒断流）→ 提示「正在重新应用」；没开防护时只回一条结果 |

### 上线记录（2026-11-21 15:00 北京时间）

- 流水线：commit `13b0e8c` → run `44877740331`（macos-15 runner），`SIGN_PHASE_OK` / `ENT_OK` / `OBF_OK` / `SYMBOL_OK`
- 包：

| 文件 | 大小 | SHA-256 |
|---|---|---|
| HeiMao_Pro_v1.2.7_build126_signed.ipa | 1,396,613 B | d5195a11c08ee796a9b54bcf6cf27bf5b370ac6fb0baf9da75ed0b347f0c7d73 |
| HeiMao_Pro_v1.2.7_build126_unsigned.ipa | 1,373,637 B | 1dc859cdfc1a3ded4afe1754bdc708c74e547526d9448fcaecf207ffa82e6040 |

- 代码段指纹 `30d8647259e886a6…`（签名包与未签名包一致）
- 双端 1.2.7 / 126，MinimumOSVersion 14.0，三端 755，Frameworks 只留 HMKit
- 线上版本表 id=14 → 1.2.7 / 126（force_update=1，min_version=1.2.7）；下载页显示 1.2.7（126）、两个 SHA-256 与指纹；`/dl/*` 两包实测 200、大小与源文件一致
- `/dl/manifest.json` 已更新；1.2.5 移入 `archive_old/`，`/dl/` 只留 1.2.6 与 1.2.7
- 备份：`storage/sqlite/app.db.bak_126_*`、`archive_old/manifest.json.bak_1.2.6_125`

### 待真机验证

- 设置 → 规则库：应看到「端口段拦截」开关，**默认是关的**；打开后防护会自动重连一次
- 打开后正常上网、授权、同步规则都应照常（核心端口放行）
- iOS 14 真机：卡密输入框、粘贴按钮、自动弹键盘（1.2.6 的修复一并带上）

---

**v1.2.6 build 125**（2026-11-21 · 修 iOS 14 卡密无法输入 + 公告保存 + 设备指纹口径统一）

### 客户端

| 问题 | 处置 |
|---|---|
| iOS 14 上卡密输入框点不动、键盘不弹（1.2.3 只修了 sheet 弹不出来，输入框本身没修） | **已改**。卡密输入框改为 `Sources/App/Views/CardCodeField.swift`：直接包一层 `UITextField`（UIKit 自己的命中测试，14–27 一致），占位符改成原生 `attributedPlaceholder`，不再用 ZStack 盖一层 Text。设置页出现且未激活时自动 `becomeFirstResponder`（0.45s / 1.2s 各一次，等 sheet 转场走完），并把卡密那一格滚动到可视区。旁边加「粘贴」按钮，从剪贴板直接灌入并规范化，键盘即使起不来也能激活 |
| iOS 14 上全屏背景 + 主圆球跑三个 `repeatForever` 无限动画 | **已改**。`AuroraBackground` 与 `HeroOrb` 的无限动画在 iOS 15 以下不启动（14 上实测会抢触摸、拖输入框焦点）；旧系统给静止背景，观感基本一致 |
| 卡密输入体验 | 输入即规范化：只留字母数字、自动补 `4-4-4-4` 短横线、上限 16 位；键盘用 `.asciiCapable` + 深色；回车直接提交激活 |

### 服务端（已上线）

| 问题 | 处置 |
|---|---|
| 后台「发布公告」保存了但客户端/后台仍显示旧公告 | **已改**。根因是表里有多条 `active=1`：`save()` 更新的是 id 最小那行，`current()` 读的却是 id 最大那行，写读口径不一致。现在一次事务里更新目标行 + 其余全部置 `active=0`，读取按 `updated_at DESC, id DESC` 取最新，与写入一致。审计写失败不再把已生效的公告回滚掉 |
| 公告正文被静默截断 | **已改**。上限 240 → 2000 字（后台表单同步 `maxlength=2000`，标题 60）；发布失败时把服务端错误码显示出来，不再只显示「发布失败」 |
| 后台 HTTP Basic 口令 | **已关**（站长要求）。nginx 里 `auth_basic` 两行注释掉，应用层登录与会话鉴权不变；要恢复把那两行注释放开即可，口令文件仍在 `/www/server/nginx/conf/.hm_admin` |
| 设备指纹换机口径 | **对齐文档**。`adoptByDev`（重装免输卡密）原本就要求原设备离线 150 秒；这次把 `bind()` 里「指纹相同直接改绑」这条也补上同样前置条件——以前只凭指纹就能在线把卡密抢走、原设备当场被踢 |

### 发布

- 变更文件：`Sources/App/Views/CardCodeField.swift`（新增）、`Sources/App/Views/SettingsView.swift`、`Sources/App/Views/GlassKit.swift`、`Sources/Shared/AppConfig.swift`、`project.yml`

### 上线记录（2026-11-21 14:47 北京时间）

- 流水线：commit `682b0b4` → run `44876312716`（macos-15 runner），`SIGN_PHASE_OK` / `ENT_OK` / `OBF_OK` / `SYMBOL_OK`
- 包：

| 文件 | 大小 | SHA-256 |
|---|---|---|
| HeiMao_Pro_v1.2.6_build125_signed.ipa | 1,392,990 B | 0b04691fccdedf179ce08db901d898443da246ad6d69a607f93afae60df52c22 |
| HeiMao_Pro_v1.2.6_build125_unsigned.ipa | 1,370,233 B | 64d876fb626a37fcbe31c32f8aad04a96b6ff559b23eeaa1ae9d7d144424fa49 |

- 代码段指纹 `b36c505b9e9344b4…`（签名包与未签名包完全一致，重签不会触发看门狗误判）
- 双端 1.2.6 / 125，MinimumOSVersion 14.0，三端 755，Frameworks 只留 HMKit（无 libswift_Concurrency）
- entitlements 无 `get-task-allow`；ATS 全站 HTTPS
- 线上版本表 id=13 → 1.2.6 / 125（force_update=1，min_version=1.2.6）；下载页自动显示 1.2.6（125）、哈希与指纹，`/dl/*` 两个包实测 200、大小与源文件一致
- `/dl/manifest.json` 已更新（version 1.2.6 / build 125 / code_hash）；1.2.4 已移入 `archive_old/`，`/dl/` 只留 1.2.5 与 1.2.6
- 备份：`storage/sqlite/app.db.bak_125_*`、`archive_old/manifest.json.bak_1.2.5_124`

### 待真机验证

- 装 1.2.6 后「设置 → 关于 → 代码指纹」应显示 `b36c 505b 9e93 44b4`
- iOS 14 真机：点卡密输入框能起键盘、光标能落、粘贴按钮可用；iOS 15+ 回归一遍
- 后台公告：发一条 500+ 字公告，刷新页面与客户端都应立即显示新内容

---

**v1.2.5 build 124**（2026-11-21 · 按第三方安全审计收紧客户端与发布面）

审计报告（H-01…G-04）逐条处置如下。「做了」的都已上线并实测；「没做」的写清理由，不是漏掉。

### A. 客户端（已随 1.2.5 发布）

| 编号 | 问题 | 处置 |
|---|---|---|
| H-01 | App 全局关闭 ATS，任何请求都可能走明文 HTTP | **已改**。`NSAllowsArbitraryLoads=false`，只给 `ios.ouovo.cc` 留 TLS1.2 起的例外（`NSExceptionAllowsInsecureHTTPLoads=false`）。全仓核对过：除 SecureChannel 外没有任何 URLSession；本地统计服务走 BSD socket + 127.0.0.1，不经过 ATS |
| H-02 | 发布包带 `get-task-allow` / `platform-application` | **已改**。`get-task-allow` 从两个 entitlements 里删掉，CI 增加硬校验（`ldid -e` 里出现即构建失败）。`platform-application` **保留** —— 巨魔安装必需，且它不扩大调试面 |
| H-02 补充 | 可被 debugserver attach 读内存里的卡密 | **已加**。`Sources/Shared/Hardening.swift`：启动 `PT_DENY_ATTACH`（dlsym 取符号，避开 SDK 参数差异），再叠 `P_TRACED` 复查；被挂上就清掉本地授权并退出。主程序与隧道扩展都装 |
| H-03 | 主包没有真签名 / 无法验证来源 | **部分**。没有 Apple 开发者证书，这一点做不了；能做的都做了：下载页显示 SHA256 + 大小、新增 `/dl/manifest.json`、App「设置 → 关于 → 代码指纹」显示自身 `__TEXT,__text` 指纹（前 16 位），与清单里的 `code_hash` 可直接对照 |
| H-04 | 卡密 / 设备码明文存在 NSUserDefaults | **已改**。授权改为 AES-256-GCM 加密 + HMAC 落盘（`HML2`），读 plist 只能看到密文；旧 `HML1` 自动迁移并立刻按新格式重写 |
| G-01 | 混淆强度不足 | 已有（构建期字符串加密 + 顶层类型改名 + 符号剥离），本次未改 |
| G-02 | 无越狱 / 调试检测 | **部分**。调试检测已从「只上报」升级为「拒绝附加 + 清授权退出」；越狱检测不硬拦（巨魔用户本身就在越狱环境，硬拦等于封死主要用户群） |
| M-03 | 通道密钥硬编码在包里 | **没改**。客户端必须能加密请求，对称密钥只能随包分发，换非对称/ECDH 是协议级改造（要服务端同步发密钥、老客户端兼容），收益不抵风险，留到下一个大版本 |

### B. 服务端（已上线）

| 编号 | 问题 | 处置 |
|---|---|---|
| M-01 | `/admin/` 未登录可拿到完整控制台与全部接口清单 | **已改**。`/admin/` 加 HTTP Basic 口令（`hmadmin`），接口层仍按原会话鉴权 |
| M-02 | 软 404：不存在的路径全返回 200 + 首页 | **已改**。`try_files $uri $uri/ =404`，`/backup.zip`、`/nginx_status` 等实测 404 |
| L-01 | 缺 CSP / Permissions-Policy | **已改**（保留 `unsafe-inline`，后台是单文件内联脚本） |
| L-02 | HSTS 未加强 | **部分**。`max-age` 拉到两年；**没加** `includeSubDomains` —— `auth.api.ouovo.cc` 目前只有 80 端口，加上会把那个子域打挂 |
| L-03 | 登录限速只在 IP 维度 | **已改**。保留 IP 限速，新增账号维度：同一账号 15 分钟内失败 10 次锁到窗口过期，前台提示「尝试次数过多」 |
| L-04 | `/api/*` 未知路径返回 400 而非 404 | **没改**。加白名单才能区分「路由存在」，维护成本高于收益，且状态码差异不构成实质风险 |
| M-04 | 下载无完整性校验 | **部分**。SHA256 + 大小 + manifest.json + `Content-Disposition` 已做；一次性签名 URL 没做（App 内和浏览器下载都要兼容，收益低） |
| 旧包暴露 | `/dl/` 长期堆着历史版本 | **已改**。1.2.2 / 1.2.3 全部移到 web 根外，`/dl/` 只留当前版 |

### C. 发布（build 124）

| 文件 | 大小 | SHA-256 |
|---|---|---|
| HeiMao_Pro_v1.2.5_build124_signed.ipa | 1,385,225 B | f25d05f90bec1b1039679b99373663873532f724654d82f4ea48ec9a469d99cd |
| HeiMao_Pro_v1.2.5_build124_unsigned.ipa | 1,362,586 B | 00df0e24630eee11b3a90a9331f523d23e77be01da9a39b744b4313dd7fced50 |

- 代码段指纹 `75c0f9e09a5cd304…`，签名包与未签名包完全一致（重签不会误判）
- 双端 1.2.5 / 124，MinimumOSVersion 14.0，三端 755
- entitlements 已无 `get-task-allow`；ATS 已收紧（CI 两道硬校验）
- 线上版本表 id=12 → 1.2.5 / 124（force_update=1），下载页自动显示新版与哈希

### D. 待真机验证

- 装 1.2.5 后「设置 → 关于 → 代码指纹」应显示 `75c0 f9e0 9a5c d304`，与下载页一致
- 旧版本升级上来：卡密应当还在（HML1 → HML2 自动迁移），不需要重新激活
- 巨魔安装 / ESign 重签两条路径都验一次

---

## 当前版本

**v1.2.4 build 123**（2026-11-21 · 熔断即时生效 / 独立加密心跳 / 看门狗互校验 / 规则界面去敏感信息 / 线上安全修复）

### A. 熔断与维护：从「开关摆设」到即时生效

用户反馈：后台把熔断关掉，客户端还是崩；维护开关点了没反应。

根因两处：

1. 客户端把云端结论**钉在本地后无条件执行** —— 下次启动 `enforcePinned()` 直接崩，
   根本没有机会再去问云端。开关只是改了服务端，客户端还按旧钉子走
2. 运维状态只在启动和每 4 分钟一次的版本检查里拉，窗口太长

现在：

- **本地钉子不再直接执行**。启动时只取出来挂着，先问云端；云端说 `off` 立刻拔钉
  （这就是「后台一关就恢复」），云端说仍然命中才崩
- 新增独立心跳 `POST /api/app/pulse`：不带卡密、v4 裸密文、25 秒一次。
  它同时承担运维状态下发 —— 维护 / 熔断从「几分钟」变成「半分钟内」
- 心跳失败 12 次（约 5 分钟）才熔断；**从没连通过验证站、本地也没有熔断钉子时不崩**
  （避免「刚装就没网」被误杀）。改过包的人一样拿不到规则，强度和可用性取平衡
- 后台运维页即时保存：开关一改立刻提交、二次确认、状态回显，不再需要先点「保存」再猜

### B. 看门狗：从「单向往返」到真正的双向锁

- 看门狗（HMKit）读主程序 Mach-O 的 `__TEXT` 段算 SHA-256，与**构建期写进二进制的**
  期望值比对。用 `__TEXT` 而不是整文件：重签只动 `__LINKEDIT`，整文件哈希会误杀正常用户
- 主程序反过来校验框架结构：文件在不在、`__TEXT` 段大小、内部标记串
- 主程序把「卡密 + 设备码」交给看门狗，由看门狗用**另一套独立实现**验格式与派生值；
  对不上直接按未授权处理 —— 只 patch 主程序那段校验会被这里挡住
- 增加一串互相牵制的垃圾函数，结果参与每 17 秒一次的自检；改其中任何一个握手就崩
- 构建期注入：`Tools/seal_binaries.py` 先写框架大小、再算主程序哈希、最后写进看门狗。
  顺序不能反，`Tools/verify_seal.py` 在打包前复核

### C. 规则界面去敏感信息

- 设置页不再显示 IP / 域名 / 端口的分项条数、规则集名字、「端口段拦截」开关
- 端口段由模式决定：全局模式自动开、规则模式自动关，不再作为用户选项暴露
- 规则详情页只保留「总条目 / 套数 / 版本 / 同步时间」

### D. 线上安全修复（服务端，与客户端版本无关，已上线）

| # | 问题 | 处理 |
|---|---|---|
| 1 | `public/` 下 9 个 `.bak` 备份可被直接下载 → 服务端源码公开 | 移到 web 根外；nginx 按后缀 deny |
| 2 | `/dl/EntranceFlow.lua` 绕过卡密可直接下载 | 下架；`.lua` 后缀 deny |
| 3 | 无条件信任 `X-Forwarded-For` → 伪造 IP 绕过限流/审计/封禁 | 默认只认 `REMOTE_ADDR`，转发头需显式信任代理 |
| 4 | 设备指纹认领卡密无前置条件 → 可抢占他人卡密 | 原设备必须离线 150 秒才允许认领 |
| 5 | `storage/admin_initial.txt` 明文初始密码长期留存 | 已删；改为权限 600 且登录成功后自动清理 |
| 6 | 旧版本 ipa 长期公开在 `/dl/` | 归档到 web 根外，只留最近两版 |

### F. 发布（build 123）

| 文件 | 大小 | SHA-256 |
|---|---|---|
| HeiMao_Pro_v1.2.4_build123_signed.ipa | 1,382,014 B | 37bad36c5f1f777a2886ab626b5266a44cf949691cd0db84ce7ca68ff6fca0a9 |
| HeiMao_Pro_v1.2.4_build123_unsigned.ipa | 1,359,699 B | 6654dfd844be83a965a88b34e4a4edf6f55ff0b0016791998f95ed5514b4aa75 |

- 双端 1.2.4 / 123，MinimumOSVersion 14.0，三端 755，框架带 _CodeSignature
- 自校验锚点校验通过：签名包与未签名包的 `__TEXT,__text` 哈希一致（c8b235e8…），
  说明 ldid / 巨魔 / ESign 这套重签流程不会触发看门狗的「改包」判定
- 线上版本表 id=11 → 1.2.4 / 123（force_update=1），下载页自动显示最新 build

### E. 版本闸门

后台可设「最低可用 build」：低于该值的客户端拿不到规则包（返回 `force_update`），
不会闪退、不影响登录。客户端把这条错误翻译成「当前版本已停止下发规则，请更新到最新版本」。

**v1.2.3 build 122**（2026-11-21 · iOS14 弹窗修复 / 全局或规则二选一 / 维护与熔断 / 看门狗 / 去掉无用 Swift 兼容库修重签）

### 后台控制台重做（Tailwind · 白色主题）

用户反馈：功能太分散、界面不够企业级。整站前端重写（后端接口一行没动）：

- 技术：Tailwind CSS 3 本地编译，样式内联进单文件 `admin/index.php`（无 CDN 依赖，弱网也不掉样式）
- 白色主题：zinc 中性色 + 单一强调色（近黑），卡片 12px 圆角、1px 边框、极浅阴影
- 信息架构从 8 个散页收成 7 个入口、3 个分组：
  运营（概览 / 卡密 / 设备与配对）、发布（规则与版本 / 公告）、系统（日志 / 设置）
- 概览加了：4 张指标卡、运行状态（版本 / 规则 / 维护 / 熔断）、事件构成占比条、最近活动
- 交互统一：生成卡密、卡密详情、规则集编辑、版本发布全部改成侧边抽屉；
  确认 / 输入改用站内弹窗（不再用浏览器 prompt，手机端也能正常弹）
- 表格：吸顶表头、横向滚动、空状态、批量操作条
- 移动端：侧边栏抽屉 + 顶栏菜单，390px 宽度实测无横向溢出

修掉的问题：登录成功后登录层不消失（`hidden` 属性被 `display:flex` 类覆盖，
用户体感是「点登录没反应」）。改用 `.is-hidden{display:none!important}` 显式控制。

### build 122：修「ipa 没法签名」

现象：1.2.3 build 121 的包，ESign / 爱思重签直接失败；1.2.2 及以前都正常。

根因：1.2.3 新增了动态框架 HMKit，Xcode 顺带给 iOS 14 目标的动态框架塞了
`Frameworks/libswift_Concurrency.dylib`（7.7MB）。用 otool 逐二进制核对：
主程序 / 隧道扩展 / HMKit **都没有链接它**（全是 DispatchQueue，没有 async-await），
纯属白带的死重量。这类苹果自签的大体积 dylib 留在第三方包里，重签工具会直接报错，
包体积也从 1.28MB 涨到 3.88MB。

修复（build.yml 打包阶段）：
- 打包时遍历 `Frameworks/*.dylib`，用 `otool -L` 查主程序 / 扩展 / HMKit 是否引用；
  没引用就删掉，并打印 `PRUNE:` / `KEEP:` 日志
- 加硬校验：若 `libswift_Concurrency.dylib` 仍在包里 → `PRUNE_FAIL` 中断构建
- 结果：包回到 ~1.3MB 量级，结构跟 1.2.2 一致（只多一个我们自己签过的 HMKit）

版本号：1.2.3 / build 122（build 号必须大于 121，否则已装 121 的用户收不到更新）。

### 1.2.3 改动

> 用户反馈：iOS 14 点设置没反应、未激活点「输入卡密」没反应、开防护偶尔断网、拦截状态被截断；
> 同时要服务端的卡密清理、维护、熔断，并把混淆重做。

#### A. iOS 14 两个「点了没反应」

根因不是按钮，是 SwiftUI：同一个视图挂了**两个 `.sheet`**（设置 / 规则详情），
iOS 14 只认最后一个，`showSettings` 永远不生效 —— 所以右上角设置、主界面
「激活卡密」「输入卡密」全部失灵（它们都指向设置页）。

- 改成单一 `.sheet(item: ActiveSheet)`，设置 / 规则详情二选一
- 未激活点圆球时的 `showLicense` 接到同一个弹窗上，不再是一条死路
- 规则详情、设置页的关闭逻辑不变

#### B. 拦截模式：规则 / 全局，主界面直接选

断网的根因：1.2.2 只有一种跑法 —— 默认路由全接管，规则外的流量靠
「补集例外」交回物理网卡。规则 IP 一多，例外表就装不下，退回窄口之后
系统 DNS 又不进隧道，体感就是「一开防护网就断」。

现在主界面两颗按钮：

| 模式 | 路由 | DNS | 适用 |
|---|---|---|---|
| 规则（默认） | 只把规则 IP 段 + 假 DNS 拉进隧道 | split DNS：**只接管要拦的域名** | 正常上网 + 拦规则，最稳 |
| 全局 | 0.0.0.0/0 全接管 + 精确补集例外 | 接管全部域名（CNAME 也拦） | 要拦得更全，路由条数敏感 |

- 规则模式有降级阶梯：精确 → /24 → /20 → 只剩假 DNS，最差也保域名拦截
- 全局模式的补集装不下时**回退到规则模式**，绝不把流量关进隧道再黑洞掉
- 切模式 / 切端口开关会自动重连一次生效（约 2 秒）

#### C. 拦截状态不再被截断

设置页「拦截状态」改成上下两行 + 自动折行（`InfoRow(multiline:)`），
同时把「兼容」一行改成 iOS 14.0 – 27。

#### D. 新 beta 规则的适配

看过线上 beta 包：539 IP / 685 域名 / 2650 端口。

- IP、域名两段客户端本来就认，路由与 split DNS 直接吃
- **`#DIRECT` 段是这次补的**：服务端合并规则时会把放行名单追加成 `#DIRECT`
  （旧站是 `#ALLOW` / `#WHITELIST`）。以前客户端不认这个段头，段里的域名会被
  算成上一个段的规则 —— 白名单直接变成拦截名单。现在三段都能识别，放行优先
- `#PORT` 段 2650 条以前只计数不生效。这次接上了，但**默认关闭**：
  这批端口里含 53 / 80 / 443，按端口全网封会当场断网（授权通道本身走 443）。
  设置页「规则库」里有「端口段拦截」开关，打开后 `AppConfig.corePorts`
  （22/53/80/123/443/853/8080/8443）永远放行

#### E. 维护模式（服务端可控）

- 服务端：设置页新增「维护模式」开关 + 原因，存 `settings` 表
- `/app/version` 每次下发 `maintenance: {on, reason}`
- 客户端：启动 / 每 4 分钟检查，命中就盖一层维护页，正文原样显示原因；
  不闪退，用户可以等维护结束

#### F. 熔断（防破解兜底）

- 服务端：`fuse: { mode: off|all|below, build, reason }`，可全部熔断或指定 build 以下熔断
- 客户端：命中直接崩（写非法地址 + `abort()`），并把结论**钉在本地** ——
  下次断网启动也照样崩；版本追上阈值后自动拔钉
- 只对拿得到云端结论的版本生效；改包拿不到正常版本号也逃不过

#### G. 看门狗 dylib（HMGuardKit）

- 新增动态库 target `HMGuardKit`，主程序 `import` 并嵌入 `Frameworks/`
- 互相校验：看门狗每秒出随机挑战，主程序用派生密钥回 HMAC；主程序每秒报心跳，
  停 6 秒即判；主程序同时校验看门狗心跳与签名。任一侧连续三次不对 → 一起崩
- 删掉 dylib 主程序起不来（LC_LOAD_DYLIB 缺库），只 patch 一侧也过不了握手
- 首次心跳前不按「停摆」判死，避免极端环境下误崩

#### H. 混淆重做

原来只有「顶层类型改名」一层。这次加了两层：

1. **构建期字符串加密**（`Tools/obfuscate_strings.py`）
   - 安全核心（Sources/Shared）里 300+ 条字面量在打包时替换成 `StrBox.d([...])`，
     运行时按内置密钥表异或还原；二进制 `strings` 不到路由、错误码、路径
   - 逐字符扫描字面量边界，含转义/插值的跳过，`case "...":` 模式位置跳过
2. **构建选项加固**：wholemodule 编译、dead_strip、STRIP_SWIFT_SYMBOLS

CI 产物自检仍然是 `OBF_OK` / `SYMBOL_OK`，并新增看门狗框架嵌入校验。

---

## 当前版本

**v1.2.2 build 120**（2026-11-20 · 后台常驻 / 心跳下沉扩展 / 切网自愈 / 不再误断）

### 1.2.2 改动

> 用户反馈：1.2.1 挂后台经常断，心跳也断。这一版专治后台存活，不加功能。

#### A. 三个真正的断线原因

1. **App 侧把「窗口过期」当成「授权失效」直接停隧道**
   `verifyNow` / `refreshLicense` 里只要 `isUsable() == false` 就 `tunnel.stop()`。
   而 `isUsable()` 把「在线窗口过期」（后台久了、刚切网还没校验上）也算 false ——
   于是一回到前台、网络还没恢复的那一下，正在跑的防护就被掐了。
   现在新增 `LicenseState.isHardInvalid`（作废 / 到期 / 封禁 / 强下线 / 卡密为空），
   只有它才停隧道；窗口过期只提示，下一次心跳成功自动恢复。

2. **心跳完全依赖 App 进程，一进后台必然断档**
   iOS 会把 App 冻结，主线程 Timer 全停。以前心跳只在 App 里跑，后台 10 分钟窗口就凉了。
   现在心跳下沉到隧道扩展：`keepAliveTimer` 每 5 分钟调 `/renew`（服务端窗口 600 秒，
   留两次余量），每 15 分钟做一次真实 `/check`。App 在不在、开没开，在线状态都一样。
   App 侧前台心跳从 60 秒放宽到 90 秒，进后台只补发一次（用 25 秒后台额度），
   不再靠被冻结的定时器硬撑。

3. **按需连接没写进去就再也拉不回来**
   部分环境（伪签名 / 巨魔 / 系统升级后）`saveToPreferences` 会吞掉 `isOnDemandEnabled`
   但照回成功。隧道掉一次，系统不会拉回，用户看到「自己断了再也不恢复」。
   新增 `TunnelController.healOnDemand()`：回前台核对一次，被吞掉就补写并读回确认。
   另加 `protectionGuard`：用户明确开过、授权没硬失效、隧道却断着 → 自动重连
   （45 秒节流、连续 8 次失败停手、只在第一次提示「已自动恢复防护」）。

#### B. 切网 / 锁屏之后拦截失效

隧道设置里的 DNS 与路由绑在启动时那套网络上。WiFi ↔ 蜂窝 切换、锁屏醒来之后
不重放一次设置，表现就是「VPN 显示已连接、域名一条都不拦、网还慢」。
新增 `NWPathMonitor`：只在「断网→有网」或「蜂窝 ↔ WiFi 换接口」时，延迟 1.2 秒
用最后成功的方案重放 `setTunnelNetworkSettings`（不重算路由，代价最小）。
`wake()` 同时去掉 `phase == "running"` 的硬条件 —— 系统重起扩展时 phase 是 starting，
以前卡住就等于「连着但一个包都不读」。

#### C. 后台资源占用（被系统回收的根因）

| 项 | 1.2.1 | 1.2.2 |
|---|---|---|
| 统计落盘 | 每 2 秒无条件写 4 个路径 + `synchronize()` | 有变化才写，空闲 30 秒保温写一次；去掉 synchronize |
| DNS 上游 | 每个查询往全局队列丢 3 个任务 + `group.wait` | 一个线程 poll 三个 fd，线程数恒定 6 个 |
| DNS 缓存 | 1024 条，满了盲砍前 256 条 | 512 条，先按过期清再砍最老的一半 |
| RST 去重表 | 4096 | 2048 |

扩展是长期驻留的，一天几万次原子写盘 + 线程数浮动，会被系统按资源占用回收 ——
这就是「挂久了断」的经典形态。

#### D. 版本

- `AppConfig.appVersion = 1.2.2` / `buildNumber = 120`
- `offlineGrace` 10 分钟 → 30 分钟（硬失效不走宽限，安全性不变）
- 新增 `tunnelBeatInterval = 300` / `tunnelVerifyInterval = 900` / `statsPublishInterval = 10`

#### E. 最低系统降到 iOS 14

用户要求 1.2.2 覆盖 iOS 14–27（原为 15.0 起）。

- `project.yml`：`deploymentTarget.iOS` 与 `IPHONEOS_DEPLOYMENT_TARGET` 均改为 `14.0`
- CI 硬校验同步改为 14.0（`COMPAT_OK: iOS 14.0 起装，向上兼容 iOS 27`）
- 全量扫过 iOS 15+ API，实际只有两处，都已补兼容：
  - `.animation(_:value:)` → 新增 `View.animate(_:value:)`，15 以上走按值动画，
    14 退回旧签名（这些动画都只挂在一个属性上，观感一致）
  - `.alert(_:isPresented:actions:message:)` → 改回 `Alert(title:message:primaryButton:secondaryButton:)`
- 其余 UI 全部是 iOS 13/14 就有的写法（自绘玻璃球、GridPattern 是自定义 Shape，
  不是 SwiftUI Grid；`presentation.wrappedValue.dismiss()` 是 iOS 14 的老 API）
- 运行时新增的 `NWPathMonitor` / `UIBackgroundTask` 都是 iOS 12/4 起可用

### 1.2.2 上线记录（2026-11-20 00:55 北京时间）

- 包：`HeiMao_Pro_v1.2.2_build120_signed.ipa`（1,288,823 B）、`_unsigned.ipa`（1,270,167 B）
- sha256：签名 `dd97f5b11d86b70c19a6c93dfaf98d94c0eaf7865a1995c124fd65e107dd6763`
  / 未签 `a259d95ff0dc637fa124a2729866f6a79372344f9dc3997fdfc7f6fae268f53e`
- 核对：双端 1.2.2 / 120、MinimumOSVersion 14.0、双端 755、双端签名段、
  双端含 networkextension + platform-application 权限段、包内无 rules.txt、OBF_OK / SYMBOL_OK
- 线上：`https://ios.ouovo.cc` 已指向这版，两个地址实测 206（可下载），页面显示 iOS 14–27
- 版本表：1.2.2 / 120，force_update = 1；1.2.1 记录置为 inactive
- 公告已换成 1.2.2
- 服务端：在线判定窗口 150 → 300 秒（`CardService::stats` 两处、`SessionService::online` 默认值），
  配合扩展 150 秒心跳；备份在 `/root/bak-beat-20261119_161712/`
- 下载页文案：iOS 15 → iOS 14（备份 `/root/bak-index-*.php`）

### 待验证（需真机）

- 挂后台 2 小时以上不断、回前台「心跳」秒数新鲜
- WiFi ↔ 蜂窝 切换后仍能拦截（进规则域名应该连不上）
- 服务端「在线设备」页在 App 后台期间仍显示在线

## 上一版：v1.2.0 build 118（2026-11-19 · 通道收口 / 卡密分层 / 封禁与强制下线 / CRC 链）

### 1.2.0 改动

#### A. 加密通道 v4：抓包只剩随机字节

v3 的问题不是不安全，是「太明显」——`{"v":3,"n":…,"e":…,"sig":…}` 一眼看出结构。

v4：
- 请求体 = `iv(12) || AES-256-GCM 密文 || tag(16)`，`Content-Type: application/octet-stream`
- 响应体同样格式，**没有任何 JSON 信封、没有自定义头、业务错误也在密文里**（HTTP 恒 200）
- 每条请求独立密钥：`HKDF-SHA512(master, salt=iv, info="hm4/req")`，响应用请求 iv 派生
- 签名 `HMAC-SHA512("h4|路由|设备码|ts|ivhex|sha256(参数规范串)")`，改一个字节/换个路由/晚 5 分钟重放全过不去
- **客户端只走 v4，不降级**：v3 信封、明文+HMAC 降级、候选密钥重试链全部删除；
  通道对不上直接报错要求升级，绝不退回可被抓包的旧协议
- 服务端：客户端业务接口不再接受无签名明文（`secure_channel_required`）；
  后台 / 公开公告 / 下载轮询保留
- 存量兼容：`allow_v3` / `allow_v2p` 两个开关（config，默认开）
  —— 老客户端还能用 v3 过渡，想彻底停掉把 `allow_v3` 设 0 即可
- v4 的错误响应也走密文：抓包仍只有随机字节，客户端能读懂 stale_request / replay 等原因

#### B. 卡密按版本分层（free / beta / pro / max）

- `cards.tier`：一张卡密绑定一个版本，老卡密默认 pro（行为不变）
- `rule_sets.tiers`：每套规则可指定下发给哪些版本（空 = 全部）
- 下发按层合并：同一版本拿到「自己那层可见的规则集」合并包；内容相同的层共用一份
- `rule_packs.tier`：分别生成 `free` / `pro,max` / `all` 等快照，客户端按卡密自动取
- 后台：生成卡密时选版本；规则集表单可勾选下发版本

#### C. 封禁原因 + 在线心跳 + 强制下线

- `cards.ban_reason` / `banned_at`：封禁必须带原因，后台列表直接显示
- 客户端收到 `card_revoked` 时带上原因，界面显示「这张卡密已被封禁：xxx」
- 心跳：`pins.last_beat` / `app_ver`（renew 时刷新）
- 后台「在线设备」页：150 秒内有心跳算在线，显示版本/IP/授权状态
- 强制下线：`pins.kick_at` / `kick_reason` → 客户端心跳拿到 `kicked` → **断开 VPN + 清空规则**，显示原因；后台点「解除下线」才恢复

#### D. 客户端 CRC 环环校验

- 构建期 `Tools/gen_crc.py` 把每个源文件 CRC32 写进 `IntegritySeal.swift`
- 运行时 `arm(stage) → checkA → checkB → checkC` 逐层依赖复算，任一层不符链就断
- 四个关键入口挂链：`SecureChannel.post`(0) / `LicenseClient.apply`(1) / `check`(2) / 隧道启动(3)
- 结果只上报（`itg=crc`）并取消「本地信任」，不阻断正常用户（自签/巨魔本来就会改包）
- `Tools/rename_types.py` 加保护名单，`IntegritySeal` 不参与改名（生成脚本按原名写）

#### 卡密版本现状

- 2026-11-19：服务端现存 **351 张卡密全部改为 MAX**（改前 pro=351），逐张生效于下次校验
- 规则集当前 tiers 为空 = 全版本下发，MAX 卡拿到全部规则

#### 服务端上线记录（2026-11-19 22:03 北京时间）

- 备份：`/root/backup_before_120_20261119_220329.tgz`
- 迁移自动加列（cards.tier/ban_reason/banned_at、pins.last_beat/app_ver/kick_at/kick_reason、rule_sets.tiers、rule_packs.tier）
- 线上验证：
  - v3 通道（老客户端）签名/解密/业务回包正常
  - v4 通道 211~230 字节纯密文，解密得到完整业务 JSON
  - 后台登录、公告、规则下发正常
- 测试副本验证（/tmp/hmtest）：卡密生成带 tier、规则集按层生成 `free` / `pro,max` 两套快照、max 卡拿到 pro,max 包、在线列表、踢下线后 `reason=kicked`

#### 1.2.0 构建与上线（2026-11-19 22:1x 北京时间）

- 构建 run `44541180105`（commit `5354afa`），macos-26 / macos-26-intel / macos-15 均 success
- 签名包 `/dl/HeiMao_Pro_v1.2.0_build118_signed.ipa`（1,265,646 B，sha256 `21a73a8…f95df1`）
- 未签包 `/dl/HeiMao_Pro_v1.2.0_build118_unsigned.ipa`（1,247,827 B，sha256 `86a84e0…c411d2`）
- 已核对：主程序/扩展均 1.2.0 / 118、MinimumOSVersion 15.0、双端 755、
  二进制里 `hm4/req` / `heimao-v3-salt` / master key 全部搜不到（常量仍走混淆表）
- 线上：`app_versions` 新增 1.2.0 / 118（force_update=1），两个下载地址实测 200、回读哈希一致
- 公告更新为「1.2.0 已发布 / 安全通道全面升级」
- 线上实测：v4 正常（211 字节纯密文可解）、v3 存量兼容正常、无签名明文客户端请求被拒、
  stale_request 返回 64 字节密文错误

#### 待验证

- iOS 真机：v4 通道实际连通、版本徽章、封禁提示、强制下线后的断连行为

---


## 当前版本

**v1.1.1 build 117**（2026-11-19 · 修「拦不完整 + VPN 老断开」）

### 1.1.1 改动（两个线上反馈：拦截不完整 / 隧道频繁掉线）

#### A. VPN 老断开：四个主动/被动断开点全部收掉

1. App 侧心跳：`renewFailures >= 2` 就 `RuleService.clear()` + `tunnel.stop()`
   —— 60 秒一次，网络抖两分钟就断。改为只提示，不停隧道、不清规则。
2. 扩展侧复核：`verifyFails >= 2` 就 `dropProtection(heartbeat_lost)`
   —— 5 分钟一次，锁屏/切网必踩。改为只计数，只有服务端明确返回
   `authorized:false` 才断。
3. 启动 20 秒的 `stray > 75%` 自动断开检查：窄口下规则 IP 的非目标端口、
   全接管下 DNS 转发都会计入 stray，正常使用也会被误判。整段删除。
4. 热更新兜底 `restart()` 与 onDemand 撞车：先关 onDemand 再 stop，停稳 1.8 秒再起。

#### B. 掉线不自动回来：补上按需连接

- `manager.isOnDemandEnabled = true` + `NEOnDemandRuleConnect()`
- 伪签名/巨魔环境不认 onDemand 时自动退回普通保存，不影响开启
- 手动关闭时先关 onDemand 再 stop，避免"点了关闭又被系统拉起来"

#### C. 拦截不完整：路由回到全接管 + 精确例外

- 1.1.0 窄口（只把 275 条规则 IP 拽进隧道）的硬伤：iOS split 隧道下系统 DNS
  经常不进隧道 → 213 条域名规则等于没生效
- 1.1.1：`included = 0.0.0.0/0`，`excluded = 精确补集`，阶梯 精确 → /24 → /20
  - 当前规则算下来精确补集 3362 条（1.0.11 验证过 2708 条可用）
  - 装不下自动退 /24（约 1734 条），再退窄口，再退 DNS-only，逐档兜底
  - 假 DNS /32 与本机地址从补集里挖掉，保证留在隧道内
- DNS 转发应答加 CNAME 链检查：规则里配的是 CNAME 目标时，只看 qname 会漏
- DNS 上游改三路并行竞速（600ms），原来是串行 900ms×3；全失败回 SERVFAIL，
  不再让客户端干等超时

#### D. 引擎稳定性

- DNS 转发从 concurrent + semaphore(8) 改成 6 个固定串行 worker：
  原来网页一开几十个域名并发，每个阻塞 2.7 秒，GCD 线程数一爆扩展就被系统回收
  —— 这也是"VPN 老断开"的一条根因
- `sleep/wake` 处理：唤醒后按需重建读包循环（60 秒无包才重建，幂等）
- 统计加 `routeMode`（full/narrow）、`dnsFail`

#### 待验证

- 本机无 Xcode / 真机，包结构、版本号、双端权限、路由方案参数静态核对
- 需真机确认：设置页「拦截状态」应显示「全接管 · 例外 3362 条」或「例外 1734 条」
- 若走窄口说明全接管装不下，把整行发回来

### 上线记录（2026-11-19 11:45 北京时间）

- 构建 run `44452517256`（commit `8eb93e3`），四个 macOS 机型全部 success
- 签名包 `/dl/HeiMao_Pro_v1.1.1_build117_signed.ipa`（1,265,453 B，sha256 `f098b01b…b59754`）
- 未签包 `/dl/HeiMao_Pro_v1.1.1_build117_unsigned.ipa`（1,247,758 B，sha256 `74fdc92f…5972c`）
- 已核对：主程序/扩展均 1.1.1 / 117、MinimumOSVersion 15.0、双端 755、
  entitlements 含 platform-application + packet-tunnel-provider、包内无规则文件、
  二进制含新逻辑（「全接管 · 例外」/「服务端暂时连不上」），旧「心跳连续失败」已消失
- 服务端 `app_versions`：1.1.1 / 117，`force_update` 保持 1，url 仍是 https://ios.ouovo.cc
- 线上两包 HTTP 200，回读 sha256 与本地逐字节一致；下载页显示「1.1.1（117）」
- 服务端规则未改：仍为 `Max beta`（id=8，启用，275 个去重 IP / 213 域名 / 1953 端口）

---

## 1.1.0 build 116（2026-11-19 · 拦截内核按 ACE 3.0 同构重写）

### 1.1.0 改动（大版本：拦截模式换了，不是调参）

按《HeiMao_Pro 拦截逻辑实现工作文档》落地，逐条对应：

1. 路由模型：全接管 → 窄口
   - 旧：includedRoutes = 0.0.0.0/0，靠 2700 多条补集例外把非规则流量放回去（补集一超上限就降级成 split，域名规则静默失效）
   - 新：includedRoutes = 规则里的 IP 段（261 条 CIDR）+ 假 DNS 10.111.0.1/32，不生成补集
   - 非规则流量压根不进隧道，用户不会因为路由算错被断网
2. DNS：命中域名答 `0.0.0.0` / TTL 60（与 ACE 逐字节一致：`C0 0C 00 01 00 01 00 00 00 3C 00 04 00 00 00 00`）
   - 非 A 查询（AAAA / HTTPS / SVCB）一律 NODATA：ANCOUNT=0，不放任何地址，避免 Happy Eyeballs 走 v6 绕过
   - 应答源地址跟随查询目标，源端口固定 53；未命中走上游 223.5.5.5 → 119.29.29.29 → 114.114.114.114
3. TCP RST：40 字节定长（ID 0 / DF / TTL 64 / window 0），握手包 seq=0 + RST|ACK + ack=对端 seq+1
   - 已建立连接仍用 RFC 793 的写法（seq 取对端 ACK、不带 ACK 位），否则会被当窗口外乱包丢掉、体感变成等超时
   - 已用文档 4.5 的十六进制向量逐字节核对通过
4. 规则解析改成 ACE 的状态机契约
   - 段头：剥 `#` / `//` / `;` 后 startsWith `IP` / `DOMAIN` / `域名` / `PORT` / `端口`
   - 第一个段头之前的内容丢弃；IP 行支持 `/N`、`:端口`、`:起-止`、`,DIRECT` / `,ALLOW`
   - 域名行：去 DIRECT → 小写 → 去 scheme → 第一个 `/` 截断 → 去行首点；天然含子域
   - 端口段照原版只入集合、不参与判定
   - 兼容层保留 hosts / dnsmasq / AdGuard 写法，老云端规则包不会解析成空
5. 规则集不进包，全部走服务端下发
   - 新增服务端规则集 `Max`（id=8）：276 IP / 757 域名 / 1953 端口，已勾选下发
   - 当前下发快照 `20261119.0039.2s.9e86b2`：Pro + Max 合并 = 276 IP / 1331 域名 / 1953 端口（41883 B）
   - 包内不再放 rules.txt，客户端只从云端取（老 1.0.x 客户端也能解析这份合并包）
6. 统计与诊断
   - 诊断行改成「收包 · DNS · 拦截 · 心跳 · 阶段 · 规则接管·路由 N 条 · 通道」
   - `routeCount = 0` 时标「无 IP 路由·仅域名拦截」，不再有已删除的降级文案

### 已验证 / 未验证

- 已验证：服务端 Max 规则落库 276 / 757 / 1953，下发合并包 276 / 1331 / 1953 分段完整、
  路由 CIDR 261 条（相邻 /32 合并）、
  `szmg.qq.com` 命中、`notszmg.qq.com` 不命中、RST 40 字节向量与文档完全一致
- 未验证：iOS 真机上的实际拦截效果（本机没有 Xcode / 设备），需要装上跑

### 上线记录（2026-11-19 00:5x 北京时间）

- 构建 run `44349996534`（commit `0948c2d`，macos-15-intel 先出包，其余机型并行在跑）
- 签名包 `/dl/HeiMao_Pro_v1.1.0_build116_signed.ipa`（1,260,149 B，sha256 `064b315c…23cb0`）
- 未签包 `/dl/HeiMao_Pro_v1.1.0_build116_unsigned.ipa`（1,242,759 B，sha256 `f0a683b9…2e3e`）
- 服务器端两个文件与实际包逐字节一致（sha256 回读比对）
- 版本表 `app_versions`：1.1.0 / 116，`force_update` 保持 1 未动
- 下载页自动认最新 build，已显示「1.1.0（116）」两个下载按钮，URL 实测 200
- 服务端规则：rule_sets 新增 `Max`（id=8，enabled=1，276/757/1953），
  下发快照 `20261119.0039.2s.9e86b2`（Pro + Max，276 IP / 1331 域名 / 1953 端口，41,883 B）
- 包里不含任何规则文件（已 `find` 过，rules.txt 为 0）

---

## 1.0.12 build 115（2026-11-18 · 文案去公益口径 + 频道改官方 + 公告完整换行）

### 1.0.12 改动（纯 UI / 文案，拦截核心与路由一行未动）

1. 去掉「公益免费」口径
   - 主界面 footer：`黑猫拦截 Pro · 公益免费 · 不采集任何流量内容` → `黑猫拦截 Pro · 全网最强 · 不采集任何流量内容`
   - 设置页 footer：`公益免费 · @HeiMaoClub` → `全网最强 · @HeiMaoClub`
2. 频道口径改官方
   - 主界面频道卡标题：`公益频道` → `官方频道`
   - 设置页关于：`加入公益频道` → `加入官方频道`
   - 内置兜底公告第 5 条：`请到公益频道` → `请到官方频道`
3. 主界面公告换行 / 截断
   - 标题原来 `lineLimit(1)`，长标题被截成一行省略号 → 改为不限行 + fixedSize，标签 `fixedSize()` 不再挤压标题
   - 正文原来是 `lineLimit(2)`（收起态只有两行）→ 收起态 5 行、展开不限行
   - `announcementOpen` 默认 `false` → `true`，进 App 第一眼就是公告全文
   - 文本列补 `frame(maxWidth: .infinity, alignment: .leading)` + `layoutPriority`，卡片宽度全用上
   - 设置页公告标题 `lineLimit(1)` → 2 行
4. 下载页（服务端 public/index.php）：`公益频道` → `官方频道`；`仅供学习与公益使用` → `仅供个人学习与使用`
5. 版本：`AppConfig` 1.0.12 / 115，`project.yml` MARKETING_VERSION 1.0.12 / CURRENT_PROJECT_VERSION 115

### 现场事实

- 云端公告（announcements id=1）实际是三行 71 字：
  `感谢使用黑猫拦截，本系统当前已开启付费` / `当前下发规则：Pro版（v2026.11.17）` / `希望大家多多订阅我们的频道： @HeiMaoClub`
  收起态只显示两行 → 第三行看不到，这就是用户说的「字看不全」

### 上线记录（2026-11-18 18:06 北京时间）

- 最终包：`/dl/HeiMao_Pro_v1.0.12_build115_signed.ipa`（1,255,816 B，sha256 `44a20b83…4f86`）
- 未签：`/dl/HeiMao_Pro_v1.0.12_build115_unsigned.ipa`（1,238,257 B，sha256 `b31cfbb1…f6d3`）
- 构建 run 44281576876 / 3c82ec2（macos-15 先出包）
- 首轮 44281077030 作废在权限位：ldid 签名后把 appex 重置成 644，iOS 会拒绝加载扩展。
  已在 workflow Pre-sign 之后补 `chmod 755` + 打包后 `unzip -Z` 硬校验，再打包
- 已核对：主程序与扩展均 1.0.12 / 115、MinimumOSVersion 15.0、双端 755、
  entitlements 含 platform-application + networking.networkextension、签名段在
- 二进制内「公益」出现 0 次、「全网最强」1 次、「官方频道」2 次
- 版本表 `app_versions`：1.0.12 / 115，force_update 保持 1，min_version 1.0.0
- 线上两包实测 200，sha256 与本地逐字节一致；下载页已自动指向 1.0.12
- 备份：`/root/app.db.bak_115_1806`
- 传输方式：GitHub release 临时资产（用后已删）→ 服务器 curl 拉取

### 待验证（我这边没有 iOS 真机）

- 公告在 iPhone 上的实际换行效果、长标题是否折行正常 —— 需装上后看一眼
- 设置页底部、频道卡文案

## 历史版本

**v1.0.11 build 114**（2026-11-18 · 服务端换新规则后不拦截的根因修复）

### 现场事实（用户实测）

- 拦截本身好（1.0.10 之前装的那版能拦住）
- 用户换服务端新规则后：「数据包好像不拦截下发的」

### 根因：路由补集的条数越过了写死的上限，整档被放弃 → 降级成 split

- 老规则（id=33）：108 条 IP → 合并 105 区间 → 补集 **1553** 条 CIDR
- 新规则（id=35，当前 active）：196 条 IP → 合并 188 区间 → 补集 **2708** 条 CIDR
- `routePlan(maxRoutes: 2600)`：2708 > 2600 → 直接返回 `degraded=true`（只接管规则段）
- 而 `plans = [exact, wide24, wide16, split]`：degraded 的 exact 照样能装成功，
  `applyRoutePlan` 第一个成功就停 → 永远走不到 wide24，隧道永远停在 split
- split 模式下 iOS 不把系统 DNS 交给隧道 → 域名规则一条都碰不到
- 附带 bug：`wide24.hijackAll = plan.hijackAll` 把降级状态传给了更好的方案（逻辑错）

### 1.0.11 改动

1. `RuleSet.routePlan` 的 `maxRoutes` 2600 → 9000（新规则 2708 条现在能全接管）
2. `makeRoutePlans`：候选改为「精确 → /24 → /20 → 只接管规则段」逐级回退，
   只有全都装不下才退 split；修掉 `hijackAll` 被覆盖的错
3. 规则热更新后 `rebuildRoutes()` 重设网络设置，按新规则重算路由
   （原来只换 ruleSet 不换路由，新增规则 IP 仍躺在 excludedRoutes 里）
4. `pushRules` 带 2 秒回调，送不进扩展就重启隧道；`checkRuleFreshness` 每 15 分钟比对服务端规则版本
5. 诊断行在降级时追加「分段模式(域名不建议)」

### 上线记录（2026-11-18 11:54 北京时间）

- 最终包：`/dl/HeiMao_Pro_v1.0.11_build114_signed.ipa`（1,252,724 B，sha256 `a648c98e…e76e`）
- 未签：`/dl/HeiMao_Pro_v1.0.11_build114_unsigned.ipa`（1,235,587 B，sha256 `c5928282…0d66`）
- 首轮构建（bf24228）只作废在「说明书」这一步：降级文案改成「分段模式·域名不拦」后重出（6f568c4）
- 两包实测 200、sha256 与本地逐字节一致；首页已自动指向 1.0.11
- 版本表：1.0.11 / 114，force_update=1，min_version 1.0.0
- 构建 run 44233326105 / bf24228（macos-26 先出包）
- 传输方式：GitHub release 临时资产 → 服务器 curl 拉取（不再分块 base64）
- 备份：`/root/app.db.bak_114_1154`

### 账：规则规模继续长会怎样

精确补集条数 ≈ 2 × 离散 IP 段数。9000 上限大约能撑到 4000 条离散 IP 段；
超过就自动退到 /24 聚合（补集减半，代价是同 /24 里没列进规则的地址会进隧道、
引擎不转发 → 那部分连不上）。所以服务端规则里的 IP 尽量用 CIDR 段写、能合并就合并。

## 历史版本

**v1.0.10 build 113**（2026-11-18 · 统计改走本机直连通道）

### 现场事实（用户实测）

- 1.0.7 / 1.0.8：拦截有效，面板「收包 / DNS / 旁路」全是 0
- 1.0.9：设置页直接显示「隧道已连接，但扩展没回传统计」—— 说明连一份快照都没拿到

### 结论：1.0.9 的两条通道在这个环境下都走不通

`sendProviderMessage`（官方消息回调）和「扩展写共享目录 / 主程序读」这两条，
都依赖签名环境和沙箱放行。伪签名（巨魔）场景下：
- 消息回调整条失效（隧道照样在跑、照样在拦）
- 应用组容器 / 公共缓存目录的写入被静默拒绝（`try?` 吞掉，看不出来）

于是数字一步都送不出来，而拦截本身完全正常。

### 1.0.10 的做法：本机回环直连（新增，主通道）

- 扩展启动第一件事起一个小服务：`127.0.0.1:47831`（备用 47832 / 47833），
  只监听回环，外部连不进来
- 主程序每 3 秒连一次，发 `HMSTATS\n`，扩展回一份 JSON 统计
- 不经过沙箱共享目录、不走消息回调、不依赖签名 —— 环境挡不住
- 原两条通道全部保留：直连失败 → 消息回调 → 落盘快照，谁先给数字用谁
- 设置页「拦截状态」末尾会标出用的是哪条通道：`本机直连` / `隧道回包` / `扩展落盘`

### 上线记录（2026-11-18 02:42 北京时间）

- 包：`/dl/HeiMao_Pro_v1.0.10_build113_signed.ipa`（1,246,142 B，sha256 `571d5708…582c`）
- 未签：`/dl/HeiMao_Pro_v1.0.10_build113_unsigned.ipa`（1,229,337 B，sha256 `37958539…50d5`）
- 下载页自动取最新 build，已指向 1.0.10；两个地址实测可下、回传 sha256 与本地逐字节一致
- 版本表 `app_versions`：1.0.10 / 113（`force_update` 保持 0，用户自己在测）
- `/api/app/version?current=1.0.10` 实测：`update_available=false`
- 传输方式：临时 PHP 接收口 POST 整包（传完立刻删除接收口），不再分块
- 构建：run 44149853697 / b076f8a，macOS 两个机型成功

### 顺带修掉的隐患

- `statsPayload()` 之前会被四个地方同时调用（定时器 / 消息回包 / 落盘 / 直连），
  而规则热更新会在主线程换 `ruleSet` —— 加 `payloadLock`，避免读到半个规则集
- 监听线程自己关监听口（跨线程 close 会跟 accept/poll 抢同一个 fd 号）


## 当前版本

**v1.0.9 build 112**（2026-11-18 · 统计通道重做）

### 现场事实（用户实测）

- 1.0.7 / 1.0.8：**拦截有效**（规则内域名被拦），但面板「收包 / DNS / 旁路」一直是 0
- 说明隧道在跑、DNS 进了隧道、引擎在拦 —— 坏的只是「扩展 → 主程序」的统计通道

### 这次改的三处（只动统计，不动拦截）

1. **VPN 配置选取**（`TunnelController.pick`）
   以前一律取 `loadAllFromPreferences().first`。设备上只要残留过一条旧配置
   （重装、改 bundle id、手动新建都会留下），拿到的可能就是那条早已断开的，
   于是 `session.status == .connected` 永远不成立，统计一条都发不出去。
   现在优先取在连接 / 恢复中的那条，其次取 bundle id 对得上的。

2. **统计落盘改成多路径全覆盖**（`StatsBridge`）
   以前「第一个路径写成功就走」，App Group 容器拿得到路径却写不进去时，
   退到 `UserDefaults(suiteName:)` —— 那个域在两个进程里各是一份，
   等于写了个只有扩展自己看得见的文件，App 永远是 0。
   现在 App Group / `/var/mobile/Library/Caches/com.heimao.interceptor` / 临时目录
   全部各写一份，App 读的时候取 `bridgeAt` 最新的那一份。

3. **统计拉取与启动时序**
   - `fetchStats` 不再因为 `status != .connected` 直接返回空（reassert 期间会整条掐断），
     超时 1 秒放宽到 2.5 秒
   - 授权校验从「启动前必过」挪到「隧道起来 3 秒后异步做」，网络慢不再拖垮启动窗口
   - 扩展从 `startTunnel` 第一毫秒起就写心跳，快照带 `phase`
     （starting / running / failed:原因 / stopped:原因）

### 上线记录（2026-11-18 02:31 北京时间）

- 包：`/dl/HeiMao_Pro_v1.0.9_build112_signed.ipa`（1,240,813 B，sha256 `07b2e010…ef04`）
- 未签：`/dl/HeiMao_Pro_v1.0.9_build112_unsigned.ipa`（1,223,706 B，sha256 `21749ac8…3c63`）
- 下载页自动取最新 build，已指向 1.0.9；两个地址实测 200、大小与源文件一致
- 版本表 `app_versions`：1.0.9 / 112，`force_update` 保持 1，`min_version` 1.0.0
- `/api/app/version` 实测：`update_available=true`、`force_update=true`、`latest=1.0.9/112`
- 备份：`/root/app.db.bak_112_0230`
- 传输：两包 xz 压缩后经命令通道分块 base64 推送（75 块），落地 sha256 与本地逐字节一致

### 统计通道为什么必须走 App Documents

`sendProviderMessage` 是官方通道，但它只能问「当前 manager 那条连接」；
App Group 容器在 TrollStore 伪签名下经常拿得到路径却写不进去；
`UserDefaults(suiteName:)` 在两个进程里各是一份，等于没共享。
所以这次由主程序在 `providerConfiguration` 里带上自己的 Documents 路径，
扩展照这个路径写 —— 容器是本 App 自己的，权限一定通。

### 诊断行现在长这样

设置页最下面「拦截状态」：

```
收包 128 · DNS 46 · 拦截 12 · 心跳 2秒前 · running · 全接管 · 例外 1577 条 · 扩展落盘
```

- 拿不到任何统计 → 直接显示「隧道已连接，但扩展没回传统计（通道断了，不是没流量）」
- `心跳 N秒前` 一直在涨 → 扩展进程没了
- `phase failed:*` → 隧道卡在哪一步直接写出来


## 当前版本

**v1.0.8 build 111**（2026-11-18 · 计数修复上线）

### 这次修的是什么（拦截有效但数字不动）

- `provider` 回统计时把 `dns` 计数覆盖成了 DNS 地址字符串，App 侧 `as? Int` 恒读 0 → 字段改名 `dnsServer`，计数单独回
- DNS 缓存命中后走「缓存直接拦」分支，那条路原来不加计数 → 缓存命中现在照样计入拦截数
- 统计加第二条通道：扩展把快照落盘（App Group / 缓存目录），`sendProviderMessage` 回包丢失时 App 直接读快照
- 回包加 1 秒硬超时，不再因为不回调让面板整块停在 0
- 数字解析兼容 NSNumber / String；隧道重连 30 秒内接续计数不清零
- 设置页「拦截状态」显示统计来源（隧道回包 / 扩展落盘 / 上次快照）

### 上线记录（2026-11-18 02:12 北京时间）

- 包：`/dl/HeiMao_Pro_v1.0.8_build111_signed.ipa`（1,239,270 B，sha256 `4c401cff…c0fe`）
- 未签：`/dl/HeiMao_Pro_v1.0.8_build111_unsigned.ipa`（1,222,262 B，sha256 `5997204b…55e5`）
- 下载页主入口 → 签名包；「备用 IPA」展开后 → 未签名包；两个地址实测 200、大小与源文件一致
- 版本表 `app_versions`：1.0.8 / 111，`force_update` 保持 1，`min_version` 1.0.0
- 传输方式：两包合并 xz 压缩后经命令通道分块 base64 推送（单条上限 32KB，共 73 块），落地 sha256 与本地逐字节一致


## 当前版本

**v1.0.7 build 110**（2026-11-18 · 拦截核心按 ACE 拦截 APK 的思路重写）

### 1.0.7 改了什么

**根因（对照 APK 反编译结果）**

ACE 拦截 2.0 的做法：`addDnsServer` 把系统 DNS 指到隧道内 `10.111.0.1`、`addRoute` 把
规则 IP 段逐个拉进隧道、53 端口全部自己应答、命中域名回黑洞、命中 IP 直接 RST。

我们 iOS 侧有两个硬伤：

1. **规则 IP 段一条都没进隧道** —— `TunnelController` 从来没给 `conf["routes"]` 赋值，
   隧道里只有 DNS /32 和黑洞 /32 两条路由，IP 规则永远命不中。
2. **iOS 在 split tunnel 下经常不把 DNS 交给隧道** —— 只接管几个网段时，
   系统的 DNS 查询仍走物理接口，`NEDNSSettings` 等于摆设，域名规则一条都碰不到。
   这就是「装了、开了、一点没拦截」的直接原因。

**修法**

- 路由改成「默认路由指向隧道 + excludedRoutes 放规则补集」：
  `included = 0.0.0.0/0`，`excluded = 规则之外的地址（CIDR 精确补集，实测 1577 条）`。
  隧道成为默认出口 → DNS 设置必然生效；真正进隧道的仍然只有规则 IP 段，
  其余流量照常走 Wi-Fi / 蜂窝，速度不受影响。
- DNS 代理地址与黑洞地址从补集里挖掉，保证它们留在隧道内。
- 隧道内**任何 53 端口的 UDP 都按 DNS 处理**（不再只认 10.111.0.1），
  兜住系统仍按旧 DNS 发查询的情况。
- 多级降级：精确补集 → /24 聚合 → /16 聚合 → 只接管规则段；
  前三种都保住「DNS 一定进隧道」。
- 断网保护：启动 20 秒后若旁路包占比过高（说明系统没执行排除路由），
  自动断开隧道并给出提示，宁可防护失效也不让用户上不了网。
- 统计加 `收包 / DNS / 旁路 / 路由方案`，设置页「拦截状态」直接看链路断在哪：
  收包 0 = 流量没进隧道；DNS 0 = DNS 没接管；旁路涨 = 补集没生效。

**加密通道**

- `AES.GCM.seal` 不再依赖 `combined` 的隐式布局，改成显式 12 字节 IV +
  手工拼 `IV + 密文 + tag`，与服务端「前 12 / 中 / 后 16」的切法逐字节对齐。
- v3 五个候选全失败时自动降级成「明文 + HMAC 签名」（`X-Sign` / `X-Ts`），
  服务端 `Req::verifyPlain` 验签后照常处理 —— 授权、规则、版本不会再被通道卡死。
- 服务端补丁已上线：`app/Services/SecureV3.php`（备份 `/root/bak-20261118-0100/`）。


## 当前版本

**v1.0.6 build 109**（2026-11-17 · 关键代码混淆 / 运行环境自检 / 规则跟随防护生命周期）

### 1.0.6 改了什么

**防止 ipa 被拆改（这一轮主线）**

- 常量表：服务端地址、通道主密钥、两套派生盐、黑洞地址改成运行时按位还原
  （`Sources/Shared/Obfs.swift` 由 `Tools/gen_obfs.py` 生成，明文不进二进制，`strings` 搜不到）
- 类型名混淆：构建期把 52 个自定义顶层类型改成无意义短名（`Tools/rename_types.py`），
  映射表只留在流水线产物里；源码仓库仍可读
- 产物去符号：`STRIP_INSTALLED_PRODUCT` / `DEPLOYMENT_POSTPROCESSING` / `GCC_SYMBOLS_PRIVATE_EXTERN`，关掉 loc strings
- 运行环境自检（`Integrity`）：注入镜像、调试器附着、包结构被改（bundle id / 版本 / 扩展被删）三类留痕；
  被调试时授权只留内存不落盘
- 本地授权封条（`LicenseSeal`）：HMAC 覆盖整段授权数据，手改 UserDefaults 伪造「已授权」无效
- 流水线加产物自检：二进制里还能搜到主密钥 / 域名 / 盐就标 `OBF_FAIL`

**在线更新与卡密验证加固**

- 强制更新「钉在本地」：判过一次必须更新就落盘，升级到位前一直有效，
  这一次检查被 hook 成「无更新」也绕不过
- 规则下发带 build；服务端可用 `rules_min_build` 做版本闸门（补丁已备好，未上线）
- 开防护前强校验 + 隧道内每 5 分钟复查 + 规则包密钥由卡密派生（没卡密解不开包）

**规则跟随防护生命周期**

- 启动不再预拉规则；点开防护时才「拉取 → 解密 → 校验 → 进内存 → 起隧道」
- 关防护立刻卸载内存里的规则，界面回到「未加载」
- 隧道起不来也清掉刚下发的规则，不留空防护
- 心跳连续 3 次失败（约 90 秒）→ 卸载规则 + 断开隧道
- 隧道内周期校验连续 3 次失败 → 扩展自己卸载规则并断开
- 设置页 / 规则页手动同步要求防护已开启，否则提示「开启防护后才会下发规则」

**界面**

- 规则详情删掉「多套规则会合并成一个加密包下发」整张说明卡
- 设置页删掉「HTTPS 拦截 / 不需要安装证书」整张说明卡（含相关说明行）

**功能库校验（客户端已带，服务端待上线）**

- 7 个功能 × 5 条 CRC，全部取自真实实现输出：`crypto.sha256`、`crypto.hmac`、
  `ruleset.parse`、`ruleset.match`、`license.code`、`license.verdict`、`core.const`
- 随 `auth/check` 上报；服务端按「build + 功能」登记一条哈希（`server/god-live/app/Services/FeatureService.php`）
- 服务端补丁 `server/deploy/api.php.feature`（功能校验 + 版本闸门）、建表
  `server/god-live/sql/feature_checks.sql`、上线脚本 `server/deploy_feature_check.sh`
- 默认只记账不阻断，先攒基线，零误报后再决定是否当门禁

---

### 1.0.5 改了什么

**设备码重构（卸载重装不再换码）**

- 旧实现：`ConfigStore.makePin()` 首次启动随机生成 8 位数字存 UserDefaults，卸载即丢
- 新实现：`DeviceIdentity`，取源优先级 —— 钥匙串 → 老版本遗留码（原样沿用）→
  MobileGestalt 设备唯一标识 → 随机 128 位 + 硬件锚（型号/内存/CPU/磁盘）
- 设备码 = SHA256(设备标识|hm-pin-v2) 取 8 位十进制；设备指纹 dev = SHA256(…|hm-dev-v2) 前 32 hex
- 每次请求 body 带 `dev`，服务端据此识别「同一台设备换了设备码」
- 巨魔 entitlements 补 `application-identifier` / `keychain-access-groups`，
  否则伪签名环境下钥匙串返回 -34018，重装后仍会变码

**服务端换机迁移**

- `cards.bound_dev` 记录设备指纹；同一 dev 换 pin → 自动迁移绑定（`rebind_same_device`）
- 升级前绑的老卡（无 bound_dev）：旧设备码闲置 15 分钟即可认领一次（`rebind_legacy`），之后严格按指纹
- `auth/check` 新增 `adoptByDev`：新设备码 + 已知指纹 → 直接认回卡密，重装后连卡密都不用重输
- 测试：同 dev 换 pin 迁移成功、异 dev 被判 card_bound、无卡设备靠 dev 找回成功

**下载页（public/index.php 重写）**

- 改为下载页：巨魔直装 / 自签安装两行，按 /dl 下安装包自动聚合最新 build
- 删除在线激活、历史版本、公告区块；更新内容置顶
- 中性色浅色界面，无渐变/发光/emoji，行式左右布局，统一线性图标
- 服务端版本表已更 1.0.5 / 108，`force_update = 1`，下载地址 `https://ios.ouovo.cc`

**下载页调整（同日二版）**

- 主下载只留一份已签名包（`*_signed.ipa`）：巨魔直装与 ESign / 爱思自签共用
- 未签名原始包收进「备用 IPA」折叠行（原生 `<details>`），点击才展开下载
- 安装说明同步改为「同一个包，两种装法」；补回丢失的页脚 `<p class="foot">` 起始标签
- 线上已替换并核验：`/dl/*_signed.ipa` 与 `/dl/*_unsigned.ipa` 均 200，移动端/桌面端渲染正常
- 备份：`/root/bak-20261117-2250/index.php.bak`

正式名称：**黑猫拦截 Pro**（显示名、包内标题、设置页统一）

---

## 1.0.4 改了什么

### 1. 巨魔（TrollStore）启动失败 permission denied —— 根因是包没签名

事实：1.0.3 及以前的 ipa 里，主程序和扩展二进制**完全没有代码签名**
（Mach-O 里连 `LC_CODE_SIGNATURE` 段都没有）。iOS 15+ 对 App 内嵌扩展
的签名校验是强制的：主程序签了、`PlugIns/HeiMaoTunnel.appex` 没签，
系统会直接拒绝整个 App，表现就是「启动失败: permission denied」。

修复（构建流水线内完成）：

- 发布前用 `ldid` 对**扩展**和**主程序**都做 ad-hoc 签名，从内到外按顺序签
- 签名时写入 `Resources/TrollStore-App.entitlements` /
  `Resources/TrollStore-Tunnel.entitlements`：
  `platform-application`、`get-task-allow`、`com.apple.developer.networking.networkextension`
- TrollStore 安装时会读取二进制里已有的 entitlements 并沿用，
  所以 VPN 权限也跟着进去（之前没签 → 只能创建配置、开不起来）
- 产物两套：
  - `HeiMao_Pro_v1.0.4_build107_trollstore.ipa`（已签名，巨魔直装）
  - `HeiMao_Pro_v1.0.4_build107.ipa`（未签名，ESign / 爱思自签用）
- 打包前后都强制 `chmod 755` 主程序与扩展，防止执行位在压缩环节丢失

### 2. 拦截内核升级

| 项目 | 1.0.3 | 1.0.4 |
|---|---|---|
| AAAA 查询 | 返回空答案 | 保持（确认无 IPv6 绕过） |
| HTTPS/SVCB(64/65) 查询 | **照常转发真实记录** | 拦截域名一律空答案，堵住 ipv4hint/ipv6hint 绕过 |
| DNS 解析 | 每个查询都打上游 | 本地缓存（拦截 30s / 放行 90s，1024 条上限，LRU 淘汰） |
| 缓存一致性 | — | 规则热更新时整体清空，避免「已改拦截但缓存还在放行」 |
| 上游 DNS | 串行回退，超时 2.5s×3 | `connect()` 绑定上游 + 校验事务 ID + 900ms 超时 |
| DNS 并发 | 无上限（可能爆线程） | 信号量限 8 路 |
| TCP RST（已建立连接） | seq=0，被内核当窗口外丢弃 → 等超时 | seq=对端 ACK、ack=0、仅 RST 位，立即失败 |
| TCP RST（重复包） | 每包都回 | 同一五元组 2 秒内只回一次，防 RST 风暴 |
| 规则读取 | 每包一次 `DispatchQueue.sync` | 换成 `NSLock` 保护快照，单包开销降一个数量级 |
| 统计 | 每包 +1 连接数 | 连接数只在真正回 RST 时 +1 |

### 3. 隧道权限错误提示

`TunnelController.explain()` 把系统的 `permission denied` / NEVPNError
翻成能照着做的中文提示（签名不完整 / 配置被停用 / 隧道启动失败）。

---

## 1.0.1 改了什么

### 1. 只留一个开关

- 主界面删掉「开启防护 / 关闭防护」那颗按钮
- 唯一的控制入口就是中间那个大圆球：点一下开、再点一下关
- 球下方只留状态点、状态文案、一行「轻触圆球开启/关闭防护」提示
- 开启时球体放大 5%，给一个弹簧反馈，避免用户不确定点没点上

### 2. 卡密校验 / 解密 / 规则下发全部移到后台

新增 `Sources/Shared/WorkQueue.swift`（串行后台队列，qos userInitiated）。

| 动作 | 原来 | 现在 |
|---|---|---|
| `/auth/check` 校验结果解析 + 落盘 | 主线程 | WorkQueue |
| `/session/renew` 续期合并 + 落盘 | 主线程 | WorkQueue |
| 卡密兑换结果落盘 | 主线程 | WorkQueue |
| 规则包 AES-GCM 解密 + sha256 校验 | 网络回调线程 | WorkQueue |
| 规则文本解析（上万条） | 每次 `refreshRules` 都重解析 | 解析一次存 `RuleService.parsed`，界面读缓存 |
| 隧道启动时规则解析 | provider 启动线程 | WorkQueue |
| 规则热更新解析 | provider 消息线程 | WorkQueue |

配套改动：

- `ConfigStore.license` 加锁读写，写入只在 WorkQueue
- `ConfigStore.currentRuleSet()` 直接返回缓存，不再每次 parse
- 主线程只剩 `@Published` 赋值和 UI 刷新

### 3. 设置页的「刷新」结果回主界面显示

- 设置里的「刷新状态 / 同步云端规则 / 刷新公告」改成 `AppModel.runQuickAction(_:)`
- 点下去的瞬间收起设置页（`closeSettingsRequest`），回到主界面
- 结果统一落在主界面公告下方的结果横幅：进行中 → 成功 / 失败，失败给红色调
- 横幅可手动关闭，不再用「飘一下就消失」的 toast
- 激活成功后同样回主界面看结果

### 4. HTTPS 拦截：不需要 CA 证书，但补上了真正的连接级拦断

结论先说：**本应用不破解 TLS，所以不用装根证书、也不用信任描述文件。**

域名命中的拦截链条改成三段：

1. **DNS 层**：命中的域名（含子域）不再返回 `0.0.0.0`，改返回隧道内黑洞地址 `10.111.0.9`
2. **连接层**：`10.111.0.9` 的 /32 路由被拉进隧道，TCP 直接回 RST、UDP（QUIC）直接丢包
3. **统计**：连接级拦断计入「HTTPS 拦断」，界面看到的是真实连接数，不是 DNS 查询数

为什么这样更好：

- 原来返回 `0.0.0.0`，客户端去连一个非法地址，行为取决于系统，可能等超时；现在一进隧道立刻断，用户体感是「秒失败」
- QUIC（HTTP/3）走 UDP，原来靠 DNS 黑洞被动失败；现在 UDP 443 到黑洞地址直接被丢，客户端会回退 TCP
- 拦断动作可见、可统计

已知盲区（界面上如实写了）：App 内置 DoH/DoT 自己解析域名时，DNS 层管不到。这类要靠 SNI 或全流量接管，属于后续版本。

**没有做 MITM 的原因**：要替换成拦截提示页 / 看页面内容，必须动态签每个域名的证书，需要用户装 CA 并全局信任；所有 TLS 都要过 App 解密，性能与隐私成本都很高。公益拦截不需要这个，所以不做。

### 5. UI 细节

- 统计格「UDP 丢弃」换成「HTTPS 拦断」
- 设置页新增「HTTPS 拦截」说明卡（三条链路 + 为什么不用证书）
- 关于页补版本行
- 公告兜底文案更新为 1.0.1 的操作方式（点大圆球）

---

## 1.0.3 build 106 上线记录（2026-11-17 19:20）

- 包已上传服务器：`https://ios.ouovo.cc/dl/HeiMao_Pro_v1.0.3_build106.ipa`（1,150,614 B，sha256 `97abeec6…7800`）
- 后台 `app_versions` 记录更新为 1.0.3 / 106，`force_update = 0`，`min_version = 1.0.0`
- 线上实测（真实卡密 11223344）：
  - `rules/manifest` 返回 `set_count = 1`、`sets = ["公益规则"]`、`sets_detail` 含名称/版本/条数
  - `rules/download` 按客户端算法（HKDF + AES-256-GCM，HMR1 头）解密成功，sha256 与 manifest 一致
  - `app/version`：1.0.3 不提示更新；1.0.2 / 1.0 提示但不强制
- 服务端多套合并实测（临时建两套 → 删掉）：
  - 三套合并后 manifest `set_count = 3`，合并内容含两套的 IP/域名/端口段
  - `admin/rulesets/sort` 上移生效，合并顺序跟着变
  - 删除两套后重新下发，`sha256` 与测试前完全一致 —— 合并无损
- 已知内容问题：当前「公益规则」里没有 `#PORT` 段（端口 0 条），端口拦截处于关闭状态

## 构建

- 仓库：`GodLiaoke/HeiMaoInterceptor`，分支 `main`
- 提交：见 git log 顶部
- 流水线：`.github/workflows/build.yml`（4 个 macOS 机型并行）
- 产物：未签名 ipa，`AppConfig.buildNumber = 103`，`MARKETING_VERSION = 1.0.1`

## 待办（需要你处理）

- 包是未签名的，用 ESign / 爱思自签
- 服务器 `103.231.58.74` 上的下载目录需要放新包（上一轮的密码已失效，需要新密码）
- 后台「版本」记录里的下载地址指向服务器 /dl/，不要指向 GitHub（仓库带源码）


---

## 1.0.3（build 105）

### 客户端
- manifest 新增解析 `set_count` / `sets` / `sets_detail`：主界面新增「N 套规则」条，点开是规则详情页
- 规则详情页：每套名称、版本、IP/域名/端口条数、合并版本、最近同步时间、手动同步入口
- 设置页规则卡补上「规则集 N 套 / 下发内容 / 端口规则 / 下发版本」
- 服务端版本号是 `20261117.1854.1s.f695a5` 这种长串，界面统一显示成 `11-17 18:54`，不再被压成小字截断
- 主界面「规则」统计把端口条数一起算进去
- 版本号 1.0.3 / 105

### 服务端
- 多套规则合并支持 `#DIRECT` / `@@||` / hosts 两列写法；放行优先，同一域名不会既拦又放
- 合并时保留后端勾选顺序，新增上移/下移排序接口 `admin/rulesets/sort`
- manifest 带 `sets_detail`（每套名称/版本/条数）和 `pack_note`，老客户端忽略新字段不受影响
- 升级上来的老站：manifest 会自动把正在下发的包登记成「默认规则」，客户端不会再显示 0 套
- 后台：当前下发显示套名清单，新增「全部下发 / 全部停用」和排序按钮
