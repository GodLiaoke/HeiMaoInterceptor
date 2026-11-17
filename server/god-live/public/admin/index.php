<?php
declare(strict_types=1);
require __DIR__ . '/../../app/bootstrap.php';
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>卡密控制台</title>
<link rel="stylesheet" href="/assets/admin.css">
</head>
<body>

<!-- ══════════════ 登录 ══════════════ -->
<div id="auth" class="auth">
  <div class="auth-box">
    <div class="auth-brand">
      <h1>卡密控制台</h1>
      <p>God 授权系统 · 管理后台</p>
    </div>
    <form id="loginForm" autocomplete="on">
      <label class="field">
        <span class="label">账号</span>
        <input id="u" class="input" autocomplete="username" required>
      </label>
      <label class="field">
        <span class="label">密码</span>
        <input id="p" type="password" class="input" autocomplete="current-password" required>
      </label>
      <div class="err" id="loginErr"></div>
      <button type="submit" class="btn btn-primary" style="width:100%">登录</button>
    </form>
  </div>
</div>

<!-- ══════════════ 主界面 ══════════════ -->
<div id="shell" class="shell" hidden>
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-mark">GD</div>
      <div class="brand-text">
        <b>God 授权系统</b>
        <span>卡密与配对码管理</span>
      </div>
    </div>

    <nav class="nav" id="nav">
      <button class="nav-item active" data-view="overview" data-icon="grid">概览</button>
      <button class="nav-item" data-view="cards" data-icon="key">卡密</button>
      <button class="nav-item" data-view="pins" data-icon="link">配对码</button>
      <button class="nav-item" data-view="notice" data-icon="message">公告</button>
      <button class="nav-item" data-view="versions" data-icon="cloud">版本</button>
      <button class="nav-item" data-view="logs" data-icon="list">日志</button>
      <button class="nav-item" data-view="settings" data-icon="sliders">设置</button>
    </nav>

    <div class="sidebar-foot">
      <span id="whoami">—</span>
      <button class="btn-text" id="logout">退出</button>
    </div>
  </aside>

  <main class="main">

    <!-- 概览 -->
    <section class="page" id="view-overview">
      <div class="page-head">
        <h2>概览</h2>
        <p>授权状态与最近活动</p>
      </div>

      <div class="metrics">
        <div class="metric"><div class="k">在线授权</div><div class="v" id="m_online">–</div></div>
        <div class="metric"><div class="k">未使用卡密</div><div class="v" id="m_unused">–</div></div>
        <div class="metric"><div class="k">24 小时兑换</div><div class="v" id="m_redeem">–</div></div>
        <div class="metric"><div class="k">24 小时失败</div><div class="v" id="m_fail">–</div></div>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>最近活动</h3>
          <p>卡密兑换与授权变更记录</p>
        </div>
        <div class="table-wrap">
          <table class="tbl">
            <thead><tr><th style="width:150px">时间</th><th style="width:150px">类型</th><th>配对码</th><th>IP</th><th>详情</th></tr></thead>
            <tbody id="ov_events"></tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- 卡密 -->
    <section class="page" id="view-cards" hidden>
      <div class="page-head">
        <h2>卡密</h2>
        <p>批量生成、分类管理与导出</p>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>生成卡密</h3>
          <p>选择类型与时长，一次生成一批</p>
        </div>

        <form id="genForm">
          <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:0 16px">
            <label class="field">
              <span class="label">卡密类型</span>
              <select id="g_type" class="select">
                <option value="trial">试用 · 1 天</option>
                <option value="week">周卡 · 7 天</option>
                <option value="month" selected>月卡 · 30 天</option>
                <option value="quarter">季卡 · 90 天</option>
                <option value="year">年卡 · 365 天</option>
                <option value="custom">自定义时长</option>
              </select>
            </label>

            <label class="field" id="g_daysField" hidden>
              <span class="label">自定义天数</span>
              <input id="g_days" class="input" type="number" min="1" max="3650" value="30">
            </label>

            <label class="field">
              <span class="label">功能套餐</span>
              <select id="g_plan" class="select">
                <option value="all" selected>全部功能</option>
                <option value="basic">基础 · 核心与瞄准</option>
                <option value="pro">专业 · 不含驱动</option>
              </select>
            </label>

            <label class="field">
              <span class="label">数量</span>
              <input id="g_count" class="input" type="number" min="1" max="1000" value="10">
            </label>

            <label class="field">
              <span class="label">卡密字符集</span>
              <select id="g_charset" class="select">
                <option value="std" selected>标准 · 去形近字</option>
                <option value="digit">纯数字</option>
                <option value="alpha">纯字母</option>
                <option value="full">全量字母数字</option>
              </select>
            </label>

            <label class="field">
              <span class="label">批次名称</span>
              <input id="g_batch" class="input" placeholder="留空自动生成">
            </label>
          </div>

          <label class="field">
            <span class="label">备注（可选）</span>
            <input id="g_note" class="input" placeholder="例如：渠道 A、活动赠送">
          </label>

          <div class="err" id="genErr"></div>
          <button type="submit" class="btn btn-primary" id="genBtn">生成</button>
        </form>

        <div class="out" id="genOut" hidden>
          <div class="out-head">
            <span id="genSummary">—</span>
            <span style="display:flex;gap:8px">
              <button class="btn btn-sm" id="copyCodes">复制</button>
              <button class="btn btn-sm" id="downloadCodes">下载</button>
            </span>
          </div>
          <textarea id="genCodes" readonly spellcheck="false"></textarea>
        </div>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>卡密列表</h3>
          <p>支持按状态、批次筛选与批量操作</p>
        </div>

        <div class="toolbar">
          <input id="f_q" class="input search" placeholder="搜索卡密或绑定配对码">
          <select id="f_status" class="select">
            <option value="-1">全部状态</option>
            <option value="0">未使用</option>
            <option value="1">已兑换</option>
            <option value="2">已作废</option>
          </select>
          <select id="f_batch" class="select"><option value="">全部批次</option></select>
          <span class="grow"></span>
          <button class="btn btn-sm" id="exportBtn">导出 CSV</button>
        </div>

        <div class="bulkbar" id="bulkbar" hidden>
          <span id="bulkCount">已选 0 项</span>
          <button class="btn btn-sm" data-bulk="unban">解除作废</button>
          <button class="btn btn-sm" data-bulk="ban">作废</button>
          <button class="btn btn-sm" data-bulk="extend">延期 7 天</button>
          <button class="btn btn-sm btn-danger" data-bulk="delete">删除</button>
        </div>

        <div class="table-wrap">
          <table class="tbl">
            <thead>
              <tr>
                <th class="col-check"><input type="checkbox" id="checkAll"></th>
                <th style="width:200px">卡密</th>
                <th style="width:130px">批次</th>
                <th style="width:90px">时长</th>
                <th style="width:90px">状态</th>
                <th style="width:170px">到期时间</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody id="rows"></tbody>
          </table>
        </div>

        <div class="pager">
          <span id="pagerInfo">—</span>
          <span class="btns">
            <button class="btn btn-sm" id="prev">上一页</button>
            <button class="btn btn-sm" id="next">下一页</button>
          </span>
        </div>
      </div>
    </section>

    <!-- 配对码 -->
    <section class="page" id="view-pins" hidden>
      <div class="page-head">
        <h2>配对码</h2>
        <p>客户端上报的配对码与授权状态</p>
      </div>
      <div class="table-wrap">
        <table class="tbl">
          <thead>
            <tr>
              <th style="width:110px">配对码</th>
              <th style="width:150px">首次出现</th>
              <th style="width:150px">最近活跃</th>
              <th style="width:130px">IP</th>
              <th style="width:170px">授权到期</th>
              <th style="width:80px">兑换次数</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody id="pinRows"></tbody>
        </table>
      </div>
    </section>

    <!-- 公告 -->
    <section class="page" id="view-notice" hidden>
      <div class="page-head">
        <h2>公告</h2>
        <p>下发到客户端的提示内容</p>
      </div>
      <div class="group">
        <form id="noticeForm">
          <label class="field">
            <span class="label">标题</span>
            <input id="n_title" class="input" placeholder="可选">
          </label>
          <label class="field">
            <span class="label">内容</span>
            <textarea id="n_content" class="textarea" placeholder="留空表示不下发公告"></textarea>
          </label>
          <div class="hint" id="n_now">—</div>
          <div class="err" id="n_hint"></div>
          <div style="display:flex;gap:8px;margin-top:16px">
            <button type="submit" class="btn btn-primary" id="n_save">发布</button>
            <button type="button" class="btn" id="n_clear">清空公告</button>
          </div>
        </form>
      </div>
    </section>

    <!-- 日志 -->
    <section class="page" id="view-logs" hidden>
      <div class="page-head">
        <h2>日志</h2>
        <p>后台操作审计与客户端事件</p>
      </div>
      <div class="tabs">
        <button class="tab active" data-tab="audit">操作审计</button>
        <button class="tab" data-tab="events">客户端事件</button>
      </div>
      <div class="table-wrap">
        <table class="tbl">
          <thead id="logHead"></thead>
          <tbody id="logRows"></tbody>
        </table>
      </div>
    </section>

    <!-- 版本管理 / 云端规则 -->
    <section class="page" id="view-versions" hidden>
      <div class="page-head">
        <h2>版本管理</h2>
        <p>客户端更新检测、强制更新与下载地址</p>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>发布版本</h3>
          <p>保存后客户端下次检测即可看到</p>
        </div>
        <form id="verForm">
          <input type="hidden" id="v_id" value="0">
          <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:0 16px">
            <label class="field">
              <span class="label">平台</span>
              <select id="v_platform" class="select">
                <option value="ios" selected>iOS</option>
                <option value="android">Android</option>
              </select>
            </label>
            <label class="field">
              <span class="label">版本号</span>
              <input id="v_version" class="input" placeholder="1.0">
            </label>
            <label class="field">
              <span class="label">Build</span>
              <input id="v_build" class="input" type="number" min="1" value="1">
            </label>
            <label class="field">
              <span class="label">最低支持版本</span>
              <input id="v_min" class="input" placeholder="可留空，如 0.9">
            </label>
          </div>
          <label class="field">
            <span class="label">IPA 下载地址</span>
            <input id="v_url" class="input" placeholder="https://example.com/HeiMao.ipa">
          </label>
          <label class="field">
            <span class="label">更新说明</span>
            <textarea id="v_notes" class="textarea" placeholder="这一版改了什么，会显示在客户端弹窗里"></textarea>
          </label>
          <div class="rows">
            <div class="row">
              <div class="row-label"><div class="t">强制更新</div><div class="d">开启后旧版本必须升级才能继续使用</div></div>
              <div class="row-control"><input type="checkbox" id="v_force"></div>
            </div>
            <div class="row">
              <div class="row-label"><div class="t">启用</div><div class="d">关闭后客户端检测不到这一版</div></div>
              <div class="row-control"><input type="checkbox" id="v_active" checked></div>
            </div>
          </div>
          <div class="err" id="v_err"></div>
          <div style="display:flex;gap:8px;margin-top:16px">
            <button type="submit" class="btn btn-primary" id="v_save">保存并发布</button>
            <button type="button" class="btn" id="v_reset">新建</button>
          </div>
        </form>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>版本记录</h3>
          <p>按发布时间倒序，可编辑或删除</p>
        </div>
        <div class="table-wrap">
          <table class="tbl">
            <thead><tr>
              <th>平台</th><th>版本</th><th>Build</th><th>强制</th><th>下载地址</th><th>发布时间</th><th style="width:130px">操作</th>
            </tr></thead>
            <tbody id="verRows"></tbody>
          </table>
        </div>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>云端规则库</h3>
          <p>规则只存服务器，客户端凭有效卡密加密下载，解析后仅在内存中使用</p>
        </div>
        <div class="hint" id="r_now">—</div>
        <form id="rulesForm">
          <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:10px">
            <input type="file" id="r_file" accept=".txt,.conf,.list,.rules,.csv,text/plain" hidden>
            <button type="button" class="btn btn-primary" id="r_pick">导入 txt（自动适配）</button>
            <button type="button" class="btn" id="r_fix">把下面内容自动适配</button>
            <span class="muted" id="r_import" style="font-size:12px">
              支持 #IP/#DOMAIN/#PORT 分段、hosts、dnsmasq、AdGuard、纯 IP/CIDR、带端口
            </span>
          </div>
          <div style="display:grid;grid-template-columns:1fr 2fr;gap:0 16px">
            <label class="field">
              <span class="label">规则版本</span>
              <input id="r_version" class="input" placeholder="2026.11.17">
            </label>
            <label class="field">
              <span class="label">说明</span>
              <input id="r_note" class="input" placeholder="本次更新了什么">
            </label>
          </div>
          <label class="field">
            <span class="label">规则内容</span>
            <textarea id="r_content" class="textarea"
              style="min-height:240px;font-family:ui-monospace,Menlo,monospace;font-size:12px"
              placeholder="#IP&#10;1.2.3.4&#10;#DOMAIN&#10;example.com&#10;#PORT&#10;80"></textarea>
          </label>
          <div class="err" id="r_err"></div>
          <div style="margin-top:12px">
            <button type="submit" class="btn btn-primary" id="r_save">保存并加密下发</button>
          </div>
        </form>
      </div>
    </section>

    <!-- 设置 -->
    <section class="page" id="view-settings" hidden>
      <div class="page-head">
        <h2>设置</h2>
        <p>默认值、账号安全与维护</p>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>生成默认值</h3>
          <p>生成卡密时预填的参数</p>
        </div>
        <div class="rows">
          <div class="row">
            <div class="row-label"><div class="t">默认数量</div><div class="d">单批生成条数</div></div>
            <div class="row-control"><input id="s_count" class="input" type="number" min="1" max="1000"></div>
          </div>
          <div class="row">
            <div class="row-label"><div class="t">默认时长</div><div class="d">单位：天</div></div>
            <div class="row-control"><input id="s_days" class="input" type="number" min="1" max="3650"></div>
          </div>
          <div class="row">
            <div class="row-label"><div class="t">默认套餐</div><div class="d">决定客户端可用功能</div></div>
            <div class="row-control">
              <select id="s_plan" class="select">
                <option value="all">全部功能</option>
                <option value="basic">基础</option>
                <option value="pro">专业</option>
              </select>
            </div>
          </div>
          <div class="row">
            <div class="row-label"><div class="t">默认字符集</div><div class="d">卡密使用的字符范围</div></div>
            <div class="row-control">
              <select id="s_charset" class="select">
                <option value="std">标准 · 去形近字</option>
                <option value="digit">纯数字</option>
                <option value="alpha">纯字母</option>
                <option value="full">全量字母数字</option>
              </select>
            </div>
          </div>
          <div class="row">
            <div class="row-label"><div class="t">批次前缀</div><div class="d">自动生成批次名时使用</div></div>
            <div class="row-control"><input id="s_batch" class="input" maxlength="8"></div>
          </div>
        </div>
        <div class="err" id="s_err"></div>
        <div style="margin-top:16px"><button class="btn btn-primary" id="s_save">保存设置</button></div>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>修改密码</h3>
          <p>修改后当前会话保持有效</p>
        </div>
        <form id="pwForm" style="max-width:360px">
          <label class="field">
            <span class="label">当前密码</span>
            <input id="pw_cur" type="password" class="input" autocomplete="current-password">
          </label>
          <label class="field">
            <span class="label">新密码</span>
            <input id="pw_new" type="password" class="input" autocomplete="new-password">
            <span class="hint">至少 8 位</span>
          </label>
          <label class="field">
            <span class="label">确认新密码</span>
            <input id="pw_new2" type="password" class="input" autocomplete="new-password">
          </label>
          <div class="err" id="pw_err"></div>
          <button type="submit" class="btn btn-primary">更新密码</button>
        </form>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>维护</h3>
          <p>以下操作不可撤销，请确认后执行</p>
        </div>
        <div class="danger-row">
          <div>
            <div class="t">清空未使用卡密</div>
            <div class="d">删除所有尚未兑换的卡密，已兑换的保留</div>
          </div>
          <button class="btn btn-danger" data-danger="clear_unused_cards">清空</button>
        </div>
        <div class="danger-row">
          <div>
            <div class="t">清空日志</div>
            <div class="d">删除全部操作审计与客户端事件记录</div>
          </div>
          <button class="btn btn-danger" data-danger="clear_logs">清空</button>
        </div>
      </div>
    </section>

  </main>
