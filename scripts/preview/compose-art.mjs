// Composes marketing art (thumbnails, icon, vertical video cover, square post) from rendered scenes plus text.
//   node compose-art.mjs <dir with hero.png clash.png roster.png vert.png icon_bg.png hero_sq.png> <out-dir>
// Scene specs for those renders: scripts/preview/art/*.json (export-scene.luau scene mode).
import { chromium } from "playwright";
import { readFileSync } from "node:fs";
const dir = process.argv[2], out = process.argv[3];
const img = (f) => "data:image/png;base64," + readFileSync(`${dir}/${f}`).toString("base64");
const base = `*{margin:0;box-sizing:border-box} body{width:var(--w);height:var(--h);overflow:hidden;position:relative;font-family:'Inter Display','Inter',sans-serif}
.bg{position:absolute;inset:0;background-size:cover;background-position:center}
.vig{position:absolute;inset:0;background:radial-gradient(ellipse at center,transparent 45%,rgba(0,0,10,.75) 100%)}
.logo{position:absolute;font-weight:900;font-style:italic;letter-spacing:-.02em;line-height:.9;color:#fff;
 background:linear-gradient(180deg,#fff 0%,#ffe27a 55%,#ff8a1f 100%);-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;
 filter:drop-shadow(0 6px 0 #1a0f3a) drop-shadow(0 0 24px rgba(255,140,40,.6));-webkit-text-stroke:3px #1a0f3a}
.big{position:absolute;font-weight:900;font-style:italic;line-height:.88;color:#fff;-webkit-text-stroke:6px #120a2e;paint-order:stroke fill;
 text-shadow:0 10px 0 #120a2e,0 0 40px rgba(80,220,255,.7)}
.box{position:absolute;background:rgba(10,14,40,.85);border:5px solid #5ff2ff;border-radius:22px;box-shadow:0 0 40px #2fd8ff,inset 0 0 20px rgba(95,242,255,.3);
 color:#eaffff;font-family:'DejaVu Sans Mono',monospace;font-weight:700;display:flex;align-items:center;padding:0 34px}
.cur{display:inline-block;width:.55em;height:1.05em;background:#5ff2ff;margin-left:6px;box-shadow:0 0 14px #5ff2ff}
.burst{position:absolute;border-radius:50%;background:radial-gradient(circle,#fff 0%,#fff6c0 12%,rgba(255,170,40,.85) 28%,rgba(255,80,20,.0) 62%);mix-blend-mode:screen}
.lines{position:absolute;inset:0;background:repeating-conic-gradient(from 0deg at var(--cx) var(--cy),rgba(255,255,255,.22) 0deg 1.2deg,transparent 1.2deg 9deg);
 -webkit-mask:radial-gradient(circle at var(--cx) var(--cy),transparent 18%,#000 60%);mask:radial-gradient(circle at var(--cx) var(--cy),transparent 18%,#000 60%)}
.tag{position:absolute;background:#ff2d55;color:#fff;font-weight:900;font-style:italic;padding:8px 22px;border-radius:12px;transform:rotate(-4deg);box-shadow:0 8px 0 #6a0820}
.red{color:#ff2340;-webkit-text-stroke:8px #fff;text-shadow:0 12px 0 #5a0010,0 0 50px rgba(255,40,60,.9)}`;
const pages = {
 thumb_type_any_fighter: [1920,1080,`<div class=bg style="background-image:url(${img("hero.png")})"></div><div class=vig></div>
  <div class=big style="left:70px;top:46px;font-size:150px">TYPE <span style="color:#5ff2ff">ANY</span><br>FIGHTER</div>
  <div class=box style="right:70px;top:90px;width:760px;height:120px;font-size:46px">lava golem + hammer<span class=cur></span></div>
  <div class=logo style="right:70px;bottom:50px;font-size:96px;text-align:right">PROMPT<br>FIGHTERS</div>`],
 thumb_999_percent: [1920,1080,`<div class=bg style="background-image:url(${img("clash.png")})"></div>
  <div class=lines style="--cx:56%;--cy:40%"></div><div class=burst style="left:810px;top:180px;width:520px;height:520px"></div><div class=vig></div>
  <div class="big red" style="right:60px;bottom:40px;font-size:330px">999%</div>
  <div class=tag style="left:80px;top:70px;font-size:80px">SMASH!</div>
  <div class=logo style="left:70px;bottom:60px;font-size:72px">PROMPT<br>FIGHTERS</div>`],
 thumb_16_fighters: [1920,1080,`<div class=bg style="background-image:url(${img("roster.png")})"></div><div class=vig></div>
  <div class=big style="left:0;right:0;text-align:center;top:40px;font-size:140px">16 FIGHTERS<span style="color:#ffd23f">.</span> 1 WINNER<span style="color:#ffd23f">.</span></div>
  <div class=logo style="left:0;right:0;text-align:center;bottom:50px;font-size:90px">PROMPT FIGHTERS</div>`],
 icon: [1024,1024,`<div class=bg style="background-image:url(${img("icon_bg.png")})"></div>
  <div style="position:absolute;inset:0;background:radial-gradient(circle at 50% 40%,transparent 40%,rgba(0,0,20,.7) 100%)"></div>
  <div class=box style="left:110px;right:110px;bottom:80px;height:150px;font-size:96px;justify-content:center;border-width:8px">PF<span class=cur></span></div>
  <div style="position:absolute;inset:0;border:18px solid #5ff2ff;border-radius:0;box-shadow:inset 0 0 60px #2fd8ff"></div>`],
 tiktok_vertical: [1080,1920,`<div class=bg style="background-image:url(${img("vert.png")})"></div><div class=vig></div>
  <div class=big style="left:60px;right:60px;top:110px;font-size:104px;text-align:center">I TYPED<br><span style="color:#ffb23f">"LAVA GOLEM"</span><br>AND GOT THIS</div>
  <div class=box style="left:90px;right:90px;bottom:420px;height:120px;font-size:50px">lava golem + hammer<span class=cur></span></div>
  <div class=logo style="left:0;right:0;text-align:center;bottom:150px;font-size:110px">PROMPT<br>FIGHTERS</div>
  <div style="position:absolute;left:0;right:0;bottom:70px;text-align:center;color:#fff;font:800 44px Inter;opacity:.9">jetzt auf Roblox</div>`],
 post_square: [1080,1080,`<div class=bg style="background-image:url(${img("hero_sq.png")})"></div><div class=vig></div>
  <div class=big style="left:0;right:0;text-align:center;top:60px;font-size:96px">TYPE ANY FIGHTER.<br><span style="color:#5ff2ff">FIGHT YOUR FRIENDS.</span></div>
  <div class=logo style="left:0;right:0;text-align:center;bottom:60px;font-size:100px">PROMPT FIGHTERS</div>`],
};
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
for (const [name, [w, h, body]] of Object.entries(pages)) {
  const tab = await browser.newPage({ viewport: { width: w, height: h } });
  await tab.setContent(`<!doctype html><html><head><style>:root{--w:${w}px;--h:${h}px}${base}</style></head><body>${body}</body></html>`);
  await tab.waitForTimeout(300);
  await tab.screenshot({ path: `${out}/${name}.png` });
  await tab.close(); console.log(name);
}
await browser.close();
