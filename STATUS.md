# STATUS — 黑猫拦截 Pro · iOS

## 当前版本

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

- 包：`/dl/HeiMao_Pro_v1.0.11_build114_signed.ipa`（1,252,726 B，sha256 `421eb2bd…1552`）
- 未签：`/dl/HeiMao_Pro_v1.0.11_build114_unsigned.ipa`（1,235,596 B，sha256 `aff0af70…a313`）
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