</div>

<div class="toast" id="toast"></div>

<script>
/* ═══════════ 基础 ═══════════ */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

let CSRF = '';
let STATE = { view: 'overview', page: 1, per: 20, total: 0, rows: [], selected: new Set(), tab: 'audit', settings: null };

function toast(msg, isErr) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast show' + (isErr ? ' error' : '');
  clearTimeout(t._h);
  t._h = setTimeout(() => { t.className = 'toast'; }, 2600);
}

async function api(path, opt = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (CSRF) headers['X-CSRF'] = CSRF;
  let res;
  try {
    res = await fetch('/api/' + path, {
      method: opt.method || 'GET',
      headers,
      credentials: 'same-origin',
      body: opt.body ? JSON.stringify(opt.body) : undefined,
    });
  } catch (e) {
    return { ok: false, error: 'network' };
  }
  if (res.status === 401) { showAuth(); return { ok: false, error: 'unauthenticated' }; }
  try { return await res.json(); } catch (e) { return { ok: false, error: 'bad_response' }; }
}

const ts = (n) => {
  if (!n) return '—';
  const d = new Date(n * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
};

const dur = (sec) => {
  sec = +sec || 0;
  if (sec % 86400 === 0) return (sec / 86400) + ' 天';
  if (sec % 3600 === 0) return (sec / 3600) + ' 小时';
  return Math.round(sec / 60) + ' 分钟';
};

/* 线性图标，统一 1.6 描边 */
const ICONS = {
  grid: '<path d="M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="M10.8 12.2 20 3M17 3h3v3"/>',
  link: '<path d="M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1"/><path d="M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1"/>',
  message: '<path d="M21 12a8 8 0 0 1-8 8H7l-4 3V12a8 8 0 0 1 8-8h2a8 8 0 0 1 8 8z"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  sliders: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
  cloud: '<path d="M7 18a5 5 0 0 1 0-10 6 6 0 0 1 11.5-1.5A4.5 4.5 0 0 1 18 18H7z"/>',
};
function paintIcons() {
  $$('.nav-item').forEach(el => {
    const n = el.dataset.icon;
    if (!n || !ICONS[n]) return;
    el.insertAdjacentHTML('afterbegin',
      `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
        stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${ICONS[n]}</svg>`);
  });
}

/* ═══════════ 登录 ═══════════ */
function showAuth() {
  $('#auth').hidden = false;
  $('#shell').hidden = true;
}
function showShell(user) {
  $('#auth').hidden = true;
  $('#shell').hidden = false;
  $('#whoami').textContent = user || 'admin';
  paintIcons();
  switchView('overview');
}

$('#loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#loginErr').textContent = '';
  const r = await api('admin/login', { method: 'POST', body: { username: $('#u').value.trim(), password: $('#p').value } });
  if (!r.ok) { $('#loginErr').textContent = '账号或密码不正确'; return; }
  CSRF = r.csrf || '';
  showShell(r.user);
});

