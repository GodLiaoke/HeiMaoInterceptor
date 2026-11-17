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

/* ---------- 公告 ---------- */
$ann = null;
try {
    $ann = $pdo->query("SELECT title, content, updated_at FROM announcements
                        WHERE active = 1 ORDER BY updated_at DESC, id DESC LIMIT 1")->fetch();
} catch (Throwable $e) {}

/* ---------- 版本记录（后台维护的那条） ---------- */
$vrow = null;
try {
    $vrow = $pdo->query("SELECT version, build, notes, force_update FROM app_versions
                         WHERE platform = 'ios' AND active = 1
                         ORDER BY build DESC, id DESC LIMIT 1")->fetch();
} catch (Throwable $e) {}

/* ---------- 扫描 /dl 下的安装包，按 build 聚合 ---------- */
$packs = [];
$dir = __DIR__ . '/dl';
foreach (glob($dir . '/*.ipa') ?: [] as $path) {
    $name = basename($path);
    if (!preg_match('/v?(\d+\.\d+\.\d+)[_-]build(\d+)/i', $name, $m)) { continue; }
    $build = (int) $m[2];
    $kind = 'unsigned';
    if (preg_match('/trollstore|巨魔/i', $name))          { $kind = 'trollstore'; }
    elseif (preg_match('/unsigned|nosign|未签名/i', $name)) { $kind = 'unsigned'; }
    elseif (preg_match('/signed|通用|universal/i', $name)) { $kind = 'signed'; }

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
$latestBuild = $latest ? $latest['build'] : 0;

/* 主包选择：巨魔用 trollstore / signed，自签用 unsigned / signed */
$pickTroll = function (array $p): ?array {
    return $p['files']['trollstore'] ?? $p['files']['signed'] ?? null;
};
$pickUser = function (array $p): ?array {
    return $p['files']['unsigned'] ?? $p['files']['signed'] ?? null;
};
$oneForAll = $latest
    && isset($latest['files']['signed'])
    && !isset($latest['files']['trollstore'])
    && !isset($latest['files']['unsigned']);

$pinLen = (int) Config::get('pin_len', 8);
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#060911">
<title>黑猫拦截 Pro · 下载</title>
<style>
:root{
  --bg:#060911; --ink:#eef3fb; --sub:#8f9cb3;
  --aqua:#3ddad7; --aqua2:#37a6ff; --violet:#8b7cff;
  --glass:rgba(255,255,255,.055); --line:rgba(255,255,255,.10);
  --ok:#4ade80; --warn:#fbbf24; --err:#fb7185;
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;padding:0}
body{
  background:var(--bg); color:var(--ink); min-height:100vh;
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro SC","PingFang SC","Noto Sans SC",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased; letter-spacing:.01em;
  overflow-x:hidden;
}
body::before{
  content:""; position:fixed; inset:-20% -10% auto -10%; height:70vh; z-index:0; pointer-events:none;
  background:
    radial-gradient(42vw 42vw at 18% 6%, rgba(61,218,215,.20), transparent 62%),
    radial-gradient(46vw 46vw at 84% 0%, rgba(139,124,255,.20), transparent 60%),
    radial-gradient(38vw 38vw at 50% 34%, rgba(55,166,255,.13), transparent 65%);
  filter:blur(14px);
}
.wrap{position:relative;z-index:1;max-width:860px;margin:0 auto;padding:26px 18px 64px}
@media(min-width:760px){ .wrap{padding:44px 26px 80px} }

/* ---------- 头部 ---------- */
.brand{display:flex;align-items:center;gap:14px;margin-bottom:22px}
.logo{
  width:56px;height:56px;border-radius:17px;flex:0 0 auto;
  background:linear-gradient(150deg,rgba(61,218,215,.95),rgba(55,166,255,.85) 55%,rgba(139,124,255,.95));
  display:grid;place-items:center; box-shadow:0 14px 34px -12px rgba(61,218,215,.55), inset 0 1px 0 rgba(255,255,255,.5);
  position:relative; overflow:hidden;
}
.logo svg{width:34px;height:34px;display:block}
.logo::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(255,255,255,.35),transparent 55%);opacity:.5}
.brand h1{margin:0;font-size:20px;font-weight:800;letter-spacing:-.01em}
.brand h1 span{
  background:linear-gradient(92deg,var(--aqua),#9fe7ff 45%,var(--violet));
  -webkit-background-clip:text;background-clip:text;color:transparent;
}
.brand p{margin:3px 0 0;font-size:12.5px;color:var(--sub);letter-spacing:.02em}

/* ---------- 玻璃卡 ---------- */
.card{
  position:relative;border:1px solid var(--line);border-radius:24px;
  background:linear-gradient(180deg,rgba(255,255,255,.075),rgba(255,255,255,.028));
  -webkit-backdrop-filter:blur(26px) saturate(155%); backdrop-filter:blur(26px) saturate(155%);
  box-shadow:0 26px 60px -30px rgba(0,0,0,.9), inset 0 1px 0 rgba(255,255,255,.16);
  padding:22px;
}
.card + .card{margin-top:16px}
.card-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:18px}
.tag{
  display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:700;letter-spacing:.08em;
  text-transform:uppercase;color:#0a1220;padding:5px 10px;border-radius:999px;
  background:linear-gradient(92deg,var(--aqua),#7fe9ff);
}
.tag.ghost{background:rgba(255,255,255,.08);color:var(--sub);border:1px solid var(--line)}
.ver{font-size:30px;font-weight:800;letter-spacing:-.02em;margin:2px 0 4px}
.ver small{font-size:13px;font-weight:600;color:var(--sub);margin-left:8px;letter-spacing:0}
.meta{font-size:12.5px;color:var(--sub);line-height:1.7}

/* ---------- 下载按钮 ---------- */
.dl{display:grid;gap:12px;margin-top:18px}
@media(min-width:620px){ .dl{grid-template-columns:1fr 1fr} }
.btn{
  display:flex;align-items:center;gap:13px;text-decoration:none;color:inherit;
  border-radius:18px;padding:15px 16px;border:1px solid var(--line);
  background:linear-gradient(180deg,rgba(255,255,255,.075),rgba(255,255,255,.02));
  transition:transform .16s ease, border-color .16s ease, background .16s ease;
}
.btn:active{transform:scale(.985)}
.btn.primary{
  border-color:rgba(61,218,215,.42);
  background:linear-gradient(180deg,rgba(61,218,215,.20),rgba(55,166,255,.10));
  box-shadow:0 16px 40px -22px rgba(61,218,215,.75), inset 0 1px 0 rgba(255,255,255,.2);
}
.btn .ico{
  width:40px;height:40px;border-radius:12px;flex:0 0 auto;display:grid;place-items:center;
  background:rgba(255,255,255,.09);border:1px solid var(--line);
}
.btn .ico svg{width:20px;height:20px;stroke:var(--aqua);fill:none;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.btn.primary .ico svg{stroke:#c9fffd}
.btn b{display:block;font-size:14.5px;font-weight:700;letter-spacing:.01em}
.btn em{display:block;font-style:normal;font-size:11.5px;color:var(--sub);margin-top:3px}

/* ---------- 说明区 ---------- */
.note{margin-top:16px;padding:14px 15px;border-radius:16px;background:rgba(255,255,255,.04);border:1px solid var(--line)}
.note h4{margin:0 0 8px;font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--sub);font-weight:700}
.note ol{margin:0;padding-left:18px;font-size:13px;line-height:1.85;color:#d7e0ee}
.note li{margin:2px 0}
.note b{color:var(--aqua)}
.hint{font-size:12px;color:var(--sub);line-height:1.75;margin:12px 2px 0}

/* ---------- 历史版本 ---------- */
details.history{margin-top:16px}
details.history > summary{
  list-style:none;cursor:pointer;padding:14px 16px;border-radius:16px;border:1px solid var(--line);
  background:rgba(255,255,255,.045);font-size:13.5px;font-weight:600;color:#cfd9e8;
  display:flex;align-items:center;justify-content:space-between;
}
details.history > summary::-webkit-details-marker{display:none}
details.history > summary::after{content:"⌄";font-size:16px;color:var(--sub);transition:transform .2s}
details.history[open] > summary::after{transform:rotate(180deg)}
.hrow{
  display:flex;align-items:center;justify-content:space-between;gap:10px;
  padding:13px 4px;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px;
}
.hrow:last-child{border-bottom:0}
.hrow .v{font-weight:700}
.hrow .s{color:var(--sub);font-size:11.5px;margin-top:3px}
.hlinks{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}
.mini{
  text-decoration:none;color:#dff9ff;font-size:12px;font-weight:600;padding:7px 11px;border-radius:10px;
  border:1px solid rgba(61,218,215,.3);background:rgba(61,218,215,.12);white-space:nowrap;
}
.mini.gray{color:var(--sub);border-color:var(--line);background:rgba(255,255,255,.045)}

/* ---------- 公告 ---------- */
.ann{border-left:3px solid var(--aqua);padding:2px 0 2px 14px;margin:2px 0 0}
.ann h3{margin:0 0 6px;font-size:14.5px;font-weight:700}
.ann p{margin:0;font-size:13px;line-height:1.8;color:#cdd7e6;white-space:pre-wrap}

/* ---------- 激活 ---------- */
.act-grid{display:grid;gap:10px;margin-top:14px}
@media(min-width:560px){ .act-grid{grid-template-columns:1fr 1fr} }
input{
  width:100%;padding:13px 14px;border-radius:14px;border:1px solid var(--line);
  background:rgba(6,10,18,.55);color:var(--ink);font-size:15px;outline:none;
  font-family:ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.14em;
}
input:focus{border-color:rgba(61,218,215,.55);box-shadow:0 0 0 3px rgba(61,218,215,.12)}
.act-btn{
  width:100%;margin-top:12px;padding:14px;border:0;border-radius:15px;cursor:pointer;
  font-size:15px;font-weight:800;color:#05121a;letter-spacing:.02em;
  background:linear-gradient(92deg,var(--aqua),#8de8ff 60%,#b7c6ff);
  box-shadow:0 18px 40px -20px rgba(61,218,215,.8);
}
.act-btn:disabled{opacity:.6;cursor:default}
.msg{display:none;margin-top:12px;padding:12px 14px;border-radius:13px;font-size:13px;line-height:1.6}
.msg.ok{display:block;background:rgba(74,222,128,.12);border:1px solid rgba(74,222,128,.35);color:#b7f7cf}
.msg.err{display:block;background:rgba(251,113,133,.12);border:1px solid rgba(251,113,133,.35);color:#ffd0d6}
.msg.info{display:block;background:rgba(255,255,255,.06);border:1px solid var(--line);color:#cbd6e6}

/* ---------- 底部 ---------- */
.foot{margin-top:26px;text-align:center;font-size:12px;color:#68758a;line-height:2}
.foot a{color:var(--aqua);text-decoration:none}
.badges{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}
.badge{font-size:11px;padding:6px 10px;border-radius:999px;border:1px solid var(--line);background:rgba(255,255,255,.045);color:var(--sub)}
.dot{width:6px;height:6px;border-radius:50%;background:var(--ok);display:inline-block;margin-right:6px;box-shadow:0 0 10px var(--ok)}
</style>
</head>
<body>
<div class="wrap">

  <div class="brand">
    <div class="logo" aria-hidden="true">
      <svg viewBox="0 0 48 48" fill="none">
        <path d="M14 19c-2.6 0-4.4-2-4.4-4.4 0-1.6.9-3 2.3-3.7-.2 2.4 1.2 3.6 2.6 3.9C16.2 10.6 20 8 24 8s7.8 2.6 9.5 6.8c1.4-.3 2.8-1.5 2.6-3.9 1.4.7 2.3 2.1 2.3 3.7C38.4 17 36.6 19 34 19c1.6 1.9 2.4 4.2 2.4 6.7 0 6.5-5.5 11.3-12.4 11.3S11.6 32.2 11.6 25.7c0-2.5.8-4.8 2.4-6.7Z" fill="#0a1520"/>
        <circle cx="19.4" cy="24.4" r="1.9" fill="#9bf6f2"/>
        <circle cx="28.6" cy="24.4" r="1.9" fill="#9bf6f2"/>
        <path d="M21.6 29.4c1.5 1.2 3.3 1.2 4.8 0" stroke="#9bf6f2" stroke-width="1.6" stroke-linecap="round"/>
      </svg>
    </div>
    <div>
      <h1>黑猫拦截 <span>Pro</span></h1>
      <p>网络层拦截 · iOS 15 – 27 · 公益频道 @HeiMaoClub</p>
    </div>
  </div>

<?php if (!empty($ann['content']) || !empty($ann['title'])): ?>
  <div class="card">
    <div class="card-head" style="margin-bottom:10px">
      <span class="tag ghost">📢 公告</span>
    </div>
    <div class="ann">
      <?php if (!empty($ann['title'])): ?><h3><?= h($ann['title']) ?></h3><?php endif; ?>
      <p><?= h($ann['content'] ?? '') ?></p>
    </div>
  </div>
<?php endif; ?>

  <!-- ---------- 最新版本 ---------- -->
  <div class="card">
    <div class="card-head">
      <div>
        <span class="tag"><span class="dot"></span>最新版本</span>
        <div class="ver">
          <?= $latest ? h('v' . $latest['version']) : h(($vrow['version'] ?? '—')) ?>
          <small><?= $latest ? 'build ' . (int) $latest['build'] : '' ?></small>
        </div>
        <div class="meta">
          <?php if ($latest): ?>
            更新于 <?= date('Y-m-d H:i', (int) max(array_column($latest['files'], 'mtime'))) ?> ·
            <?= h(fmtSize((int) array_sum(array_column($latest['files'], 'size')))) ?>
          <?php else: ?>
            安装包还在路上，稍后刷新本页
          <?php endif; ?>
        </div>
      </div>
      <span class="tag ghost">iOS</span>
    </div>

    <?php if ($latest): ?>
    <div class="dl">
      <?php if ($t = $pickTroll($latest)): ?>
      <a class="btn <?= $oneForAll ? 'primary' : 'primary' ?>" href="/dl/<?= h(rawurlencode($t['name'])) ?>" download>
        <span class="ico"><svg viewBox="0 0 24 24"><path d="M12 3v12"/><path d="m7 11 5 5 5-5"/><path d="M5 20h14"/></svg></span>
        <span>
          <b><?= isset($latest['files']['trollstore']) ? '巨魔直装包' : '通用包（巨魔直装）' ?></b>
          <em>TrollStore 直接安装 · <?= h(fmtSize($t['size'])) ?></em>
        </span>
      </a>
      <?php endif; ?>

      <?php if ($u = $pickUser($latest)): ?>
      <a class="btn" href="/dl/<?= h(rawurlencode($u['name'])) ?>" download>
        <span class="ico"><svg viewBox="0 0 24 24"><path d="M12 15V3"/><path d="m8 7 4-4 4 4"/><path d="M4 14v5a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5"/></svg></span>
        <span>
          <b><?= isset($latest['files']['unsigned']) ? '自签包（未签名）' : '自签 / ESign 重签' ?></b>
          <em><?= isset($latest['files']['unsigned']) ? 'ESign · 爱思 · 侧载工具' : '同一个包，重签后安装' ?> · <?= h(fmtSize($u['size'])) ?></em>
        </span>
      </a>
      <?php endif; ?>
    </div>

    <?php if ($oneForAll): ?>
      <p class="hint">这一个包里主程序和隧道扩展都已经签好，巨魔直接装；用 ESign / 爱思的重新签一次也能装，不需要再找第二个包。</p>
    <?php endif; ?>

    <div class="badges">
      <span class="badge"><span class="dot"></span>支持 iOS 15 – 27</span>
      <span class="badge">DNS + 连接层拦截</span>
      <span class="badge">云端多套规则</span>
      <span class="badge">卡密授权</span>
    </div>
    <?php endif; ?>

    <?php if (!empty($vrow['notes'])): ?>
    <div class="note">
      <h4>这个版本改了什么</h4>
      <p style="margin:0;font-size:13px;line-height:1.85;color:#d7e0ee;white-space:pre-wrap"><?= h($vrow['notes']) ?></p>
    </div>
    <?php endif; ?>

    <div class="note">
      <h4>安装步骤</h4>
      <ol>
        <li><b>巨魔用户</b>：点上面的巨魔包下载 → TrollStore 打开 → 直接 Install，<b>不要</b>再用「巨魔签名」重签一次。</li>
        <li><b>自签用户</b>：点自签包下载 → ESign / 爱思导入 → 用你自己的证书签名安装。</li>
        <li>装之前先把手机里的旧版删掉，避免两个版本并存。</li>
        <li>装好后打开 App → 输入卡密激活 → 点中间的大圆球开启防护。</li>
      </ol>
    </div>
  </div>

  <!-- ---------- 历史版本 ---------- -->
  <?php if (count($packs) > 1): ?>
  <details class="history">
    <summary><span>历史版本（<?= count($packs) - 1 ?> 个）</span></summary>
    <div class="card" style="margin-top:10px;padding:10px 16px">
      <?php foreach ($packs as $b => $p): if ($b === $latestBuild) continue; ?>
        <div class="hrow">
          <div>
            <div class="v">v<?= h($p['version']) ?> <span style="color:var(--sub);font-weight:500">build <?= (int) $p['build'] ?></span></div>
            <div class="s"><?= date('Y-m-d H:i', (int) max(array_column($p['files'], 'mtime'))) ?></div>
          </div>
          <div class="hlinks">
            <?php if ($t = $pickTroll($p)): ?>
              <a class="mini" href="/dl/<?= h(rawurlencode($t['name'])) ?>" download>巨魔</a>
            <?php endif; ?>
            <?php if ($u = $pickUser($p)): ?>
              <a class="mini gray" href="/dl/<?= h(rawurlencode($u['name'])) ?>" download>自签</a>
            <?php endif; ?>
          </div>
        </div>
      <?php endforeach; ?>
    </div>
  </details>
  <?php endif; ?>

  <!-- ---------- 在线激活（保留） ---------- -->
  <details class="history" id="activate">
    <summary><span>已经有卡密？在线激活 / 查状态</span></summary>
    <div class="card" style="margin-top:10px">
      <p class="meta" style="margin:0 0 4px">把 App 设置页显示的 8 位设备码和卡密填进来，激活后 App 里点「刷新状态」即可。</p>
      <div class="act-grid">
        <input id="pin" inputmode="numeric" maxlength="<?= $pinLen ?>" placeholder="设备码（<?= $pinLen ?> 位数字）">
        <input id="code" placeholder="卡密 XXXX-XXXX-XXXX-XXXX" autocomplete="off" spellcheck="false">
      </div>
      <button class="act-btn" id="go">激活 / 续期</button>
      <div class="msg" id="msg"></div>
    </div>
  </details>

  <div class="foot">
    公益频道 <a href="https://t.me/HeiMaoClub" target="_blank" rel="noopener">@HeiMaoClub</a> · 仅供学习与公益使用<br>
    遇到问题带上设备码和截图找管理员
  </div>
</div>

<script>
(function () {
  var pin = document.getElementById('pin'), code = document.getElementById('code');
  var btn = document.getElementById('go'), msg = document.getElementById('msg');
  var ERR = {
    card_not_found: '卡密不存在，核对一下有没有输错',
    card_bound: '这张卡绑在另一台设备上。如果刚重装过，让管理员在后台解绑一次即可（1.0.5 起设备码不会再变）',
    card_used: '这张卡刚被别人抢用了，稍后重试',
    card_expired: '这张卡已到期',
    card_revoked: '这张卡已被作废',
    card_format: '卡密格式不对',
    bad_pin: '设备码必须是 <?= $pinLen ?> 位数字',
    rate_limited: '请求太频繁，歇一会儿再试',
    server_error: '服务器繁忙，稍后重试'
  };
  function say(text, kind) {
    msg.textContent = text;
    msg.className = 'msg ' + (kind || 'info');
  }
  pin.addEventListener('input', function () {
    pin.value = pin.value.replace(/\D/g, '').slice(0, <?= $pinLen ?>);
  });
  code.addEventListener('input', function () {
    var v = code.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 16);
    code.value = v.replace(/(.{4})/g, '$1-').replace(/-$/, '');
  });
  btn.addEventListener('click', function () {
    var p = (pin.value || '').replace(/\D/g, '');
    var c = (code.value || '').trim();
    if (p.length !== <?= $pinLen ?>) { say('先填完整的设备码', 'err'); return; }
    if (!c) { say('先填卡密', 'err'); return; }
    btn.disabled = true; btn.textContent = '提交中…';
    fetch('/api/card/redeem', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pin: p, code: c })
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.ok) {
        var t = new Date((j.card_expire_at || j.expire_at) * 1000);
        say('激活成功，到期时间 ' + t.toLocaleString('zh-CN'), 'ok');
      } else {
        say(ERR[(j && j.error) || ''] || '激活失败，稍后再试', 'err');
      }
    }).catch(function () {
      say('网络不通，检查一下网络再试', 'err');
    }).finally(function () {
      btn.disabled = false; btn.textContent = '激活 / 续期';
    });
  });
})();
</script>
</body>
</html>
