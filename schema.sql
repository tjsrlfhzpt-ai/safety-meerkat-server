-- ============================================================
-- 안전 미어캣 Pro — 서버 데이터 모델 (1단계 코어)
-- SQLite로 로컬 검증. datetime('now')/TEXT 타입 위주로 작성해
-- PostgreSQL로 옮길 때도 큰 변경 없이 이식되도록 함.
--
-- id 규칙: v5.7의 IdGenerator가 이미 "{PREFIX}-{연도}-{6자리}" 형식
-- (예: RISK-2026-000001)의 사람이 읽을 수 있는 ID를 쓰고 있으므로,
-- 안전관리 도메인 테이블은 이 규칙을 서버에서도 그대로 이어받는다.
-- (id_counters 테이블이 기존 State.idCounters 역할을 대신함)
-- 신규로 생기는 조직/사업장/사용자/권한 관련 테이블은 기존 앱에
-- 대응 개념이 없었으므로 ORG-/SITE-/USER- 접두어를 새로 부여한다.
-- ============================================================

CREATE TABLE id_counters (
  counter_key   TEXT PRIMARY KEY,   -- 예: 'RISK-2026', 'CAPA-2026'
  value         INTEGER NOT NULL DEFAULT 0
);

-- 1. 조직 계층 (지시서 5번: 회사-사업장-부서-팀) --------------------
CREATE TABLE organizations (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  biz_reg_no    TEXT,
  plan_tier     TEXT NOT NULL DEFAULT 'free',   -- free/basic/professional/enterprise (52번)
  status        TEXT NOT NULL DEFAULT 'active',
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted       INTEGER NOT NULL DEFAULT 0,
  deleted_at    TEXT,
  deleted_by    TEXT
);

CREATE TABLE sites (
  id            TEXT PRIMARY KEY,
  org_id        TEXT NOT NULL REFERENCES organizations(id),
  name          TEXT NOT NULL,
  address       TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted       INTEGER NOT NULL DEFAULT 0,
  deleted_at    TEXT,
  deleted_by    TEXT
);