$('#logout').addEventListener('click', async () => {
  await api('admin/logout', { method: 'POST' });
  CSRF = '';
  showAuth();
});

/* ═══════════ 视图切换 ═══════════ */
function switchView(v) {
  STATE.view = v;
  $$('.nav-item').forEach(b => b.classList.toggle('active', b.dataset.view === v));
  ['overview', 'cards', 'pins', 'notice', 'versions', 'logs', 'settings'].forEach(k => {
    $('#view-' + k).hidden = (k !== v);
  });
  if (v === 'overview') loadOverview();
  if (v === 'cards') loadCards();
  if (v === 'pins') loadPins();
  if (v === 'notice') loadNotice();
  if (v === 'versions') { loadVersions(); loadRules(); }
  if (v === 'logs') loadLogs();
  if (v === 'settings') loadSettings();
}
$$('.nav-item').forEach(b => b.addEventListener('click', () => switchView(b.dataset.view)));

/* ═══════════ 概览 ═══════════ */
async function loadOverview() {
  const s = await api('admin/stats');
  if (s.ok) {
    $('#m_online').textContent = s.pins_online;
    $('#m_unused').textContent = s.cards_unused;
    $('#m_redeem').textContent = s.redeem_24h;
    $('#m_fail').textContent = s.fail_24h;
  }
  const l = await api('admin/logs');
  if (!l.ok) return;
  const rows = (l.events || []).slice(0, 12);
  $('#ov_events').innerHTML = rows.length ? rows.map(e => `<tr>
    <td class="muted num">${ts(e.ts)}</td>
    <td>${esc(e.kind)}</td>
    <td class="mono">${esc(e.pin || '—')}</td>
    <td class="mono muted">${esc(e.ip || '—')}</td>
    <td class="muted">${esc(e.detail || '')}</td>
  </tr>`).join('') : `<tr><td colspan="5" class="empty">暂无记录</td></tr>`;
}

