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
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>卡密控制台</title>
<link rel="stylesheet" href="/assets/admin.css">
<style>
/* ── 卡密等级 ── */
.tier {
  display: inline-block; padding: 1px 7px; border-radius: var(--r-1);
  font-size: 11px; font-weight: 600; letter-spacing: .4px;
  border: 1px solid var(--c-line-2); color: var(--c-text-2); background: var(--c-bg-sunken);
  white-space: nowrap;
}
.tier-free { color: var(--c-text-3); }
.tier-beta { color: #1e40af; border-color: #bfdbfe; background: #eff6ff; }
.tier-pro  { color: #166534; border-color: #bbf7d0; background: #f0fdf4; }
.tier-max  { color: #92400e; border-color: #fde68a; background: #fffbeb; }

/* ── 卡密详情抽屉 ── */
.cd[hidden] { display: none; }
.cd { position: fixed; inset: 0; z-index: 60; }
.cd-mask { position: absolute; inset: 0; background: rgba(24, 24, 27, .32); }
.cd-panel {
  position: absolute; top: 0; right: 0; bottom: 0; width: min(520px, 100%);
  background: var(--c-bg); border-left: 1px solid var(--c-line);
  display: flex; flex-direction: column;
  box-shadow: -12px 0 32px rgba(24, 24, 27, .08);
}
.cd-head {
  display: flex; align-items: flex-start; justify-content: space-between; gap: var(--s-3);
  padding: var(--s-4) var(--s-5); border-bottom: 1px solid var(--c-line);
}
.cd-code { font-size: var(--f-4); font-weight: 600; letter-spacing: .4px; }
.cd-meta {
  margin-top: var(--s-2); display: flex; align-items: center; gap: var(--s-2);
  flex-wrap: wrap; font-size: var(--f-1); color: var(--c-text-3);
}
.cd-body { flex: 1; overflow: auto; padding: var(--s-4) var(--s-5) var(--s-7); -webkit-overflow-scrolling: touch; }
.cd-sec { margin-bottom: var(--s-5); }
.cd-sec > h4 {
  margin: 0 0 var(--s-2); font-size: var(--f-1); font-weight: 600;
  color: var(--c-text-3); text-transform: uppercase; letter-spacing: .6px;
}
.cd-kv { margin: 0; display: grid; grid-template-columns: 96px 1fr; gap: var(--s-2) var(--s-3); }
.cd-kv dt { color: var(--c-text-3); font-size: var(--f-2); }
.cd-kv dd { margin: 0; font-size: var(--f-2); color: var(--c-text); word-break: break-all; }
.cd-actions { display: flex; flex-wrap: wrap; gap: var(--s-2); margin-top: var(--s-3); align-items: center; }
.cd-events { margin: 0; padding: 0; list-style: none; }
.cd-events li {
  display: flex; gap: var(--s-3); padding: 6px 0;
  border-bottom: 1px solid var(--c-bg-sunken); font-size: var(--f-2);
}
.cd-events .t { color: var(--c-text-3); white-space: nowrap; font-variant-numeric: tabular-nums; }
@media (max-width: 720px) {
  .cd-panel { width: 100%; border-left: 0; }
  .cd-kv { grid-template-columns: 84px 1fr; }
  .cd-head, .cd-body { padding-left: var(--s-4); padding-right: var(--s-4); }
}
</style>

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
      <button class="nav-item" data-view="online" data-icon="grid">在线设备</button>
      <button class="nav-item" data-view="pins" data-icon="link">配对码</button>
      <button class="nav-item" data-view="notice" data-icon="message">公告</button>
      <button class="nav-item" data-view="versions" data-icon="cloud">版本与规则</button>
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
              <span class="label">卡密版本（决定能拿到哪套规则）</span>
              <select id="g_tier" class="select">
                <option value="free">FREE · 基础规则</option>
                <option value="beta">BETA · 测试通道</option>
                <option value="pro" selected>PRO · 正式版</option>
                <option value="max">MAX · 全量规则</option>
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
                <th style="width:86px">等级</th>
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

    <!-- 在线设备 -->
    <section class="page" id="view-online" hidden>
      <div class="page-head">
        <h2>在线设备</h2>
        <p>客户端心跳（150 秒内有心跳算在线），可强制下线并显示原因</p>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>强制下线</h3>
          <p>被下线的设备会立刻断开 VPN 并清空本地规则，直到这里点「解除」</p>
        </div>
        <form id="kickForm">
          <div style="display:grid;grid-template-columns:1fr 2fr auto;gap:12px;align-items:end">
            <label class="field">
              <span class="label">设备码 / 配对码</span>
              <input id="k_pin" class="input" placeholder="8 位数字" maxlength="8">
            </label>
            <label class="field">
              <span class="label">下线原因（客户端会显示）</span>
              <input id="k_reason" class="input" placeholder="例如：检测到多设备共享 / 违规使用">
            </label>
            <button type="submit" class="btn btn-primary">强制下线</button>
          </div>
        </form>
      </div>

      <div class="table-wrap">
        <table class="tbl">
          <thead>
            <tr>
              <th style="width:110px">配对码</th>
              <th style="width:80px">版本</th>
              <th style="width:120px">客户端</th>
              <th style="width:130px">IP</th>
              <th style="width:120px">最后心跳</th>
              <th style="width:110px">授权</th>
              <th>状态 / 原因</th>
              <th style="width:170px">操作</th>
            </tr>
          </thead>
          <tbody id="onlineRows"></tbody>
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
          <h3>下发状态</h3>
          <p>规则只存服务器，客户端凭有效卡密加密下载，解析后仅在内存中使用</p>
        </div>
        <div class="rows">
          <div class="row">
            <div class="row-label">
              <div class="t">当前下发</div>
              <div class="d" id="rs_now">还没有下发任何规则</div>
            </div>
            <div class="row-control" style="display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end">
              <button type="button" class="btn" id="rs_all_on">全部下发</button>
              <button type="button" class="btn" id="rs_all_off">全部停用</button>
              <button type="button" class="btn" id="rs_apply">重新应用</button>
            </div>
          </div>
        </div>
      </div>

      <div class="group">
        <div class="group-head">
          <h3>规则集</h3>
          <p>勾选哪几套就要下发哪几套，客户端拿到的就是勾选的合集</p>
        </div>
        <div class="table-wrap">
          <table class="tbl">
            <thead><tr>
              <th style="width:70px">下发</th>
              <th>规则集名称</th>
              <th style="width:130px">版本</th>
              <th style="width:150px">下发版本</th>
              <th style="width:200px">规则量</th>
              <th style="width:90px">大小</th>
              <th style="width:130px">更新时间</th>
              <th style="width:180px">操作</th>
            </tr></thead>
            <tbody id="rsRows"></tbody>
          </table>
        </div>
      </div>

      <div class="group">
        <div class="group-head">
          <h3 id="rs_form_title">新建规则集</h3>
          <p>导入 txt 或者直接把规则贴进来，填个名字就能存</p>
        </div>
        <form id="rsForm">
          <input type="hidden" id="rs_id" value="0">
          <div style="display:grid;grid-template-columns:2fr 1fr 2fr;gap:0 16px">
            <label class="field">
              <span class="label">规则集名称</span>
              <input id="rs_name" class="input" placeholder="例如：广告域名拦截">
            </label>
            <label class="field">
              <span class="label">版本（可留空）</span>
              <input id="rs_version" class="input" placeholder="留空自动生成">
            </label>
            <label class="field">
              <span class="label">说明</span>
              <input id="rs_note" class="input" placeholder="这套规则是干什么的">
            </label>
          </div>
          <label class="field">
            <span class="label">规则内容</span>
            <textarea id="rs_content" class="textarea"
              style="min-height:220px;font-family:ui-monospace,Menlo,monospace;font-size:12px"
              placeholder="#IP&#10;1.2.3.4&#10;#DOMAIN&#10;example.com&#10;#PORT&#10;80&#10;#DIRECT&#10;pass.example.com"></textarea>
          </label>
          <div class="rows">
            <div class="row">
              <div class="row-label"><div class="t">保存后参与下发</div><div class="d">勾上就立刻进下发合集，客户端马上拿到</div></div>
              <div class="row-control"><input type="checkbox" id="rs_enabled" checked></div>
            </div>
            <div class="row">
              <div class="row-label"><div class="t">下发给哪些版本</div><div class="d">不勾 = 全部版本都下发；FREE &lt; BETA &lt; PRO &lt; MAX，每张卡密只拿自己那层的规则</div></div>
              <div class="row-control" style="display:flex;gap:14px;flex-wrap:wrap">
                <label style="display:flex;gap:6px;align-items:center"><input type="checkbox" class="rs-tier" value="free">FREE</label>
                <label style="display:flex;gap:6px;align-items:center"><input type="checkbox" class="rs-tier" value="beta">BETA</label>
                <label style="display:flex;gap:6px;align-items:center"><input type="checkbox" class="rs-tier" value="pro">PRO</label>
                <label style="display:flex;gap:6px;align-items:center"><input type="checkbox" class="rs-tier" value="max">MAX</label>
              </div>
            </div>
          </div>
          <div class="err" id="rs_err"></div>
          <div style="margin-top:12px;display:flex;gap:8px;align-items:center;flex-wrap:wrap">
            <button type="submit" class="btn btn-primary" id="rs_save">保存规则集</button>
            <button type="button" class="btn" id="rs_import">导入 TXT</button>
            <input type="file" id="rs_file" accept=".txt,.csv,.list,text/plain" hidden>
            <button type="button" class="btn" id="rs_new">清空新建</button>
            <span class="muted" id="rs_hint" style="font-size:12px;line-height:1.5">
              支持 .txt / .csv，单套最大 2MB；没分节的清单会自动归类。可写 #IP / #DOMAIN / #PORT / #DIRECT（放行），放行优先于拦截
            </span>
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


<!-- ══════════════ 卡密详情 ══════════════ -->
<div class="cd" id="cd" hidden>
  <div class="cd-mask" data-cd-close></div>
  <section class="cd-panel" role="dialog" aria-modal="true" aria-label="卡密详情">
    <header class="cd-head">
      <div>
        <div class="cd-code mono" id="cdCode">—</div>
        <div class="cd-meta" id="cdMeta">—</div>
      </div>
      <button class="btn-text" data-cd-close>关闭</button>
    </header>
    <div class="cd-body" id="cdBody"></div>
  </section>
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

async function refreshCsrf() {
  try {
    const r = await fetch('/api/admin/csrf', { credentials: 'same-origin' });
    if (!r.ok) return false;
    const j = await r.json();
    if (j && j.ok && j.csrf) { CSRF = j.csrf; return true; }
  } catch (e) {}
  return false;
}

async function api(path, opt = {}, _retried = false) {
  const isForm = (typeof FormData !== 'undefined') && (opt.body instanceof FormData);
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
    res = await fetch('/api/' + path, {
      method: opt.method || 'GET',
      headers,
      credentials: 'same-origin',
      body,
    });
  } catch (e) {
    return { ok: false, error: 'network' };
  }
  if (res.status === 419 && !_retried && path !== 'admin/csrf') {
    if (await refreshCsrf()) return api(path, opt, true);
  }
  if (res.status === 401) { showAuth(); return { ok: false, error: 'unauthenticated' }; }
  try { return await res.json(); } catch (e) { return { ok: false, error: 'bad_response' }; }
}

const ts = (n) => {
  /* 服务端 SQLite 出来的整数是字符串（"0"），这里一并按无效处理，别显示成 1970 年 */
  if (!n || +n <= 0) return '—';
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
    // 先清掉已有图标，避免重复调用时图标叠加
    el.querySelectorAll('svg').forEach(s => s.remove());
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
  ['overview', 'cards', 'online', 'pins', 'notice', 'versions', 'logs', 'settings'].forEach(k => {
    $('#view-' + k).hidden = (k !== v);
  });
  if (v === 'overview') loadOverview();
  if (v === 'online') loadOnline();
  if (v === 'cards') loadCards();
  if (v === 'pins') loadPins();
  if (v === 'notice') loadNotice();
  if (v === 'versions') { loadVersions(); loadRuleSets(); }
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
      tier: $('#g_tier').value,
    },
  });
  btn.disabled = false;
  if (!r.ok) { $('#genErr').textContent = '生成失败'; return; }
  $('#genOut').hidden = false;
  $('#genSummary').textContent = `已生成 ${r.created} 张 · ${days} 天 · ${String(r.tier || '').toUpperCase()} · 批次 ${batch}`;
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
    const tip = [c.bound_pin ? '绑定 ' + c.bound_pin : '', c.note || ''] .filter(Boolean).join(' · ');
    const tier = String(c.tier || 'pro').toUpperCase();
    const ban = (c.status === 2 && c.ban_reason)
      ? `<div class="muted" style="font-size:12px;margin-top:3px;color:#c0392b">封禁：${esc(c.ban_reason)}</div>` : '';
    return `<tr>
      <td class="col-check"><input type="checkbox" data-id="${c.id}"></td>
      <td class="mono" title="${esc(tip)}">${esc(c.code)}${ban}</td>
      <td class="muted">${esc(c.batch || '—')}</td>
      <td class="muted">${dur(c.duration_sec)}</td>
      <td class="${s[1]}">${s[0]}</td>
      <td>${tierBadge(c.tier)}</td>
      <td class="muted num">${c.expire_at ? ts(c.expire_at) : '—'}</td>
      <td>
        <button class="btn btn-sm" data-act="detail" data-id="${c.id}">详情</button>
        <button class="btn btn-sm" data-act="extend" data-id="${c.id}">延期</button>
        <button class="btn btn-sm" data-act="toggle" data-id="${c.id}" data-status="${c.status}">${c.status === 2 ? '解封' : '作废'}</button>
        ${c.bound_pin ? `<button class="btn btn-sm" data-act="unbind" data-id="${c.id}">解绑</button>` : ''}
        <button class="btn btn-sm btn-danger" data-act="delete" data-id="${c.id}">删除</button>
      </td>
    </tr>`;
  }).join('') : `<tr><td colspan="8" class="empty">没有符合条件的数据</td></tr>`;

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
  if (act === 'detail') { openCardDetail(id); return; }
  if (act === 'extend') {
    const d = prompt('延期天数（负数表示缩短）', '7');
    if (d === null || d === '' || isNaN(+d)) return;
    const r = await api('admin/cards/extend', { method: 'POST', body: { id, days: +d } });
    if (!r.ok) { toast('操作失败', true); return; }
    toast('已调整有效期'); loadCards(); return;
  }
  if (act === 'toggle') {
    const to = +btn.dataset.status === 2 ? 0 : 2;
    let reason = '';
    if (to === 2) {
      reason = prompt('封禁原因（会显示在后台，并下发到客户端提示用户）', '违规使用') ;
      if (reason === null) return;
      if (!reason.trim()) reason = '管理员封禁';
    }
    const r = await api('admin/cards/status', { method: 'POST', body: { id, status: to, reason } });
    if (!r.ok) { toast('操作失败', true); return; }
    toast(to === 2 ? '已封禁' : '已解封'); loadCards(); return;
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
  if (action === 'ban') {
    const reason = prompt('批量封禁原因（会显示在后台并下发到客户端）', '违规使用');
    if (reason === null) return;
    body.reason = reason.trim() || '管理员封禁';
  }
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

/* ═══════════ 在线设备 ═══════════ */
async function loadOnline() {
  const r = await api('admin/online');
  if (!r.ok) return;
  const rows = r.rows || [];
  $('#onlineRows').innerHTML = rows.length ? rows.map(o => {
    const dead = o.kicked;
    const state = dead
      ? `<span style="color:#c0392b">已下线：${esc(o.kick_reason || '管理员操作')}</span>`
      : (o.authorized ? '<span class="state-1">在线</span>' : '<span class="muted">在线但未授权</span>');
    return `<tr>
      <td class="mono">${esc(o.pin)}</td>
      <td class="mono">${esc(o.tier_label || '—')}</td>
      <td class="muted">${esc(o.app_ver || '—')}</td>
      <td class="mono muted">${esc(o.ip || '—')}</td>
      <td class="muted num">${o.online_s < 60 ? o.online_s + ' 秒前' : Math.floor(o.online_s / 60) + ' 分钟前'}</td>
      <td class="num ${o.authorized ? 'state-1' : 'muted'}">${o.authorized ? '有效' : '—'}</td>
      <td>${state}${o.code ? `<div class="muted" style="font-size:12px;margin-top:2px">卡密 ${esc(o.code)}</div>` : ''}</td>
      <td>
        ${dead
          ? `<button class="btn btn-sm" data-unkick="${esc(o.pin)}">解除下线</button>`
          : `<button class="btn btn-sm btn-danger" data-kick="${esc(o.pin)}">强制下线</button>`}
      </td>
    </tr>`;
  }).join('') : `<tr><td colspan="8" class="empty">现在没有在线设备</td></tr>`;

  $$('#onlineRows [data-kick]').forEach(b => b.addEventListener('click', async () => {
    const pin = b.dataset.kick;
    const reason = prompt(`让设备 ${pin} 强制下线，原因（客户端会显示）：`, '检测到多设备共享');
    if (reason === null) return;
    const r2 = await api('admin/kick', { method: 'POST', body: { pin, reason: reason.trim() } });
    if (!r2.ok) { toast('操作失败：' + (r2.error || 'unknown'), true); return; }
    toast('已下发下线指令，客户端下次心跳（1 分钟内）生效');
    loadOnline();
  }));

  $$('#onlineRows [data-unkick]').forEach(b => b.addEventListener('click', async () => {
    const pin = b.dataset.unkick;
    const r2 = await api('admin/unkick', { method: 'POST', body: { pin } });
    if (!r2.ok) { toast('操作失败', true); return; }
    toast('已解除，设备可以重新连接');
    loadOnline();
  }));
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

/* ---- 规则集：可以存多套，勾选哪几套就下发哪几套 ---- */
let RULE_SETS = [];

const rsBytes = (n) => {
  n = +n || 0;
  if (n < 1024) return n + ' B';
  if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
  return (n / 1048576).toFixed(2) + ' MB';
};
const rsCount = (v) => `${v.ip_count} IP / ${v.domain_count} 域名 / ${v.port_count} 端口`;

function rsReset() {
  $('#rs_id').value = '0';
  $('#rs_name').value = '';
  $('#rs_version').value = '';
  $('#rs_note').value = '';
  $('#rs_content').value = '';
  $('#rs_enabled').checked = true;
  $$('.rs-tier').forEach(cb => { cb.checked = false; });
  $('#rs_err').textContent = '';
  $('#rs_hint').textContent = '支持 .txt / .csv，单套最大 2MB；没分节的清单会自动归类。可写 #IP / #DOMAIN / #PORT / #DIRECT（放行），放行优先于拦截';
  $('#rs_form_title').textContent = '新建规则集';
  $('#rs_save').textContent = '保存规则集';
}

async function loadRuleSets() {
  const r = await api('admin/rulesets');
  if (!r.ok) return;
  RULE_SETS = r.rows || [];
  const s = r.summary || {};
  const p = s.pack;

  if (p) {
    const names = (s.sets && s.sets.length) ? s.sets.join(' · ') : '未命名';
    $('#rs_now').textContent = `下发 ${s.set_count || 0} 套（${names}）· 版本 ${p.version} · ${p.ip_count} IP / ${p.domain_count} 域名 / ${p.port_count} 端口 · ${rsBytes(p.bytes)} · ${ts(p.updated_at)}`;
  } else if ((s.total || 0) > 0) {
    $('#rs_now').textContent = '当前一套都没勾，客户端会提示规则加载失败';
  } else {
    $('#rs_now').textContent = '还没有规则集，在下面新建一套就能下发';
  }

  $('#rsRows').innerHTML = RULE_SETS.length ? RULE_SETS.map(x => `<tr>
      <td><input type="checkbox" data-rs-toggle="${x.id}" ${x.enabled == 1 ? 'checked' : ''}></td>
      <td>${esc(x.name)}${x.note ? `<div class="muted" style="font-size:12px;margin-top:2px">${esc(x.note)}</div>` : ''}</td>
      <td class="mono muted">${esc(x.version || '—')}</td>
      <td class="mono muted">${(x.tiers || '').trim() ? esc(String(x.tiers).toUpperCase().replace(/,/g, ' / ')) : '全部'}</td>
      <td class="muted num">${rsCount(x)}</td>
      <td class="muted num">${rsBytes(x.bytes)}</td>
      <td class="muted num">${ts(x.updated_at)}</td>
      <td>
        <button class="btn btn-sm" data-rs-up="${x.id}" title="上移">↑</button>
        <button class="btn btn-sm" data-rs-down="${x.id}" title="下移">↓</button>
        <button class="btn btn-sm" data-rs-edit="${x.id}">编辑</button>
        <button class="btn btn-sm btn-danger" data-rs-del="${x.id}">删除</button>
      </td>
    </tr>`).join('') : `<tr><td colspan="8" class="empty">还没有规则集</td></tr>`;

  /* 勾选 = 这套参与下发，改完立刻重算快照 */
  $$('#rsRows [data-rs-toggle]').forEach(cb => cb.addEventListener('change', async () => {
    const id = +cb.dataset.rsToggle;
    const on = cb.checked;
    cb.disabled = true;
    const r2 = await api('admin/rulesets/toggle', { method: 'POST', body: { id, enabled: on } });
    cb.disabled = false;
    if (!r2.ok) {
      cb.checked = !on;
      toast('设置失败：' + (r2.error || 'unknown'), true);
      return;
    }
    const a = r2.applied || {};
    if (a.ok) toast(`${on ? '已加入' : '已移出'}下发 · 现在共 ${a.set_count} 套`);
    else toast(on ? '已加入下发' : '已移出下发（现在一套都没有，不下发）', !on);
    loadRuleSets();
  }));

  $$('#rsRows [data-rs-edit]').forEach(b => b.addEventListener('click', async () => {
    const r2 = await api('admin/rulesets/get', { method: 'POST', body: { id: +b.dataset.rsEdit } });
    if (!r2.ok || !r2.row) { toast('读取失败', true); return; }
    const v = r2.row;
    $('#rs_id').value = v.id;
    $('#rs_name').value = v.name || '';
    $('#rs_version').value = v.version || '';
    $('#rs_note').value = v.note || '';
    $('#rs_content').value = v.content || '';
    $('#rs_enabled').checked = v.enabled == 1;
    const vt = String(v.tiers || '').split(',').map(x => x.trim()).filter(Boolean);
    $$('.rs-tier').forEach(cb => { cb.checked = vt.length === 0 || vt.includes(cb.value); });
    $('#rs_err').textContent = '';
    $('#rs_hint').textContent = `正在编辑「${v.name}」· ${rsCount(v)}`;
    $('#rs_form_title').textContent = '编辑规则集';
    $('#rs_save').textContent = '保存修改';
    $('#rs_content').scrollIntoView({ behavior: 'smooth', block: 'center' });
    toast('已载入，改完点保存');
  }));

  const moveSet = async (id, dir) => {
    const r2 = await api('admin/rulesets/sort', { method: 'POST', body: { id, dir } });
    if (!r2.ok) { toast('调整失败：' + (r2.error || 'unknown'), true); return; }
    if (r2.moved === false) { toast(dir === 'up' ? '已经在最前面了' : '已经在最后面了'); return; }
    toast(`顺序已调整 · 第 ${r2.position} 套`);
    loadRuleSets();
  };

  $$('#rsRows [data-rs-up]').forEach(b => b.addEventListener('click', () => moveSet(+b.dataset.rsUp, 'up')));
  $$('#rsRows [data-rs-down]').forEach(b => b.addEventListener('click', () => moveSet(+b.dataset.rsDown, 'down')));

  $$('#rsRows [data-rs-del]').forEach(b => b.addEventListener('click', async () => {
    const v = RULE_SETS.find(x => String(x.id) === b.dataset.rsDel);
    if (!confirm(`删除规则集「${v ? v.name : b.dataset.rsDel}」？删了就找不回来`)) return;
    const r2 = await api('admin/rulesets/delete', { method: 'POST', body: { id: +b.dataset.rsDel } });
    if (!r2.ok) { toast('删除失败：' + (r2.error || 'unknown'), true); return; }
    toast('已删除');
    loadRuleSets();
  }));
}

$('#rsForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const body = {
    id: +$('#rs_id').value || 0,
    name: $('#rs_name').value.trim(),
    version: $('#rs_version').value.trim(),
    note: $('#rs_note').value.trim(),
    content: $('#rs_content').value,
    enabled: $('#rs_enabled').checked,
    tiers: $$('.rs-tier').filter(cb => cb.checked).map(cb => cb.value).join(','),
  };
  if (!body.name) { $('#rs_err').textContent = '请填写规则集名称'; return; }
  if (body.content.trim().length < 20) { $('#rs_err').textContent = '规则内容太短'; return; }
  $('#rs_err').textContent = '';
  $('#rs_save').disabled = true;
  const r = await api('admin/rulesets/save', { method: 'POST', body });
  $('#rs_save').disabled = false;

  if (!r.ok) {
    const map = {
      bad_name: '名称不合法',
      name_too_long: '名称太长（最多 60 字）',
      name_exists: '已经有同名规则集',
      empty_rules: '规则内容太短',
      too_large: '单套超过 2MB，请拆分',
      too_many_sets: '规则集数量已达上限 50 套',
      bad_version: '版本号太长（最多 32 字符）',
      server_error: '服务器开小差了',
    };
    $('#rs_err').textContent = '保存失败：' + (map[r.error] || r.error || 'unknown');
    return;
  }

  let msg = `${r.replaced ? '已覆盖同名规则集' : '已保存'}：${r.name} · ${r.ip} IP / ${r.domain} 域名 / ${r.port} 端口`;
  const a = r.applied;
  if (a && a.ok) msg += ` · 已下发 ${a.set_count} 套`;
  else if (a && a.error === 'no_enabled_sets') msg += ' · 当前没有启用规则，不下发';
  toast(msg);
  rsReset();
  loadRuleSets();
});

