const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data.sqlite');
const isNew = !fs.existsSync(DB_PATH);

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

if (isNew) {
  const schema = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf-8');
  db.exec(schema);
  console.log('[db] schema.sql 적용 완료:', DB_PATH);
}

// 2026-08-28: 개인정보 동의(2-3절) 컬럼 추가. schema.sql은 "새 DB를 처음 만들 때만" 적용되므로
// (위 isNew 분기), 이미 존재하는 DB에는 반영되지 않는다. 기존 데이터는 절대 건드리지 않고
// 누락된 컬럼만 안전한 기본값(NULL)으로 추가하는 방식 - README가 지켜온 마이그레이션 원칙과
// 동일하다. 컬럼이 이미 있으면 조용히 건너뛴다(재기동해도 안전 = idempotent).
function addColumnIfMissing(table, column, ddl) {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
  if (!cols.includes(column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${ddl}`);
    console.log(`[db] 마이그레이션: ${table}.${column} 컬럼 추가`);
  }
}
addColumnIfMissing('users', 'consent_privacy_at', 'consent_privacy_at TEXT');
addColumnIfMissing('users', 'consent_terms_at', 'consent_terms_at TEXT');
addColumnIfMissing('users', 'consent_sensitive_at', 'consent_sensitive_at TEXT');
addColumnIfMissing('users', 'consent_policy_version', 'consent_policy_version TEXT');

// 2026-08-28 후속조치(출시전 점검보고서 3절 "12개 모듈 PATCH API 부재"): 수정 기능을 추가하며
// "누가 언제 고쳤는지"도 함께 남긴다(지침 10 - 변경이력). 이 12개 테이블은 원래 created_by/
// created_at만 있고 updated_*가 아예 없었다.
const UPDATABLE_TABLES = [
  'risk_assessments', 'incidents', 'near_misses', 'tbm_records', 'voice_reports',
  'legal_meetings', 'msds_items', 'health_records', 'training_records', 'ppe_records',
  'legal_appointments', 'contractors',
];
for (const t of UPDATABLE_TABLES) {
  addColumnIfMissing(t, 'updated_at', 'updated_at TEXT');
  addColumnIfMissing(t, 'updated_by', 'updated_by TEXT');
}

module.exports = db;
module.exports.DB_PATH = DB_PATH;