/* ═══════════ 卡密 ═══════════ */
const DURATIONS = { trial: 1, week: 7, month: 30, quarter: 90, year: 365 };

function currentDays() {
  const t = $('#g_type').value;
  return t === 'custom' ? Math.max(1, +$('#g_days').value || 1) : DURATIONS[t];
}

$('#g_type').addEventListener('change', () => {
  $('#g_daysField').hidden = $('#g_type').value !== 'custom';
});

$('#genForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#genErr').textContent = '';
  const days = currentDays();
  const batch = $('#g_batch').value.trim()
    || (($('#s_batch') && $('#s_batch').value ? $('#s_batch').value : 'B') + new Date().toISOString().slice(0, 10).replace(/-/g, ''));
  const btn = $('#genBtn');
  btn.disabled = true;
  const r = await api('admin/cards/generate', {
    method: 'POST',
    body: {
      count: Math.max(1, +$('#g_count').value || 1),
      duration: days * 86400,
      batch,
      note: $('#g_note').value.trim(),
      plan: $('#g_plan').value,
      charset: $('#g_charset').value,
    },
  });
  btn.disabled = false;
  if (!r.ok) { $('#genErr').textContent = '生成失败'; return; }
  $('#genOut').hidden = false;
  $('#genSummary').textContent = `已生成 ${r.created} 张 · ${days} 天 · 批次 ${batch}`;
  $('#genCodes').value = (r.codes || []).join('\n');
  toast('已生成 ' + r.created + ' 张卡密');
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

