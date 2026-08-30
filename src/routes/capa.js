const express = require('express');
const { authenticate, requirePermission, hasPermission, requireHomeSite, accessibleSiteIds } = require('../auth-middleware');
const { nextDomainId } = require('../ids');
const { writeAudit } = require('../audit');
const { queryPaginatedList } = require('../pagination');

// v5.7 CapaEngine의 상태값과 동일하게 유지 (등록→조치중→완료요청→검증중→승인/반려→종결)
const ALLOWED_TRANSITIONS = {
  '등록': ['조치중'],
  '조치중': ['완료요청'],
  '완료요청': ['검증중'],
  '검증중': ['승인', '반려'],
  '반려': ['조치중'],
  '승인': ['종결'],
};

// 2026-08-28 후속조치(출시전 점검보고서 3절 "CAPA 자동연계가 위험성평가에만 존재"):
// schema.sql의 capa_actions.source_type 주석이 예정하고 있던 7개 값. 위험성평가(고위험 시)와
// 사고(신고 즉시)는 자동생성되지만(risk.js/accident.js), 아차사고·법정회의점검·소리함·PTW는
// "이 중에 CAPA로 이어갈 만한 게 있는지"를 사람이 판단해야 한다고 보고 자동생성 대신
// 수동 생성 API를 열었다 - 전부 자동화하면 사소한 건까지 CAPA가 남발돼 오히려 추적이
// 어려워질 수 있다(원칙 15 - 불필요한 기능 남발 경계).
const VALID_SOURCE_TYPES = {
  risk_assessment: 'risk_assessments',
  incident: 'incidents',
  near_miss: 'near_misses',
  legalmeet: 'legal_meetings',
  voice: 'voice_reports',
  ptw: 'permits',
  report: null, // 특정 근거 기록 없이 여는 CAPA (정기점검 등에서 발견한 사항)
};

module.exports = function capaRoutes(db) {
  const router = express.Router();
  router.use(authenticate);

  router.post('/', requirePermission(db, 'capa.update'), requireHomeSite, (req, res) => {
    const b = req.body || {};
    if (!b.title) return res.status(400).json({ error: '제목은 필수입니다.' });

    const sourceType = b.sourceType || 'report';
    if (!Object.prototype.hasOwnProperty.call(VALID_SOURCE_TYPES, sourceType)) {
      return res.status(400).json({ error: `sourceType은 ${Object.keys(VALID_SOURCE_TYPES).join('/')} 중 하나여야 합니다.` });
    }

    const sourceTable = VALID_SOURCE_TYPES[sourceType];
    let sourceId = null;
    if (sourceTable) {
      if (!b.sourceId) return res.status(400).json({ error: 'sourceId는 필수입니다 (report 유형 제외).' });
      const siteIds = accessibleSiteIds(db, req);
      const sitePh = siteIds.map(() => '?').join(',');
      const src = siteIds.length
        ? db.prepare(`SELECT id FROM ${sourceTable} WHERE id = ? AND site_id IN (${sitePh})`).get(b.sourceId, ...siteIds)
        : null;
      if (!src) return res.status(400).json({ error: '연결하려는 항목을 찾을 수 없습니다 (다른 사업장이거나 존재하지 않음).' });
      sourceId = b.sourceId;
    }

    const id = nextDomainId(db, 'capa');
    db.prepare(`
      INSERT INTO capa_actions (id, site_id, source_type, source_id, title, description, assignee_id, due_date, status, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, '등록', ?)
    `).run(id, req.user.siteId, sourceType, sourceId, b.title, b.description || null, b.assigneeId || null, b.dueDate || null, req.user.sub);

    writeAudit(db, {
      actorUserId: req.user.sub, actorName: req.user.name, action: 'create',
      entityType: 'capa_action', entityId: id, after: b,
    });

    res.status(201).json({ id });
  });

  router.get('/', requirePermission(db, 'capa.read'), (req, res) => {
    const siteIds = accessibleSiteIds(db, req);
    const { rows, total } = queryPaginatedList(db, 'capa_actions', siteIds, req.query);
    res.set('X-Total-Count', String(total));
    res.json(rows);
  });

  router.patch('/:id/status', requirePermission(db, 'capa.update'), (req, res) => {
    const { status: nextStatus, rejectReason } = req.body || {};
    const siteIds = accessibleSiteIds(db, req);
    if (!siteIds.length) return res.status(404).json({ error: '대상을 찾을 수 없습니다.' });
    const sitePh = siteIds.map(() => '?').join(',');
    const capa = db.prepare(`SELECT * FROM capa_actions WHERE id = ? AND site_id IN (${sitePh})`)
      .get(req.params.id, ...siteIds);
    if (!capa) return res.status(404).json({ error: '대상을 찾을 수 없습니다.' });

    const allowed = ALLOWED_TRANSITIONS[capa.status] || [];
    if (!allowed.includes(nextStatus)) {
      return res.status(422).json({
        error: `${capa.status} → ${nextStatus} 전환은 허용되지 않습니다.`,
        allowed,
      });
    }
    if (nextStatus === '승인' && !hasPermission(db, req.user.sub, 'capa.approve')) {
      return res.status(403).json({ error: '승인 권한이 없습니다.' });
    }

    db.prepare(`
      UPDATE capa_actions SET status = ?, updated_by = ?, updated_at = datetime('now'), reject_reason = ?
      WHERE id = ?
    `).run(nextStatus, req.user.sub, nextStatus === '반려' ? (rejectReason || null) : null, req.params.id);

    writeAudit(db, {
      actorUserId: req.user.sub, actorName: req.user.name, action: 'status_change',
      entityType: 'capa_action', entityId: req.params.id,
      before: { status: capa.status }, after: { status: nextStatus },
    });

    res.json({ ok: true, from: capa.status, to: nextStatus });
  });

  return router;
};
