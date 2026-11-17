# STATUS — 黑猫公益拦截 · iOS

## 当前版本

**v1.0 build 101**（2026-11-17 · 1.0 补充更新，不是新版本号）

本次在 v1.0 基础上做补充升级，功能与接口向下兼容。

---

## 本次（1.0 补充）改了什么

### 1. 卡密作废 / 到期后，App 不再显示「已授权」

**原来的问题链**

- 服务端 `authorized` 只看 `pins.authorized_until`（600 秒在线校验窗口）
- 卡密在后台被作废之后，窗口还没过的那几分钟里，服务端仍然回 `authorized = true`
- 客户端 `isUsable()` 只看本地缓存的时间，冷启动根本不向服务端求证
- 结果：主界面显示「已授权」，但隧道启动时联网校验失败 → VPN 开不起来

**现在的做法**

| 层 | 改动 |
|---|---|
| 服务端 | 新增 `AuthGate`：卡密存在 + 未作废 + 未到期 + 窗口有效，四关全过才算可用 |
| 服务端 | 判定为 `card_revoked` / `card_expired` 时，顺手把该设备会话清零 |
| 服务端 | 后台作废 / 删除卡密时，`AuthGate::sealByCard()` 立刻封掉绑定设备的会话 |
| 服务端 | 新增 `POST /api/auth/check`：每次查库的强校验端点 |
| 客户端 | `LicenseState.verdict` 记录服务端判定（ok / card_revoked / card_expired / card_not_found / no_card / window_expired） |
| 客户端 | `isUsable()` 以 verdict 为准：判死立即失效，不给离线宽限 |
| 客户端 | App 启动、回到前台、点开启 VPN 之前，都先调 `auth/check` |
| 客户端 | 隧道扩展启动前再校验一次；运行中每 5 分钟复查，失效主动断开 |
| 客户端 | 授权失效时界面同步变红横幅 + 锁形图标，不再出现「显示已授权但开不了」 |

### 2. 全链路 AES 加密 + 每次请求带签名

抓包只能看到随机字节，改一个字节直接验签失败，重发同一条会被 nonce 拒掉。

```
请求：{ v:3, p:设备码, ts:秒, n:32位hex随机, e:AES-256-GCM密文, sig:HMAC }
响应：{ v:3, n, e, sig }
```

- 密钥：`HKDF-SHA256(主密钥, salt="heimao-v3-salt", info="heimao-v3-req"/"res")`
- 签名：`HMAC-SHA256(主密钥, "v3|路径|设备码|ts|nonce|sha256(密文)")`
- 防重放：`ts` ±300 秒 + 一次性 nonce（服务端 `nonces` 表去重）
- 覆盖范围：公告、卡密兑换、续期、状态、强校验、版本检测、规则下发
- 规则包本身仍是双层加密：传输层一层 + `HMR1` 包体一层

明文老接口保留（没有 `v=3` 就走原逻辑），老客户端不受影响。

### 3. 公告放显眼位置

- 主界面：顶栏正下方、开关球之上，琥珀色渐变横幅，默认露两行，点一下展开全文
- 设置页：同样置顶一张公告卡
- 公告随 App 启动 / 回前台 / 设置页刷新自动更新

### 4. UI 与代码整理

- 开关球支持「授权失效」态（锁形 + 琥珀色），不再让人误以为可以点开
- 状态卡补上卡密掩码、剩余时间、规则规模，加「刷新状态 / 激活卡密」按钮
- 顶栏加校验中的转圈提示
- 设置页补「最后确认」时间，能看到上次和服务端对上的时刻
- `RuleService` / `VersionService` / `LicenseClient` 统一走 `SecureChannel`，删掉三套重复的 URLSession

---

## 服务端

部署位置：`/www/wwwroot/ios.ouovo.cc`（PHP 8.0.26）

新增 / 改动文件：

```
app/Services/AuthGate.php     新增：唯一授权判定
app/Services/SecureV3.php     新增：v3 加密通道 + Req/Res 统一出入口
app/Services/PinService.php   改：status() 走 AuthGate
app/Services/SessionService.php 改：state() 走 AuthGate，payload 带 reason
app/Services/CardService.php  改：作废/删除时封会话
public/api.php                改：全端点接加密通道 + auth/check
```

备份：改动前已 `cp -a` 到 `~/bak-hm-<时间戳>/`。

---

## 机器人接口（bot.php）密钥位置

文件：`/www/wwwroot/ios.ouovo.cc/storage/bot_config.php`（web 根目录之外，下载不到）

```php
return [
    'api_key'     => 'fe317846cb8a2393a755ef34241bd7a2',   // 请求头 X-Api-Key
    'secret'      => 'abb9b3b0...ba4beae1',                // HMAC 签名密钥
    'time_window' => 300,
];
```

- `api_key`：调用 `POST https://ios.ouovo.cc/bot.php` 时放在 `X-Api-Key`
- `secret`：给请求签名用的 HMAC 密钥
- 签名校验开关默认 **关闭**（`require_signature` 未设置 = false）；
  要开启就在同一个数组里加一行 `'require_signature' => true`，
  开启后每次请求要带 `X-Timestamp` 和 `X-Sign`
- 改完立即生效，不用重启任何服务

---

## 尚未完成 / 需要你处理

- 出包仍需 GitHub Actions（本机没有 macOS 工具链）
- 包是未签名的，用 ESign / 爱思自签，或自备 p12 + profile
- 后台「版本」页里 1.0 那条的 IPA 下载地址需要填上托管链接，客户端更新弹窗才点得动