async function loadBatches() {
  const r = await api('admin/batches');
  if (!r.ok) return;
  const sel = $('#f_batch');
  const cur = sel.value;
  sel.innerHTML = '<option value="">全部批次</option>' +
    (r.rows || []).map(x => `<option value="${esc(x.batch)}">${esc(x.batch)} (${x.c})</option>`).join('');
  sel.value = cur;
}

async function loadCards() {
  const q = encodeURIComponent($('#f_q').value.trim());
  const st = $('#f_status').value;
  const b = encodeURIComponent($('#f_batch').value);
  const r = await api(`admin/cards?page=${STATE.page}&per=${STATE.per}&q=${q}&status=${st}` + (b ? `&batch=${b}` : ''));
  if (!r.ok) return;
  const rows = r.rows || [];
  STATE.rows = rows;
  STATE.total = r.total;
  STATE.selected.clear();
  $('#checkAll').checked = false;
  renderBulk();

  const pages = Math.max(1, Math.ceil(STATE.total / STATE.per));
  $('#pagerInfo').textContent = `共 ${STATE.total} 条 · 第 ${STATE.page} / ${pages} 页`;

  const STATE_TXT = { 0: ['未使用', 'state-0'], 1: ['已兑换', 'state-1'], 2: ['已作废', 'state-2'] };
  $('#rows').innerHTML = rows.length ? rows.map(c => {
    const s = STATE_TXT[c.status] || ['未知', 'muted'];
    const tip = [c.bound_pin ? '绑定 ' + c.bound_pin : '', c.note || ''].filter(Boolean).join(' · ');
    return `<tr>
      <td class="col-check"><input type="checkbox" data-id="${c.id}"></td>
      <td class="mono" title="${esc(tip)}">${esc(c.code)}</td>
      <td class="muted">${esc(c.batch || '—')}</td>
      <td class="muted">${dur(c.duration_sec)}</td>
      <td class="${s[1]}">${s[0]}</td>
      <td class="muted num">${c.expire_at ? ts(c.expire_at) : '—'}</td>
      <td>
        <button class="btn btn-sm" data-act="extend" data-id="${c.id}">延期</button>
        <button class="btn btn-sm" data-act="toggle" data-id="${c.id}" data-status="${c.status}">${c.status === 2 ? '解封' : '作废'}</button>
        ${c.bound_pin ? `<button class="btn btn-sm" data-act="unbind" data-id="${c.id}">解绑</button>` : ''}
        <button class="btn btn-sm btn-danger" data-act="delete" data-id="${c.id}">删除</button>
      </td>
    </tr>`;
  }).join('') : `<tr><td colspan="7" class="empty">没有符合条件的数据</td></tr>`;

  $$('#rows input[type=checkbox]').forEach(cb => cb.addEventListener('change', () => {
    const id = +cb.dataset.id;
    cb.checked ? STATE.selected.add(id) : STATE.selected.delete(id);
    renderBulk();
  }));

  $$('#rows [data-act]').forEach(btn => btn.addEventListener('click', () => cardAction(btn)));
  loadBatches();
}

