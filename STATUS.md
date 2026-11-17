# STATUS — 黑猫公益拦截 · iOS

## 当前版本

v1.0（2026-11-17）

## 本次改造

### 1. 规则上云，本地不留明文

- 安装包里的 `Resources/Rules/rules.txt` 已移除，target 也不再打包规则资源
- 新的下载链路：`POST /api/rules/manifest` → `POST /api/rules/download`
- 两步都要有效卡密，服务端实时校验绑定关系
- 包体：`HMR1 + nonce(12) + AES-256-GCM 密文 + tag(16)`
- 密钥：`SHA256(pin|卡密|当日桶|版本) → HKDF-SHA256`，服务端 UTC 0 点轮换
- 客户端解出后只放在 `RuleService.text`（进程内存），解析成 `RuleSet` 后不写任何磁盘
- 隧道通过 `providerConfiguration` 拿到已解密的文本；扩展自己也能兜底拉取

### 2. 版本管理

- 服务端 `app_versions` 表 + 后台「版本」页（发布 / 编辑 / 删除 / 强制更新 / 下载地址 / 更新说明 / 最低版本）
- 客户端 `GET /api/app/version?platform=ios&current=1.0`
- 可选更新：弹窗可稍后；强制更新：全屏遮罩挡住主界面
- 版本号 1.0 / build 1

### 3. 授权系统修复（重点）

**根因一：卡密到期与在线窗口混用**

旧代码 `expireAt` 直接取服务端的 `expire_at`，而服务端这个字段是 60 秒的校验窗口；
窗口一过，`authorized` 就变 false，主界面显示未授权。

**根因二：两个页面读两份状态**

- 主界面读 `AppModel.authorized`（经 `LicenseState.isUsable()` 计算）
- 设置页读 `license.authorized`（服务端原始布尔）
两者天然会不一致。

现在：

- `LicenseState` 拆成 `expireAt`（卡密到期，服务端 `card_expire_at` / `card_seconds_left`）
  与 `sessionUntil`（在线窗口，服务端 `authorized_until` / `expires_in`）
- 判定只有一份：`LicenseState.isUsable()`，所有页面都用 `statusText()`
- 窗口过期后还有 10 分钟宽限，状态显示「离线校验中」，不误判
- 客户端每 60 秒打 `/api/session/renew` 续窗口，App 在前台/后台都持续续
- 重复兑换语义修正：同设备再兑换=续期；换设备=`card_bound`（后台卡密列表可一键解绑）
- 之前测试用的 `AAKQ-GRLE-KUUW-9UU6` 是 5 分钟测试卡，第二次兑换确实已到期，
  那是测试卡本身的问题

## 服务端接口（已部署 ios.ouovo.cc）

| 接口 | 说明 |
|---|---|
| `POST /api/card/redeem` | 兑换 / 绑定 |
| `POST /api/session/renew` | 续期（不产生兑换记录） |
| `GET  /api/session/state` | 只读状态 |
| `POST /api/rules/manifest` | 规则清单（需卡密） |
| `POST /api/rules/download` | 加密规则包（需卡密） |
| `GET  /api/app/version` | 版本检测 |
| `GET/POST /api/admin/versions*` | 后台版本管理 |
| `GET/POST /api/admin/rules*` | 后台规则库 |
| `POST /api/admin/cards/unbind` | 解绑设备 |

## 实测（线上）

- 兑换：`expires_in=600`，`card_expire_at` 正确（1 天卡 = 86400 秒）
- 换设备：`card_bound` ✅
- 规则清单：`2026.11.17` / 108 IP / 615 域名 / 725 端口
- 规则包 15803 字节，同参数解密 15771 字节，sha256 与清单一致 ✅
- 版本检测：1.0 不提示、0.9 提示 ✅

## 待办

1. 后台「版本管理」里填 IPA 下载地址，客户端更新弹窗才能点下载
2. 出签名 IPA 需要 p12 + 两个 profile + TeamID（仓库 Secrets）
3. App ID 必须开 Network Extensions + App Groups(`group.com.heimao.club`)
