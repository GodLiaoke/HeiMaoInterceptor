<?php
declare(strict_types=1);
require __DIR__ . '/../app/bootstrap.php';

function h($s): string { return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8'); }

function fmtSize(int $bytes): string {
    if ($bytes >= 1048576) { return round($bytes / 1048576, 1) . ' MB'; }
    if ($bytes >= 1024)    { return round($bytes / 1024) . ' KB'; }
    return $bytes . ' B';
}

$pdo = Database::pdo();

/* 后台维护的版本记录 */
$vrow = null;
try {
    $vrow = $pdo->query("SELECT version, build, notes FROM app_versions
                         WHERE platform = 'ios' AND active = 1
                         ORDER BY build DESC, id DESC LIMIT 1")->fetch();
} catch (Throwable $e) {}

/* 只认最新一个 build 的安装包；历史版本不再展示 */
$packs = [];
$dir = __DIR__ . '/dl';
foreach (glob($dir . '/*.ipa') ?: [] as $path) {
    $name = basename($path);
    if (!preg_match('/v?(\d+\.\d+\.\d+)[_-]build(\d+)/i', $name, $m)) { continue; }
    $build = (int) $m[2];
    $kind = 'unsigned';
    if (preg_match('/trollstore|巨魔/i', $name))            { $kind = 'trollstore'; }
    elseif (preg_match('/unsigned|nosign|未签名/i', $name))  { $kind = 'unsigned'; }
    elseif (preg_match('/signed|通用|universal/i', $name))   { $kind = 'signed'; }

    if (!isset($packs[$build])) {
        $packs[$build] = ['version' => $m[1], 'build' => $build, 'files' => []];
    }
    $packs[$build]['files'][$kind] = [
        'name'  => $name,
        'size'  => (int) @filesize($path),
        'mtime' => (int) @filemtime($path),
    ];
}
krsort($packs, SORT_NUMERIC);
$latest = $packs ? reset($packs) : null;

$troll = $latest ? ($latest['files']['trollstore'] ?? $latest['files']['signed'] ?? null) : null;
$self  = $latest ? ($latest['files']['unsigned'] ?? $latest['files']['signed'] ?? null) : null;
$samePack = $latest && $troll && $self && $troll['name'] === $self['name'];

$versionText = $latest ? $latest['version'] : (string) ($vrow['version'] ?? '');
$buildText   = $latest ? (string) (int) $latest['build'] : (string) ($vrow['build'] ?? '');
$updatedAt   = $latest ? (int) max(array_column($latest['files'], 'mtime')) : 0;
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#f7f8fa">
<title>黑猫拦截 Pro · 下载</title>
<style>
:root{
  --bg:#f7f8fa;
  --surface:#ffffff;
  --text:#141821;
  --text-2:#6b7280;
  --text-3:#9aa1ae;
  --line:#e7e9ee;
  --line-strong:#d8dbe2;
  --btn:#1b2230;
  --btn-hover:#2a3346;

  /* 间距档位：4 / 8 / 12 / 16 / 24 / 32 / 48 */
  --s1:4px; --s2:8px; --s3:12px; --s4:16px; --s5:24px; --s6:32px; --s7:48px;

  /* 圆角档位：6 / 10 / 14 */
  --r1:6px; --r2:10px; --r3:14px;
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;padding:0}
body{
  background:var(--bg); color:var(--text);
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro SC","PingFang SC","Noto Sans SC",system-ui,sans-serif;
  font-size:15px; line-height:1.5; -webkit-font-smoothing:antialiased;
}
.page{max-width:680px;margin:0 auto;padding:var(--s6) var(--s4) var(--s7)}
@media(min-width:720px){ .page{padding:var(--s7) var(--s5) 64px} }

/* ---------- 头部 ---------- */
.hd{display:flex;align-items:center;gap:var(--s3);padding-bottom:var(--s6)}
.hd-mark{
  width:44px;height:44px;border-radius:var(--r2);background:var(--btn);
  display:grid;place-items:center;flex:0 0 auto;
}
.hd-mark svg{width:24px;height:24px;stroke:#fff;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.hd-text{min-width:0}
.hd-title{font-size:17px;font-weight:600;letter-spacing:-.01em}
.hd-sub{margin-top:2px;font-size:13px;color:var(--text-2)}

/* ---------- 分组 ---------- */
.group + .group{margin-top:var(--s6)}
.group-title{
  font-size:13px;font-weight:600;color:var(--text-2);
  margin:0 0 var(--s2); padding-left:0;
}
.rows{background:var(--surface);border:1px solid var(--line);border-radius:var(--r3);overflow:hidden}

/* ---------- 行：左标签 右控件 ---------- */
.row{
  display:flex;align-items:center;justify-content:space-between;gap:var(--s4);
  padding:var(--s4);
  min-height:64px;
}
.row + .row{border-top:1px solid var(--line)}
.row-main{display:flex;align-items:center;gap:var(--s3);min-width:0}
.row-icon{width:20px;height:20px;flex:0 0 auto;color:var(--text-2)}
.row-icon svg{width:20px;height:20px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.row-text{min-width:0}
.row-label{font-size:15px;font-weight:500;letter-spacing:-.005em}
.row-desc{margin-top:2px;font-size:12.5px;color:var(--text-2)}
.row-value{font-size:14px;color:var(--text-2);text-align:right;flex:0 0 auto}
.row-stack{display:flex;flex-direction:column;align-items:flex-end;gap:var(--s2);flex:0 0 auto}

/* ---------- 按钮 ---------- */
.btn{
  display:inline-flex;align-items:center;justify-content:center;gap:var(--s2);
  height:36px;padding:0 16px;border-radius:var(--r1);
  font-size:14px;font-weight:500;text-decoration:none;white-space:nowrap;
  border:1px solid transparent;cursor:pointer;transition:background .15s ease,border-color .15s ease;
}
.btn svg{width:16px;height:16px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.btn-primary{background:var(--btn);color:#fff}
.btn-primary:hover{background:var(--btn-hover)}
.btn-secondary{background:var(--surface);color:var(--text);border-color:var(--line-strong)}
.btn-secondary:hover{background:#f2f4f7}
.btn[aria-disabled="true"]{background:#eef0f3;color:var(--text-3);pointer-events:none}

/* ---------- 文本块 ---------- */
.body-text{padding:var(--s4);font-size:14px;line-height:1.75;color:var(--text)}
.body-text p{margin:0}
.body-text p + p{margin-top:var(--s2)}

.hint{padding:0 var(--s4) var(--s4);font-size:12.5px;line-height:1.7;color:var(--text-2)}

/* ---------- 步骤 ---------- */
.steps{margin:0;padding:var(--s4) var(--s4) var(--s4) 34px;font-size:14px;line-height:1.85;color:var(--text)}
.steps li{padding-left:2px}
.steps li + li{margin-top:var(--s1)}
.steps b{font-weight:600}

/* ---------- 页脚 ---------- */
.foot{margin-top:var(--s6);font-size:12.5px;color:var(--text-3);line-height:1.8}
.foot a{color:var(--text-2);text-decoration:none;border-bottom:1px solid var(--line-strong)}
.row-link{color:var(--text-2);text-decoration:none}
.row-link:hover{color:var(--text)}
</style>
</head>
<body>
<main class="page">

  <header class="hd">
    <div class="hd-mark">
      <svg viewBox="0 0 24 24"><path d="M12 3l7 3v5.2c0 4.2-2.9 7.9-7 9.8-4.1-1.9-7-5.6-7-9.8V6l7-3z"/><path d="M9.2 11.6h.01M14.8 11.6h.01"/><path d="M9.6 14.6c1.5 1.2 3.3 1.2 4.8 0"/></svg>
    </div>
    <div class="hd-text">
      <div class="hd-title">黑猫拦截 Pro</div>
      <div class="hd-sub">iOS 15 – 27 · 网络层拦截</div>
    </div>
  </header>

  <?php if (!empty($vrow['notes'])): ?>
  <!-- 更新内容 -->
  <section class="group">
    <h2 class="group-title">更新内容</h2>
    <div class="rows">
      <div class="body-text"><p><?= nl2br(h($vrow['notes'])) ?></p></div>
    </div>
  </section>
  <?php endif; ?>

  <!-- 下载 -->
  <section class="group">
    <h2 class="group-title">下载</h2>
    <div class="rows">
      <div class="row">
        <div class="row-main">
          <span class="row-icon">
            <svg viewBox="0 0 24 24"><rect x="6" y="2.5" width="12" height="19" rx="2.5"/><path d="M10.5 5.5h3"/><path d="M9 11.5h6"/><path d="M9 15h4"/></svg>
          </span>
          <div class="row-text">
            <div class="row-label">巨魔直装</div>
            <div class="row-desc">TrollStore 安装，已签名<?= $troll ? ' · ' . h(fmtSize($troll['size'])) : '' ?></div>
          </div>
        </div>
        <?php if ($troll): ?>
          <a class="btn btn-primary" href="/dl/<?= h(rawurlencode($troll['name'])) ?>" download>
            <svg viewBox="0 0 24 24"><path d="M12 4v10"/><path d="m8 10.5 4 4 4-4"/><path d="M5 19h14"/></svg>
            下载
          </a>
        <?php else: ?>
          <span class="btn btn-primary" aria-disabled="true">暂不可用</span>
        <?php endif; ?>
      </div>

      <div class="row">
        <div class="row-main">
          <span class="row-icon">
            <svg viewBox="0 0 24 24"><path d="M12 3v9"/><path d="m8.5 8.5 3.5 3.5 3.5-3.5"/><path d="M4 14v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4"/></svg>
          </span>
          <div class="row-text">
            <div class="row-label">自签安装</div>
            <div class="row-desc">ESign、爱思或其它侧载工具重签<?= ($self && !$samePack) ? ' · ' . h(fmtSize($self['size'])) : '' ?></div>
          </div>
        </div>
        <?php if ($self): ?>
          <a class="btn btn-secondary" href="/dl/<?= h(rawurlencode($self['name'])) ?>" download>
            <svg viewBox="0 0 24 24"><path d="M12 4v10"/><path d="m8 10.5 4 4 4-4"/><path d="M5 19h14"/></svg>
            下载
          </a>
        <?php else: ?>
          <span class="btn btn-secondary" aria-disabled="true">暂不可用</span>
        <?php endif; ?>
      </div>
    </div>
    <?php if ($samePack): ?>
      <p class="hint">两项为同一个安装包：主程序与隧道扩展都已签名，巨魔可直接安装，用自签工具重新签名同样可用。</p>
    <?php endif; ?>
  </section>

  <!-- 安装说明 -->
  <section class="group">
    <h2 class="group-title">安装说明</h2>
    <div class="rows">
      <ol class="steps">
        <li><b>巨魔用户</b>：下载后打开 TrollStore，选择 Install。不要再用 TrollStore 内的签名功能重新签一次。</li>
        <li><b>自签用户</b>：下载后导入 ESign 或爱思，使用自己的证书签名安装。</li>
        <li>安装前先卸载手机中的旧版本，避免两个版本同时存在。</li>
        <li>首次打开后输入卡密激活，再点主界面中间的圆形按钮开启防护。</li>
      </ol>
    </div>
  </section>

  <!-- 应用信息 -->
  <section class="group">
    <h2 class="group-title">应用信息</h2>
    <div class="rows">
      <div class="row">
        <div class="row-label">版本</div>
        <div class="row-value"><?= h($versionText ?: '—') ?><?= $buildText !== '' ? '（' . h($buildText) . '）' : '' ?></div>
      </div>
      <div class="row">
        <div class="row-label">支持系统</div>
        <div class="row-value">iOS 15.0 及以上</div>
      </div>
      <?php if ($latest): ?>
      <div class="row">
        <div class="row-label">安装包大小</div>
        <div class="row-value"><?= h(fmtSize((int) ($troll['size'] ?? $self['size'] ?? 0))) ?></div>
      </div>
      <?php endif; ?>
      <?php if ($updatedAt > 0): ?>
      <div class="row">
        <div class="row-label">更新时间</div>
        <div class="row-value"><?= date('Y-m-d H:i', $updatedAt) ?></div>
      </div>
      <?php endif; ?>
      <div class="row">
        <div class="row-label">公益频道</div>
        <div class="row-value"><a class="row-link" href="https://t.me/HeiMaoClub" target="_blank" rel="noopener">@HeiMaoClub</a></div>
      </div>
    </div>
  </section>

仅供学习与公益使用。安装或使用中遇到问题，请带上设备码与截图联系管理员。</p>
</main>
</body>
</html>
