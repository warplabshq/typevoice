// One place for everything a rebrand touches. Text nodes with data-brand="key" fill from here.
window.SITE = {
  name: "Murmur",
  tagline: "Local dictation for Mac",
  company: "Priyam Ventures",
  email: "support@REPLACE-ME.example",     // support + privacy contact
  domain: "https://REPLACE-ME.example",    // where this site is hosted
  appStoreURL: "https://apps.apple.com/app/idREPLACE-ME",
  updated: "September 18, 2026",
  price: "One-time",         // e.g. "$19" once the App Store price is set
  priceNote: "purchase",     // e.g. "once, forever"
  jurisdiction: "India",
};
document.addEventListener("DOMContentLoaded", () => {
  for (const el of document.querySelectorAll("[data-brand]")) {
    const v = SITE[el.dataset.brand];
    if (v === undefined) continue;
    if (el.tagName === "A" && el.dataset.href !== undefined) el.href = v; else el.textContent = v;
  }
  for (const a of document.querySelectorAll("a[data-mail]")) { a.href = "mailto:" + SITE.email; a.textContent = SITE.email; }
  for (const a of document.querySelectorAll("a[data-store]")) a.href = SITE.appStoreURL;
  document.title = document.title.replace("Murmur", SITE.name);
  const y = document.querySelector("[data-year]"); if (y) y.textContent = new Date().getFullYear();
  // Hero pill: calm, voice-like bars on a canvas.
  const c = document.getElementById("wave");
  if (c) {
    const ctx = c.getContext("2d"), dpr = window.devicePixelRatio || 1;
    const W = 168, H = 40; c.width = W * dpr; c.height = H * dpr; c.style.width = W + "px"; c.style.height = H + "px"; ctx.scale(dpr, dpr);
    const n = 18, bw = 2.5, gap = 2; let disp = new Array(n).fill(0);
    function bands(t) { const out = []; const syl = (0.35 + 0.65 * Math.max(0, Math.sin(t * 4.2))) * (0.7 + 0.3 * Math.sin(t * 0.9));
      for (let b = 0; b < 10; b++) { const f = 0.55 + 0.45 * Math.sin(t * 2.7 + b * 1.1); out.push(Math.min(1, Math.max(0, (0.15 + 0.85 * syl * f) * (1 - b * 0.055)))); } return out; }
    function targets(bs) { const half = (n - 1) / 2, raw = []; for (let i = 0; i < n; i++) { const d = Math.abs(i - half) / half, pos = d * 9, lo = Math.floor(pos), hi = Math.min(lo + 1, 9), f = pos - lo; let v = bs[lo] * (1 - f) + bs[hi] * f; if (i % 2) v = v * 0.85 + bs[Math.min(hi + 1, 9)] * 0.15; raw.push(v); }
      const out = raw.slice(); for (let i = 1; i < n - 1; i++) out[i] = raw[i-1] * 0.25 + raw[i] * 0.5 + raw[i+1] * 0.25; return out; }
    let last = performance.now();
    function frame(now) { const dt = Math.min(0.05, (now - last) / 1000); last = now; const t = now / 1000, tg = targets(bands(t));
      const up = 1 - Math.pow(0.001, dt * 3.2), down = 1 - Math.pow(0.001, dt * 1.6);
      ctx.clearRect(0, 0, W, H); const total = n * (bw + gap) - gap; let x = (W - total) / 2; const half = (n - 1) / 2;
      for (let i = 0; i < n; i++) { disp[i] += (tg[i] - disp[i]) * (tg[i] > disp[i] ? up : down); const h = Math.max(2, disp[i] * H * 0.82);
        const edge = Math.abs(i - half) / half; ctx.fillStyle = `rgba(255,255,255,${0.95 - 0.3 * edge})`;
        ctx.beginPath(); ctx.roundRect(x, H / 2 - h / 2, bw, h, bw / 2); ctx.fill(); x += bw + gap; }
      requestAnimationFrame(frame); }
    requestAnimationFrame(frame);

    // Product loop: listen → type the sentence into the field → clear → repeat.
    const pill = c.parentElement, typed = document.getElementById("typed"), caret = document.getElementById("caret");
    const phrases = ["Can we move the launch review to Wednesday at 3? Wednesday works better for the design team.",
                     "Shipped the new export flow to VidAI. Two things to watch: cold start, and the retry logic.",
                     "Groceries: milk, eggs, bread. Also call the dentist on Monday."];
    let pi = 0;
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const keycap = document.getElementById("keycap");
    (async function loop() {
      while (true) {
        typed.textContent = ""; pill.classList.remove("done"); pill.style.width = "";
        keycap.classList.add("down");
        await sleep(3400);                                  // listening
        keycap.classList.remove("down");
        const text = phrases[pi++ % phrases.length];
        pill.classList.add("done");
        await sleep(350);
        for (let i = 1; i <= text.length; i++) { typed.textContent = text.slice(0, i); await sleep(text.length > 60 ? 22 : 28); }
        await sleep(3200);
        pill.classList.remove("done");
        await sleep(900);
      }
    })();
  }
  // Sticky header shadow.
  const hdr = document.querySelector("header.nav");
  if (hdr) { const onScroll = () => hdr.classList.toggle("scrolled", window.scrollY > 8); onScroll(); addEventListener("scroll", onScroll, { passive: true }); }
  // You say / you get: cycle real examples.
  const pair = document.getElementById("pair");
  if (pair) {
    const ex = [
      ["um so the launch is tuesday no wait wednesday and i think we're gonna need like two more days for QA", "The launch is Wednesday, and I think we're going to need two more days for QA."],
      ["send the invoice to priyam at vid ai for twenty twenty four q three, five thousand dollars", "Send the invoice to Priyam at VidAI for 2024 Q3, $5,000."],
      ["things to buy bullet milk bullet eggs bullet point bread new paragraph call the dentist monday", "Things to buy\n- Milk\n- Eggs\n- Bread\n\nCall the dentist Monday."],
      ["the the meeting was very very good, honestly it's it's the best one this quarter", "The meeting was very very good, honestly it's the best one this quarter."],
    ];
    const say = document.getElementById("say"), get = document.getElementById("get"); let i = 0;
    const show = () => { say.textContent = "“" + ex[i][0] + "”"; get.textContent = ex[i][1]; };
    show();
    setInterval(async () => { pair.classList.add("swap"); await new Promise(r => setTimeout(r, 600)); i = (i + 1) % ex.length; show(); pair.classList.remove("swap"); }, 6500);
  }
  // Mock window: dictations keep arriving, calmly.
  const list = document.querySelector("#mock .list");
  if (list) {
    const feed = [
      ["a1", "✉︎", "Mail", "Thanks for the intro, Maya. Happy to jump on a call Thursday afternoon if that works for you.", 19, 7],
      ["a2", "#", "Slack", "Merged the fix for the retry logic. Cold start on the older machines is down to about a second.", 18, 6],
      ["a3", "✎", "Notes", "Ideas for the talk: start with the demo, keep the slides to five, end on the privacy story.", 17, 6],
      ["a1", "✉︎", "Mail", "Can you send over the signed version by Friday? I'll countersign the same day.", 15, 5],
      ["a2", "#", "Slack", "Design review moved to 4. Bring the new export flow and the onboarding cards.", 14, 5],
    ];
    let fi = 0, minutes = 9 * 60 + 41;
    const wordsEl = document.querySelector('.tile b[data-count="24,310"]'), dictEl = document.querySelector('.tile b[data-count="893"]');
    let words = 24310, dicts = 893;
    setInterval(() => {
      const [cls, glyph, app, text, w, sec] = feed[fi++ % feed.length];
      minutes += 3; const h = Math.floor(minutes / 60), m = minutes % 60;
      const item = document.createElement("div"); item.className = "item arriving";
      item.innerHTML = `<span class="app ${cls}">${glyph}</span><div><p></p><small>${app} · ${h}:${String(m).padStart(2, "0")} AM · ${w} words · ${sec}s · ${180 + Math.round(Math.random() * 80)} ms</small></div>`;
      item.querySelector("p").textContent = text;
      list.prepend(item); requestAnimationFrame(() => item.classList.remove("arriving"));
      while (list.children.length > 3) list.lastElementChild.remove();
      if (wordsEl && wordsEl.dataset.done) { words += w; dicts += 1; wordsEl.textContent = words.toLocaleString(); dictEl.textContent = dicts.toLocaleString(); }
    }, 7000);
  }
  // Reveal on scroll, count-up numbers.
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: 0.12 });
  document.querySelectorAll(".reveal").forEach(el => io.observe(el));
  const co = new IntersectionObserver(es => es.forEach(e => { if (!e.isIntersecting) return; co.unobserve(e.target); countUp(e.target); }), { threshold: 0.4 });
  document.querySelectorAll("[data-count]").forEach(el => co.observe(el));
  function countUp(el) {
    const target = el.dataset.count, m = target.match(/^([\d,.]+)(.*)$/); if (!m) { el.textContent = target; return; }
    const isTime = /h .*m$/.test(target);
    if (isTime) { const [h, mm] = target.match(/(\d+)h (\d+)m/).slice(1).map(Number); const total = h * 60 + mm; const t0 = performance.now();
      (function step(now) { const p = Math.min(1, (now - t0) / 2200), e = 1 - Math.pow(1 - p, 3), v = Math.round(total * e); el.textContent = Math.floor(v / 60) + "h " + (v % 60) + "m"; if (p < 1) requestAnimationFrame(step); })(t0); return; }
    const num = parseFloat(m[1].replace(/,/g, "")), suffix = m[2], decimals = (m[1].split(".")[1] || "").length, t0 = performance.now();
    (function step(now) { const p = Math.min(1, (now - t0) / 2200), e = 1 - Math.pow(1 - p, 3), v = num * e;
      el.textContent = (decimals ? v.toFixed(decimals) : Math.round(v).toLocaleString()) + suffix; if (p < 1) requestAnimationFrame(step); else el.dataset.done = "1"; })(t0);
  }
});
