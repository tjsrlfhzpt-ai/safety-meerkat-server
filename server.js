require('dotenv').config();

// app.js가 require 시점에 JWT_SECRET/NODE_ENV를 읽으므로 dotenv.config()가 반드시 먼저 실행돼야 한다.
const app = require('./src/app');
const db = require('./src/db');
const { ensureSeed } = require('./src/seed');

// 역할/권한 체계가 자동으로 준비되도록 함 (조직/사업장은 2026-08-30부터 /setup 화면
// 또는 POST /organizations를 통해 실제 가입으로만 생성됨 - src/seed.js 참고)
// (ensureSeed 내부가 이미 존재 여부를 확인하고 없을 때만 만들기 때문에 재기동해도 안전함)
try {
  ensureSeed();
} catch (e) {
  console.error('[fatal] 초기 시드 실패:', e);
  process.exit(1);
}

const PORT = process.env.PORT || 4000;
const server = app.listen(PORT, () => {
  console.log(`[safety-meerkat-server] listening on http://localhost:${PORT} (NODE_ENV=${process.env.NODE_ENV || 'development'})`);
});

// 컨테이너 플랫폼(Fly/Railway 등)은 재배포·스케일 조정 시 SIGTERM을 보낸다.
// 연결을 마무리하고 DB 핸들을 정리한 뒤 종료해야 강제 종료로 인한 데이터 손상을 피할 수 있다.
function shutdown(signal) {
  console.log(`[safety-meerkat-server] ${signal} 수신 - graceful shutdown 시작`);
  server.close(() => {
    db.close();
    console.log('[safety-meerkat-server] 정상 종료 완료');
    process.exit(0);
  });
  setTimeout(() => {
    console.warn('[safety-meerkat-server] graceful shutdown 시간 초과 - 강제 종료');
    process.exit(1);
  }, 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