function renderBulk() {
  const n = STATE.selected.size;
  $('#bulkbar').hidden = n === 0;
  $('#bulkCount').textContent = `已选 ${n} 项`;
}

$('#checkAll').addEventListener('change', (e) => {
  const on = e.target.checked;
  $$('#rows input[type=checkbox]').forEach(cb => {
    cb.checked = on;
    const id = +cb.dataset.id;
    on ? STATE.selected.add(id) : STATE.selected.delete(id);
  });
  renderBulk();
});

async function cardAction(btn) {
  const id = +btn.dataset.id;
  const act = btn.dataset.act;
  if (act === 'extend') {
    const d = prompt('延期天数（负数表示缩短）', '7');
    if (d === null || d === '' || isNaN(+d)) return;
    const r = await api('admin/cards/extend', { method: 'POST', body: { id, days: +d } });
    if (!r.ok) { toast('操作失败', true); return; }
    toast('已调整有效期'); loadCards(); return;
  }
  if (act === 'toggle') {
    const to = +btn.dataset.status === 2 ? 0 : 2;
    const r = await api('admin/cards/status', { method: 'POST', body: { id, status: to } });
    if (!r.ok) { toast('操作失败', true); return; }
    toast(to === 2 ? '已作废' : '已解封'); loadCards(); return;
  }
  if (act === 'unbind') {
    if (!confirm('解绑后这张卡密可以在别的设备上继续使用（剩余时长不变），确认？')) return;
    const r = await api('admin/cards/unbind', { method: 'POST', body: { id } });
    if (!r.ok) { toast('解绑失败', true); return; }
    toast('已解绑'); loadCards(); return;
  }
  if (act === 'delete') {
    if (!confirm('删除后不可恢复，确认删除这张卡密？')) return;
    const r = await api('admin/cards/delete', { method: 'POST', body: { id } });
    if (!r.ok) { toast('删除失败', true); return; }
    toast('已删除'); loadCards();
  }
}

$$('[data-bulk]').forEach(b => b.addEventListener('click', async () => {
  const ids = Array.from(STATE.selected);
  if (!ids.length) return;
  const action = b.dataset.bulk;
  if (action === 'delete' && !confirm(`确认删除选中的 ${ids.length} 张卡密？`)) return;
  const body = { ids, action };
  if (action === 'extend') body.days = 7;
  const r = await api('admin/cards/bulk', { method: 'POST', body });
  if (!r.ok) { toast('批量操作失败', true); return; }
  toast(`已处理 ${r.done} 项`);
  loadCards();
}));

$('#exportBtn').addEventListener('click', () => {
  const q = encodeURIComponent($('#f_q').value.trim());
  const st = $('#f_status').value;
  const b = encodeURIComponent($('#f_batch').value);
  window.location.href = `/api/admin/cards/export?q=${q}&status=${st}` + (b ? `&batch=${b}` : '');
});

$('#f_q').addEventListener('input', () => { STATE.page = 1; clearTimeout(window._qt); window._qt = setTimeout(loadCards, 260); });
$('#f_status').addEventListener('change', () => { STATE.page = 1; loadCards(); });
$('#f_batch').addEventListener('change', () => { STATE.page = 1; loadCards(); });
$('#prev').addEventListener('click', () => { if (STATE.page > 1) { STATE.page--; loadCards(); } });
$('#next').addEventListener('click', () => {
  if (STATE.page * STATE.per < STATE.total) { STATE.page++; loadCards(); }
});

/* ═══════════ 配对码 ═══════════ */
async function loadPins() {
  const r = await api('admin/pins');
  if (!r.ok) return;
  const rows = r.rows || [];
  $('#pinRows').innerHTML = rows.length ? rows.map(p => `<tr>
    <td class="mono">${esc(p.pin)}</td>
    <td class="muted num">${ts(p.first_seen)}</td>
    <td class="muted num">${ts(p.last_seen)}</td>
    <td class="mono muted">${esc(p.ip || '—')}</td>
    <td class="num ${p.authorized_until > 0 ? 'state-1' : 'muted'}">${p.authorized_until ? ts(p.authorized_until) : '未授权'}</td>
    <td class="num muted">${p.redeem_count}</td>
    <td><button class="btn btn-sm btn-danger" data-pin="${esc(p.pin)}">解除授权</button></td>
  </tr>`).join('') : `<tr><td colspan="7" class="empty">暂无配对码</td></tr>`;

  $$('#pinRows [data-pin]').forEach(b => b.addEventListener('click', async () => {
    if (!confirm(`解除配对码 ${b.dataset.pin} 的授权？`)) return;
    const r2 = await api('admin/pins/revoke', { method: 'POST', body: { pin: b.dataset.pin } });
    if (!r2.ok) { toast('操作失败', true); return; }
    toast('已解除授权'); loadPins();
  }));
}

