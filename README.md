# 黑猫公益拦截 · HeiMaoInterceptor

iOS 15 – iOS 27 · 企业级液态玻璃 UI · Packet Tunnel 拦截内核

公益频道：[@HeiMaoClub](https://t.me/HeiMaoClub)

## 构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild archive -project HeiMaoInterceptor.xcodeproj \
  -scheme HeiMaoInterceptor -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/HeiMaoInterceptor.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

推送 main 分支后由 GitHub Actions 自动产出无签名 ipa（artifact：`HeiMaoInterceptor-ipa`）。

## 架构

- `Sources/App` — SwiftUI 客户端（液态玻璃 UI、卡密激活、状态面板）
- `Sources/Tunnel` — NetworkExtension 分包隧道：DNS 黑洞 + 伪造 TCP RST
- `Sources/Shared` — 规则库解析、卡密/公告通道、AES-GCM 配置包解密
- `Resources/Rules/rules.txt` — 内置规则库（IP / DOMAIN / PORT）

## 授权

- 设备码由安装实例生成，卡密在 `https://ios.ouovo.cc` 兑换
- 云端配置包使用 AES-256-GCM，密钥由 `卡密 + 设备码` 派生，客户端不保存明文密钥
- 配置包带过期时间，过期后隧道拒绝启动


---

## v1.0 更新（2026-11-17）

- **规则上云**：安装包不再带规则；`/api/rules/manifest` + `/api/rules/download` 凭卡密下载，
  AES-256-GCM 加密、密钥按天轮换，明文只进内存
- **版本管理**：后台可发布版本、设强制更新、填 IPA 下载地址；客户端启动检测
- **授权修复**：卡密到期与在线校验窗口分开；所有页面统一 `LicenseState.isUsable()`，
  不再出现「设置已授权 / 主页未授权」；换设备复用卡密返回 `card_bound`
