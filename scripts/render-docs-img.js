// 把 docs/img/src/*.html 渲染成 docs/img/*.png（教程配图）
// 用法：npm i playwright && node scripts/render-docs-img.js
const path = require('path'), fs = require('fs');
const { chromium } = require('playwright');
(async () => {
  const src = path.join(__dirname, '..', 'docs', 'img', 'src');
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 100 }, deviceScaleFactor: 1 });
  for (const f of fs.readdirSync(src).filter(f => f.endsWith('.html'))) {
    await p.goto('file://' + path.join(src, f));
    await p.waitForTimeout(300);
    const out = path.join(src, '..', f.replace(/\.html$/, '.png'));
    await p.screenshot({ path: out, fullPage: true });
    console.log(f, '→', path.basename(out));
  }
  await b.close();
})();
