<?php
declare(strict_types=1);
require __DIR__ . '/../../app/bootstrap.php';
/* 后台页面不缓存：避免手机浏览器拿着旧版脚本，和新接口对不上 */
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="#0f1115">
<title>黑猫拦截 Pro · 运维控制台</title>
<style>
/* ─────────────────────────────────────────────────────────────
   设计系统
   深色侧栏 + 浅色工作区；1px 边框、8px 圆角、无渐变、无阴影堆叠。
   信息密度优先：13px 正文、12px 辅助、11px 标签。
   ───────────────────────────────────────────────────────────── */
*,*::before,*::after{box-sizing:border-box}
:root{
  --bg:#f6f7f9; --panel:#ffffff; --line:#e6e8ec; --line-soft:#eef0f3;
  --ink:#111827; --ink-2:#4b5563; --ink-3:#8b93a1; --ink-4:#aeb5c0;
  --nav:#0f1115; --nav-2:#171a20; --nav-ink:#c8ccd4; --nav-ink-2:#7b828f;
  --accent:#2563eb; --accent-soft:#eff4ff;
  --ok:#059669; --ok-soft:#ecfdf5;
  --warn:#d97706; --warn-soft:#fffbeb;
  --danger:#dc2626; --danger-soft:#fef2f2;
  --r:8px; --r-sm:6px;
}
html,body{margin:0;padding:0}
body{
  background:var(--bg); color:var(--ink);
  font:13px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility;
}
button,input,select,textarea{font:inherit;color:inherit}
a{color:var(--accent);text-decoration:none}
.hide{display:none!important}
.mono{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;font-variant-numeric:tabular-nums}
.num{font-variant-numeric:tabular-nums}

