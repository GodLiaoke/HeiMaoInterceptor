-- God 卡密验证系统 / SQLite schema
CREATE TABLE IF NOT EXISTS cards (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  code         TEXT    NOT NULL UNIQUE,
  batch        TEXT    NOT NULL DEFAULT '',
  duration_sec INTEGER NOT NULL DEFAULT 300,
  status       INTEGER NOT NULL DEFAULT 0,      -- 0=未用 1=已兑换 2=已作废
  bound_pin    TEXT,
  bound_ip     TEXT,
  redeemed_at  INTEGER,
  expire_at    INTEGER,
  note         TEXT    NOT NULL DEFAULT '',
  created_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cards_status ON cards(status);
CREATE INDEX IF NOT EXISTS idx_cards_batch  ON cards(batch);

CREATE TABLE IF NOT EXISTS pins (
  pin              TEXT PRIMARY KEY,
  first_seen       INTEGER NOT NULL,
  last_seen        INTEGER NOT NULL,
  ip               TEXT,
  ua               TEXT,
  card_id          INTEGER,
  authorized_until INTEGER NOT NULL DEFAULT 0,
  redeem_count     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_pins_until ON pins(authorized_until);

CREATE TABLE IF NOT EXISTS events (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  ts     INTEGER NOT NULL,
  kind   TEXT NOT NULL,
  pin    TEXT,
  code   TEXT,
  ip     TEXT,
  ua     TEXT,
  detail TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind);

CREATE TABLE IF NOT EXISTS admins (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  username   TEXT NOT NULL UNIQUE,
  pass_hash  TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_login INTEGER,
  is_active  INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS audit (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  ts     INTEGER NOT NULL,
  admin  TEXT,
  action TEXT NOT NULL,
  target TEXT,
  ip     TEXT,
  detail TEXT
);
CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit(ts);

CREATE TABLE IF NOT EXISTS rate (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  k  TEXT NOT NULL,
  ts INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rate_k_ts ON rate(k, ts);

CREATE TABLE IF NOT EXISTS announcements (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  title      TEXT NOT NULL DEFAULT '',
  content    TEXT NOT NULL DEFAULT '',
  active     INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS card_uses (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  card_id INTEGER NOT NULL,
  pin     TEXT NOT NULL,
  ip      TEXT,
  ts      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_card_uses_card ON card_uses(card_id);
CREATE INDEX IF NOT EXISTS idx_card_uses_pin  ON card_uses(pin);

CREATE TABLE IF NOT EXISTS nonces (
  n  TEXT PRIMARY KEY,
  ts INTEGER NOT NULL,
  ip TEXT
);
CREATE INDEX IF NOT EXISTS idx_nonces_ts ON nonces(ts);

CREATE TABLE IF NOT EXISTS settings (
  k          TEXT PRIMARY KEY,
  v          TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL DEFAULT 0
);


-- 客户端版本管理（强制更新 / 下载地址）
CREATE TABLE IF NOT EXISTS app_versions (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  platform     TEXT    NOT NULL DEFAULT 'ios',
  version      TEXT    NOT NULL,
  build        INTEGER NOT NULL DEFAULT 1,
  force_update INTEGER NOT NULL DEFAULT 0,
  url          TEXT    NOT NULL DEFAULT '',
  notes        TEXT    NOT NULL DEFAULT '',
  min_version  TEXT    NOT NULL DEFAULT '',
  active       INTEGER NOT NULL DEFAULT 1,
  created_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_versions_platform ON app_versions(platform, active);

-- 云端规则库（加密下发）
CREATE TABLE IF NOT EXISTS rule_packs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  version      TEXT    NOT NULL,
  note         TEXT    NOT NULL DEFAULT '',
  content      TEXT    NOT NULL,
  sha256       TEXT    NOT NULL,
  bytes        INTEGER NOT NULL DEFAULT 0,
  ip_count     INTEGER NOT NULL DEFAULT 0,
  domain_count INTEGER NOT NULL DEFAULT 0,
  port_count   INTEGER NOT NULL DEFAULT 0,
  active       INTEGER NOT NULL DEFAULT 1,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rulepacks_active ON rule_packs(active, id);
