<?php
declare(strict_types=1);

require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/Services/PinService.php';
require __DIR__ . '/../app/Services/SessionService.php';
require __DIR__ . '/../app/Services/CardService.php';
require __DIR__ . '/../app/Services/RulesService.php';
require __DIR__ . '/../app/Services/VersionService.php';
require __DIR__ . '/../app/Services/AdminService.php';
require __DIR__ . '/../app/Services/NoticeService.php';
require __DIR__ . '/../app/Services/CryptoService.php';
require __DIR__ . '/../app/Services/SettingsService.php';

$path   = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$path   = str_replace('/api/', '', $path);
$path   = trim($path, '/');
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$ip     = Http::ip();
$ua     = Http::ua();

header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');

try {
    switch ($path . '|' . $method) {

        // ---------- 客户端：配对码状态轮询（每 3 秒一次） ----------
        case 'pin/status|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) ($_GET['pin'] ?? ''));
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('pin:' . $pin, (int) Config::get('rate_pin'))) {
                Http::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $st = PinService::status($pin);
            Http::json(['ok' => true] + $st);
        }

        // ---------- 客户端：心跳登记 ----------
        case 'pin/beat|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            PinService::touch($pin, $ip, $ua);
            Http::json(['ok' => true] + PinService::status($pin));
        }

        // ---------- 网页：配对码 + 卡密兑换 ----------
        case 'card/redeem|POST': {
            if (!RateLimit::hit('ip:' . $ip, 10) || !RateLimit::hit('rdm:' . $ip, 10)) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = (string) ($b['code'] ?? '');
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rdp:' . $pin, 6)) {
                Http::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $r = CardService::redeem($pin, $code, $ip, $ua);
            if (!$r['ok']) {
                Http::json(['ok' => false, 'error' => $r['error']], 200);
            }
            /* 同时返回窗口（expire_at，兼容旧客户端）与卡密真实到期（card_expire_at） */
            Http::json($r);
        }

        // ---------- 客户端：续期（只推窗口，不产生兑换记录） ----------
        case 'session/renew|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = (string) ($b['code'] ?? '');
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rn:' . $pin, 30)) {
                Http::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $r = SessionService::renew($pin, $code, $ip, $ua);
            if (!$r['ok']) {
                Http::json(['ok' => false, 'error' => $r['error']], 200);
            }
            Http::json($r);
        }

        // ---------- 客户端：只读状态（不改计数） ----------
        case 'session/state|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) ($_GET['pin'] ?? ''));
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            Http::json(SessionService::state($pin));
        }

        // ---------- 客户端：云端规则库（必须有效卡密） ----------
        case 'rules/manifest|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = (string) ($b['code'] ?? '');
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rm:' . $pin, 30)) {
                Http::abort(429, 'rate_limited');
            }
            PinService::touch($pin, $ip, $ua);
            $s = SessionService::renew($pin, $code, $ip, $ua);
            if (!$s['ok']) {
                Http::json(['ok' => false, 'error' => $s['error']], 403);
            }
            Http::json(RulesService::manifest());
        }

        case 'rules/download|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            $code = CardService::normalise((string) ($b['code'] ?? ''));
            if (!PinService::valid($pin)) {
                Http::abort(400, 'bad_pin');
            }
            if (!RateLimit::hit('rd:' . $pin, 20)) {
                Http::abort(429, 'rate_limited');
            }
            $s = SessionService::renew($pin, $code, $ip, $ua);
            if (!$s['ok']) {
                Http::json(['ok' => false, 'error' => $s['error']], 403);
            }
            $pack = RulesService::current();
            if (!$pack) {
                Http::json(['ok' => false, 'error' => 'no_rules'], 404);
            }
            $want = (string) ($b['version'] ?? '');
            if ($want !== '' && $want !== (string) $pack['version']) {
                Http::json(['ok' => false, 'error' => 'version_mismatch',
                            'version' => $pack['version']], 409);
            }
            [$bucket] = RulesService::bucket();
            $key = RulesService::deriveKey($pin, $code, $bucket, (string) $pack['version']);
            $blob = RulesService::encrypt(RulesService::content((int) $pack['id']), $key);

            header('Content-Type: application/octet-stream');
            header('Content-Length: ' . strlen($blob));
            header('X-Rules-Version: ' . $pack['version']);
            header('X-Rules-Sha256: ' . $pack['sha256']);
            header('X-Rules-Bucket: ' . $bucket);
            header('Cache-Control: no-store');
            echo $blob;
            exit;
        }

        // ---------- 客户端：版本检测 ----------
        case 'app/version|GET': {
            if (!RateLimit::hit('ver:' . $ip, 120)) {
                Http::abort(429, 'rate_limited');
            }
            Http::json(VersionService::check(
                (string) ($_GET['platform'] ?? 'ios'),
                (string) ($_GET['current'] ?? '')
            ));
        }

        // ---------- 客户端：公告/授权状态（复用脚本自带 HTTP 拉取通道） ----------
        case 'notice|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) ($_GET['pin'] ?? ''));
            $ann = NoticeService::currentText();

            /* 不带 pin：纯公告模式（无卡密版客户端走这条） */
            if (!PinService::valid($pin)) {
                $text = $ann !== '' ? $ann : '欢迎使用 God 全系统';
                /* msg 与 notice 都放公告正文：客户端取任一字段都能显示 */
                Http::json(['code' => 200, 'msg' => $text, 'notice' => $text,
                            'announcement' => $ann]);
            }
            PinService::touch($pin, $ip, $ua);
            $st = PinService::status($pin);
            $ann = NoticeService::currentText();

            if (!$st['authorized']) {
                /* 未授权：notice 返回布尔 false —— 客户端据此不构建菜单 */
                Http::json(['code' => 200, 'msg' => 'ok', 'notice' => false,
                            'announcement' => $ann, 'authorized' => false]);
            }
            $text = '到期时间：' . date('Y-m-d H:i:s', $st['expire_at']);
            if ($ann !== '') {
                $text = $ann . ' ｜ ' . $text;
            }
            Http::json(['code' => 200, 'msg' => 'ok', 'notice' => $text,
                        'announcement' => $ann, 'authorized' => true]);
        }

        // ---------- 公开：当前公告（用户页顶部展示） ----------
        case 'announcement|GET': {
            $c = NoticeService::current();
            Http::json(['ok' => true, 'title' => $c['title'], 'content' => $c['content'],
                        'updated_at' => $c['updated_at']]);
        }

        // ---------- 后台：公告管理 ----------
        case 'admin/notice|GET': {
            AdminService::require();
            Http::json(['ok' => true, 'current' => NoticeService::current(),
                        'history' => NoticeService::history(20)]);
        }

        case 'admin/notice/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $r = NoticeService::save((string) ($b['title'] ?? ''), (string) ($b['content'] ?? ''), $admin, $ip);
            Http::json(['ok' => true] + $r);
        }

        case 'admin/notice/clear|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            NoticeService::clear($admin, $ip);
            Http::json(['ok' => true]);
        }

        // ---------- 后台登录 ----------
        case 'admin/login|POST': {
            if (!RateLimit::hit('login:' . $ip, 10)) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $r = AdminService::login((string) ($b['username'] ?? ''), (string) ($b['password'] ?? ''), $ip);
            if (!$r['ok']) {
                Http::json($r, 401);
            }
            Http::json($r);
        }

        case 'admin/logout|POST': {
            AdminService::require();
            AdminService::logout($ip);
            Http::json(['ok' => true]);
        }

        // ---------- 后台数据 ----------
        case 'admin/stats|GET': {
            AdminService::require();
            Http::json(['ok' => true] + CardService::stats());
        }

        case 'admin/cards|GET': {
            AdminService::require();
            $page = max(1, (int) ($_GET['page'] ?? 1));
            $per  = min(100, max(10, (int) ($_GET['per'] ?? 20)));
            $q    = trim((string) ($_GET['q'] ?? ''));
            $st   = isset($_GET['status']) ? (int) $_GET['status'] : -1;
            $bt   = trim((string) ($_GET['batch'] ?? ''));
            Http::json(['ok' => true] + CardService::listPage($page, $per, $q, $st, $bt));
        }

        case 'admin/cards/generate|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $plan = (string) ($b['plan'] ?? 'all');
            $planTag = in_array($plan, ['basic', 'pro'], true) ? ('plan:' . $plan . ' ') : '';
            $charset = (string) ($b['charset'] ?? 'std');
            if (!in_array($charset, ['std', 'digit', 'alpha', 'full'], true)) {
                $charset = 'std';
            }
            $r = CardService::createBatch(
                (int) ($b['count'] ?? 10),
                (int) ($b['duration'] ?? Config::get('grant_seconds', 300)),
                substr((string) ($b['batch'] ?? 'B' . date('Ymd')), 0, 32),
                $planTag . substr((string) ($b['note'] ?? ''), 0, 110),
                $admin, $ip, $charset
            );
            Http::json(['ok' => true] + $r);
        }

        case 'admin/cards/status|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $ok = CardService::setStatus((int) ($b['id'] ?? 0), (int) ($b['status'] ?? 0), $admin, $ip);
            Http::json(['ok' => $ok]);
        }

        case 'admin/cards/extend|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $days = (int) ($b['days'] ?? 0);
            if ($days === 0 || abs($days) > 3650) {
                Http::json(['ok' => false, 'error' => 'bad_days'], 400);
            }
            Http::json(CardService::extend((int) ($b['id'] ?? 0), $days, $admin, $ip));
        }

        case 'admin/cards/delete|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            Http::json(['ok' => CardService::remove((int) ($b['id'] ?? 0), $admin, $ip)]);
        }

        case 'admin/cards/unbind|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            Http::json(['ok' => CardService::unbind((int) ($b['id'] ?? 0), $admin, $ip)]);
        }

        // ---------- 后台：版本管理 ----------
        case 'admin/versions|GET': {
            AdminService::require();
            Http::json(['ok' => true, 'rows' => VersionService::all()]);
        }

        case 'admin/versions/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $r = VersionService::save(Http::body(), $admin, $ip);
            Http::json($r, $r['ok'] ? 200 : 400);
        }

        case 'admin/versions/delete|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            Http::json(['ok' => VersionService::remove((int) ($b['id'] ?? 0), $admin, $ip)]);
        }

        // ---------- 后台：云端规则库 ----------
        case 'admin/rules|GET': {
            AdminService::require();
            $pack = RulesService::current();
            if (!$pack) {
                Http::json(['ok' => true, 'current' => null, 'content' => '']);
            }
            Http::json(['ok' => true, 'current' => $pack, 'content' => RulesService::content((int) $pack['id'])]);
        }

        case 'admin/rules/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $r = RulesService::save(
                (string) ($b['version'] ?? ''),
                (string) ($b['note'] ?? ''),
                (string) ($b['content'] ?? ''),
                $admin, $ip
            );
            Http::json($r, $r['ok'] ? 200 : 400);
        }

        case 'admin/pins|GET': {
            AdminService::require();
            Http::json(['ok' => true, 'rows' => PinService::offlineList(200)]);
        }


        case 'admin/logs|GET': {
            AdminService::require();
            Http::json(['ok' => true,
                        'audit'  => AdminService::auditLog(100),
                        'events' => AdminService::recentEvents(150)]);
        }

        case 'admin/csrf|GET': {
            AdminService::require();
            Http::json(['ok' => true, 'csrf' => AdminService::csrf()]);
        }

        // ---------- 后台：批量 / 导出 / 设置 / 改密 / 危险操作 ----------
        case 'admin/batches|GET': {
            AdminService::require();
            $rows = Database::pdo()->query('SELECT batch, COUNT(*) c FROM cards GROUP BY batch ORDER BY MAX(id) DESC LIMIT 100')->fetchAll();
            Http::json(['ok' => true, 'rows' => $rows]);
        }

        case 'admin/cards/bulk|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $ids = $b['ids'] ?? [];
            if (!is_array($ids) || count($ids) === 0) {
                Http::json(['ok' => false, 'error' => 'no_selection'], 400);
            }
            $action = (string) ($b['action'] ?? '');
            $days   = (int) ($b['days'] ?? 0);
            $done = 0;
            foreach ($ids as $id) {
                $id = (int) $id;
                if ($id <= 0) continue;
                if ($action === 'ban')      { CardService::setStatus($id, 2, $admin, $ip); $done++; }
                elseif ($action === 'unban'){ CardService::setStatus($id, 0, $admin, $ip); $done++; }
                elseif ($action === 'delete'){ CardService::remove($id, $admin, $ip); $done++; }
                elseif ($action === 'extend' && $days !== 0) { CardService::extend($id, $days, $admin, $ip); $done++; }
            }
            Http::json(['ok' => true, 'done' => $done]);
        }

        case 'admin/cards/export|GET': {
            AdminService::require();
            $q  = trim((string) ($_GET['q'] ?? ''));
            $st = isset($_GET['status']) ? (int) $_GET['status'] : -1;
            $bt = trim((string) ($_GET['batch'] ?? ''));
            $page = CardService::listPage(1, 2000, $q, $st, $bt);
            header('Content-Type: text/csv; charset=utf-8');
            header('Content-Disposition: attachment; filename="cards-' . date('Ymd-His') . '.csv"');
            echo "\xEF\xBB\xBF";
            $out = fopen('php://output', 'w');
            fputcsv($out, ['卡密', '批次', '时长(天)', '状态', '绑定配对码', '兑换时间', '到期时间', '备注']);
            $map = [0 => '未使用', 1 => '已兑换', 2 => '已作废'];
            foreach ($page['rows'] as $r) {
                fputcsv($out, [
                    $r['code'], $r['batch'], round(((int) $r['duration_sec']) / 86400, 2),
                    $map[(int) $r['status']] ?? '?', $r['bound_pin'] ?: '',
                    $r['redeemed_at'] ? date('Y-m-d H:i:s', (int) $r['redeemed_at']) : '',
                    $r['expire_at'] ? date('Y-m-d H:i:s', (int) $r['expire_at']) : '',
                    (string) ($r['note'] ?? ''),
                ]);
            }
            fclose($out);
            exit;
        }

        case 'admin/settings|GET': {
            AdminService::require();
            Http::json(['ok' => true, 'settings' => Settings::all()]);
        }

        case 'admin/settings/save|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            Settings::save([
                'default_count'  => max(1, min(1000, (int) ($b['default_count'] ?? 10))),
                'default_days'   => max(1, min(3650, (int) ($b['default_days'] ?? 30))),
                'default_plan'   => in_array($b['default_plan'] ?? '', ['all', 'basic', 'pro'], true) ? $b['default_plan'] : 'all',
                'default_charset'=> in_array($b['default_charset'] ?? '', ['std', 'digit', 'alpha', 'full'], true) ? $b['default_charset'] : 'std',
                'batch_prefix'   => substr(preg_replace('/[^A-Za-z0-9]/', '', (string) ($b['batch_prefix'] ?? 'B')), 0, 8) ?: 'B',
            ], $admin);
            Http::json(['ok' => true, 'settings' => Settings::all()]);
        }

        case 'admin/password|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $cur = (string) ($b['current'] ?? '');
            $new = (string) ($b['new'] ?? '');
            if (strlen($new) < 8) {
                Http::json(['ok' => false, 'error' => 'too_short'], 400);
            }
            $st = Database::pdo()->prepare('SELECT pass_hash FROM admins WHERE username = ?');
            $st->execute([$admin]);
            $hash = (string) $st->fetchColumn();
            if (!password_verify($cur, $hash)) {
                Http::json(['ok' => false, 'error' => 'bad_current'], 400);
            }
            AdminService::changePassword($admin, $new);
            Database::pdo()->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'password.change', $admin, $ip, '']);
            Http::json(['ok' => true]);
        }

        case 'admin/pins/revoke|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $pin = PinService::normalise((string) ($b['pin'] ?? ''));
            if (!PinService::valid($pin)) {
                Http::json(['ok' => false, 'error' => 'bad_pin'], 400);
            }
            PinService::revoke($pin);
            Database::pdo()->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'pin.revoke', $pin, $ip, '']);
            Http::json(['ok' => true]);
        }

        case 'admin/danger|POST': {
            $admin = AdminService::require();
            AdminService::checkCsrf($_SERVER['HTTP_X_CSRF'] ?? null);
            $b = Http::body();
            $what = (string) ($b['action'] ?? '');
            $pdo = Database::pdo();
            $n = 0;
            if ($what === 'clear_unused_cards') {
                $n = (int) $pdo->query('SELECT COUNT(*) FROM cards WHERE status = 0')->fetchColumn();
                $pdo->exec('DELETE FROM cards WHERE status = 0');
            } elseif ($what === 'clear_logs') {
                $n = (int) $pdo->query('SELECT COUNT(*) FROM audit')->fetchColumn();
                $pdo->exec('DELETE FROM audit');
                $pdo->exec('DELETE FROM events');
            } else {
                Http::json(['ok' => false, 'error' => 'unknown'], 400);
            }
            $pdo->prepare('INSERT INTO audit(ts, admin, action, target, ip, detail) VALUES(?,?,?,?,?,?)')
                ->execute([time(), $admin, 'danger.' . $what, '', $ip, 'rows=' . $n]);
            Http::json(['ok' => true, 'affected' => $n]);
        }

        // ---------- v2：加密通道（握手 / 卡密 / 服务端模块） ----------
        case 'v2/handshake|POST': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $c = Crypto::checkRequest('handshake', $b);
            if (!$c) {
                Http::abort(400, 'bad_sig');
            }
            PinService::touch($c['pin'], $ip, $ua);
            Http::json(Crypto::statusBox($c['pin'], $c['dev'], $c['n']));
        }

        case 'v2/card|POST': {
            if (!RateLimit::hit('ip:' . $ip, 30) || !RateLimit::hit('v2c:' . $ip, 30)) {
                Http::abort(429, 'rate_limited');
            }
            $b = Http::body();
            $c = Crypto::checkRequest('card', $b);
            if (!$c) {
                Http::abort(400, 'bad_sig');
            }
            PinService::touch($c['pin'], $ip, $ua);
            $code = (string) ($b['code'] ?? '');
            $r = CardService::redeem($c['pin'], $code, $ip, $ua);
            if (!$r['ok']) {
                Http::json(Crypto::box(['ok' => false, 'error' => $r['error']], $c['n']));
            }
            Http::json(Crypto::statusBox($c['pin'], $c['dev'], $c['n']));
        }

        // 服务端下发 Lua 模块（客户端验签后 load）：把功能函数真正放到服务器上
        case 'v2/module|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $pin = PinService::normalise((string) ($_GET['pin'] ?? ''));
            $st  = PinService::valid($pin) ? PinService::status($pin) : ['authorized' => false];
            if (empty($st['authorized'])) {
                Http::json(['ok' => false, 'error' => 'not_authorized']);
            }
            $file = APP_STORAGE . '/remote/module.lua';
            $src  = is_file($file) ? (string) file_get_contents($file) : '';
            if ($src === '') {
                Http::json(['ok' => false, 'error' => 'no_module']);
            }
            Http::json([
                'ok'  => true,
                'src' => base64_encode($src),
                'sig' => Crypto::sign('l|' . $src),
            ]);
        }

        // ---------- GOD 注入器：卡密换 lua ----------
        case 'god/download|GET': {
            if (!RateLimit::hit('ip:' . $ip, (int) Config::get('rate_ip'))) {
                Http::abort(429, 'rate_limited');
            }
            $code = CardService::normalise((string) ($_GET['card'] ?? ''));
            if (!preg_match('/^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$/', $code)) {
                Http::json(['ok' => false, 'error' => 'card_format'], 400);
            }
            $pdo = Database::pdo();
            $st = $pdo->prepare('SELECT id, status, expire_at FROM cards WHERE code = ?');
            $st->execute([$code]);
            $card = $st->fetch();
            if (!$card) {
                CardService::event('god_dl_fail', null, $code, $ip, $ua, 'not_found');
                Http::json(['ok' => false, 'error' => 'card_not_found'], 404);
            }
            if ((int) $card['status'] === 2) {
                CardService::event('god_dl_fail', null, $code, $ip, $ua, 'revoked');
                Http::json(['ok' => false, 'error' => 'card_revoked'], 403);
            }
            $now = time();
            if ((int) $card['status'] === 1 && (int) $card['expire_at'] <= $now) {
                CardService::event('god_dl_fail', null, $code, $ip, $ua, 'expired');
                Http::json(['ok' => false, 'error' => 'card_expired'], 403);
            }
            $file = APP_STORAGE . '/god/EntranceFlow.lua';
            if (!is_file($file)) {
                Http::json(['ok' => false, 'error' => 'no_file'], 500);
            }
            CardService::event('god_download', null, $code, $ip, $ua, 'ok');
            header('Content-Type: application/octet-stream');
            header('Content-Length: ' . filesize($file));
            header('Content-Disposition: attachment; filename="EntranceFlow.lua"');
            header('Cache-Control: no-store');
            readfile($file);
            exit;
        }

        default:
            Http::abort(404, 'not_found');
    }
} catch (Throwable $e) {
    Log::file('app', 'api fatal: ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine());
    Http::json(['ok' => false, 'error' => 'server_error'], 500);
}