/* ═══════════ 公告 ═══════════ */
async function loadNotice() {
  const r = await api('admin/notice');
  if (!r.ok) return;
  const c = r.current || {};
  $('#n_title').value = c.title || '';
  $('#n_content').value = c.content || '';
  $('#n_now').textContent = c.content ? `当前生效内容更新于 ${ts(c.updated_at)}` : '当前没有下发公告';
}

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
  if (!confirm('确认清空当前公告？')) return;
  const r = await api('admin/notice/clear', { method: 'POST' });
  if (!r.ok) { toast('操作失败', true); return; }
  toast('公告已清空');
  loadNotice();
});

/* ═══════════ 版本管理 / 云端规则 ═══════════ */
function resetVerForm() {
  $('#v_id').value = '0';
  $('#v_platform').value = 'ios';
  $('#v_version').value = '';
  $('#v_build').value = '1';
  $('#v_min').value = '';
  $('#v_url').value = '';
  $('#v_notes').value = '';
  $('#v_force').checked = false;
  $('#v_active').checked = true;
  $('#v_err').textContent = '';
}

async function loadVersions() {
  const r = await api('admin/versions');
  if (!r.ok) return;
  const rows = r.rows || [];
  STATE.versions = rows;
  $('#verRows').innerHTML = rows.length ? rows.map(v => `<tr>
      <td>${v.platform === 'android' ? 'Android' : 'iOS'}</td>
      <td class="mono">${esc(v.version)}</td>
      <td class="muted num">${v.build}</td>
      <td class="${v.force_update == 1 ? 'state-2' : 'muted'}">${v.force_update == 1 ? '强制' : '可选'}</td>
      <td class="muted" style="max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${esc(v.url || '')}">${esc(v.url || '—')}</td>
      <td class="muted num">${ts(v.created_at)}</td>
      <td>
        <button class="btn btn-sm" data-ver-edit="${v.id}">编辑</button>
        <button class="btn btn-sm btn-danger" data-ver-del="${v.id}">删除</button>
      </td>
    </tr>`).join('') : `<tr><td colspan="7" class="empty">还没有发布过版本</td></tr>`;

  $$('#verRows [data-ver-edit]').forEach(b => b.addEventListener('click', () => {
    const v = (STATE.versions || []).find(x => String(x.id) === b.dataset.verEdit);
    if (!v) return;
    $('#v_id').value = v.id;
    $('#v_platform').value = v.platform;
    $('#v_version').value = v.version;
    $('#v_build').value = v.build;
    $('#v_min').value = v.min_version || '';
    $('#v_url').value = v.url || '';
    $('#v_notes').value = v.notes || '';
    $('#v_force').checked = v.force_update == 1;
    $('#v_active').checked = v.active == 1;
    toast('已载入，改完点保存');
  }));

  $$('#verRows [data-ver-del]').forEach(b => b.addEventListener('click', async () => {
    if (!confirm('删除这条版本记录？')) return;
    const r2 = await api('admin/versions/delete', { method: 'POST', body: { id: +b.dataset.verDel } });
    if (!r2.ok) { toast('删除失败', true); return; }
    toast('已删除'); loadVersions();
  }));
}

$('#verForm').addEventListener('submit', async (e) => {
  e.preventDefault();
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
  toast('已保存'); resetVerForm(); loadVersions();
});

$('#v_reset').addEventListener('click', resetVerForm);

async function loadRules() {
  const r = await api('admin/rules');
  if (!r.ok) return;
  const c = r.current;
  if (c) {
    $('#r_now').textContent = `当前版本 ${c.version} · ${c.ip_count} IP / ${c.domain_count} 域名 / ${c.port_count} 端口 · ${c.bytes} 字节 · ${ts(c.updated_at)}`;
    $('#r_version').value = c.version;
    $('#r_note').value = c.note || '';
    $('#r_content').value = r.content || '';
  } else {
    $('#r_now').textContent = '还没有下发任何规则，客户端会提示规则加载失败';
  }
}

/* ── 规则导入：任意格式 → 标准三段式 ── */
function applyImported(r, name) {
  $('#r_content').value = r.text || '';
  const d = new Date();
  const p2 = (x) => String(x).padStart(2, '0');
  $('#r_version').value = `${d.getFullYear()}.${p2(d.getMonth() + 1)}.${p2(d.getDate())}`;
  const parts = [];
  parts.push(`${r.ips} IP`);
  parts.push(`${r.domains} 域名`);
  if (r.direct) parts.push(`${r.direct} 放行`);
  parts.push(`${r.ports} 端口`);
  $('#r_note').value = (name ? `导入 ${name}：` : '导入：') + parts.join(' / ');
  $('#r_import').textContent =
    `已适配 ${r.ips} IP / ${r.domains} 域名 / ${r.ports} 端口` +
    (r.skipped ? ` · 跳过 ${r.skipped} 行` : '') +
    ` · 原文件 ${r.lines} 行 → ${(r.text || '').split('\n').length} 行，确认后点保存`;
}

async function importRulesText(text, name) {
  const r = await api('admin/rules/import', { method: 'POST', body: { content: text } });
  if (!r.ok) {
    $('#r_import').textContent = r.message || ('导入失败：' + (r.error || 'unknown'));
    toast(r.message || '导入失败', true);
    return false;
  }
  applyImported(r, name);
  toast(`已适配 ${r.ips} IP / ${r.domains} 域名 / ${r.ports} 端口，确认后点保存`);
  return true;
}