/* ── 登录 ── */
#auth{position:fixed;inset:0;display:flex;background:var(--nav)}
.auth-side{
  flex:1;display:none;flex-direction:column;justify-content:space-between;
  padding:40px;color:#fff;background:
    radial-gradient(700px 380px at 12% 8%, rgba(37,99,235,.20), transparent 70%),
    linear-gradient(180deg,#0f1115,#0b0d11);
}
.auth-brand{display:flex;align-items:center;gap:10px}
.auth-mark{width:34px;height:34px;border-radius:9px;background:#fff;color:#0f1115;display:grid;place-items:center;font-weight:700;font-size:14px}
.auth-side h2{margin:0 0 10px;font-size:27px;line-height:1.35;font-weight:650;letter-spacing:-.02em}
.auth-side p{margin:0;max-width:380px;color:#9aa2af;font-size:13px;line-height:1.75}
.auth-facts{display:flex;gap:28px;margin-top:30px}
.auth-facts b{display:block;font-size:19px;font-weight:650;letter-spacing:-.01em}
.auth-facts span{font-size:11px;color:#7b828f}
.auth-main{width:100%;max-width:460px;display:flex;align-items:center;justify-content:center;background:var(--bg);padding:28px}
.auth-card{width:100%;max-width:352px}
.auth-card h1{margin:0;font-size:20px;font-weight:650;letter-spacing:-.01em}
.auth-card .sub{margin:5px 0 22px;color:var(--ink-3);font-size:12.5px}
@media(min-width:900px){
  .auth-side{display:flex}
  .auth-main{flex:0 0 480px}
}

/* ── 布局 ── */
#shell{min-height:100vh}
.sidebar{
  position:fixed;inset:0 auto 0 0;width:236px;z-index:50;
  background:var(--nav);color:var(--nav-ink);display:flex;flex-direction:column;
  transform:translateX(-100%);transition:transform .18s ease;
}
.sidebar.open{transform:translateX(0)}
.sb-brand{height:56px;display:flex;align-items:center;gap:10px;padding:0 14px;border-bottom:1px solid #22262e}
.sb-mark{width:28px;height:28px;border-radius:7px;background:#fff;color:#0f1115;display:grid;place-items:center;font-weight:700;font-size:12px;flex:none}
.sb-name{font-size:12.5px;font-weight:600;color:#e9ebef;line-height:1.25}
.sb-sub{font-size:10.5px;color:var(--nav-ink-2);line-height:1.25}
.sb-nav{flex:1;overflow-y:auto;padding:10px 8px 16px}
.sb-group{font-size:10px;letter-spacing:.09em;text-transform:uppercase;color:#5b626e;padding:14px 8px 6px;font-weight:600}
.nav-item{
  width:100%;display:flex;align-items:center;gap:9px;height:32px;padding:0 9px;margin:1px 0;
  background:none;border:0;border-radius:6px;color:var(--nav-ink);font-size:12.5px;text-align:left;cursor:pointer;
}
.nav-item:hover{background:#181c22;color:#fff}
.nav-item.active{background:#1d222a;color:#fff;font-weight:550}
.nav-item .dot{margin-left:auto;width:5px;height:5px;border-radius:50%;background:var(--warn)}
.nav-item svg{flex:none;opacity:.85}
.sb-foot{border-top:1px solid #22262e;padding:10px 14px;display:flex;align-items:center;justify-content:space-between;gap:8px}
.sb-foot .who{font-size:11.5px;color:var(--nav-ink-2)}
.sb-foot .who b{display:block;color:#e9ebef;font-size:12px;font-weight:550}

.work{margin-left:0;min-height:100vh;display:flex;flex-direction:column}
@media(min-width:1024px){
  .sidebar{transform:none}
  .work{margin-left:236px}
}
.topbar{
  height:56px;background:#fff;border-bottom:1px solid var(--line);
  display:flex;align-items:center;gap:12px;padding:0 20px;position:sticky;top:0;z-index:30;
}
#navToggle{display:grid;place-items:center;width:32px;height:32px;border:1px solid var(--line);border-radius:6px;background:#fff;cursor:pointer}
@media(min-width:1024px){#navToggle{display:none}}
.crumb{display:flex;align-items:center;gap:8px;font-size:12.5px;color:var(--ink-3);min-width:0}
.crumb b{color:var(--ink);font-weight:600}
.top-right{margin-left:auto;display:flex;align-items:center;gap:8px}
.env{display:inline-flex;align-items:center;gap:6px;height:26px;padding:0 9px;border-radius:999px;
  border:1px solid var(--line);background:#fff;font-size:11.5px;color:var(--ink-2);white-space:nowrap}
.env .led{width:6px;height:6px;border-radius:50%;background:var(--ok)}
.env.warn .led{background:var(--warn)}
.env.bad .led{background:var(--danger)}
.env.warn{color:#92400e;background:var(--warn-soft);border-color:#fde68a}
.env.bad{color:#991b1b;background:var(--danger-soft);border-color:#fecaca}

.content{flex:1;padding:20px;max-width:1320px;width:100%;margin:0 auto}
.page{display:none}
.page.active{display:block}
.page-head{display:flex;align-items:flex-start;gap:16px;margin-bottom:16px}
.page-head h1{margin:0;font-size:18px;font-weight:650;letter-spacing:-.01em}
.page-head p{margin:3px 0 0;color:var(--ink-3);font-size:12px}
.page-head .actions{margin-left:auto;display:flex;gap:8px;flex-wrap:wrap}

/* ── 卡片 ── */
.card{background:var(--panel);border:1px solid var(--line);border-radius:var(--r)}
.card-hd{padding:13px 16px;border-bottom:1px solid var(--line-soft);display:flex;align-items:center;gap:12px}
.card-hd h2{margin:0;font-size:13px;font-weight:600}
.card-hd p{margin:2px 0 0;font-size:11.5px;color:var(--ink-3)}
.card-hd .right{margin-left:auto;display:flex;gap:6px;align-items:center}
.card-bd{padding:16px}
.grid{display:grid;gap:12px}
.g4{grid-template-columns:repeat(2,minmax(0,1fr))}
.g3{grid-template-columns:repeat(1,minmax(0,1fr))}
.g2{grid-template-columns:minmax(0,1fr)}
@media(min-width:820px){
  .g4{grid-template-columns:repeat(4,minmax(0,1fr))}
  .g3{grid-template-columns:repeat(3,minmax(0,1fr))}
  .g2{grid-template-columns:repeat(2,minmax(0,1fr))}
  .g21{grid-template-columns:minmax(0,2fr) minmax(0,1fr)}
}

/* 指标卡 */
.metric{padding:15px 16px}
.metric .lbl{font-size:11.5px;color:var(--ink-3);display:flex;align-items:center;gap:6px}
.metric .val{font-size:27px;font-weight:650;letter-spacing:-.02em;line-height:1.15;margin-top:6px;font-variant-numeric:tabular-nums}
.metric .foot{margin-top:5px;font-size:11px;color:var(--ink-4);display:flex;align-items:center;gap:5px;min-height:15px}
.metric .trend{color:var(--ok);font-weight:550}
.metric .trend.down{color:var(--danger)}

/* 状态行 */
.srow{display:flex;align-items:center;gap:12px;padding:11px 16px;border-bottom:1px solid var(--line-soft)}
.srow:last-child{border-bottom:0}
.srow .t{font-size:12.5px;color:var(--ink)}
.srow .d{font-size:11px;color:var(--ink-3);margin-top:1px}
.srow .v{margin-left:auto;font-size:12.5px;color:var(--ink-2)}

/* ── 表格 ── */
.tbl-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}
table.tbl{width:100%;border-collapse:collapse;font-size:12.5px}
table.tbl th{
  position:sticky;top:0;background:#fafbfc;text-align:left;font-weight:600;color:var(--ink-3);
  font-size:11px;letter-spacing:.04em;text-transform:uppercase;padding:9px 12px;border-bottom:1px solid var(--line);
  white-space:nowrap;
}
table.tbl td{padding:10px 12px;border-bottom:1px solid var(--line-soft);vertical-align:middle}
table.tbl tbody tr:hover{background:#fafbfc}
table.tbl tbody tr:last-child td{border-bottom:0}
table.tbl td.actions{text-align:right;white-space:nowrap}
table.tbl .empty{text-align:center;color:var(--ink-4);padding:34px 12px;font-size:12.5px}

/* ── 控件 ── */
.btn{
  display:inline-flex;align-items:center;justify-content:center;gap:6px;height:32px;padding:0 12px;
  border-radius:var(--r-sm);border:1px solid var(--line);background:#fff;color:var(--ink);
  font-size:12.5px;font-weight:500;cursor:pointer;white-space:nowrap;transition:background .12s,border-color .12s;
}
.btn:hover{background:#f7f8fa;border-color:#d8dce2}
.btn:disabled{opacity:.55;cursor:not-allowed}
.btn-primary{background:var(--ink);border-color:var(--ink);color:#fff}
.btn-primary:hover{background:#1f2937;border-color:#1f2937}
.btn-danger{color:var(--danger);border-color:#f3c4c4;background:#fff}
.btn-danger:hover{background:var(--danger-soft);border-color:#efa9a9}
.btn-danger-solid{background:var(--danger);border-color:var(--danger);color:#fff}
.btn-danger-solid:hover{background:#b91c1c;border-color:#b91c1c}
.btn-ghost{border-color:transparent;background:transparent;color:var(--ink-2)}
.btn-ghost:hover{background:#f2f4f7}
.btn-sm{height:27px;padding:0 9px;font-size:11.5px;border-radius:5px}
.btn-xs{height:24px;padding:0 8px;font-size:11px;border-radius:5px}
.label{display:block;font-size:11.5px;font-weight:550;color:var(--ink-2);margin-bottom:5px}
.input,.select,.textarea{
  width:100%;height:32px;padding:0 10px;border:1px solid var(--line);border-radius:var(--r-sm);background:#fff;
  font-size:12.5px;outline:none;transition:border-color .12s,box-shadow .12s;
}
.textarea{height:auto;padding:9px 10px;line-height:1.6;resize:vertical}
.input:focus,.select:focus,.textarea:focus{border-color:#9db6f0;box-shadow:0 0 0 3px rgba(37,99,235,.10)}
.input::placeholder,.textarea::placeholder{color:#b6bcc6}
.hint{font-size:11px;color:var(--ink-4);margin:6px 0 0;line-height:1.5}
.check{width:14px;height:14px;border-radius:4px;border:1px solid #cfd4dc;accent-color:var(--ink)}
.row{display:flex;align-items:center;gap:10px}
.space-y>*+*{margin-top:12px}
.err{font-size:11.5px;color:var(--danger);min-height:16px}

/* 开关 */
.switch{position:relative;display:inline-flex;width:36px;height:20px;flex:none;cursor:pointer}
.switch input{position:absolute;opacity:0;width:100%;height:100%;margin:0;cursor:pointer}
.switch i{position:absolute;inset:0;border-radius:999px;background:#d5d9e0;transition:background .16s}
.switch i::after{content:"";position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#fff;transition:transform .16s;box-shadow:0 1px 2px rgba(0,0,0,.15)}
.switch input:checked+i{background:var(--ink)}
.switch input:checked+i::after{transform:translateX(16px)}
.switch.danger input:checked+i{background:var(--danger)}

/* 徽标 */
.pill{display:inline-flex;align-items:center;gap:4px;height:20px;padding:0 7px;border-radius:4px;font-size:10.5px;font-weight:600;letter-spacing:.02em;white-space:nowrap}
.pill-zinc{background:#f2f4f7;color:#4b5563}
.pill-green{background:var(--ok-soft);color:#047857}
.pill-amber{background:var(--warn-soft);color:#b45309}
.pill-rose{background:var(--danger-soft);color:#b91c1c}
.pill-blue{background:var(--accent-soft);color:#1d4ed8}
.pill-violet{background:#f5f3ff;color:#6d28d9}

/* 分段标签 */
.tabs{display:inline-flex;padding:2px;background:#f2f4f7;border-radius:7px;gap:2px}
.tabs button{border:0;background:none;height:26px;padding:0 11px;border-radius:5px;font-size:12px;color:var(--ink-2);cursor:pointer;font-weight:500}
.tabs button.active{background:#fff;color:var(--ink);box-shadow:0 1px 2px rgba(16,24,40,.06)}

/* 空状态 */
.empty-state{padding:30px 16px;text-align:center;color:var(--ink-4);font-size:12px}
.empty-state b{display:block;color:var(--ink-2);font-size:12.5px;font-weight:550;margin-bottom:3px}

/* 进度条 */
.bar{height:6px;border-radius:999px;background:#f0f2f5;overflow:hidden}
.bar>i{display:block;height:100%;border-radius:999px;background:var(--ink)}

/* 抽屉 */
.drawer{position:fixed;inset:0;z-index:80}
.drawer-mask{position:absolute;inset:0;background:rgba(15,17,21,.38)}
.drawer-panel{
  position:absolute;top:0;right:0;bottom:0;width:min(520px,100%);background:#fff;
  border-left:1px solid var(--line);display:flex;flex-direction:column;
  animation:slidein .18s ease-out;
}
@keyframes slidein{from{transform:translateX(18px);opacity:.6}to{transform:none;opacity:1}}
.drawer-hd{height:60px;padding:0 18px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:12px;flex:none}
.drawer-hd .ttl{font-size:14px;font-weight:600;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.drawer-hd .sub{font-size:11.5px;color:var(--ink-3);margin-top:1px}
.drawer-bd{flex:1;overflow-y:auto;padding:18px}
.drawer-ft{border-top:1px solid var(--line);padding:12px 18px;display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap;background:#fff;flex:none}

/* 弹窗 */
.modal{position:fixed;inset:0;z-index:90;display:grid;place-items:center;padding:18px}
.modal-mask{position:absolute;inset:0;background:rgba(15,17,21,.42)}
.modal-panel{position:relative;width:min(420px,100%);background:#fff;border-radius:10px;border:1px solid var(--line);overflow:hidden}
.modal-hd{padding:18px 18px 0}
.modal-hd h3{margin:0;font-size:14px;font-weight:600}
.modal-hd p{margin:5px 0 0;font-size:12px;color:var(--ink-3);line-height:1.6}
.modal-bd{padding:14px 18px 0}
.modal-ft{padding:16px 18px 18px;display:flex;justify-content:flex-end;gap:8px}

/* Toast */
.toast{
  position:fixed;left:50%;bottom:26px;transform:translate(-50%,12px);z-index:100;
  background:#111827;color:#fff;font-size:12.5px;padding:9px 15px;border-radius:7px;
  opacity:0;pointer-events:none;transition:opacity .16s,transform .16s;max-width:88vw;text-align:center;
}
.toast.show{opacity:1;transform:translate(-50%,0)}
.toast.error{background:#b91c1c}

/* 折线/柱状 */
.spark{display:flex;align-items:flex-end;gap:4px;height:56px}
.spark i{flex:1;background:#e5e7eb;border-radius:3px 3px 0 0;min-height:3px;position:relative}
.spark i.hot{background:#111827}
.legend{display:flex;gap:14px;font-size:11px;color:var(--ink-3);margin-top:10px;flex-wrap:wrap}
.legend span{display:inline-flex;align-items:center;gap:5px}
.legend b{width:7px;height:7px;border-radius:2px;display:inline-block}

/* 运维页专用 */
.op-hero{display:grid;gap:12px}
@media(min-width:900px){.op-hero{grid-template-columns:1fr 1fr}}
.op-card{padding:18px}
.op-card .head{display:flex;align-items:flex-start;gap:12px}
.op-card .head h3{margin:0;font-size:14px;font-weight:600}
.op-card .head p{margin:4px 0 0;font-size:11.5px;color:var(--ink-3);line-height:1.6;max-width:340px}
.op-card .ctrl{margin-left:auto}
.op-state{display:flex;align-items:center;gap:8px;margin-top:14px;padding:10px 12px;border-radius:6px;background:#fafbfc;border:1px solid var(--line-soft);font-size:12px;color:var(--ink-2)}
.op-state b{color:var(--ink)}
.dot{width:7px;height:7px;border-radius:50%;display:inline-block;flex:none}
.dot.on{background:var(--ok)}
.dot.off{background:#c3c8d0}
.dot.warn{background:var(--warn)}
.dot.bad{background:var(--danger)}

.alert{display:flex;gap:10px;padding:11px 13px;border-radius:7px;font-size:12px;line-height:1.6;border:1px solid}
.alert-info{background:#f8fafc;border-color:var(--line);color:var(--ink-2)}
.alert-warn{background:var(--warn-soft);border-color:#fde68a;color:#92400e}
.alert-bad{background:var(--danger-soft);border-color:#fecaca;color:#991b1b}
.alert b{font-weight:600}
</style>
</head>
<body>

<!-- ═══════════ 登录 ═══════════ -->
<div id="auth">
  <aside class="auth-side">
    <div class="auth-brand">
      <div class="auth-mark">黑</div>
      <div>
        <div style="font-size:13px;font-weight:600">黑猫拦截 Pro</div>
        <div style="font-size:11px;color:#7b828f">运维控制台</div>
      </div>
    </div>
    <div>
      <h2>把授权、设备与云端规则<br>收进一个面板</h2>
      <p>卡密分层、在线心跳、强制下线、规则合并下发、版本发布、维护与熔断，全部集中在这里。所有写操作留审计。</p>
      <div class="auth-facts">
        <div><b>4</b><span>授权层级</span></div>
        <div><b>v4</b><span>加密通道</span></div>
        <div><b>iOS 14+</b><span>支持范围</span></div>
      </div>
    </div>
    <div style="font-size:11px;color:#5b626e">仅授权人员访问 · 操作留痕</div>
  </aside>

  <main class="auth-main">
    <div class="auth-card">
      <h1>登录控制台</h1>
      <p class="sub">使用管理员账号继续</p>
      <form id="loginForm" autocomplete="on">
        <div style="margin-bottom:12px">
          <label class="label" for="u">账号</label>
          <input id="u" class="input" style="height:36px" autocomplete="username" placeholder="admin" spellcheck="false">
        </div>
        <div style="margin-bottom:12px">
          <div style="display:flex;align-items:center;justify-content:space-between">
            <label class="label" for="p">密码</label>
            <button type="button" id="pwToggle" class="btn btn-ghost btn-xs" style="margin-bottom:5px">显示</button>
          </div>
          <input id="p" type="password" class="input" style="height:36px" autocomplete="current-password" placeholder="••••••••">
        </div>
        <div id="loginErr" class="alert alert-bad hide" style="margin-bottom:12px"></div>
        <button class="btn btn-primary" style="height:36px;width:100%" type="submit" id="loginBtn">登录</button>
      </form>
      <p class="hint" style="margin-top:16px">连续输错会被限流，稍等一会儿再试。<br>建议使用 Chrome / Safari 最新版访问。</p>
    </div>
  </main>
</div>

<!-- ═══════════ 主界面 ═══════════ -->
<div id="shell" class="hide">
  <div id="navMask" class="drawer-mask hide" style="z-index:45;position:fixed;inset:0;background:rgba(15,17,21,.36)" onclick="document.getElementById('sidebar').classList.remove('open');this.classList.add('hide')"></div>

  <aside class="sidebar" id="sidebar">
    <div class="sb-brand">
      <div class="sb-mark">黑</div>
      <div>
        <div class="sb-name">黑猫拦截 Pro</div>
        <div class="sb-sub">运维控制台 v1.2.4</div>
      </div>
    </div>

    <nav class="sb-nav">
      <div class="sb-group">运营</div>
      <button class="nav-item active" data-view="overview">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>
        概览
      </button>
      <button class="nav-item" data-view="cards">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="8" cy="15" r="4"/><path d="M10.8 12.2 20 3M17 3h3v3"/></svg>
        卡密
      </button>
      <button class="nav-item" data-view="devices">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/></svg>
        设备与配对
      </button>

      <div class="sb-group">发布</div>
      <button class="nav-item" data-view="rules">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m12 3 9 5-9 5-9-5 9-5z"/><path d="m3 13 9 5 9-5"/></svg>
        规则与版本
      </button>
      <button class="nav-item" data-view="notice">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 12a8 8 0 0 1-8 8H7l-4 3V12a8 8 0 0 1 8-8h2a8 8 0 0 1 8 8z"/></svg>
        公告
      </button>

      <div class="sb-group">系统</div>
      <button class="nav-item" data-view="ops">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3v9"/><path d="M6.5 6.5a8 8 0 1 0 11 0"/></svg>
        维护与熔断<span class="dot hide" id="navOpsDot"></span>
      </button>
      <button class="nav-item" data-view="logs">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>
        日志
      </button>
      <button class="nav-item" data-view="settings">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/></svg>
        设置
      </button>
    </nav>

    <div class="sb-foot">
      <div class="who"><b id="whoami">admin</b>管理员</div>
      <button class="btn btn-ghost btn-xs" id="logout" style="color:#9aa2af">退出</button>
    </div>
  </aside>

  <div class="work">
    <header class="topbar">
      <button id="navToggle" aria-label="菜单">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18M3 12h18M3 18h18"/></svg>
      </button>
      <div class="crumb"><span>控制台</span><span style="color:#c3c8d0">/</span><b id="topTitle">概览</b></div>
      <div class="top-right">
        <span class="env" id="topStatus"><i class="led"></i>运行正常</span>
        <span class="env" id="topVersion" style="font-family:ui-monospace,monospace">—</span>
      </div>
    </header>

    <main class="content">

      <!-- 概览 -->
      <section class="page active" data-page="overview">
        <div class="page-head">
          <div>
            <h1>概览</h1>
            <p>授权、设备与云端发布的当前状态</p>
          </div>
          <div class="actions">
            <button class="btn btn-sm" id="ov_refresh">刷新</button>
            <button class="btn btn-sm btn-primary" data-go="cards" data-act="gen">生成卡密</button>
          </div>
        </div>

        <div class="grid g4" style="margin-bottom:12px">
          <div class="card metric">
            <div class="lbl">在线设备</div>
            <div class="val" id="k_online">—</div>
            <div class="foot" id="k_online_foot">近 5 分钟有心跳</div>
          </div>
          <div class="card metric">
            <div class="lbl">未使用卡密</div>
            <div class="val" id="k_unused">—</div>
            <div class="foot" id="k_unused_foot">库存</div>
          </div>
          <div class="card metric">
            <div class="lbl">24 小时兑换</div>
            <div class="val" id="k_redeem">—</div>
            <div class="foot" id="k_redeem_foot">成功兑换</div>
          </div>
          <div class="card metric">
            <div class="lbl">24 小时失败</div>
            <div class="val" id="k_fail">—</div>
            <div class="foot" id="k_fail_foot">兑换失败</div>
          </div>
        </div>

        <div class="grid g21" style="margin-bottom:12px">
          <div class="card">
            <div class="card-hd">
              <div><h2>运行状态</h2><p>云端开关对客户端的实际影响</p></div>
              <div class="right"><button class="btn btn-xs" data-go="ops">运维设置</button></div>
            </div>
            <div id="ov_status"></div>
          </div>
          <div class="card">
            <div class="card-hd"><div><h2>发布</h2><p>当前版本与规则</p></div></div>
            <div id="ov_publish"></div>
          </div>
        </div>

        <div class="grid g2">
          <div class="card">
            <div class="card-hd">
              <div><h2>事件构成</h2><p>最近 150 条客户端事件</p></div>
              <div class="right"><span class="pill pill-zinc" id="ov_total">—</span></div>
            </div>
            <div class="card-bd" id="ov_kinds"></div>
          </div>
          <div class="card">
            <div class="card-hd">
              <div><h2>最近活动</h2><p>最新 8 条</p></div>
              <div class="right"><button class="btn btn-xs" data-go="logs">全部</button></div>
            </div>
            <div class="tbl-wrap">
              <table class="tbl"><thead><tr><th>时间</th><th>类型</th><th>设备</th><th>详情</th></tr></thead>
              <tbody id="ov_events"></tbody></table>
            </div>
          </div>
        </div>
      </section>

      <!-- 卡密 -->
      <section class="page" data-page="cards">
        <div class="page-head">
          <div><h1>卡密</h1><p>生成、分级、延期、作废与清理</p></div>
          <div class="actions">
            <button class="btn btn-sm" id="cardsExport">导出 CSV</button>
            <button class="btn btn-sm" id="cardsCleanup">清理</button>
            <button class="btn btn-sm btn-primary" id="genOpen">生成卡密</button>
          </div>
        </div>

        <div class="card" style="margin-bottom:12px">
          <div class="card-bd" style="padding:12px 16px">
            <div class="row" style="flex-wrap:wrap">
              <input id="c_q" class="input" style="width:220px" placeholder="搜索卡密 / 批次 / 配对码 / IP / 备注">
              <select id="c_status" class="select" style="width:130px">
                <option value="-1">全部状态</option>
                <option value="0">未使用</option>
                <option value="1">已兑换</option>
                <option value="2">已作废</option>
              </select>
              <select id="c_batch" class="select" style="width:190px"><option value="">全部批次</option></select>
              <span class="pill pill-zinc" id="c_total" style="margin-left:auto">—</span>
            </div>
          </div>
        </div>

        <div class="card">
          <div id="bulkbar" class="hide" style="padding:10px 16px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:8px;background:#fafbfc;flex-wrap:wrap">
            <span style="font-size:12px;color:#4b5563" id="bulkCount">已选 0 项</span>
            <div style="margin-left:auto;display:flex;gap:6px;flex-wrap:wrap">
              <button class="btn btn-xs" data-bulk="extend">延期 7 天</button>
              <button class="btn btn-xs" data-bulk="unban">解封</button>
              <button class="btn btn-xs btn-danger" data-bulk="ban">批量作废</button>
              <button class="btn btn-xs btn-danger" data-bulk="delete">删除</button>
            </div>
          </div>
          <div class="tbl-wrap">
            <table class="tbl">
              <thead><tr>
                <th style="width:34px"><input type="checkbox" class="check" id="checkAll"></th>
                <th>卡密</th><th style="width:76px">等级</th><th style="width:86px">状态</th>
                <th style="width:82px">时长</th><th style="width:140px">到期</th><th style="width:96px">绑定设备</th>
                <th style="width:190px"></th>
              </tr></thead>
              <tbody id="cardRows"></tbody>
            </table>
          </div>
          <div style="display:flex;align-items:center;gap:10px;padding:11px 16px;border-top:1px solid var(--line)">
            <span style="font-size:11.5px;color:#8b93a1" id="pageInfo">—</span>
            <div style="margin-left:auto;display:flex;gap:6px">
              <button class="btn btn-xs" id="pagePrev">上一页</button>
              <button class="btn btn-xs" id="pageNext">下一页</button>
            </div>
          </div>
        </div>
      </section>

      <!-- 设备与配对 -->
      <section class="page" data-page="devices">
        <div class="page-head">
          <div><h1>设备与配对</h1><p>在线心跳、强制下线、配对码授权</p></div>
          <div class="actions">
            <div class="tabs" id="devTabs">
              <button class="active" data-devtab="online">在线设备</button>
              <button data-devtab="pins">配对码</button>
            </div>
            <button class="btn btn-sm" id="devRefresh">刷新</button>
          </div>
        </div>

        <div id="dev-online">
          <div class="grid g3" style="margin-bottom:12px">
            <div class="card metric"><div class="lbl">当前在线</div><div class="val" id="onlineCount">—</div><div class="foot">近 5 分钟有心跳</div></div>
            <div class="card metric"><div class="lbl">在线窗口</div><div class="val">300<span style="font-size:13px;color:#8b93a1"> 秒</span></div><div class="foot">超过即判离线</div></div>
            <div class="card metric"><div class="lbl">心跳间隔</div><div class="val">150<span style="font-size:13px;color:#8b93a1"> 秒</span></div><div class="foot">由隧道扩展发出</div></div>
          </div>

          <div class="card" style="margin-bottom:12px">
            <div class="card-hd"><div><h2>强制下线</h2><p>手动指定设备码，客户端下次心跳（1 分钟内）断隧道并清规则</p></div></div>
            <form id="kickForm" class="card-bd">
              <div class="row" style="flex-wrap:wrap">
                <input id="k_pin" class="input mono" style="width:150px" placeholder="8 位设备码" maxlength="8">
                <input id="k_reason" class="input" style="flex:1;min-width:180px" placeholder="下线原因（客户端会显示）">
                <button class="btn btn-danger" type="submit">强制下线</button>
              </div>
            </form>
          </div>

          <div class="card">
            <div class="tbl-wrap">
              <table class="tbl">
                <thead><tr><th>设备码</th><th style="width:76px">等级</th><th style="width:96px">客户端</th><th>IP</th><th style="width:110px">最近心跳</th><th style="width:80px">授权</th><th>状态</th><th style="width:110px"></th></tr></thead>
                <tbody id="onlineRows"></tbody>
              </table>
            </div>
          </div>
        </div>

        <div id="dev-pins" class="hide">
          <div class="card">
            <div class="card-hd"><div><h2>配对码</h2><p>设备首次激活时登记的识别码</p></div></div>
            <div class="tbl-wrap">
              <table class="tbl">
                <thead><tr><th>配对码</th><th>首次出现</th><th>最近出现</th><th>IP</th><th>授权到</th><th style="width:80px">兑换次数</th><th style="width:110px"></th></tr></thead>
                <tbody id="pinRows"></tbody>
              </table>
            </div>
          </div>
        </div>
      </section>

      <!-- 规则与版本 -->
      <section class="page" data-page="rules">
        <div class="page-head">
          <div><h1>规则与版本</h1><p>规则集合并下发、客户端版本发布</p></div>
          <div class="actions">
            <button class="btn btn-sm" id="rs_apply">重算下发</button>
            <button class="btn btn-sm" id="rsNew">新建规则集</button>
          </div>
        </div>

        <div class="card" style="margin-bottom:12px">
          <div class="card-hd">
            <div><h2>当前下发</h2><p>勾选的规则集合并后加密下发</p></div>
            <div class="right">
              <button class="btn btn-xs" id="rs_all_on">全部启用</button>
              <button class="btn btn-xs" id="rs_all_off">全部停用</button>
            </div>
          </div>
          <div class="card-bd" id="rs_now"></div>
        </div>

        <div class="card" style="margin-bottom:18px">
          <div class="tbl-wrap">
            <table class="tbl">
              <thead><tr>
                <th style="width:40px">下发</th><th>名称</th><th style="width:110px">版本</th>
                <th style="width:120px">等级</th><th style="width:190px">规模</th><th style="width:80px">大小</th>
                <th style="width:130px">更新</th><th style="width:180px"></th>
              </tr></thead>
              <tbody id="rsRows"></tbody>
            </table>
          </div>
        </div>

        <div class="page-head" style="margin-top:6px">
          <div><h1 style="font-size:15px">客户端版本</h1><p>检测更新、强制更新与下载地址</p></div>
          <div class="actions">
            <button class="btn btn-sm" id="verRefresh">刷新</button>
            <button class="btn btn-sm btn-primary" id="verNew">发布版本</button>
          </div>
        </div>
        <div class="card">
          <div class="tbl-wrap">
            <table class="tbl">
              <thead><tr><th style="width:80px">平台</th><th style="width:100px">版本</th><th style="width:70px">Build</th><th style="width:80px">更新</th><th>下载地址</th><th style="width:130px">发布</th><th style="width:120px"></th></tr></thead>
              <tbody id="verRows"></tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- 公告 -->
      <section class="page" data-page="notice">
        <div class="page-head">
          <div><h1>公告</h1><p>客户端主界面顶部展示，发布后立即生效</p></div>
          <div class="actions"><button class="btn btn-sm btn-danger" id="n_clear">清空公告</button></div>
        </div>
        <div class="grid g2">
          <div class="card">
            <div class="card-hd"><div><h2>编辑</h2><p id="n_now">—</p></div></div>
            <form id="noticeForm" class="card-bd space-y-3">
              <div>
                <label class="label" for="n_title">标题</label>
                <input id="n_title" class="input" maxlength="80" placeholder="例如：1.2.4 已发布">
              </div>
              <div>
                <label class="label" for="n_content">正文</label>
                <textarea id="n_content" class="textarea" style="min-height:220px" placeholder="支持换行，客户端原样显示"></textarea>
              </div>
              <div class="err" id="n_hint"></div>
              <button class="btn btn-primary" type="submit">发布公告</button>
            </form>
          </div>
          <div class="card">
            <div class="card-hd"><div><h2>预览</h2><p>客户端实际观感</p></div></div>
            <div class="card-bd">
              <div style="border:1px solid var(--line);border-radius:8px;padding:14px;background:#fafbfc">
                <div id="pv_title" style="font-size:13px;font-weight:600;margin-bottom:6px;color:#8b93a1">公告标题</div>
                <div id="pv_body" style="font-size:12px;color:#8b93a1;white-space:pre-wrap;line-height:1.7">正文预览</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 维护与熔断 -->
      <section class="page" data-page="ops">
        <div class="page-head">
          <div><h1>维护与熔断</h1><p>改动即时生效：客户端下一个心跳（25 秒内）就会照做</p></div>
          <div class="actions"><button class="btn btn-sm" id="opsRefresh">刷新状态</button></div>
        </div>

        <div class="alert alert-info" style="margin-bottom:12px">
          <div>
            <b>即时生效说明</b>：客户端每 25 秒走一次独立心跳通道拉取这里的状态，不依赖卡密、不读缓存。
            维护开关一关，已经在维护页的客户端下一个心跳就会恢复；熔断一关，下一次启动或心跳就会正常进入。
          </div>
        </div>

        <div class="op-hero" style="margin-bottom:12px">
          <div class="card op-card">
            <div class="head">
              <div>
                <h3>维护模式</h3>
                <p>开启后客户端启动即进维护页，正文原样显示原因；后台与下载页不受影响。</p>
              </div>
              <div class="ctrl">
                <label class="switch" id="maintSwitch"><input type="checkbox" id="s_maint"><i></i></label>
              </div>
            </div>
            <div class="op-state" id="maintState"><span class="dot off"></span><span>当前：<b>正常</b></span></div>
            <div style="margin-top:12px">
              <label class="label" for="s_maint_reason">维护原因（客户端显示）</label>
              <input id="s_maint_reason" class="input" maxlength="200" placeholder="例如：服务端升级维护，预计 30 分钟">
            </div>
            <div style="margin-top:12px;display:flex;gap:8px;align-items:center">
              <button class="btn btn-sm btn-primary" id="maint_save">保存并立即生效</button>
              <span class="hint" style="margin:0" id="maint_hint"></span>
            </div>
          </div>

          <div class="card op-card">
            <div class="head">
              <div>
                <h3>熔断</h3>
                <p>防破解兜底：命中条件的客户端直接退出。关闭后，客户端下一个心跳即解除本地熔断标记。</p>
              </div>
              <div class="ctrl"><span class="pill pill-zinc" id="fusePill">关闭</span></div>
            </div>
            <div class="op-state" id="fuseState"><span class="dot off"></span><span>当前：<b>未熔断</b></span></div>
            <div style="margin-top:12px;display:grid;gap:10px;grid-template-columns:1fr 110px">
              <div>
                <label class="label" for="s_fuse_mode">熔断范围</label>
                <select id="s_fuse_mode" class="select">
                  <option value="off">关闭</option>
                  <option value="all">全部版本</option>
                  <option value="below">指定 build 以下</option>
                </select>
              </div>
              <div>
                <label class="label" for="s_fuse_build">Build 阈值</label>
                <input id="s_fuse_build" class="input num" type="number" min="0" max="999999" placeholder="121">
              </div>
            </div>
            <div style="margin-top:10px">
              <label class="label" for="s_fuse_reason">备注（仅后台可见）</label>
              <input id="s_fuse_reason" class="input" maxlength="200" placeholder="例：检测到 1.2.2 被改包">
            </div>
            <div style="margin-top:12px;display:flex;gap:8px;align-items:center">
              <button class="btn btn-sm btn-danger-solid" id="fuse_save">保存熔断设置</button>
              <span class="hint" style="margin:0" id="fuse_hint"></span>
            </div>
          </div>
        </div>

        <div class="card">
          <div class="card-hd"><div><h2>客户端闸门</h2><p>心跳与最低可用版本</p></div></div>
          <div class="card-bd">
            <div class="grid g2">
              <div>
                <label class="label" for="s_min_build">最低可用 build</label>
                <input id="s_min_build" class="input num" type="number" min="0" max="999999" placeholder="0 = 不限">
                <p class="hint">低于该 build 的客户端拿不到规则包；0 表示不限制。仅影响规则下发，不会让客户端闪退。</p>
              </div>
              <div>
                <div class="label">独立心跳</div>
                <div style="font-size:12px;color:#4b5563;line-height:1.7">
                  路径 <span class="mono">/api/app/pulse</span> · 25 秒一次 · 走 v4 加密通道<br>
                  连续 12 次拿不到结果（约 5 分钟）客户端按熔断处理；从没连通过的新装设备不会因此退出。
                </div>
                <button class="btn btn-sm" id="min_save" style="margin-top:10px">保存</button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- 日志 -->
      <section class="page" data-page="logs">
        <div class="page-head">
          <div><h1>日志</h1><p>后台操作审计与客户端事件</p></div>
          <div class="actions">
            <div class="tabs" id="logTabs">
              <button class="active" data-logtab="audit">后台审计</button>
              <button data-logtab="events">客户端事件</button>
            </div>
            <button class="btn btn-sm" id="logRefresh">刷新</button>
          </div>
        </div>
        <div class="card">
          <div class="tbl-wrap">
            <table class="tbl">
              <thead id="logHead"></thead>
              <tbody id="logRows"></tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- 设置 -->
      <section class="page" data-page="settings">
        <div class="page-head">
          <div><h1>设置</h1><p>生成默认值与账号安全</p></div>
        </div>

        <div class="grid g2" style="margin-bottom:12px">
          <div class="card">
            <div class="card-hd"><div><h2>生成默认值</h2><p>生成卡密时预填的参数</p></div></div>
            <div class="card-bd space-y-3">
              <div class="grid g2" style="gap:10px">
                <div><label class="label" for="s_count">默认数量</label><input id="s_count" class="input num" type="number" min="1" max="1000"></div>
                <div><label class="label" for="s_days">默认时长（天）</label><input id="s_days" class="input num" type="number" min="1" max="3650"></div>
              </div>
              <div class="grid g2" style="gap:10px">
                <div>
                  <label class="label" for="s_plan">默认套餐</label>
                  <select id="s_plan" class="select">
                    <option value="all">全部功能</option>
                    <option value="basic">基础</option>
                    <option value="pro">专业</option>
                  </select>
                </div>
                <div>
                  <label class="label" for="s_charset">默认字符集</label>
                  <select id="s_charset" class="select">
                    <option value="std">标准 · 去形近字</option>
                    <option value="digit">纯数字</option>
                    <option value="alpha">纯字母</option>
                    <option value="full">全量字母数字</option>
                  </select>
                </div>
              </div>
              <div><label class="label" for="s_batch">批次前缀</label><input id="s_batch" class="input" maxlength="8"></div>
              <div class="err" id="s_err"></div>
              <button class="btn btn-primary" id="s_save">保存设置</button>
            </div>
          </div>

          <div class="card">
            <div class="card-hd"><div><h2>账号安全</h2><p>修改后当前会话保持有效</p></div></div>
            <form id="pwForm" class="card-bd space-y-3">
              <div><label class="label" for="pw_cur">当前密码</label><input id="pw_cur" type="password" class="input" autocomplete="current-password"></div>
              <div><label class="label" for="pw_new">新密码</label><input id="pw_new" type="password" class="input" autocomplete="new-password"><p class="hint">至少 8 位</p></div>
              <div><label class="label" for="pw_new2">确认新密码</label><input id="pw_new2" type="password" class="input" autocomplete="new-password"></div>
              <div class="err" id="pw_err"></div>
              <button class="btn btn-primary" type="submit">更新密码</button>
            </form>
          </div>
        </div>

        <div class="card" style="border-color:#f3c4c4">
          <div class="card-hd" style="border-color:#fbe4e4"><div><h2 style="color:#b91c1c">危险操作</h2><p>以下操作不可撤销</p></div></div>
          <div>
            <div class="srow"><div><div class="t">清空未使用卡密</div><div class="d">删除所有尚未兑换的卡密</div></div><div class="v"><button class="btn btn-xs btn-danger" data-danger="clear_unused_cards">清空</button></div></div>
            <div class="srow"><div><div class="t">清空已过期卡密</div><div class="d">删除已兑换且到期时间已过的卡密</div></div><div class="v"><button class="btn btn-xs btn-danger" data-danger="clear_expired_cards">清空</button></div></div>
            <div class="srow"><div><div class="t">清空全部卡密</div><div class="d">含未使用、已兑换、已作废，全部删除</div></div><div class="v"><button class="btn btn-xs btn-danger" data-danger="clear_all_cards">清空</button></div></div>
            <div class="srow"><div><div class="t">清空日志</div><div class="d">删除全部审计与客户端事件记录</div></div><div class="v"><button class="btn btn-xs btn-danger" data-danger="clear_logs">清空</button></div></div>
          </div>
        </div>
      </section>

    </main>
  </div>
</div>

<!-- 抽屉 -->
<div class="drawer hide" id="drawer">
  <div class="drawer-mask" data-drawer-close></div>
  <section class="drawer-panel" role="dialog" aria-modal="true">
    <header class="drawer-hd">
      <div style="min-width:0">
        <div class="ttl" id="drawerTitle">—</div>
        <div class="sub" id="drawerSub"></div>
      </div>
      <button class="btn btn-ghost btn-sm" data-drawer-close style="margin-left:auto">关闭</button>
    </header>
    <div class="drawer-bd" id="drawerBody"></div>
    <footer class="drawer-ft" id="drawerFoot"></footer>
  </section>
</div>

<!-- 弹窗 -->
<div class="modal hide" id="modal">
  <div class="modal-mask" data-modal-close></div>
  <div class="modal-panel">
    <div class="modal-hd">
      <h3 id="modalTitle">确认</h3>
      <p id="modalDesc"></p>
    </div>
    <div class="modal-bd" id="modalBody"></div>
    <div class="modal-bd" style="padding-bottom:0"><div class="err" id="modalErr"></div></div>
    <div class="modal-ft">
      <button class="btn" id="modalCancel">取消</button>
      <button class="btn btn-primary" id="modalOk">确认</button>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
/* ═══════════════════════════════════════════════════════════════
   黑猫拦截 Pro · 运维控制台
   单文件：无外部依赖、样式内联，弱网也不会掉。
   ═══════════════════════════════════════════════════════════════ */
(() => {
'use strict';

/* ───────── 工具 ───────── */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const ts = (n) => {
  if (!n || +n <= 0) return '—';
  const d = new Date(+n * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
};
const dur = (sec) => {
  sec = +sec || 0;
  if (sec % 86400 === 0) return (sec / 86400) + ' 天';
  if (sec % 3600 === 0) return (sec / 3600) + ' 小时';
  return Math.round(sec / 60) + ' 分钟';
};
const bytes = (n) => {
  n = +n || 0;
  if (n < 1024) return n + ' B';
  if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
  return (n / 1048576).toFixed(2) + ' MB';
};
const remainText = (sec) => {
  sec = Math.max(0, +sec || 0);
  if (!sec) return '—';
  const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d} 天 ${h} 小时`;
  if (h > 0) return `${h} 小时 ${m} 分`;
  return `${m} 分钟`;
};

let CSRF = '';
const S = {
  view: 'overview', page: 1, per: 20, total: 0, selected: new Set(),
  tab: 'audit', devTab: 'online', settings: null, ruleSets: [], versions: [], detailId: 0,
};

function toast(msg, isErr) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast show' + (isErr ? ' error' : '');
  clearTimeout(t._h);
  t._h = setTimeout(() => { t.className = 'toast'; }, 2800);
}

/* ───────── 接口 ───────── */
async function refreshCsrf() {
  try {
    const r = await fetch('/api/admin/csrf', { credentials: 'same-origin' });
    if (!r.ok) return false;
    const j = await r.json();
    if (j && j.ok && j.csrf) { CSRF = j.csrf; return true; }
  } catch (e) {}
  return false;
}

async function api(path, opt = {}, retried = false) {
  const isForm = typeof FormData !== 'undefined' && opt.body instanceof FormData;
  const isWrite = (opt.method || 'GET').toUpperCase() !== 'GET';
  if (isWrite && !CSRF) await refreshCsrf();

  const headers = {};
  if (!isForm) headers['Content-Type'] = 'application/json';
  if (CSRF) headers['X-CSRF'] = CSRF;

  let body;
  if (isForm) body = opt.body;
  else if (opt.body) body = JSON.stringify(CSRF ? Object.assign({ _csrf: CSRF }, opt.body) : opt.body);

  let res;
  try {
    res = await fetch('/api/' + path, { method: opt.method || 'GET', headers, credentials: 'same-origin', body });
  } catch (e) { return { ok: false, error: 'network' }; }

  if (res.status === 419 && !retried && path !== 'admin/csrf') {
    if (await refreshCsrf()) return api(path, opt, true);
  }
  if (res.status === 401) { showAuth(); return { ok: false, error: 'unauthenticated' }; }
  try { return await res.json(); } catch (e) { return { ok: false, error: 'bad_response' }; }
}

/* ───────── 弹窗 ───────── */
let modalPending = null;

function showModal(opts) {
  return new Promise((resolve) => {
    modalPending = { resolve, onOk: opts.onOk || null };
    $('#modalTitle').textContent = opts.title || '确认';
    $('#modalDesc').textContent = opts.desc || '';
    $('#modalDesc').className = opts.desc ? '' : 'hide';
    $('#modalBody').innerHTML = opts.html || '';
    $('#modalBody').className = opts.html ? 'modal-bd' : 'hide';
    $('#modalErr').textContent = '';
    const ok = $('#modalOk');
    ok.textContent = opts.okText || '确认';
    ok.className = 'btn ' + (opts.danger ? 'btn-danger-solid' : 'btn-primary');
    $('#modal').classList.remove('hide');
    const first = $('#modalBody input, #modalBody select, #modalBody textarea');
    setTimeout(() => { (first || ok).focus(); }, 30);
  });
}

function closeModal(value) {
  $('#modal').classList.add('hide');
  const p = modalPending;
  modalPending = null;
  if (p) p.resolve(value === undefined ? null : value);
}

function confirmAsk(opts) {
  return showModal(Object.assign({}, opts, { onOk: () => true })).then(v => v === true);
}

function promptAsk(opts) {
  const html = `<label class="label" for="m_val">${esc(opts.label || '')}</label>
    <input id="m_val" class="input" value="${esc(opts.value || '')}" placeholder="${esc(opts.placeholder || '')}">
    ${opts.hint ? `<p class="hint">${esc(opts.hint)}</p>` : ''}`;
  return showModal({
    title: opts.title, desc: opts.desc, html, okText: opts.okText, danger: opts.danger,
    onOk: () => $('#m_val').value,
  }).then(v => (v === null || v === true) ? null : String(v));
}

$('#modalOk').addEventListener('click', async () => {
  if (!modalPending) return;
  const { onOk } = modalPending;
  if (!onOk) { closeModal(true); return; }
  const btn = $('#modalOk');
  btn.disabled = true;
  let out;
  try { out = await onOk(); } catch (e) { out = false; }
  btn.disabled = false;
  if (out === false) return;
  closeModal(out);
});
$('#modalCancel').addEventListener('click', () => closeModal(null));
$$('[data-modal-close]').forEach(el => el.addEventListener('click', () => closeModal(null)));
$('#modalBody').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.tagName === 'INPUT') { e.preventDefault(); $('#modalOk').click(); }
});

/* ───────── 抽屉 ───────── */
function openDrawer({ title, sub, body, foot }) {
  $('#drawerTitle').textContent = title || '';
  $('#drawerSub').textContent = sub || '';
  $('#drawerSub').style.display = sub ? '' : 'none';
  $('#drawerBody').innerHTML = body || '';
  $('#drawerFoot').innerHTML = foot || '';
  $('#drawer').classList.remove('hide');
  document.body.style.overflow = 'hidden';
  $('#drawerBody').scrollTop = 0;
}
function closeDrawer() {
  $('#drawer').classList.add('hide');
  document.body.style.overflow = '';
}

/* ───────── 徽标 ───────── */
const TIER_LABEL = { free: 'FREE', beta: 'BETA', pro: 'PRO', max: 'MAX' };
const TIER_CLASS = { free: 'pill-zinc', beta: 'pill-blue', pro: 'pill-green', max: 'pill-violet' };
function tierPill(t) {
  let k = String(t || 'pro').toLowerCase();
  if (!TIER_LABEL[k]) k = 'pro';
  return `<span class="pill ${TIER_CLASS[k]}">${TIER_LABEL[k]}</span>`;
}
const CARD_STATE = { 0: ['未使用', 'pill-zinc'], 1: ['已兑换', 'pill-green'], 2: ['已作废', 'pill-rose'] };
function statePill(st) {
  const s = CARD_STATE[st] || ['未知', 'pill-zinc'];
  return `<span class="pill ${s[1]}">${s[0]}</span>`;
}

/* ───────── 登录 / 导航 ───────── */
function showAuth() {
  $('#auth').style.display = 'flex';
  $('#shell').classList.add('hide');
}

const NAV_TITLE = {
  overview: '概览', cards: '卡密', devices: '设备与配对', rules: '规则与版本',
  notice: '公告', ops: '维护与熔断', logs: '日志', settings: '设置',
};

function showShell(user) {
  $('#auth').style.display = 'none';
  $('#shell').classList.remove('hide');
  $('#whoami').textContent = user || 'admin';
  const h = (location.hash || '').replace('#', '');
  switchView(NAV_TITLE[h] ? h : 'overview');
}

function switchView(v) {
  S.view = v;
  $$('.nav-item').forEach(b => b.classList.toggle('active', b.dataset.view === v));
  $$('.page').forEach(p => p.classList.toggle('active', p.dataset.page === v));
  $('#topTitle').textContent = NAV_TITLE[v] || '';
  try { history.replaceState(null, '', '#' + v); } catch (e) {}
  $('#sidebar').classList.remove('open');
  $('#navMask').classList.add('hide');

  if (v === 'overview') loadOverview();
  if (v === 'cards') loadCards();
  if (v === 'devices') loadDevices();
  if (v === 'rules') loadRules();
  if (v === 'notice') loadNotice();
  if (v === 'ops') loadOps();
  if (v === 'logs') loadLogs();
  if (v === 'settings') loadSettings();
}

$('#navToggle').addEventListener('click', () => {
  $('#sidebar').classList.add('open');
  $('#navMask').classList.remove('hide');
});
$('#logout').addEventListener('click', async () => {
  await api('admin/logout', { method: 'POST' });
  CSRF = '';
  showAuth();
});

function loginError(msg) {
  const el = $('#loginErr');
  el.textContent = msg;
  el.classList.toggle('hide', !msg);
}

$('#loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn = $('#loginBtn');
  if (btn.disabled) return;
  loginError('');
  const user = $('#u').value.trim();
  const pass = $('#p').value;
  if (!user || !pass) { loginError('请填写账号和密码'); return; }

  btn.disabled = true;
  const label = btn.textContent;
  btn.textContent = '登录中…';
  const r = await api('admin/login', { method: 'POST', body: { username: user, password: pass } });
  btn.disabled = false;
  btn.textContent = label;

  if (!r.ok) {
    loginError(r.error === 'network' ? '网络不通，检查一下连接再试' : '账号或密码不正确');
    $('#p').value = '';
    $('#p').focus();
    return;
  }
  CSRF = r.csrf || '';
  $('#p').value = '';
  showShell(r.user);
});

$('#pwToggle').addEventListener('click', () => {
  const i = $('#p');
  const on = i.type === 'password';
  i.type = on ? 'text' : 'password';
  $('#pwToggle').textContent = on ? '隐藏' : '显示';
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (!$('#modal').classList.contains('hide')) { closeModal(null); return; }
  if (!$('#drawer').classList.contains('hide')) closeDrawer();
});

/* ───────── 全局事件委托 ───────── */
document.addEventListener('click', (e) => {
  const t = e.target.closest('[data-view],[data-go],[data-drawer-close],[data-danger],[data-bulk],[data-cd-act],[data-ver-edit],[data-ver-del],[data-kick],[data-unkick],[data-pin],[data-rs-edit],[data-rs-del],[data-rs-up],[data-rs-down],[data-copy]');
  if (!t) return;

  if (t.dataset.view) { switchView(t.dataset.view); return; }
  if (t.dataset.go) {
    const go = t.dataset.go;
    switchView(go);
    if (t.dataset.act === 'gen') setTimeout(openGenDrawer, 60);
    return;
  }
  if (t.dataset.copy) {
    navigator.clipboard.writeText(t.dataset.copy).then(() => toast('已复制'), () => toast('复制失败', true));
    return;
  }
  if (t.hasAttribute('data-drawer-close')) { closeDrawer(); return; }
  if (t.dataset.danger) { dangerAction(t.dataset.danger); return; }
  if (t.dataset.bulk) { bulkAction(t.dataset.bulk); return; }
  if (t.dataset.cdAct) { cdAction(t); return; }
  if (t.dataset.verEdit) { editVersion(t.dataset.verEdit); return; }
  if (t.dataset.verDel) { delVersion(+t.dataset.verDel); return; }
  if (t.dataset.kick) { kickOne(t.dataset.kick); return; }
  if (t.dataset.unkick) { unkickOne(t.dataset.unkick); return; }
  if (t.dataset.pin) { revokePin(t.dataset.pin); return; }
  if (t.dataset.rsEdit) { editRuleSet(+t.dataset.rsEdit); return; }
  if (t.dataset.rsDel) { delRuleSet(+t.dataset.rsDel); return; }
  if (t.dataset.rsUp) { moveRuleSet(+t.dataset.rsUp, 'up'); return; }
  if (t.dataset.rsDown) { moveRuleSet(+t.dataset.rsDown, 'down'); return; }
});

document.addEventListener('change', (e) => {
  const cb = e.target.closest('[data-rs-toggle]');
  if (cb) toggleRuleSet(+cb.dataset.rsToggle, cb.checked);
  const all = e.target.closest('#checkAll');
  if (all) {
    const on = all.checked;
    $$('#cardRows input[type=checkbox]').forEach(x => {
      x.checked = on;
      const id = +x.dataset.id;
      on ? S.selected.add(id) : S.selected.delete(id);
    });
    renderBulk();
  }
});

/* ═══════════ 概览 ═══════════ */
async function loadOverview() {
  const [st, set, rs, vers] = await Promise.all([
    api('admin/stats'), api('admin/settings'), api('admin/rulesets'), api('admin/versions'),
  ]);

  if (st.ok) {
    $('#k_online').textContent = st.pins_online ?? '—';
    $('#k_unused').textContent = st.cards_unused ?? '—';
    $('#k_redeem').textContent = st.redeem_24h ?? '—';
    $('#k_fail').textContent = st.fail_24h ?? '—';
    $('#k_online_foot').innerHTML = `心跳 ${st.pins_beat ?? 0} 台 · 强制下线 ${st.pins_kicked ?? 0} 台`;
    $('#k_unused_foot').innerHTML = `总卡密 ${st.cards_total ?? 0} · 已兑换 ${st.cards_used ?? 0}`;
    const rate = (st.redeem_24h + st.fail_24h) > 0
      ? Math.round(st.redeem_24h / (st.redeem_24h + st.fail_24h) * 100) : 0;
    $('#k_redeem_foot').innerHTML = `成功率 <span class="trend">${rate}%</span>`;
    $('#k_fail_foot').innerHTML = st.fail_24h > 0 ? '需要关注' : '无异常';
  }

  const s = (set.ok && set.settings) ? set.settings : null;
  S.settings = s;

  /* 顶栏状态 */
  const top = $('#topStatus');
  const maintOn = s && +s.maintenance_on === 1;
  const fuseMode = s ? (s.fuse_mode || 'off') : 'off';
  if (maintOn) { top.className = 'env warn'; top.innerHTML = '<i class="led"></i>维护中'; }
  else if (fuseMode !== 'off') { top.className = 'env bad'; top.innerHTML = '<i class="led"></i>熔断开启'; }
  else { top.className = 'env'; top.innerHTML = '<i class="led"></i>运行正常'; }
  $('#navOpsDot').classList.toggle('hide', !(maintOn || fuseMode !== 'off'));

  if (s) {
    const rows = [
      ['维护模式', maintOn
        ? `<span class="pill pill-amber">开启</span><div class="d" style="margin-top:3px">${esc(s.maintenance_reason || '未填原因')}</div>`
        : '<span class="pill pill-green">关闭</span>', '维护页对所有客户端生效'],
      ['熔断', fuseMode === 'all'
        ? '<span class="pill pill-rose">全部版本</span>'
        : (fuseMode === 'below' ? `<span class="pill pill-rose">build &lt; ${+s.fuse_build || 0}</span>` : '<span class="pill pill-zinc">关闭</span>'),
        fuseMode === 'off' ? '没有版本被强制退出' : (s.fuse_reason || '命中条件的客户端启动即退出')],
      ['最低可用 build', `<span class="num">${+s.min_build || 0}</span>`, (+s.min_build || 0) === 0 ? '不限，所有版本都能拿规则' : '低于该 build 拿不到规则'],
    ];
    $('#ov_status').innerHTML = rows.map(([k, v, d]) => `<div class="srow">
      <div><div class="t">${k}</div><div class="d">${esc(d)}</div></div>
      <div class="v">${v}</div></div>`).join('');
  } else {
    $('#ov_status').innerHTML = '<div class="empty-state">读取失败</div>';
  }

  let pubHtml = '';
  if (vers.ok) {
    const list = vers.rows || [];
    S.versions = list;
    const latest = list.find(v => String(v.active) === '1') || list[0];
    if (latest) {
      $('#topVersion').textContent = `v${latest.version} · ${latest.build}`;
      pubHtml += `<div class="srow"><div><div class="t">客户端</div><div class="d">${latest.force_update == 1 ? '强制更新' : '可选更新'} · ${ts(latest.created_at)}</div></div>
        <div class="v mono">v${esc(latest.version)} <span style="color:#aeb5c0">(${latest.build})</span></div></div>`;
    } else {
      $('#topVersion').textContent = '—';
      pubHtml += `<div class="srow"><div class="t">客户端</div><div class="v" style="color:#aeb5c0">未发布</div></div>`;
    }
  }
  if (rs.ok) {
    S.ruleSets = rs.rows || [];
    const sum = rs.summary || {};
    const p = sum.pack;
    if (p) {
      pubHtml += `<div class="srow"><div><div class="t">云端规则</div><div class="d">${p.ip_count} IP / ${p.domain_count} 域名 / ${p.port_count} 端口 · ${bytes(p.bytes)}</div></div>
        <div class="v"><span class="pill pill-green">${sum.set_count || 0} 套</span></div></div>`;
      pubHtml += `<div class="srow"><div><div class="t">规则版本</div><div class="d">${esc((sum.sets || []).join(' · ') || '—')}</div></div>
        <div class="v mono" style="font-size:11.5px">${esc(p.version)}</div></div>`;
    } else {
      pubHtml += `<div class="srow"><div class="t">云端规则</div><div class="v"><span class="pill pill-rose">未下发</span></div></div>`;
    }
  }
  $('#ov_publish').innerHTML = pubHtml || '<div class="empty-state">暂无数据</div>';

  const l = await api('admin/logs');
  if (!l.ok) return;
  const allEvents = l.events || [];
  renderKinds(allEvents);

  const rows = allEvents.slice(0, 8);
  $('#ov_events').innerHTML = rows.length ? rows.map(x => `<tr>
    <td class="num" style="color:#8b93a1;white-space:nowrap">${ts(x.ts)}</td>
    <td>${esc(x.kind)}</td>
    <td class="mono" style="font-size:12px">${esc(x.pin || '—')}</td>
    <td style="color:#6b7280">${esc(x.detail || '')}</td>
  </tr>`).join('') : '<tr><td colspan="4" class="empty">暂无记录</td></tr>';
}

function renderKinds(events) {
  const box = $('#ov_kinds');
  $('#ov_total').textContent = `${events.length} 条`;
  if (!events.length) {
    box.innerHTML = '<div class="empty-state"><b>暂无事件</b>客户端还没有上报</div>';
    return;
  }
  const map = new Map();
  events.forEach(e => {
    const k = String(e.kind || 'unknown');
    map.set(k, (map.get(k) || 0) + 1);
  });
  const list = Array.from(map.entries()).sort((a, b) => b[1] - a[1]).slice(0, 7);
  const max = Math.max(1, ...list.map(x => x[1]));
  box.innerHTML = list.map(([k, n]) => `
    <div style="margin-bottom:10px">
      <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:5px">
        <span class="mono" style="font-size:11.5px;color:#4b5563;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(k)}</span>
        <span class="num" style="font-size:11.5px;color:#8b93a1">${n}</span>
      </div>
      <div class="bar"><i style="width:${Math.max(3, Math.round(n / max * 100))}%"></i></div>
    </div>`).join('');
}

$('#ov_refresh').addEventListener('click', () => { loadOverview(); toast('已刷新'); });

/* ═══════════ 卡密 ═══════════ */
const DURATIONS = { trial: 1, week: 7, month: 30, quarter: 90, year: 365 };
let GEN_CODES = [];

function openGenDrawer() {
  openDrawer({
    title: '生成卡密',
    sub: '一次最多 1000 张，按批次归档',
    body: `
      <div class="space-y-3">
        <div class="grid g2" style="gap:10px">
          <div>
            <label class="label" for="g_type">卡密类型</label>
            <select id="g_type" class="select">
              <option value="trial">试用 · 1 天</option>
              <option value="week">周卡 · 7 天</option>
              <option value="month" selected>月卡 · 30 天</option>
              <option value="quarter">季卡 · 90 天</option>
              <option value="year">年卡 · 365 天</option>
              <option value="custom">自定义时长</option>
            </select>
          </div>
          <div id="g_daysWrap" class="hide">
            <label class="label" for="g_days">自定义天数</label>
            <input id="g_days" class="input num" type="number" min="1" max="3650" value="30">
          </div>
          <div>
            <label class="label" for="g_tier">卡密等级</label>
            <select id="g_tier" class="select">
              <option value="free">FREE · 基础规则</option>
              <option value="beta">BETA · 测试通道</option>
              <option value="pro" selected>PRO · 正式版</option>
              <option value="max">MAX · 全量规则</option>
            </select>
          </div>
          <div>
            <label class="label" for="g_plan">功能套餐</label>
            <select id="g_plan" class="select">
              <option value="all" selected>全部功能</option>
              <option value="basic">基础 · 核心与瞄准</option>
              <option value="pro">专业 · 不含驱动</option>
            </select>
          </div>
          <div>
            <label class="label" for="g_count">数量</label>
            <input id="g_count" class="input num" type="number" min="1" max="1000" value="10">
          </div>
          <div>
            <label class="label" for="g_charset">字符集</label>
            <select id="g_charset" class="select">
              <option value="std" selected>标准 · 去形近字</option>
              <option value="digit">纯数字</option>
              <option value="alpha">纯字母</option>
              <option value="full">全量字母数字</option>
            </select>
          </div>
          <div>
            <label class="label" for="g_batch">批次名称</label>
            <input id="g_batch" class="input" placeholder="留空自动生成">
          </div>
          <div>
            <label class="label" for="g_note">备注</label>
            <input id="g_note" class="input" placeholder="渠道 A、活动赠送">
          </div>
        </div>
        <p class="hint">等级决定客户端能拿到哪一层规则；套餐决定可用功能。</p>
        <div class="err" id="genErr"></div>
        <div id="genOut" class="hide" style="border:1px solid var(--line);border-radius:7px;padding:12px;background:#fafbfc">
          <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px">
            <span style="font-size:12px;color:#4b5563" id="genSummary">—</span>
            <span style="display:flex;gap:6px">
              <button class="btn btn-xs" id="copyCodes">复制</button>
              <button class="btn btn-xs" id="downloadCodes">下载</button>
            </span>
          </div>
          <textarea id="genCodes" class="textarea mono" style="min-height:180px;font-size:12px;background:#fff" readonly spellcheck="false"></textarea>
        </div>
      </div>`,
    foot: `<button class="btn" data-drawer-close>关闭</button>
           <button class="btn btn-primary" id="genBtn">生成</button>`,
  });

  const s = S.settings || {};
  if (s.default_count) $('#g_count').value = s.default_count;
  if (s.default_charset) $('#g_charset').value = s.default_charset;
  if (s.default_plan) $('#g_plan').value = s.default_plan;
  if (s.default_days) {
    const key = Object.keys(DURATIONS).find(k => DURATIONS[k] === +s.default_days);
    if (key) $('#g_type').value = key;
    else { $('#g_type').value = 'custom'; $('#g_daysWrap').classList.remove('hide'); $('#g_days').value = s.default_days; }
  }

  $('#g_type').addEventListener('change', () => {
    $('#g_daysWrap').classList.toggle('hide', $('#g_type').value !== 'custom');
  });

  $('#genBtn').addEventListener('click', async () => {
    const type = $('#g_type').value;
    const days = type === 'custom' ? Math.max(1, +$('#g_days').value || 1) : DURATIONS[type];
    const prefix = (S.settings && S.settings.batch_prefix) ? S.settings.batch_prefix : 'B';
    const batch = $('#g_batch').value.trim() || (prefix + new Date().toISOString().slice(0, 10).replace(/-/g, ''));
    const btn = $('#genBtn');
    btn.disabled = true;
    $('#genErr').textContent = '';
    const r = await api('admin/cards/generate', {
      method: 'POST',
      body: {
        count: Math.max(1, +$('#g_count').value || 1),
        duration: days * 86400,
        batch,
        note: $('#g_note').value.trim(),
        plan: $('#g_plan').value,
        charset: $('#g_charset').value,
        tier: $('#g_tier').value,
      },
    });
    btn.disabled = false;
    if (!r.ok) { $('#genErr').textContent = '生成失败，稍后再试'; return; }
    GEN_CODES = r.codes || [];
    $('#genOut').classList.remove('hide');
    $('#genSummary').textContent = `已生成 ${r.created} 张 · ${days} 天 · ${String(r.tier || '').toUpperCase()} · 批次 ${batch}`;
    $('#genCodes').value = GEN_CODES.join('\n');
    toast(`已生成 ${r.created} 张卡密`);
    loadCards();
  });

  $('#copyCodes').addEventListener('click', async () => {
    const ta = $('#genCodes');
    try { await navigator.clipboard.writeText(ta.value); toast('已复制'); }
    catch (e) { ta.select(); document.execCommand('copy'); toast('已复制'); }
  });

  $('#downloadCodes').addEventListener('click', () => {
    const blob = new Blob([$('#genCodes').value], { type: 'text/plain;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'cards-' + Date.now() + '.txt';
    a.click();
    URL.revokeObjectURL(a.href);
  });
}
$('#genOpen').addEventListener('click', openGenDrawer);

async function loadBatches() {
  const r = await api('admin/batches');
  if (!r.ok) return;
  const sel = $('#c_batch');
  const cur = sel.value;
  sel.innerHTML = '<option value="">全部批次</option>' +
    (r.rows || []).map(x => `<option value="${esc(x.batch)}">${esc(x.batch)} (${x.c})</option>`).join('');
  sel.value = cur;
}

async function loadCards() {
  const q = encodeURIComponent($('#c_q').value.trim());
  const stv = $('#c_status').value;
  const b = encodeURIComponent($('#c_batch').value);
  const r = await api(`admin/cards?page=${S.page}&per=${S.per}&q=${q}&status=${stv}` + (b ? `&batch=${b}` : ''));
  if (!r.ok) return;

  const rows = r.rows || [];
  S.total = r.total || 0;
  S.selected.clear();
  $('#checkAll').checked = false;
  renderBulk();

  const pages = Math.max(1, Math.ceil(S.total / S.per));
  $('#c_total').textContent = `共 ${S.total} 张`;
  $('#pageInfo').textContent = `第 ${S.page} / ${pages} 页 · 每页 ${S.per} 条`;

  $('#cardRows').innerHTML = rows.length ? rows.map(c => {
    const ban = (c.status === 2 && c.ban_reason)
      ? `<div style="margin-top:2px;font-size:11px;color:#b91c1c">封禁：${esc(c.ban_reason)}</div>` : '';
    return `<tr>
      <td><input type="checkbox" class="check" data-id="${c.id}"></td>
      <td>
        <div class="mono" style="font-size:12.5px;font-weight:550;color:#111827">${esc(c.code)}</div>
        ${ban}
      </td>
      <td>${tierPill(c.tier)}</td>
      <td>${statePill(c.status)}</td>
      <td style="color:#6b7280">${dur(c.duration_sec)}</td>
      <td class="num" style="color:#6b7280">${c.expire_at ? ts(c.expire_at) : '—'}</td>
      <td class="mono" style="font-size:12px;color:#6b7280">${esc(c.bound_pin || '—')}</td>
      <td class="actions">
        <button class="btn btn-xs" data-act="detail" data-id="${c.id}">详情</button>
        <button class="btn btn-xs" data-act="extend" data-id="${c.id}">延期</button>
        <button class="btn btn-xs ${c.status === 2 ? '' : 'btn-danger'}" data-act="toggle" data-id="${c.id}" data-status="${c.status}">${c.status === 2 ? '解封' : '作废'}</button>
      </td>
    </tr>`;
  }).join('') : '<tr><td colspan="8" class="empty">没有符合条件的数据</td></tr>';

  $$('#cardRows input[type=checkbox]').forEach(cb => cb.addEventListener('change', () => {
    const id = +cb.dataset.id;
    cb.checked ? S.selected.add(id) : S.selected.delete(id);
    renderBulk();
  }));

  loadBatches();
}

function renderBulk() {
  const n = S.selected.size;
  const bar = $('#bulkbar');
  bar.classList.toggle('hide', n === 0);
  $('#bulkCount').textContent = `已选 ${n} 项`;
}

document.addEventListener('click', async (e) => {
  const btn = e.target.closest('#cardRows [data-act]');
  if (!btn) return;
  const id = +btn.dataset.id;
  const act = btn.dataset.act;

  if (act === 'detail') { openCardDetail(id); return; }

  if (act === 'extend') {
    const v = await promptAsk({ title: '调整有效期', desc: '正数延期，负数缩短，单位天。', label: '天数', value: '7', okText: '保存' });
    if (v === null) return;
    const d = parseInt(v, 10);
    if (!d || isNaN(d)) { toast('请输入数字', true); return; }
    if (await extendCard(id, d)) loadCards();
    return;
  }

  if (act === 'toggle') {
    const cur = +btn.dataset.status;
    if (await setCardStatus(id, cur === 2 ? 0 : 2)) loadCards();
  }
});

async function extendCard(id, days) {
  const r = await api('admin/cards/extend', { method: 'POST', body: { id, days } });
  if (!r.ok) { toast('操作失败', true); return false; }
  toast(`已${days > 0 ? '延长' : '缩短'} ${Math.abs(days)} 天`);
  return true;
}

async function setCardStatus(id, toStatus) {
  let reason = '';
  if (toStatus === 2) {
    reason = await promptAsk({
      title: '作废这张卡密', desc: '原因会显示在后台，也会下发到客户端提示用户。',
      label: '原因', value: '违规使用', okText: '作废', danger: true,
    });
    if (reason === null) return false;
    reason = reason.trim() || '管理员封禁';
  }
  const r = await api('admin/cards/status', { method: 'POST', body: { id, status: toStatus, reason } });
  if (!r.ok) { toast('操作失败', true); return false; }
  toast(toStatus === 2 ? '已作废' : '已解封');
  return true;
}

async function bulkAction(action) {
  const ids = Array.from(S.selected);
  if (!ids.length) return;
  const body = { ids, action };

  if (action === 'delete') {
    const ok = await confirmAsk({ title: '删除选中卡密', desc: `确认删除选中的 ${ids.length} 张？不可恢复。`, okText: '删除', danger: true });
    if (!ok) return;
  }
  if (action === 'ban') {
    const reason = await promptAsk({ title: '批量作废', desc: `将作废选中的 ${ids.length} 张卡密。`, label: '原因', value: '违规使用', okText: '作废', danger: true });
    if (reason === null) return;
    body.reason = reason.trim() || '管理员封禁';
  }
  if (action === 'extend') {
    const v = await promptAsk({ title: '批量延期', desc: `对选中的 ${ids.length} 张卡密调整有效期。`, label: '天数（负数为缩短）', value: '7', okText: '执行' });
    if (v === null) return;
    const d = parseInt(v, 10);
    if (!d || isNaN(d)) { toast('请输入数字', true); return; }
    body.days = d;
  }

  const r = await api('admin/cards/bulk', { method: 'POST', body });
  if (!r.ok) { toast('批量操作失败', true); return; }
  toast(`已处理 ${r.done} 项`);
  loadCards();
}

$('#cardsCleanup').addEventListener('click', async () => {
  const v = await showModal({
    title: '清理卡密', desc: '选择范围，执行后不可撤销。',
    html: `<label class="label" for="m_val">清理范围</label>
      <select id="m_val" class="select">
        <option value="unused">未使用卡密</option>
        <option value="expired">已过期卡密</option>
        <option value="all">全部卡密（含已兑换）</option>
      </select>`,
    okText: '下一步', danger: true,
    onOk: () => $('#m_val').value,
  });
  if (!v) return;
  const label = { unused: '未使用卡密', expired: '已过期卡密', all: '全部卡密' }[v];
  const ok = await confirmAsk({ title: `确认清除${label}`, desc: '此操作不可撤销。', okText: '确认清除', danger: true });
  if (!ok) return;
  const r = await api('admin/cards/purge', { method: 'POST', body: { scope: v } });
  if (!r.ok) { toast('清除失败', true); return; }
  toast(`已清除 ${r.affected} 张`);
  S.page = 1;
  loadCards();
});

$('#cardsExport').addEventListener('click', () => {
  const q = encodeURIComponent($('#c_q').value.trim());
  const st = $('#c_status').value;
  const b = encodeURIComponent($('#c_batch').value);
  window.location.href = `/api/admin/cards/export?q=${q}&status=${st}` + (b ? `&batch=${b}` : '');
});

$('#c_q').addEventListener('input', () => { S.page = 1; clearTimeout(window._qt); window._qt = setTimeout(loadCards, 260); });
$('#c_status').addEventListener('change', () => { S.page = 1; loadCards(); });
$('#c_batch').addEventListener('change', () => { S.page = 1; loadCards(); });
$('#pagePrev').addEventListener('click', () => { if (S.page > 1) { S.page--; loadCards(); } });
$('#pageNext').addEventListener('click', () => {
  if (S.page * S.per < S.total) { S.page++; loadCards(); }
});

/* ───────── 卡密详情 ───────── */
const cdKv = (k, v) => `<dt style="color:#8b93a1;font-size:12px">${k}</dt><dd style="margin:0;font-size:12.5px;color:#1f2937;word-break:break-all">${v}</dd>`;
const cdSec = (title, inner) => `<section style="margin-bottom:22px">
  <h4 style="margin:0 0 9px;font-size:10.5px;font-weight:600;letter-spacing:.07em;text-transform:uppercase;color:#aeb5c0">${title}</h4>
  ${inner}</section>`;
const cdGrid = (inner) => `<dl style="display:grid;grid-template-columns:96px 1fr;gap:8px 12px;margin:0">${inner}</dl>`;

async function openCardDetail(id) {
  const r = await api('admin/cards/detail?id=' + id);
  if (!r.ok || !r.card) { toast('读取详情失败', true); return; }
  const c = r.card;
  S.detailId = id;
  const p = c.pin_info || null;
  const st = CARD_STATE[c.status] || ['未知', 'pill-zinc'];

  let html = '';
  html += cdSec('授权', cdGrid(`
    ${cdKv('等级', tierPill(c.tier))}
    ${cdKv('状态', `<span class="pill ${st[1]}">${st[0]}</span>`)}
    ${cdKv('时长', dur(c.duration_sec))}
    ${cdKv('到期', c.expire_at ? `${ts(c.expire_at)}<span style="color:#aeb5c0">（${c.seconds_left > 0 ? '剩 ' + remainText(c.seconds_left) : '已到期'}）</span>` : '—')}
    ${cdKv('兑换', c.redeemed_at ? ts(c.redeemed_at) : '未兑换')}
    ${cdKv('创建', c.created_at ? ts(c.created_at) : '—')}
    ${cdKv('备注', c.note ? esc(c.note) : '—')}
  `) + `<div style="margin-top:12px;display:flex;align-items:center;gap:8px">
    <select class="select" style="width:120px" id="cdTier">
      ${['free', 'beta', 'pro', 'max'].map(t => `<option value="${t}"${t === c.tier ? ' selected' : ''}>${TIER_LABEL[t]}</option>`).join('')}
    </select>
    <button class="btn btn-sm" id="cdTierSave">改等级</button>
    <button class="btn btn-sm" data-copy="${esc(c.code)}">复制卡密</button>
  </div>`);

  if (p) {
    html += cdSec('绑定设备', cdGrid(`
      ${cdKv('配对码', `<span class="mono">${esc(p.pin)}</span>`)}
      ${cdKv('在线', p.online ? '<span class="pill pill-green">在线</span>' : '<span class="pill pill-zinc">离线</span>')}
      ${cdKv('最近心跳', p.last_beat ? ts(p.last_beat) : '—')}
      ${cdKv('客户端', p.app_ver ? esc(p.app_ver) : '—')}
      ${cdKv('IP', esc(p.ip || c.bound_ip || '—'))}
      ${cdKv('授权窗口', p.authorized_until ? `${ts(p.authorized_until)}（${p.authorized ? '有效' : '已过期'}）` : '—')}
      ${cdKv('设备指纹', c.bound_dev ? `<span class="mono">${esc(String(c.bound_dev).slice(0, 22))}${String(c.bound_dev).length > 22 ? '…' : ''}</span>` : '—')}
      ${cdKv('兑换次数', String(p.redeem_count == null ? 0 : p.redeem_count))}
      ${cdKv('强制下线', p.kicked ? `<span class="pill pill-rose">${esc(p.kick_reason || '已下线')}</span>` : '否')}
    `));
  } else {
    html += cdSec('绑定设备', cdGrid(`
      ${cdKv('状态', c.bound_pin ? `<span class="mono">${esc(c.bound_pin)}</span>` : '未绑定任何设备')}
      ${c.bound_ip ? cdKv('IP', esc(c.bound_ip)) : ''}
    `));
  }

  if (c.status === 2 || c.ban_reason) {
    html += cdSec('封禁', cdGrid(`
      ${cdKv('原因', `<span style="color:#b91c1c">${esc(c.ban_reason || '—')}</span>`)}
      ${cdKv('时间', c.banned_at ? ts(c.banned_at) : '—')}
    `));
  }

  if ((c.devices || []).length > 1) {
    html += cdSec(`历史设备（${c.devices.length}）`, cdGrid(
      c.devices.map(d => cdKv(`<span class="mono">${esc(d.pin)}</span>`, `${d.c} 次 · ${ts(d.last_ts)}`)).join('')));
  }

  if ((c.events || []).length) {
    html += cdSec('最近事件', `<ul style="list-style:none;margin:0;padding:0">` +
      c.events.map(x => `<li style="display:flex;gap:10px;padding:7px 0;border-bottom:1px solid #f1f3f6;font-size:12px">
        <span class="num" style="color:#aeb5c0;flex:none">${ts(x.ts)}</span>
        <span style="color:#374151">${esc(x.kind)}${x.detail ? ' · ' + esc(x.detail) : ''}</span></li>`).join('') + '</ul>');
  }

  html += `<p class="hint">改等级后客户端下次拉规则即按新等级下发。想让在线设备立刻刷新，去「设备与配对」强制下线再解除。</p>`;

  const foot = `<button class="btn btn-sm" data-cd-act="extend" data-days="7">延期 7 天</button>
    <button class="btn btn-sm" data-cd-act="extend" data-days="-7">缩短 7 天</button>
    <button class="btn btn-sm ${c.status === 2 ? '' : 'btn-danger'}" data-cd-act="toggle">${c.status === 2 ? '解封' : '作废'}</button>
    ${p ? '<button class="btn btn-sm" data-cd-act="unbind">解绑设备</button>' : ''}
    <button class="btn btn-sm btn-danger" data-cd-act="delete">删除</button>`;

  openDrawer({ title: c.code, sub: '', body: html, foot });
  $('#drawerSub').innerHTML = `${tierPill(c.tier)} <span style="margin-left:6px;color:#8b93a1">${c.batch ? '批次 ' + esc(c.batch) : '无批次'}</span>`;
  $('#drawerSub').style.display = '';

  $('#cdTierSave').addEventListener('click', async () => {
    const tier = $('#cdTier').value;
    if (tier === c.tier) { toast('等级没变'); return; }
    const r2 = await api('admin/cards/tier', { method: 'POST', body: { id: c.id, tier } });
    if (!r2.ok) { toast('改等级失败', true); return; }
    toast('等级已改为 ' + (r2.tier_label || tier.toUpperCase()));
    loadCards();
    openCardDetail(c.id);
  });
}

async function cdAction(btn) {
  const id = S.detailId;
  const act = btn.dataset.cdAct;

  if (act === 'extend') {
    const days = +btn.dataset.days;
    if (await extendCard(id, days)) { loadCards(); openCardDetail(id); }
    return;
  }
  if (act === 'toggle') {
    const d = await api('admin/cards/detail?id=' + id);
    const cur = (d.ok && d.card) ? d.card.status : 0;
    if (await setCardStatus(id, cur === 2 ? 0 : 2)) { loadCards(); openCardDetail(id); }
    return;
  }
  if (act === 'unbind') {
    const ok = await confirmAsk({ title: '解绑设备', desc: '解绑后这张卡可以在别的设备上继续使用，剩余时长不变。', okText: '解绑' });
    if (!ok) return;
    const r = await api('admin/cards/unbind', { method: 'POST', body: { id } });
    if (!r.ok) { toast('解绑失败', true); return; }
    toast('已解绑'); loadCards(); openCardDetail(id);
    return;
  }
  if (act === 'delete') {
    const ok = await confirmAsk({ title: '删除卡密', desc: '删除后不可恢复。', okText: '删除', danger: true });
    if (!ok) return;
    const r = await api('admin/cards/delete', { method: 'POST', body: { id } });
    if (!r.ok) { toast('删除失败', true); return; }
    toast('已删除'); closeDrawer(); loadCards();
  }
}

/* ═══════════ 设备与配对 ═══════════ */
function switchDevTab(tab) {
  S.devTab = tab;
  $$('[data-devtab]').forEach(b => b.classList.toggle('active', b.dataset.devtab === tab));
  $('#dev-online').classList.toggle('hide', tab !== 'online');
  $('#dev-pins').classList.toggle('hide', tab !== 'pins');
  if (tab === 'online') loadOnline(); else loadPins();
}
$$('[data-devtab]').forEach(b => b.addEventListener('click', () => switchDevTab(b.dataset.devtab)));
function loadDevices() { switchDevTab(S.devTab); }

async function loadOnline() {
  const r = await api('admin/online');
  if (!r.ok) return;
  const rows = r.rows || [];
  $('#onlineCount').textContent = rows.filter(x => !x.kicked).length;
  $('#onlineRows').innerHTML = rows.length ? rows.map(o => {
    const state = o.kicked
      ? `<span class="pill pill-rose">已下线：${esc(o.kick_reason || '管理员操作')}</span>`
      : (o.authorized ? '<span class="pill pill-green">在线</span>' : '<span class="pill pill-zinc">在线未授权</span>');
    return `<tr>
      <td class="mono" style="font-size:12.5px;font-weight:550">${esc(o.pin)}</td>
      <td>${esc(o.tier_label || '—')}</td>
      <td style="color:#6b7280">${esc(o.app_ver || '—')}</td>
      <td class="mono" style="font-size:12px;color:#6b7280">${esc(o.ip || '—')}</td>
      <td class="num" style="color:#6b7280">${o.online_s < 60 ? o.online_s + ' 秒前' : Math.floor(o.online_s / 60) + ' 分钟前'}</td>
      <td>${o.authorized ? '<span class="pill pill-green">有效</span>' : '<span class="pill pill-zinc">—</span>'}</td>
      <td>${state}${o.code ? `<div class="mono" style="margin-top:2px;font-size:11px;color:#aeb5c0">${esc(o.code)}</div>` : ''}</td>
      <td class="actions">
        ${o.kicked
          ? `<button class="btn btn-xs" data-unkick="${esc(o.pin)}">解除下线</button>`
          : `<button class="btn btn-xs btn-danger" data-kick="${esc(o.pin)}">强制下线</button>`}
      </td>
    </tr>`;
  }).join('') : '<tr><td colspan="8" class="empty">现在没有在线设备</td></tr>';
}

async function kickOne(pin) {
  const reason = await promptAsk({
    title: '强制下线', desc: `让设备 ${pin} 断开 VPN 并清空本地规则，下次心跳（1 分钟内）生效。`,
    label: '下线原因（客户端会显示）', value: '检测到多设备共享', okText: '强制下线', danger: true,
  });
  if (reason === null) return;
  const r = await api('admin/kick', { method: 'POST', body: { pin, reason: reason.trim() || '管理员强制下线' } });
  if (!r.ok) { toast('操作失败：' + (r.error || 'unknown'), true); return; }
  toast('已下发下线指令');
  loadOnline();
}

async function unkickOne(pin) {
  const r = await api('admin/unkick', { method: 'POST', body: { pin } });
  if (!r.ok) { toast('操作失败', true); return; }
  toast('已解除，设备可以重新连接');
  loadOnline();
}

$('#kickForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const pin = $('#k_pin').value.trim();
  if (!/^\d{8}$/.test(pin)) { toast('设备码必须是 8 位数字', true); return; }
  const reason = $('#k_reason').value.trim() || '管理员强制下线';
  const r = await api('admin/kick', { method: 'POST', body: { pin, reason } });
  if (!r.ok) { toast('操作失败：' + (r.error || 'unknown'), true); return; }
  toast('已下发下线指令');
  $('#k_pin').value = '';
  loadOnline();
});

async function loadPins() {
  const r = await api('admin/pins');
  if (!r.ok) return;
  const rows = r.rows || [];
  $('#pinRows').innerHTML = rows.length ? rows.map(p => `<tr>
    <td class="mono" style="font-size:12.5px">${esc(p.pin)}</td>
    <td class="num" style="color:#6b7280">${ts(p.first_seen)}</td>
    <td class="num" style="color:#6b7280">${ts(p.last_seen)}</td>
    <td class="mono" style="font-size:12px;color:#6b7280">${esc(p.ip || '—')}</td>
    <td class="num">${p.authorized_until > 0 ? `<span style="color:#047857">${ts(p.authorized_until)}</span>` : '<span style="color:#aeb5c0">未授权</span>'}</td>
    <td class="num" style="color:#6b7280">${p.redeem_count}</td>
    <td class="actions"><button class="btn btn-xs btn-danger" data-pin="${esc(p.pin)}">解除授权</button></td>
  </tr>`).join('') : '<tr><td colspan="7" class="empty">暂无配对码</td></tr>';
}

async function revokePin(pin) {
  const ok = await confirmAsk({ title: '解除授权', desc: `解除配对码 ${pin} 的授权？`, okText: '解除', danger: true });
  if (!ok) return;
  const r = await api('admin/pins/revoke', { method: 'POST', body: { pin } });
  if (!r.ok) { toast('操作失败', true); return; }
  toast('已解除授权');
  loadPins();
}

$('#devRefresh').addEventListener('click', () => {
  if (S.devTab === 'online') loadOnline(); else loadPins();
  toast('已刷新');
});

/* ═══════════ 规则与版本 ═══════════ */
function loadRules() {
  loadRuleSets();
  loadVersions();
}

async function loadRuleSets() {
  const r = await api('admin/rulesets');
  if (!r.ok) return;
  S.ruleSets = r.rows || [];
  const s = r.summary || {};
  const p = s.pack;

  if (p) {
    const names = (s.sets && s.sets.length) ? s.sets.join(' · ') : '未命名';
    $('#rs_now').innerHTML = `<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
      <span class="pill pill-green">${s.set_count || 0} 套</span>
      <span style="font-size:13px;color:#1f2937">${esc(names)}</span></div>
      <div class="mono" style="margin-top:8px;font-size:11.5px;color:#8b93a1">
        版本 ${esc(p.version)} · ${p.ip_count} IP / ${p.domain_count} 域名 / ${p.port_count} 端口 · ${bytes(p.bytes)} · 更新于 ${ts(p.updated_at)}
      </div>`;
  } else if ((s.total || 0) > 0) {
    $('#rs_now').innerHTML = '<div class="alert alert-bad"><div><b>一套都没勾</b>客户端会提示规则加载失败。</div></div>';
  } else {
    $('#rs_now').innerHTML = '<div class="empty-state"><b>还没有规则集</b>点右上角「新建规则集」开始</div>';
  }

  $('#rsRows').innerHTML = S.ruleSets.length ? S.ruleSets.map(x => `<tr>
    <td><input type="checkbox" class="check" data-rs-toggle="${x.id}" ${x.enabled == 1 ? 'checked' : ''}></td>
    <td>
      <div style="font-weight:550;color:#111827">${esc(x.name)}</div>
      ${x.note ? `<div style="margin-top:1px;font-size:11px;color:#aeb5c0">${esc(x.note)}</div>` : ''}
    </td>
    <td class="mono" style="font-size:11.5px;color:#aeb5c0">${esc(x.version || '—')}</td>
    <td style="font-size:12px;color:#6b7280">${(x.tiers || '').trim() ? esc(String(x.tiers).toUpperCase().replace(/,/g, ' / ')) : '全部'}</td>
    <td class="num" style="font-size:12px;color:#6b7280">${x.ip_count} / ${x.domain_count} / ${x.port_count}</td>
    <td class="num" style="font-size:12px;color:#6b7280">${bytes(x.bytes)}</td>
    <td class="num" style="font-size:12px;color:#6b7280">${ts(x.updated_at)}</td>
    <td class="actions">
      <button class="btn btn-xs" data-rs-up="${x.id}" title="上移">↑</button>
      <button class="btn btn-xs" data-rs-down="${x.id}" title="下移">↓</button>
      <button class="btn btn-xs" data-rs-edit="${x.id}">编辑</button>
      <button class="btn btn-xs btn-danger" data-rs-del="${x.id}">删除</button>
    </td>
  </tr>`).join('') : '<tr><td colspan="8" class="empty">还没有规则集</td></tr>';
}

async function toggleRuleSet(id, on) {
  const r = await api('admin/rulesets/toggle', { method: 'POST', body: { id, enabled: on } });
  if (!r.ok) { toast('设置失败：' + (r.error || 'unknown'), true); loadRuleSets(); return; }
  const a = r.applied || {};
  if (a.ok) toast(`${on ? '已加入' : '已移出'}下发 · 当前共 ${a.set_count} 套`);
  else toast(on ? '已加入下发' : '已移出下发（现在一套都没有，不下发）', !on);
  loadRuleSets();
}

async function moveRuleSet(id, dir) {
  const r = await api('admin/rulesets/sort', { method: 'POST', body: { id, dir } });
  if (!r.ok) { toast('调整失败：' + (r.error || 'unknown'), true); return; }
  if (r.moved === false) { toast(dir === 'up' ? '已经在最前面了' : '已经在最后面了'); return; }
  toast(`顺序已调整 · 第 ${r.position} 套`);
  loadRuleSets();
}

async function delRuleSet(id) {
  const x = S.ruleSets.find(v => +v.id === id);
  const ok = await confirmAsk({ title: '删除规则集', desc: `删除「${x ? x.name : id}」？删了就找不回来。`, okText: '删除', danger: true });
  if (!ok) return;
  const r = await api('admin/rulesets/delete', { method: 'POST', body: { id } });
  if (!r.ok) { toast('删除失败：' + (r.error || 'unknown'), true); return; }
  toast('已删除');
  loadRuleSets();
}

function rsDrawer(row) {
  const v = row || {};
  const tiers = String(v.tiers || '').split(',').map(x => x.trim()).filter(Boolean);
  const allTiers = tiers.length === 0;
  const enabled = row ? v.enabled == 1 : true;

  openDrawer({
    title: row ? '编辑规则集' : '新建规则集',
    sub: row ? `${v.ip_count} IP / ${v.domain_count} 域名 / ${v.port_count} 端口` : '导入 txt 或直接粘贴规则',
    body: `
      <div class="space-y-3">
        <div class="grid g2" style="gap:10px">
          <div>
            <label class="label" for="rs_name">名称</label>
            <input id="rs_name" class="input" maxlength="60" value="${esc(v.name || '')}" placeholder="例如：广告域名拦截">
          </div>
          <div>
            <label class="label" for="rs_version">版本（留空自动）</label>
            <input id="rs_version" class="input" maxlength="32" value="${esc(v.version || '')}">
          </div>
        </div>
        <div>
          <label class="label" for="rs_note">说明</label>
          <input id="rs_note" class="input" value="${esc(v.note || '')}" placeholder="这套规则是干什么的">
        </div>

        <div>
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:5px">
            <span class="label" style="margin:0">规则内容</span>
            <button type="button" class="btn btn-xs" id="rs_import">导入 TXT</button>
            <input type="file" id="rs_file" accept=".txt,.csv,.list,text/plain" hidden>
          </div>
          <textarea id="rs_content" class="textarea mono" style="min-height:260px;font-size:12px" spellcheck="false"
            placeholder="#IP&#10;1.2.3.4&#10;#DOMAIN&#10;example.com&#10;#PORT&#10;80&#10;#DIRECT&#10;pass.example.com">${esc(v.content || '')}</textarea>
          <p class="hint" id="rs_hint">支持 .txt / .csv，单套最大 2MB。可写 #IP / #DOMAIN / #PORT / #DIRECT（放行），放行优先于拦截。</p>
        </div>

        <div style="border:1px solid var(--line);border-radius:7px;padding:12px">
          <div style="display:flex;align-items:center;justify-content:space-between;gap:12px">
            <span style="font-size:12.5px;font-weight:550">保存后参与下发</span>
            <label class="switch"><input type="checkbox" id="rs_enabled" ${enabled ? 'checked' : ''}><i></i></label>
          </div>
          <div style="border-top:1px solid var(--line-soft);margin-top:10px;padding-top:10px">
            <div style="font-size:12px;font-weight:550;margin-bottom:7px">下发给哪些等级</div>
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:7px">
              ${['free', 'beta', 'pro', 'max'].map(t => `<label style="display:flex;align-items:center;gap:7px;font-size:12px;color:#4b5563">
                <input type="checkbox" class="check rs-tier" value="${t}" ${allTiers || tiers.includes(t) ? 'checked' : ''}>${TIER_LABEL[t]}
              </label>`).join('')}
            </div>
            <p class="hint">全都勾上等于对所有等级下发；FREE &lt; BETA &lt; PRO &lt; MAX。</p>
          </div>
        </div>

        <div class="err" id="rs_err"></div>
      </div>`,
    foot: `<button class="btn" data-drawer-close>取消</button>
           <button class="btn btn-primary" id="rs_save">${row ? '保存修改' : '保存规则集'}</button>`,
  });

  $('#rs_import').addEventListener('click', () => $('#rs_file').click());
  $('#rs_file').addEventListener('change', async () => {
    const f = $('#rs_file').files && $('#rs_file').files[0];
    if (!f) return;
    if (f.size > 2 * 1024 * 1024) { $('#rs_hint').textContent = '文件超过 2MB，请拆分后再导入'; toast('文件太大', true); $('#rs_file').value = ''; return; }
    $('#rs_hint').textContent = '正在读取…';
    const fd = new FormData();
    fd.append('file', f);
    const r = await api('admin/rules/import', { method: 'POST', body: fd });
    $('#rs_file').value = '';
    if (!r.ok) { $('#rs_hint').textContent = '读取失败，换一个 txt 再试'; toast('导入失败', true); return; }
    $('#rs_content').value = r.content || '';
    if (!$('#rs_name').value.trim()) $('#rs_name').value = f.name.replace(/\.[^.]+$/, '').slice(0, 60);
    const auto = r.auto_grouped ? '（已自动按类型归类）' : '';
    $('#rs_hint').textContent = `已载入 ${f.name} · ${r.bytes} 字节 · IP ${r.ip} / 域名 ${r.domain} / 端口 ${r.port}${auto}`;
    if ((r.ip + r.domain + r.port) === 0) { $('#rs_hint').textContent += ' · 没识别到规则'; toast('没识别到规则', true); }
    else toast('已载入，确认后点保存');
  });

  $('#rs_save').addEventListener('click', async () => {
    const body = {
      id: v.id || 0,
      name: $('#rs_name').value.trim(),
      version: $('#rs_version').value.trim(),
      note: $('#rs_note').value.trim(),
      content: $('#rs_content').value,
      enabled: $('#rs_enabled').checked,
      tiers: $$('.rs-tier').filter(x => x.checked).map(x => x.value).join(','),
    };
    if (!body.name) { $('#rs_err').textContent = '请填写名称'; return; }
    if (body.content.trim().length < 20) { $('#rs_err').textContent = '规则内容太短'; return; }
    $('#rs_err').textContent = '';
    const btn = $('#rs_save');
    btn.disabled = true;
    const r = await api('admin/rulesets/save', { method: 'POST', body });
    btn.disabled = false;
    if (!r.ok) {
      const map = {
        bad_name: '名称不合法', name_too_long: '名称太长（最多 60 字）', name_exists: '已有同名规则集',
        empty_rules: '规则内容太短', too_large: '单套超过 2MB，请拆分', too_many_sets: '规则集数量已达上限 50 套',
        bad_version: '版本号太长（最多 32 字符）', server_error: '服务器开小差了',
      };
      $('#rs_err').textContent = '保存失败：' + (map[r.error] || r.error || 'unknown');
      return;
    }
    let msg = `${r.replaced ? '已覆盖同名规则集' : '已保存'}：${r.name} · ${r.ip}/${r.domain}/${r.port}`;
    const a = r.applied;
    if (a && a.ok) msg += ` · 已下发 ${a.set_count} 套`;
    else if (a && a.error === 'no_enabled_sets') msg += ' · 当前没有启用规则';
    toast(msg);
    closeDrawer();
    loadRuleSets();
  });
}

async function editRuleSet(id) {
  const r = await api('admin/rulesets/get', { method: 'POST', body: { id } });
  if (!r.ok || !r.row) { toast('读取失败', true); return; }
  rsDrawer(r.row);
}

$('#rsNew').addEventListener('click', () => rsDrawer(null));

$('#rs_all_on').addEventListener('click', async () => {
  const ids = S.ruleSets.map(x => +x.id);
  if (!ids.length) { toast('还没有规则集', true); return; }
  const r = await api('admin/rulesets/toggle', { method: 'POST', body: { ids } });
  if (!r.ok) { toast('操作失败：' + (r.error || 'unknown'), true); return; }
  toast(`已全部纳入下发 · 共 ${r.applied && r.applied.set_count ? r.applied.set_count : ids.length} 套`);
  loadRuleSets();
});

$('#rs_all_off').addEventListener('click', async () => {
  const ok = await confirmAsk({ title: '停用全部规则集', desc: '客户端将拿不到任何规则，确认？', okText: '全部停用', danger: true });
  if (!ok) return;
  const r = await api('admin/rulesets/toggle', { method: 'POST', body: { ids: [] } });
  if (!r.ok) { toast('操作失败', true); return; }
  toast('已全部停用，当前不下发规则');
  loadRuleSets();
});

$('#rs_apply').addEventListener('click', async () => {
  const r = await api('admin/rulesets/apply', { method: 'POST' });
  if (!r.ok) {
    if (r.error === 'no_enabled_sets') { toast('一套都没勾，没有可下发的内容', true); return; }
    toast('应用失败：' + (r.error || 'unknown'), true);
    return;
  }
  toast(`已应用：${r.set_count} 套 · ${bytes(r.bytes)}`);
  loadRuleSets();
});

/* ── 版本 ── */
async function loadVersions() {
  const r = await api('admin/versions');
  if (!r.ok) return;
  S.versions = r.rows || [];
  $('#verRows').innerHTML = S.versions.length ? S.versions.map(v => `<tr>
    <td style="color:#6b7280">${v.platform === 'android' ? 'Android' : 'iOS'}</td>
    <td class="mono" style="font-size:12.5px;font-weight:550">${esc(v.version)}</td>
    <td class="num" style="color:#6b7280">${v.build}</td>
    <td>${v.force_update == 1 ? '<span class="pill pill-amber">强制</span>' : '<span class="pill pill-zinc">可选</span>'}</td>
    <td style="font-size:12px;color:#6b7280;max-width:240px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${esc(v.url || '')}">${esc(v.url || '—')}</td>
    <td class="num" style="color:#6b7280">${ts(v.created_at)}</td>
    <td class="actions">
      <button class="btn btn-xs" data-ver-edit="${v.id}">编辑</button>
      <button class="btn btn-xs btn-danger" data-ver-del="${v.id}">删除</button>
    </td>
  </tr>`).join('') : '<tr><td colspan="7" class="empty">还没有发布过版本</td></tr>';
}

function verDrawer(v) {
  const x = v || {};
  const force = x.force_update == 1;
  const active = v ? x.active == 1 : true;
  openDrawer({
    title: v ? '编辑版本' : '发布版本',
    sub: '保存后客户端下次检测即可看到',
    body: `<div class="space-y-3">
      <input type="hidden" id="v_id" value="${x.id || 0}">
      <div class="grid g2" style="gap:10px">
        <div>
          <label class="label" for="v_platform">平台</label>
          <select id="v_platform" class="select">
            <option value="ios"${(x.platform || 'ios') === 'ios' ? ' selected' : ''}>iOS</option>
            <option value="android"${x.platform === 'android' ? ' selected' : ''}>Android</option>
          </select>
        </div>
        <div>
          <label class="label" for="v_version">版本号</label>
          <input id="v_version" class="input" value="${esc(x.version || '')}" placeholder="1.2.4">
        </div>
        <div>
          <label class="label" for="v_build">Build</label>
          <input id="v_build" class="input num" type="number" min="1" value="${x.build || 1}">
        </div>
        <div>
          <label class="label" for="v_min">最低支持版本</label>
          <input id="v_min" class="input" value="${esc(x.min_version || '')}" placeholder="可留空">
        </div>
      </div>
      <div>
        <label class="label" for="v_url">IPA 下载地址</label>
        <input id="v_url" class="input" value="${esc(x.url || '')}" placeholder="https://ios.ouovo.cc">
      </div>
      <div>
        <label class="label" for="v_notes">更新说明</label>
        <textarea id="v_notes" class="textarea" style="min-height:150px" placeholder="会显示在客户端更新弹窗里">${esc(x.notes || '')}</textarea>
      </div>
      <div style="border:1px solid var(--line);border-radius:7px;padding:12px">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:12px">
          <div><div style="font-size:12.5px;font-weight:550">强制更新</div><div style="font-size:11.5px;color:#8b93a1">旧版本必须升级才能继续使用</div></div>
          <label class="switch"><input type="checkbox" id="v_force" ${force ? 'checked' : ''}><i></i></label>
        </div>
        <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;border-top:1px solid var(--line-soft);margin-top:10px;padding-top:10px">
          <div><div style="font-size:12.5px;font-weight:550">启用</div><div style="font-size:11.5px;color:#8b93a1">关闭后客户端检测不到这一版</div></div>
          <label class="switch"><input type="checkbox" id="v_active" ${active ? 'checked' : ''}><i></i></label>
        </div>
      </div>
      <div class="err" id="v_err"></div>
    </div>`,
    foot: `<button class="btn" data-drawer-close>取消</button>
           <button class="btn btn-primary" id="v_save">保存并发布</button>`,
  });

  $('#v_save').addEventListener('click', async () => {
    const body = {
      id: +$('#v_id').value || 0,
      platform: $('#v_platform').value,
      version: $('#v_version').value.trim(),
      build: +$('#v_build').value || 1,
      min_version: $('#v_min').value.trim(),
      url: $('#v_url').value.trim(),
      notes: $('#v_notes').value,
      force_update: $('#v_force').checked,
      active: $('#v_active').checked,
    };
    if (!body.version) { $('#v_err').textContent = '请填写版本号'; return; }
    $('#v_err').textContent = '';
    const r = await api('admin/versions/save', { method: 'POST', body });
    if (!r.ok) { $('#v_err').textContent = '保存失败：' + (r.error || 'unknown'); return; }
    toast('已保存');
    closeDrawer();
    loadVersions();
  });
}

$('#verNew').addEventListener('click', () => verDrawer(null));
$('#verRefresh').addEventListener('click', () => { loadVersions(); toast('已刷新'); });

function editVersion(id) {
  const v = S.versions.find(x => String(x.id) === String(id));
  if (!v) { toast('没找到这条记录', true); return; }
  verDrawer(v);
}

async function delVersion(id) {
  const ok = await confirmAsk({ title: '删除版本记录', desc: '删除后客户端检测不到这一版。', okText: '删除', danger: true });
  if (!ok) return;
  const r = await api('admin/versions/delete', { method: 'POST', body: { id } });
  if (!r.ok) { toast('删除失败', true); return; }
  toast('已删除');
  loadVersions();
}

/* ═══════════ 公告 ═══════════ */
async function loadNotice() {
  const r = await api('admin/notice');
  if (!r.ok) return;
  const c = r.current || {};
  $('#n_title').value = c.title || '';
  $('#n_content').value = c.content || '';
  $('#n_now').textContent = c.content ? `当前公告更新于 ${ts(c.updated_at)}` : '当前没有下发公告';
  syncPreview();
}

function syncPreview() {
  const t = $('#n_title').value.trim();
  const c = $('#n_content').value;
  $('#pv_title').textContent = t || '公告标题';
  $('#pv_title').style.color = t ? '#111827' : '#8b93a1';
  $('#pv_body').textContent = c || '正文预览';
  $('#pv_body').style.color = c ? '#4b5563' : '#8b93a1';
}

$('#n_title').addEventListener('input', syncPreview);
$('#n_content').addEventListener('input', syncPreview);

$('#noticeForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#n_hint').textContent = '';
  if (!$('#n_content').value.trim() && !$('#n_title').value.trim()) {
    $('#n_hint').textContent = '标题和内容不能同时为空';
    return;
  }
  const r = await api('admin/notice/save', {
    method: 'POST',
    body: { title: $('#n_title').value, content: $('#n_content').value },
  });
  if (!r.ok) { $('#n_hint').textContent = '发布失败'; return; }
  toast('公告已发布');
  loadNotice();
});

$('#n_clear').addEventListener('click', async () => {
  const ok = await confirmAsk({ title: '清空公告', desc: '清空后客户端不再显示公告。', okText: '清空', danger: true });
  if (!ok) return;
  const r = await api('admin/notice/clear', { method: 'POST' });
  if (!r.ok) { toast('操作失败', true); return; }
  toast('公告已清空');
  loadNotice();
});

/* ═══════════ 维护与熔断（即时生效） ═══════════ */
function settingsBody(extra) {
  const s = S.settings || {};
  return Object.assign({
    default_count: +s.default_count || 10,
    default_days: +s.default_days || 30,
    default_plan: s.default_plan || 'all',
    default_charset: s.default_charset || 'std',
    batch_prefix: s.batch_prefix || 'B',
    maintenance_on: +s.maintenance_on === 1 ? 1 : 0,
    maintenance_reason: s.maintenance_reason || '',
    fuse_mode: s.fuse_mode || 'off',
    fuse_build: +s.fuse_build || 0,
    fuse_reason: s.fuse_reason || '',
    min_build: +s.min_build || 0,
  }, extra || {});
}

async function saveSettings(extra) {
  const r = await api('admin/settings/save', { method: 'POST', body: settingsBody(extra) });
  if (r.ok && r.settings) S.settings = r.settings;
  return r;
}

async function loadOps() {
  const r = await api('admin/settings');
  if (!r.ok) return;
  const s = r.settings || {};
  S.settings = s;

  const maintOn = +s.maintenance_on === 1;
  $('#s_maint').checked = maintOn;
  $('#s_maint_reason').value = s.maintenance_reason || '';
  $('#maintState').innerHTML = maintOn
    ? `<span class="dot warn"></span><span>当前：<b>维护中</b> · ${esc(s.maintenance_reason || '未填原因')}</span>`
    : '<span class="dot off"></span><span>当前：<b>正常</b></span>';

  const mode = s.fuse_mode || 'off';
  $('#s_fuse_mode').value = mode;
  $('#s_fuse_build').value = s.fuse_build || 0;
  $('#s_fuse_reason').value = s.fuse_reason || '';
  const pill = $('#fusePill');
  if (mode === 'all') { pill.className = 'pill pill-rose'; pill.textContent = '全部版本'; }
  else if (mode === 'below') { pill.className = 'pill pill-rose'; pill.textContent = `build < ${+s.fuse_build || 0}`; }
  else { pill.className = 'pill pill-zinc'; pill.textContent = '关闭'; }
  $('#fuseState').innerHTML = mode === 'off'
    ? '<span class="dot off"></span><span>当前：<b>未熔断</b></span>'
    : `<span class="dot bad"></span><span>当前：<b>熔断中</b> · ${mode === 'all' ? '全部版本' : 'build &lt; ' + (+s.fuse_build || 0)}</span>`;

  $('#s_min_build').value = s.min_build || 0;

  /* 顶栏同步 */
  const top = $('#topStatus');
  if (maintOn) { top.className = 'env warn'; top.innerHTML = '<i class="led"></i>维护中'; }
  else if (mode !== 'off') { top.className = 'env bad'; top.innerHTML = '<i class="led"></i>熔断开启'; }
  else { top.className = 'env'; top.innerHTML = '<i class="led"></i>运行正常'; }
  $('#navOpsDot').classList.toggle('hide', !(maintOn || mode !== 'off'));
}

$('#maint_save').addEventListener('click', async () => {
  const on = $('#s_maint').checked ? 1 : 0;
  const reason = $('#s_maint_reason').value.trim();
  if (on === 1) {
    const ok = await confirmAsk({
      title: '开启维护模式',
      desc: reason ? `客户端会显示：${reason}` : '没填原因，客户端只会显示「系统维护中」。确认开启？',
      okText: '开启维护', danger: true,
    });
    if (!ok) { $('#s_maint').checked = false; return; }
  }
  $('#maint_hint').textContent = '保存中…';
  const r = await saveSettings({ maintenance_on: on, maintenance_reason: reason });
  if (!r.ok) { $('#maint_hint').textContent = '保存失败'; toast('保存失败', true); return; }
  $('#maint_hint').textContent = '已保存';
  toast(on ? '维护模式已开启 · 25 秒内生效' : '维护模式已关闭 · 25 秒内生效');
  loadOps();
});

$('#fuse_save').addEventListener('click', async () => {
  const mode = $('#s_fuse_mode').value;
  if (mode === 'all') {
    const ok = await confirmAsk({ title: '全部版本熔断', desc: '所有客户端打开即退出。确认？', okText: '确认熔断', danger: true });
    if (!ok) return;
  }
  $('#fuse_hint').textContent = '保存中…';
  const r = await saveSettings({
    fuse_mode: mode,
    fuse_build: +$('#s_fuse_build').value || 0,
    fuse_reason: $('#s_fuse_reason').value,
  });
  if (!r.ok) { $('#fuse_hint').textContent = '保存失败'; toast('保存失败', true); return; }
  $('#fuse_hint').textContent = '已保存';
  toast('熔断设置已保存 · 25 秒内生效');
  loadOps();
});

$('#min_save').addEventListener('click', async () => {
  const r = await saveSettings({ min_build: +$('#s_min_build').value || 0 });
  if (!r.ok) { toast('保存失败', true); return; }
  toast('已保存');
});

$('#opsRefresh').addEventListener('click', () => { loadOps(); toast('已刷新'); });

/* ═══════════ 日志 ═══════════ */
$$('[data-logtab]').forEach(t => t.addEventListener('click', () => {
  S.tab = t.dataset.logtab;
  $$('[data-logtab]').forEach(x => x.classList.toggle('active', x === t));
  loadLogs();
}));

async function loadLogs() {
  const r = await api('admin/logs');
  if (!r.ok) return;
  const isAudit = S.tab === 'audit';
  $('#logHead').innerHTML = isAudit
    ? '<tr><th style="width:150px">时间</th><th style="width:160px">动作</th><th style="width:170px">目标</th><th style="width:130px">IP</th><th>详情</th></tr>'
    : '<tr><th style="width:150px">时间</th><th style="width:150px">类型</th><th style="width:110px">配对码</th><th style="width:190px">卡密</th><th style="width:130px">IP</th><th>详情</th></tr>';
  const rows = isAudit ? (r.audit || []) : (r.events || []);
  $('#logRows').innerHTML = rows.length ? rows.map(x => isAudit
    ? `<tr><td class="num" style="color:#6b7280">${ts(x.ts)}</td><td>${esc(x.action)}</td>
        <td class="mono" style="font-size:12px;color:#6b7280">${esc(x.target || '—')}</td>
        <td class="mono" style="font-size:12px;color:#6b7280">${esc(x.ip || '—')}</td>
        <td style="color:#4b5563">${esc(x.detail || '')}</td></tr>`
    : `<tr><td class="num" style="color:#6b7280">${ts(x.ts)}</td><td>${esc(x.kind)}</td>
        <td class="mono" style="font-size:12.5px">${esc(x.pin || '—')}</td>
        <td class="mono" style="font-size:12px;color:#6b7280">${esc(x.code || '—')}</td>
        <td class="mono" style="font-size:12px;color:#6b7280">${esc(x.ip || '—')}</td>
        <td style="color:#4b5563">${esc(x.detail || '')}</td></tr>`
  ).join('') : '<tr><td colspan="6" class="empty">暂无记录</td></tr>';
}
$('#logRefresh').addEventListener('click', () => { loadLogs(); toast('已刷新'); });

/* ═══════════ 设置 ═══════════ */
async function loadSettings() {
  const r = await api('admin/settings');
  if (!r.ok) return;
  const s = r.settings || {};
  S.settings = s;
  $('#s_count').value = s.default_count;
  $('#s_days').value = s.default_days;
  $('#s_plan').value = s.default_plan;
  $('#s_charset').value = s.default_charset;
  $('#s_batch').value = s.batch_prefix;
}

$('#s_save').addEventListener('click', async () => {
  $('#s_err').textContent = '';
  const r = await saveSettings({
    default_count: +$('#s_count').value || 10,
    default_days: +$('#s_days').value || 30,
    default_plan: $('#s_plan').value,
    default_charset: $('#s_charset').value,
    batch_prefix: $('#s_batch').value,
  });
  if (!r.ok) { $('#s_err').textContent = '保存失败'; return; }
  toast('设置已保存');
  loadSettings();
});

$('#pwForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#pw_err').textContent = '';
  if ($('#pw_new').value !== $('#pw_new2').value) { $('#pw_err').textContent = '两次输入的新密码不一致'; return; }
  if ($('#pw_new').value.length < 8) { $('#pw_err').textContent = '新密码至少 8 位'; return; }
  const r = await api('admin/password', {
    method: 'POST',
    body: { current: $('#pw_cur').value, new: $('#pw_new').value },
  });
  if (!r.ok) { $('#pw_err').textContent = r.error === 'bad_current' ? '当前密码不正确' : '修改失败'; return; }
  $('#pw_cur').value = $('#pw_new').value = $('#pw_new2').value = '';
  toast('密码已更新');
});

async function dangerAction(action) {
  const labels = {
    clear_logs: ['清空全部日志', '删除所有审计与客户端事件记录。'],
    clear_unused_cards: ['清空所有未使用卡密', '尚未兑换的卡密会被删除。'],
    clear_expired_cards: ['清空所有已过期卡密', '已兑换且已到期的卡密会被删除。'],
    clear_all_cards: ['清空全部卡密', '含未使用、已兑换、已作废，全部删除。'],
  };
  const [title, desc] = labels[action] || [action, ''];
  const ok = await confirmAsk({ title, desc: desc + ' 此操作不可撤销。', okText: '确认清空', danger: true });
  if (!ok) return;
  const r = await api('admin/danger', { method: 'POST', body: { action } });
  if (!r.ok) { toast('操作失败', true); return; }
  toast(`已清理 ${r.affected} 条`);
  if (action === 'clear_logs') loadLogs(); else { S.page = 1; loadCards(); }
}

/* ═══════════ 启动 ═══════════ */
(async function boot() {
  const r = await api('admin/csrf');
  if (r.ok && r.csrf) {
    CSRF = r.csrf;
    const s = await api('admin/stats');
    if (s.ok) { showShell('admin'); return; }
  }
  showAuth();
})();

})();
</script>
</body>
</html>
