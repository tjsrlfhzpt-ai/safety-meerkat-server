const express = require('express');
const { generateId } = require('../ids');
const { writeAudit } = require('../audit');

// 2026-08-28 후속조치: "여러 고객사를 위한 SaaS로 간다"는 결정에 따라 조직 생성 API를
// 추가한다. auth.js의 /register와 정확히 같은 이유로 인증을 걸 수 없다 - 이 API를 호출하는
// 시점엔 그 조직에 사용자가 단 한 명도 없다(회사가 이제 막 가입하는 순간). 인증 대신
// app.js의 authLimiter(같은 rate limit)를 이 라우트에도 적용해 남용을 억제한다.
//
// 보안 관점에서 이 API 자체는 2-1절 취약점과 리스크 프로필이 다르다: 조직을 만드는 것만으로는
// 누구의 권한도 획득하지 못한다(빈 조직 껍데기만 생김). 실제 권한(company_admin)은 이어서
// POST /auth/register를 호출해야 생기고, 그 경로는 이미 "조직 내 최초 가입자만 자동 승격"
// 규칙으로 막혀있다(auth.js 참고). 즉 이 API의 최악의 남용 시나리오는 "빈 조직 스팸 생성"
// 정도이며, rate limit로 충분히 억제된다.
module.exports = function organizationsRoutes(db) {
  const router = express.Router();

  router.post('/', (req, res) => {
    const { name, bizRegNo, siteName } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name(회사/조직명)은 필수입니다.' });

    const orgId = generateId('ORG');
    db.prepare('INSERT INTO organizations (id, name, biz_reg_no) VALUES (?, ?, ?)').run(orgId, name, bizRegNo || null);

    // 최초 사업장까지 한 번에 만들 수 있게 해준다(선택) - 그래야 가입 직후 바로
    // POST /auth/register 한 번으로 부트스트랩 관리자 + 사업장 배정까지 끝난다.
    let siteId = null;
    if (siteName) {
      siteId = generateId('SITE');
      db.prepare('INSERT INTO sites (id, org_id, name) VALUES (?, ?, ?)').run(siteId, orgId, siteName);
    }

    writeAudit(db, {
      actorUserId: null, actorName: name, action: 'create',
      entityType: 'organization', entityId: orgId, after: { name, bizRegNo, siteName }, ip: req.ip,
    });

    res.status(201).json({ orgId, siteId });
  });

  return router;
};