$('#rs_new').addEventListener('click', rsReset);

$('#rs_all_on').addEventListener('click', async () => {
  const ids = RULE_SETS.map(x => +x.id);
  if (!ids.length) { toast('还没有规则集', true); return; }
  const r = await api('admin/rulesets/toggle', { method: 'POST', body: { ids } });
  if (!r.ok) { toast('操作失败：' + (r.error || 'unknown'), true); return; }
  toast(`已全部纳入下发 · 共 ${r.applied && r.applied.set_count ? r.applied.set_count : ids.length} 套`);
  loadRuleSets();
});

$('#rs_all_off').addEventListener('click', async () => {
  if (!confirm('停用全部规则集？客户端将拿不到任何规则')) return;
  const r = await api('admin/rulesets/toggle', { method: 'POST', body: { ids: [] } });
  if (!r.ok) { toast('操作失败：' + (r.error || 'unknown'), true); return; }
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
  toast(`已应用：${r.set_count} 套 · ${rsBytes(r.bytes)}`);
  loadRuleSets();
});

/* ---- 规则集：从 TXT / CSV 导入到编辑框 ---- */
$('#rs_import').addEventListener('click', () => $('#rs_file').click());

$('#rs_file').addEventListener('change', async () => {
  const f = $('#rs_file').files && $('#rs_file').files[0];
  if (!f) return;
  const hint = $('#rs_hint');
  if (f.size > 2 * 1024 * 1024) {
    hint.textContent = '文件超过 2MB，请拆分后再导入';
    toast('文件太大', true);
    $('#rs_file').value = '';
    return;
  }
  hint.textContent = '正在读取…';
  const fd = new FormData();
  fd.append('file', f);
  const r = await api('admin/rules/import', { method: 'POST', body: fd });
  $('#rs_file').value = '';
  if (!r.ok) {
    hint.textContent = '读取失败，换一个 txt 再试';
    toast('导入失败：' + (r.error || 'unknown'), true);
    return;
  }
  $('#rs_content').value = r.content || '';
  /* 没填名字就拿文件名兜底，省得每次都要打一遍 */
  if (!$('#rs_name').value.trim()) {
    $('#rs_name').value = f.name.replace(/\.[^.]+$/, '').slice(0, 60);
  }
  const auto = r.auto_grouped ? '（已自动按类型归类）' : '';
  hint.textContent = `已载入 ${f.name} · ${r.bytes} 字节 · IP ${r.ip} / 域名 ${r.domain} / 端口 ${r.port}${auto}`;
  if ((r.ip + r.domain + r.port) === 0) {
    hint.textContent += ' · 没识别到规则，检查一下文件内容';
    toast('没识别到规则', true);
  } else {
    toast('已载入，确认名称后点保存');
  }
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


/* ═══════════ 卡密详情 ═══════════ */
const TIER_LABEL = { free: 'FREE', beta: 'BETA', pro: 'PRO', max: 'MAX' };

function tierBadge(t) {
  let k = String(t || 'pro').toLowerCase();
  if (!TIER_LABEL[k]) k = 'pro';
  return `<span class="tier tier-${k}">${TIER_LABEL[k]}</span>`;
}

function remainText(sec) {
  sec = Math.max(0, +sec || 0);
  if (!sec) return '—';
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d} 天 ${h} 小时`;
  if (h > 0) return `${h} 小时 ${m} 分`;
  return `${m} 分钟`;
}

let CD_ID = 0;

async function openCardDetail(id) {
  const r = await api('admin/cards/detail?id=' + id);
  if (!r.ok || !r.card) { toast('读取详情失败', true); return; }
  CD_ID = id;
  renderCardDetail(r.card);
  $('#cd').hidden = false;
  document.body.style.overflow = 'hidden';
}

function closeCardDetail() {
  $('#cd').hidden = true;
  document.body.style.overflow = '';
  CD_ID = 0;
}

const cdKv = (k, v) => `<dt>${k}</dt><dd>${v}</dd>`;

function renderCardDetail(c) {
  const ST = { 0: ['未使用', 'state-0'], 1: ['已兑换', 'state-1'], 2: ['已作废', 'state-2'] };
  const st = ST[c.status] || ['未知', ''];
  const p = c.pin_info || null;

  $('#cdCode').textContent = c.code;
  $('#cdMeta').innerHTML = `${tierBadge(c.tier)}<span class="${st[1]}">${st[0]}</span>` +
    (c.batch ? `<span>批次 ${esc(c.batch)}</span>` : '<span>无批次</span>');

  let html = '';

  /* 授权 */
  html += `<div class="cd-sec"><h4>授权</h4><dl class="cd-kv">
    ${cdKv('等级', tierBadge(c.tier))}
    ${cdKv('状态', `<span class="${st[1]}">${st[0]}</span>`)}
    ${cdKv('时长', dur(c.duration_sec))}
    ${cdKv('到期时间', c.expire_at
        ? `${ts(c.expire_at)}（${c.seconds_left > 0 ? '剩 ' + remainText(c.seconds_left) : '已到期'}）`
        : '—')}
    ${cdKv('兑换时间', c.redeemed_at ? ts(c.redeemed_at) : '未兑换')}
    ${cdKv('创建时间', c.created_at ? ts(c.created_at) : '—')}
    ${cdKv('备注', c.note ? esc(c.note) : '—')}
  </dl>
  <div class="cd-actions">
    <select class="select sm" id="cdTier" style="width:118px">
      ${['free', 'beta', 'pro', 'max'].map(t =>
        `<option value="${t}"${t === c.tier ? ' selected' : ''}>${TIER_LABEL[t]}</option>`).join('')}
    </select>
    <button class="btn btn-sm" id="cdTierSave">改等级</button>
  </div></div>`;

  /* 绑定设备 */
  if (p) {
    html += `<div class="cd-sec"><h4>绑定设备</h4><dl class="cd-kv">
      ${cdKv('配对码', `<span class="mono">${esc(p.pin)}</span>`)}
      ${cdKv('在线', p.online ? '<span class="state-1">在线</span>' : '<span class="muted">离线</span>')}
      ${cdKv('最近心跳', p.last_beat ? ts(p.last_beat) : '—')}
      ${cdKv('客户端', p.app_ver ? esc(p.app_ver) : '—')}
      ${cdKv('IP', esc(p.ip || c.bound_ip || '—'))}
      ${cdKv('授权窗口', p.authorized_until
          ? `${ts(p.authorized_until)}（${p.authorized ? '有效' : '已过期'}）` : '—')}
      ${cdKv('设备指纹', c.bound_dev
          ? `<span class="mono">${esc(String(c.bound_dev).slice(0, 20))}${String(c.bound_dev).length > 20 ? '…' : ''}</span>`
          : '—')}
      ${cdKv('兑换次数', String(p.redeem_count == null ? 0 : p.redeem_count))}
      ${cdKv('强制下线', p.kicked ? `<span class="state-2">${esc(p.kick_reason || '已下线')}</span>` : '否')}
    </dl></div>`;
  } else {
    html += `<div class="cd-sec"><h4>绑定设备</h4><dl class="cd-kv">
      ${cdKv('状态', c.bound_pin ? `<span class="mono">${esc(c.bound_pin)}</span>` : '未绑定任何设备')}
      ${c.bound_ip ? cdKv('IP', esc(c.bound_ip)) : ''}
    </dl></div>`;
  }

  /* 封禁 */
  if (c.status === 2 || c.ban_reason) {
    html += `<div class="cd-sec"><h4>封禁</h4><dl class="cd-kv">
      ${cdKv('原因', `<span class="state-2">${esc(c.ban_reason || '—')}</span>`)}
      ${cdKv('时间', c.banned_at ? ts(c.banned_at) : '—')}
    </dl></div>`;
  }

  /* 历史设备 */
  if ((c.devices || []).length > 1) {
    html += `<div class="cd-sec"><h4>历史设备（${c.devices.length}）</h4><dl class="cd-kv">` +
      c.devices.map(d => cdKv(`<span class="mono">${esc(d.pin)}</span>`, `${d.c} 次 · ${ts(d.last_ts)}`)).join('') +
      `</dl></div>`;
  }

  /* 事件 */
  if ((c.events || []).length) {
    html += `<div class="cd-sec"><h4>最近事件</h4><ul class="cd-events">` +
      c.events.map(e => `<li><span class="t">${ts(e.ts)}</span>` +
        `<span>${esc(e.kind)}${e.detail ? ' · ' + esc(e.detail) : ''}</span></li>`).join('') +
      `</ul></div>`;
  }

  /* 操作 */
  html += `<div class="cd-sec"><h4>操作</h4><div class="cd-actions">
    <button class="btn btn-sm" data-cd-act="extend" data-days="7">延期 7 天</button>
    <button class="btn btn-sm" data-cd-act="extend" data-days="-7">缩短 7 天</button>
    <button class="btn btn-sm" data-cd-act="toggle">${c.status === 2 ? '解封' : '封禁'}</button>
    ${p ? '<button class="btn btn-sm" data-cd-act="unbind">解绑设备</button>' : ''}
    <button class="btn btn-sm btn-danger" data-cd-act="delete">删除</button>
  </div>
  <div class="hint">改等级后客户端下次拉规则即按新等级下发；想让在线设备立刻刷新，到「在线设备」页强制下线再解除。</div>
  </div>`;

  $('#cdBody').innerHTML = html;

  $('#cdTierSave').addEventListener('click', async () => {
    const tier = $('#cdTier').value;
    if (tier === c.tier) { toast('等级没变'); return; }
    const r = await api('admin/cards/tier', { method: 'POST', body: { id: c.id, tier } });
    if (!r.ok) { toast('改等级失败', true); return; }
    toast('等级已改为 ' + (r.tier_label || tier.toUpperCase()));
    loadCards();
    openCardDetail(c.id);
  });

  $$('#cdBody [data-cd-act]').forEach(b => b.addEventListener('click', () => cdAction(b, c)));
}

async function cdAction(btn, c) {
  const act = btn.dataset.cdAct;

  if (act === 'extend') {
    const days = +btn.dataset.days;
    const r = await api('admin/cards/extend', { method: 'POST', body: { id: c.id, days } });
    if (!r.ok) { toast('操作失败', true); return; }
    toast(`已${days > 0 ? '延长' : '缩短'} ${Math.abs(days)} 天`);
    loadCards(); openCardDetail(c.id); return;
  }

  if (act === 'toggle') {
    const to = c.status === 2 ? 0 : 2;
    let reason = '';
    if (to === 2) {
      reason = prompt('封禁原因（后台显示，也会下发到客户端提示用户）', '违规使用');
      if (reason === null) return;
      if (!reason.trim()) reason = '管理员封禁';
    }
    const r = await api('admin/cards/status', { method: 'POST', body: { id: c.id, status: to, reason } });
    if (!r.ok) { toast('操作失败', true); return; }
    toast(to === 2 ? '已封禁' : '已解封');
    loadCards(); openCardDetail(c.id); return;
  }

  if (act === 'unbind') {
    if (!confirm('解绑后这张卡密可以在别的设备上继续使用（剩余时长不变），确认？')) return;
    const r = await api('admin/cards/unbind', { method: 'POST', body: { id: c.id } });
    if (!r.ok) { toast('解绑失败', true); return; }
    toast('已解绑'); loadCards(); openCardDetail(c.id); return;
  }

  if (act === 'delete') {
    if (!confirm('删除后不可恢复，确认删除这张卡密？')) return;
    const r = await api('admin/cards/delete', { method: 'POST', body: { id: c.id } });
    if (!r.ok) { toast('删除失败', true); return; }
    toast('已删除'); closeCardDetail(); loadCards();
  }
}

$$('[data-cd-close]').forEach(el => el.addEventListener('click', closeCardDetail));
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !$('#cd').hidden) closeCardDetail();
});

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