$('#r_pick').addEventListener('click', () => $('#r_file').click());

$('#r_file').addEventListener('change', async (e) => {
  const file = e.target.files && e.target.files[0];
  if (!file) return;
  const btn = $('#r_pick');
  const old = btn.textContent;
  btn.disabled = true;
  btn.textContent = '解析中…';
  try {
    const text = await file.text();
    await importRulesText(text, file.name);
  } catch (err) {
    toast('读文件失败', true);
  } finally {
    btn.disabled = false;
    btn.textContent = old;
    e.target.value = '';
  }
});

$('#r_fix').addEventListener('click', async () => {
  const text = $('#r_content').value;
  if (!text.trim()) { toast('先把规则内容粘进去', true); return; }
  await importRulesText(text, '');
});

$('#rulesForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const body = {
    version: $('#r_version').value.trim(),
    note: $('#r_note').value.trim(),
    content: $('#r_content').value,
  };
  if (!body.version) { $('#r_err').textContent = '请填写规则版本'; return; }
  if (body.content.trim().length < 20) { $('#r_err').textContent = '规则内容太短'; return; }
  $('#r_err').textContent = '';
  const r = await api('admin/rules/save', { method: 'POST', body });
  if (!r.ok) { $('#r_err').textContent = '保存失败：' + (r.error || 'unknown'); return; }
  toast(`已保存：${r.ip} IP / ${r.domain} 域名 / ${r.port} 端口`);
  loadRules();
});

/* ═══════════ 日志 ═══════════ */
$$('.tab').forEach(t => t.addEventListener('click', () => {
  STATE.tab = t.dataset.tab;
  $$('.tab').forEach(x => x.classList.toggle('active', x === t));
  loadLogs();
}));

async function loadLogs() {
  const r = await api('admin/logs');
  if (!r.ok) return;
  const isAudit = STATE.tab === 'audit';
  $('#logHead').innerHTML = isAudit
    ? '<tr><th style="width:150px">时间</th><th style="width:160px">动作</th><th style="width:160px">目标</th><th style="width:130px">IP</th><th>详情</th></tr>'
    : '<tr><th style="width:150px">时间</th><th style="width:150px">类型</th><th style="width:110px">配对码</th><th style="width:200px">卡密</th><th style="width:130px">IP</th><th>详情</th></tr>';
  const rows = isAudit ? (r.audit || []) : (r.events || []);
  $('#logRows').innerHTML = rows.length ? rows.map(x => isAudit
    ? `<tr><td class="muted num">${ts(x.ts)}</td><td>${esc(x.action)}</td><td class="mono muted">${esc(x.target || '—')}</td>
       <td class="mono muted">${esc(x.ip || '—')}</td><td class="muted">${esc(x.detail || '')}</td></tr>`
    : `<tr><td class="muted num">${ts(x.ts)}</td><td>${esc(x.kind)}</td><td class="mono">${esc(x.pin || '—')}</td>
       <td class="mono muted">${esc(x.code || '—')}</td><td class="mono muted">${esc(x.ip || '—')}</td>
       <td class="muted">${esc(x.detail || '')}</td></tr>`
  ).join('') : `<tr><td colspan="6" class="empty">暂无记录</td></tr>`;
}

/* ═══════════ 设置 ═══════════ */
async function loadSettings() {
  const r = await api('admin/settings');
  if (!r.ok) return;
  const s = r.settings || {};
  STATE.settings = s;
  $('#s_count').value = s.default_count;
  $('#s_days').value = s.default_days;
  $('#s_plan').value = s.default_plan;
  $('#s_charset').value = s.default_charset;
  $('#s_batch').value = s.batch_prefix;

  // 生成表单跟着默认值走
  $('#g_count').value = s.default_count;
  $('#g_charset').value = s.default_charset;
  $('#g_plan').value = s.default_plan;
  const d = +s.default_days;
  const key = Object.keys(DURATIONS).find(k => DURATIONS[k] === d);
  $('#g_type').value = key || 'custom';
  $('#g_daysField').hidden = !!key;
  if (!key) $('#g_days').value = d;
}

$('#s_save').addEventListener('click', async () => {
  $('#s_err').textContent = '';
  const r = await api('admin/settings/save', {
    method: 'POST',
    body: {
      default_count: +$('#s_count').value || 10,
      default_days: +$('#s_days').value || 30,
      default_plan: $('#s_plan').value,
      default_charset: $('#s_charset').value,
      batch_prefix: $('#s_batch').value,
    },
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

$$('[data-danger]').forEach(b => b.addEventListener('click', async () => {
  const action = b.dataset.danger;
  const label = action === 'clear_logs' ? '清空全部日志' : '清空所有未使用卡密';
  if (!confirm(`确认${label}？此操作不可撤销。`)) return;
  const r = await api('admin/danger', { method: 'POST', body: { action } });
  if (!r.ok) { toast('操作失败', true); return; }
  toast(`已清理 ${r.affected} 条`);
  if (action === 'clear_logs') loadLogs(); else loadCards();
}));

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
</script>
</body>
</html>