CREATE TABLE departments (
  id            TEXT PRIMARY KEY,
  site_id       TEXT NOT NULL REFERENCES sites(id),
  name          TEXT NOT NULL,
  deleted       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE teams (
  id              TEXT PRIMARY KEY,
  department_id   TEXT NOT NULL REFERENCES departments(id),
  name            TEXT NOT NULL,
  deleted         INTEGER NOT NULL DEFAULT 0
);

-- 2. 사용자 / 역할 / 권한 (지시서 4·6번) ---------------------------
CREATE TABLE users (
  id                  TEXT PRIMARY KEY,
  legacy_id           TEXT UNIQUE,   -- v5.7 단일 사용자 데이터에서 이관 시 참조용(현재는 단일 사용자라 대부분 NULL)
  org_id              TEXT NOT NULL REFERENCES organizations(id),
  site_id             TEXT REFERENCES sites(id),
  department_id       TEXT REFERENCES departments(id),
  team_id             TEXT REFERENCES teams(id),
  login_id            TEXT NOT NULL UNIQUE,
  password_hash       TEXT NOT NULL,
  name                TEXT NOT NULL,
  employee_no         TEXT,
  position            TEXT,
  phone               TEXT,
  email               TEXT,
  user_type           TEXT NOT NULL DEFAULT 'employee',  -- employee/contractor
  account_status      TEXT NOT NULL DEFAULT 'active',    -- active/locked/dormant/disabled
  failed_login_count  INTEGER NOT NULL DEFAULT 0,
  last_login_at       TEXT,
  -- 2026-08-28: 개인정보 수집·이용/이용약관/민감정보(건강정보 등) 처리 동의 시각. NULL이면
  -- 미동의 상태 - 로그인 시 이 값들이 채워질 때까지 앱 사용 전 동의 화면을 먼저 띄운다.
  consent_privacy_at    TEXT,
  consent_terms_at      TEXT,
  consent_sensitive_at  TEXT,
  consent_policy_version TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  deleted             INTEGER NOT NULL DEFAULT 0,
  deleted_at          TEXT,
  deleted_by          TEXT
);

CREATE TABLE roles (
  id    TEXT PRIMARY KEY,
  code  TEXT NOT NULL UNIQUE,
  name  TEXT NOT NULL
);

CREATE TABLE permissions (
  id    TEXT PRIMARY KEY,
  code  TEXT NOT NULL UNIQUE
);

CREATE TABLE role_permissions (
  role_id       TEXT NOT NULL REFERENCES roles(id),
  permission_id TEXT NOT NULL REFERENCES permissions(id),
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
  user_id   TEXT NOT NULL REFERENCES users(id),
  role_id   TEXT NOT NULL REFERENCES roles(id),
  site_id   TEXT REFERENCES sites(id),   -- NULL = 조직 전체 범위
  PRIMARY KEY (user_id, role_id, site_id)
);

-- 3. 안전관리 핵심 모듈 (오늘 구현: 위험성평가, CAPA / 나머지는 6절 참고) ----
CREATE TABLE risk_assessments (
  id                  TEXT PRIMARY KEY,   -- RISK-2026-000001 형식
  legacy_id           TEXT UNIQUE,        -- v14 이전 구식 id('r1' 등)였던 경우만 채움
  site_id             TEXT NOT NULL REFERENCES sites(id),
  process_name        TEXT,
  task_name           TEXT,
  hazard              TEXT NOT NULL,
  existing_measures   TEXT,
  likelihood          INTEGER,
  severity            INTEGER,
  risk_score          INTEGER,
  reduction_measures  TEXT,
  post_likelihood     INTEGER,
  post_severity       INTEGER,
  post_risk_score     INTEGER,
  previous_assessment_id TEXT REFERENCES risk_assessments(id),  -- v16 재평가 연결과 동일 개념
  status              TEXT NOT NULL DEFAULT 'draft',
  assignee_id         TEXT REFERENCES users(id),
  due_date            TEXT,
  related_contractor  TEXT,           -- v5.14: 관련 협력업체(회사명 문자열, 로컬 앱과 동일한 방식 - 15절 참고)
  created_by          TEXT REFERENCES users(id),  -- NULL 허용: 마이그레이션된 과거 기록은 작성자를 알 수 없는 게 정직한 상태
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by          TEXT REFERENCES users(id),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  approved_by         TEXT REFERENCES users(id),
  approved_at         TEXT,
  deleted             INTEGER NOT NULL DEFAULT 0,
  deleted_at          TEXT,
  deleted_by          TEXT
);

CREATE TABLE incidents (          -- 산업재해, prefix ACC
  id              TEXT PRIMARY KEY,
  legacy_id       TEXT UNIQUE,
  site_id         TEXT NOT NULL REFERENCES sites(id),
  occurred_date   TEXT,
  occurred_time   TEXT,
  location        TEXT,
  victim_name     TEXT,
  injury_type     TEXT,
  body_part       TEXT,
  severity        TEXT,
  lost_days       INTEGER,
  description     TEXT NOT NULL,
  root_cause      TEXT,
  corrective_plan TEXT,           -- 프론트 correctiveAction과 매핑
  report_status   TEXT,           -- 산재보고 진행상태(별도) - status(사고 처리상태)와는 다른 축
  memo            TEXT,
  related_contractor TEXT,          -- v5.14: 관련 협력업체
  status          TEXT NOT NULL DEFAULT 'investigating',
  created_by      TEXT REFERENCES users(id),  -- NULL 허용(사유는 risk_assessments와 동일, 5절 참고)
  updated_at  TEXT,
  updated_by  TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  deleted         INTEGER NOT NULL DEFAULT 0,
  deleted_at      TEXT,
  deleted_by      TEXT
);

CREATE TABLE near_misses (        -- 아차사고, prefix NM
  id          TEXT PRIMARY KEY,
  legacy_id   TEXT UNIQUE,
  site_id     TEXT NOT NULL REFERENCES sites(id),
  title       TEXT,
  content     TEXT NOT NULL,
  occurred_date TEXT,
  location    TEXT,               -- v16에서 추가된 발생장소 필드와 동일 개념
  cause       TEXT,
  measure     TEXT,
  manager     TEXT,
  due_date    TEXT,
  memo        TEXT,
  related_contractor TEXT,        -- v5.14: 관련 협력업체
  status      TEXT NOT NULL DEFAULT '접수',
  created_by  TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  deleted     INTEGER NOT NULL DEFAULT 0,
  deleted_at  TEXT,
  deleted_by  TEXT
);

-- v5.11: TBM(작업 전 안전점검회의), prefix TBM
CREATE TABLE tbm_records (
  id            TEXT PRIMARY KEY,
  legacy_id     TEXT UNIQUE,
  site_id       TEXT NOT NULL REFERENCES sites(id),
  tbm_date      TEXT,
  tbm_time      TEXT,
  location      TEXT,
  topic         TEXT NOT NULL,
  hazard        TEXT,
  risk_level    TEXT,
  measure       TEXT,
  health_note   TEXT,
  notice        TEXT,
  supervisor    TEXT,
  related_contractor TEXT,      -- v5.14: 관련 협력업체
  created_by    TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted       INTEGER NOT NULL DEFAULT 0,
  deleted_at    TEXT,
  deleted_by    TEXT
);

-- v5.11: 안전의 소리함(익명 제안/신고), prefix VOC
CREATE TABLE voice_reports (
  id              TEXT PRIMARY KEY,
  legacy_id       TEXT UNIQUE,
  site_id         TEXT NOT NULL REFERENCES sites(id),
  report_date     TEXT,
  report_time     TEXT,
  location        TEXT,
  category        TEXT,
  content         TEXT NOT NULL,
  reporter_type   TEXT,            -- 익명/실명
  reporter_name   TEXT,            -- 익명이면 비워둠(프론트에서도 이미 그렇게 처리)
  action_taken    TEXT,
  memo            TEXT,
  status          TEXT NOT NULL DEFAULT '접수',
  created_by      TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  deleted         INTEGER NOT NULL DEFAULT 0,
  deleted_at      TEXT,
  deleted_by      TEXT
);

-- v5.11: 법정회의·점검(산업안전보건위원회 등), prefix LM
CREATE TABLE legal_meetings (
  id            TEXT PRIMARY KEY,
  legacy_id     TEXT UNIQUE,
  site_id       TEXT NOT NULL REFERENCES sites(id),
  meeting_date  TEXT,
  meeting_time  TEXT,
  location      TEXT,
  kind          TEXT,
  attendees     TEXT,
  content       TEXT NOT NULL,
  finding       TEXT,
  measure       TEXT,
  next_date     TEXT,
  manager       TEXT,
  memo          TEXT,
  related_contractor TEXT,      -- v5.14: 관련 협력업체
  status        TEXT NOT NULL DEFAULT '예정',
  created_by    TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted       INTEGER NOT NULL DEFAULT 0,
  deleted_at    TEXT,
  deleted_by    TEXT
);

-- v5.12: MSDS(물질안전보건자료), prefix MSDS
CREATE TABLE msds_items (
  id            TEXT PRIMARY KEY,
  legacy_id     TEXT UNIQUE,
  site_id       TEXT NOT NULL REFERENCES sites(id),
  name          TEXT NOT NULL,
  cas_no        TEXT,
  maker         TEXT,
  hazard_grade  TEXT,
  location      TEXT,
  department    TEXT,
  memo          TEXT,
  created_by    TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted       INTEGER NOT NULL DEFAULT 0,
  deleted_at    TEXT,
  deleted_by    TEXT
);

-- v5.12: 건강진단, prefix HLT
CREATE TABLE health_records (
  id            TEXT PRIMARY KEY,
  legacy_id     TEXT UNIQUE,
  site_id       TEXT NOT NULL REFERENCES sites(id),
  worker_name   TEXT NOT NULL,
  exam_type     TEXT,
  exam_date     TEXT,
  next_date     TEXT,
  result        TEXT,
  created_by    TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  deleted       INTEGER NOT NULL DEFAULT 0,
  deleted_at    TEXT,
  deleted_by    TEXT
);

-- v5.12: 안전교육 실시기록, prefix EDU
CREATE TABLE training_records (
  id                  TEXT PRIMARY KEY,
  legacy_id           TEXT UNIQUE,
  site_id             TEXT NOT NULL REFERENCES sites(id),
  name                TEXT NOT NULL,   -- 교육명
  training_date       TEXT,
  target_audience     TEXT,
  next_training_date  TEXT,
  material            TEXT,
  attendee_names      TEXT,            -- 콤마로 구분한 명단 원문 (프론트 parseNameList와 호환)
  absentee_names      TEXT,
  memo                TEXT,
  related_contractor  TEXT,          -- v5.14: 관련 협력업체
  created_by          TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  deleted             INTEGER NOT NULL DEFAULT 0,
  deleted_at          TEXT,
  deleted_by          TEXT
);

-- v5.12: 보호구(PPE) 지급기록, prefix PPE
CREATE TABLE ppe_records (
  id                  TEXT PRIMARY KEY,
  legacy_id           TEXT UNIQUE,
  site_id             TEXT NOT NULL REFERENCES sites(id),
  item_type           TEXT NOT NULL,
  recipient           TEXT,
  issue_date          TEXT,
  quantity            INTEGER,
  next_replace_date   TEXT,
  status              TEXT NOT NULL DEFAULT '지급완료',
  memo                TEXT,
  created_by          TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  deleted             INTEGER NOT NULL DEFAULT 0,
  deleted_at          TEXT,
  deleted_by          TEXT
);

-- v5.13: 법정선임(관리책임자/안전관리자 등 법정 선임자 관리), prefix APT
CREATE TABLE legal_appointments (
  id              TEXT PRIMARY KEY,
  legacy_id       TEXT UNIQUE,
  site_id         TEXT NOT NULL REFERENCES sites(id),
  role            TEXT NOT NULL,     -- 직책(관리책임자/안전관리자/보건관리자 등)
  person_name     TEXT NOT NULL,
  appoint_date    TEXT,
  next_edu_date   TEXT,
  cert_number     TEXT,
  status          TEXT NOT NULL DEFAULT '유효',
  memo            TEXT,
  created_by      TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  deleted         INTEGER NOT NULL DEFAULT 0,
  deleted_at      TEXT,
  deleted_by      TEXT
);

-- v5.13: 협력업체 - 이벤트 기록이 아니라 마스터데이터(디렉토리) 성격. 다른 모듈에서
-- "관련 협력업체"로 참조하는 연동은 이번 범위에 포함하지 않음(15절 참고). prefix CT
CREATE TABLE contractors (
  id                  TEXT PRIMARY KEY,
  legacy_id           TEXT UNIQUE,
  site_id             TEXT NOT NULL REFERENCES sites(id),
  company_name        TEXT NOT NULL,
  rep_name            TEXT NOT NULL,
  phone               TEXT,
  work_type           TEXT,
  contract_start      TEXT,
  contract_end        TEXT,
  insurance_status    TEXT,
  safety_edu_date     TEXT,
  evaluation          TEXT,
  status              TEXT NOT NULL DEFAULT '계약중',
  memo                TEXT,
  created_by          TEXT REFERENCES users(id),
  updated_at  TEXT,
  updated_by  TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  deleted             INTEGER NOT NULL DEFAULT 0,
  deleted_at          TEXT,
  deleted_by          TEXT
);

-- v5.13: PTW(작업허가서) - CAPA와 동일하게 실제 승인 워크플로우가 있어 상태전이를
-- 서버가 강제한다(15절 참고). prefix PTW
CREATE TABLE permits (
  id              TEXT PRIMARY KEY,
  legacy_id       TEXT UNIQUE,
  site_id         TEXT NOT NULL REFERENCES sites(id),
  title           TEXT NOT NULL,
  location        TEXT NOT NULL,
  work_time       TEXT NOT NULL,
  work_date       TEXT,
  manager         TEXT,
  worker          TEXT,
  hazard          TEXT,
  measure         TEXT,
  approver        TEXT,
  memo            TEXT,
  related_contractor TEXT,        -- v5.14: 관련 협력업체
  status          TEXT NOT NULL DEFAULT '등록',  -- 등록/위험확인중/승인대기/승인됨/작업중/종료/반려
  approved_at     TEXT,
  work_started_at TEXT,
  closed_at       TEXT,
  created_by      TEXT REFERENCES users(id),
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by      TEXT REFERENCES users(id),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
  deleted         INTEGER NOT NULL DEFAULT 0,
  deleted_at      TEXT,
  deleted_by      TEXT
);

-- v5.15→정정: 처음엔 중대재해처벌법 12개 항목만으로 별도 테이블을 만들었으나, 실제로는
-- 모바일 앱에 이미 "산안법 & 중처법 85개 핵심 법규 DB"(tab-checklist)가 조항·과태료까지
-- 갖춰 존재하고 있었습니다(먼저 확인하지 못한 제 실수 - 19-3절 README 참고). 그 85개 항목을
-- 그대로 서버에 반영합니다. content(tag/title/desc/penalty)는 고정 시드값이고, 사업장별로
-- checked/note만 달라집니다.
CREATE TABLE legal_checklist_items (
  id            TEXT PRIMARY KEY,
  site_id       TEXT NOT NULL REFERENCES sites(id),
  item_no       INTEGER NOT NULL,      -- 1~85, 로컬 앱과 동일한 번호 체계
  tag           TEXT NOT NULL,         -- 법령 조항 근거
  title         TEXT NOT NULL,
  description   TEXT,
  penalty       TEXT,                  -- 과태료/벌금/징역 등 위반 시 처벌 규정
  checked       INTEGER NOT NULL DEFAULT 0,
  note          TEXT,                  -- 이행 근거·증빙 메모
  checked_by    TEXT REFERENCES users(id),
  checked_at    TEXT,
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(site_id, item_no)
);

CREATE TABLE capa_actions (        -- CAPA, prefix CAPA
  id              TEXT PRIMARY KEY,
  legacy_id       TEXT UNIQUE,
  site_id         TEXT NOT NULL REFERENCES sites(id),
  source_type     TEXT NOT NULL,   -- risk_assessment/incident/near_miss/legalmeet/voice/ptw/report
  source_id       TEXT,
  title           TEXT NOT NULL,
  description     TEXT,
  status          TEXT NOT NULL DEFAULT '등록',  -- 등록/조치중/완료요청/검증중/승인/반려/종결 (기존과 동일)
  assignee_id     TEXT REFERENCES users(id),
  verifier_id     TEXT REFERENCES users(id),
  due_date        TEXT,
  before_photo_key TEXT,
  after_photo_key  TEXT,
  reject_reason   TEXT,
  created_by      TEXT REFERENCES users(id),  -- NULL 허용(사유는 risk_assessments와 동일)
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by      TEXT REFERENCES users(id),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
  approved_by     TEXT REFERENCES users(id),
  approved_at     TEXT,
  deleted         INTEGER NOT NULL DEFAULT 0
);

-- 4. 감사로그 / 첨부파일 -------------------------------------------
CREATE TABLE audit_logs (
  id            TEXT PRIMARY KEY,
  actor_user_id TEXT REFERENCES users(id),
  actor_name    TEXT,             -- 당시 이름 스냅샷(계정 삭제돼도 기록은 남게)
  action        TEXT NOT NULL,    -- create/update/delete/restore/status_change/approve/reject/login/logout
  entity_type   TEXT NOT NULL,
  entity_id     TEXT,
  before_json   TEXT,
  after_json    TEXT,
  ip_address    TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE attachments (
  id            TEXT PRIMARY KEY,
  entity_type   TEXT NOT NULL,
  entity_id     TEXT NOT NULL,
  file_key      TEXT NOT NULL,    -- 오브젝트 스토리지 키(로컬 프로토타입에서는 파일 경로)
  file_name     TEXT,
  mime_type     TEXT,
  uploaded_by   TEXT REFERENCES users(id),
  uploaded_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_users_org ON users(org_id);
CREATE INDEX idx_users_site ON users(site_id);
CREATE INDEX idx_risk_site ON risk_assessments(site_id);
CREATE INDEX idx_capa_site_status ON capa_actions(site_id, status);
CREATE INDEX idx_incident_site ON incidents(site_id);
CREATE INDEX idx_nearmiss_site ON near_misses(site_id);
CREATE INDEX idx_tbm_site ON tbm_records(site_id);
CREATE INDEX idx_voice_site ON voice_reports(site_id);
CREATE INDEX idx_legalmeet_site ON legal_meetings(site_id);
CREATE INDEX idx_msds_site ON msds_items(site_id);
CREATE INDEX idx_health_site ON health_records(site_id);
CREATE INDEX idx_training_site ON training_records(site_id);
CREATE INDEX idx_ppe_site ON ppe_records(site_id);
CREATE INDEX idx_appoint_site ON legal_appointments(site_id);
CREATE INDEX idx_contractor_site ON contractors(site_id);
CREATE INDEX idx_permit_site_status ON permits(site_id, status);
CREATE INDEX idx_legal_checklist_site ON legal_checklist_items(site_id);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);

-- ============================================================
-- 아직 만들지 않은 목표 테이블 (지시서 32번 ERD 기준, 다음 단계):
-- worker_reports, documents, notifications, inspection_templates,
-- inspection_submissions, assets, ai_records
-- 13개 안전관리 모듈 중 협력업체를 제외한 12개가 이제 API로 연결됨.
-- 협력업체는 테이블은 있으나(마스터데이터 성격) 다른 모듈과의 연동은 미착수(15절).
-- ============================================================
