const express = require('express');
const cors = require('cors');
const db = require('./db');
const authRoutes = require('./routes/auth')(db);
const riskRoutes = require('./routes/risk')(db);
const capaRoutes = require('./routes/capa')(db);
const nearmissRoutes = require('./routes/nearmiss')(db);
const tbmRoutes = require('./routes/tbm')(db);
const voiceRoutes = require('./routes/voice')(db);
const legalmeetRoutes = require('./routes/legalmeet')(db);
const accidentRoutes = require('./routes/accident')(db);
const msdsRoutes = require('./routes/msds')(db);
const healthRoutes = require('./routes/health')(db);
const eduRoutes = require('./routes/edu')(db);
const ppeRoutes = require('./routes/ppe')(db);
const appointRoutes = require('./routes/appoint')(db);
const contractorRoutes = require('./routes/contractor')(db);
const ptwRoutes = require('./routes/ptw')(db);
const legalChecklistRoutes = require('./routes/legal-checklist')(db);
const usersRoutes = require('./routes/users')(db);
const sitesRoutes = require('./routes/sites')(db);
const attachmentsRoutes = require('./routes/attachments')(db);
const organizationsRoutes = require('./routes/organizations')(db);

const app = express();

// 2026-08-28 후속조치: 헬스체크는 어떤 경우에도 막히면 안 되므로(로드밸런서 + Docker +
// 외부 uptime 모니터링이 동시에 찔러도) CORS/rate limit/인증 전부보다 앞에 둔다.
app.get('/health', (req, res) => res.json({ ok: true, service: 'safety-meerkat-server' }));

// 2026-08-30: 터미널 없이 브라우저만으로 첫 회사+관리자 계정을 만들 수 있는 페이지.
// /organizations 자체는 SaaS 특성상 계속 열려있어야 하지만(여러 회사가 계속 가입해야 하므로),
// 이 "화면"은 배포 직후 딱 한 번 쓰라고 만든 것이라 - 이미 회사가 하나라도 있으면 접속 시
// 안내만 보여준다(폼은 숨김). 오해로 인한 중복 회사 생성을 막기 위함이며, /organizations API
// 자체를 막는 것은 아니다(추가 회사 가입은 계속 가능해야 하므로 - 점검보고서 6절 참고).
const { setupPageHtml } = require('./setup-page');
app.get('/setup', (req, res) => {
  const orgCount = db.prepare('SELECT COUNT(*) c FROM organizations WHERE deleted = 0').get().c;
  res.set('Content-Type', 'text/html; charset=utf-8');
  if (orgCount > 0) {
    res.send(`<!DOCTYPE html><html lang="ko"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>안전미어캣 프로</title>
      <style>body{background:#0f172a;color:#f1f5f9;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center}
      div{max-width:400px;line-height:1.7}</style></head><body><div>
      <h2>이미 시작된 서버입니다</h2>
      <p style="color:#94a3b8">이 서버는 이미 최소 1개 이상의 회사가 등록되어 있습니다.<br>이 화면은 서버를 맨 처음 딱 한 번 준비할 때만 씁니다.<br>추가로 다른 회사를 등록하려면 관리자에게 문의해 주세요.</p>
      </div></body></html>`);
    return;
  }
  res.send(setupPageHtml());
});

// PWA는 API와 다른 도메인(예: Netlify)에서 서빙되는 경우가 많으므로 CORS가 필요하다.
//
// 2026-08-28 후속조치(출시전 점검보고서 3절): 예전엔 CORS_ORIGIN 미설정 시 "경고만 남기고
// 전체 출처를 허용"했다 - JWT_SECRET은 없으면 기동 자체를 거부하게 만들어놓고 위험도가
// 크게 다르지 않은 CORS는 다른 기준을 적용한 것이라 통일했다. 운영에서는 미설정이면
// 아예 기동을 거부한다.
const allowedOrigins = (process.env.CORS_ORIGIN || '').split(',').map(s => s.trim()).filter(Boolean);
if (allowedOrigins.length === 0 && process.env.NODE_ENV === 'production') {
  console.error(
    '[치명적 설정 오류] NODE_ENV=production인데 CORS_ORIGIN이 설정되지 않았습니다. ' +
    '이 상태로는 모든 출처를 허용하게 되어 위험하므로 기동을 중단합니다. .env.example을 참고해 ' +
    'CORS_ORIGIN=https://yourapp.example.com 형태로 지정하세요.'
  );
  process.exit(1);
}
app.use(cors({
  origin: allowedOrigins.length > 0 ? allowedOrigins : true,
  credentials: true,
}));

app.use(express.json());

// 2026-08-28 후속조치(출시전 점검보고서 3절): 계정당 5회 실패 잠금은 있었지만, 서로 다른
// 여러 계정을 대상으로 한 무차별대입이나 API 스크래핑을 막는 IP 단위 제한이 없었다.
// 인증 관련 엔드포인트는 더 엄격하게, 나머지 API는 완만하게 이중으로 건다.
const rateLimit = require('express-rate-limit');
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 100,
  message: { error: '요청이 너무 많습니다. 15분 후 다시 시도해주세요.' },
  standardHeaders: true, legacyHeaders: false,
});
const apiLimiter = rateLimit({
  windowMs: 60 * 1000, max: 300,
  message: { error: '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.' },
  standardHeaders: true, legacyHeaders: false,
});
app.use('/auth', authLimiter);
app.use('/organizations', authLimiter);
app.use(apiLimiter);

// 배포 직후 트래픽이 실제로 들어오는지 눈으로 바로 확인할 수 있는 최소 로그
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
  next();
});

app.use('/auth', authRoutes);
app.use('/risks', riskRoutes);
app.use('/capa', capaRoutes);
app.use('/nearmiss', nearmissRoutes);
app.use('/tbm', tbmRoutes);
app.use('/voice', voiceRoutes);
app.use('/legalmeet', legalmeetRoutes);
app.use('/accident', accidentRoutes);
app.use('/msds', msdsRoutes);
app.use('/health-records', healthRoutes);
app.use('/edu', eduRoutes);
app.use('/ppe', ppeRoutes);
app.use('/appoint', appointRoutes);
app.use('/contractor', contractorRoutes);
app.use('/ptw', ptwRoutes);
app.use('/compliance', legalChecklistRoutes);
app.use('/users', usersRoutes);
app.use('/sites', sitesRoutes);
app.use('/attachments', attachmentsRoutes);
app.use('/organizations', organizationsRoutes);

app.use((req, res) => {
  res.status(404).json({ error: '존재하지 않는 경로입니다.' });
});

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: '서버 오류가 발생했습니다.' });
});

module.exports = app;
