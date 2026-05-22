// 헤드노드에서 실행 — 실제 대시보드 화면 캡처
// 사용:
//   cd showcase
//   npm install playwright
//   npx playwright install chromium   # 첫 1회
//   node capture_dashboard.js [BASE_URL]
//
// 결과: dashboard_*.png 파일들 + 자동으로 showcase 페이지의 <img> 자리에 삽입 가능

const { chromium } = require('playwright');

const BASE = process.argv[2] || 'https://localhost';
const OUT = __dirname;

const targets = [
    { name: '01_main',          path: '/',                       wait: 3000 },
    { name: '02_sso',           path: '/auth_portal/',           wait: 2500 },
    { name: '03_dashboard',     path: '/dashboard/',             wait: 4500 },
    { name: '04_nodes',         path: '/dashboard/',             wait: 4000, click: 'text=/Node Management|노드/i' },
    { name: '05_jobs',          path: '/dashboard/',             wait: 4000, click: 'text=/Job Management|작업/i' },
    { name: '06_health',        path: '/dashboard/',             wait: 4000, click: 'text=/Health Check|상태/i' },
    { name: '07_cae',           path: '/cae/',                   wait: 3000 },
    { name: '08_vnc',           path: '/vnc/',                   wait: 2500 },
    { name: '09_app',           path: '/app/',                   wait: 2500 },
    { name: '10_prometheus',    url: 'http://localhost:9090',    wait: 2500, full: false },
];

(async () => {
    const browser = await chromium.launch({
        args: ['--ignore-certificate-errors', '--disable-web-security'],
    });
    const ctx = await browser.newContext({
        viewport: { width: 1600, height: 1000 },
        deviceScaleFactor: 2,
        ignoreHTTPSErrors: true,
    });
    const page = await ctx.newPage();

    const ok = [], fail = [];

    for (const t of targets) {
        const url = t.url || (BASE + t.path);
        try {
            console.log(`→ ${t.name}: ${url}`);
            await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 });
            await page.waitForTimeout(1500);
            if (t.click) {
                try { await page.locator(t.click).first().click({ timeout: 3000 }); } catch(_){}
                await page.waitForTimeout(t.wait);
            } else {
                await page.waitForTimeout(t.wait);
            }
            await page.screenshot({
                path: `${OUT}/dashboard_${t.name}.png`,
                fullPage: t.full !== false,
            });
            ok.push(t.name);
        } catch (e) {
            console.log(`  ✗ ${e.message.split('\n')[0]}`);
            fail.push(t.name);
        }
    }

    console.log('');
    console.log(`✓ ok: ${ok.length} / ${targets.length}`);
    if (fail.length) console.log(`✗ failed: ${fail.join(', ')}`);
    console.log(`Output: ${OUT}/dashboard_*.png`);

    await browser.close();
})();
