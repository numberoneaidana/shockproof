import { useState, useMemo, useEffect, useContext, createContext, useCallback } from "react";

/* ShockProof — website. Wire your FastAPI backend in BACKEND_URL. */

// ⚠️ your live Render URL
const BACKEND_URL = "https://shockproof.onrender.com";

// ────────────────────────────────────────────────────────────── Backend fetchers
async function apiFetch(path, opts = {}) {
  const res = await fetch(BACKEND_URL + path, {
    headers: { "Content-Type": "application/json", ...(opts.headers || {}) },
    ...opts,
  });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try { const j = await res.json(); if (j.detail) msg = j.detail; } catch {}
    throw new Error(msg);
  }
  return res.json();
}

function cadenceText(c) {
  const m = { weekly: "every week", biweekly: "every 2 weeks", semimonthly: "twice a month",
    monthly: "every month", quarterly: "every 3 months",
    semiannual: "twice a year", annual: "once a year" };
  return m[c] || c;
}

function daysUntil(isoStr) {
  if (!isoStr) return 30;
  try {
    const d = new Date(isoStr);
    if (isNaN(d)) return 30;
    return Math.max(0, Math.round((d - new Date()) / 864e5));
  } catch { return 30; }
}

// Full bootstrap: exchange → sync → profile + txs + risks
async function bootstrapBackend() {
  const ex = await apiFetch("/api/link/exchange", {
    method: "POST",
    body: JSON.stringify({
      public_token: "public-sandbox-mock",
      institution: "First Platypus Bank",
    }),
  });
  const accountId = ex.account_id;
  await apiFetch(`/api/accounts/${accountId}/sync?months=14`, { method: "POST" });

  const [profile, txs, riskList] = await Promise.all([
    apiFetch(`/api/accounts/${accountId}/profile`),
    apiFetch(`/api/accounts/${accountId}/transactions?limit=1000`).catch(() => ({ transactions: [] })),
    apiFetch("/api/risks").catch(() => ({ risks: [] })),
  ]);
  return { accountId, profile, txs, riskList };
}

// Backend profile → frontend data shape
function mapProfileToData(profile, transactions) {
  const b = profile.baseline || {};
  const PER = { weekly: 7, biweekly: 14, semimonthly: 15, monthly: 30, quarterly: 90, semiannual: 180, annual: 365 };
  const recurring = (profile.recurring || []).map((r) => ({
    label: r.merchant || r.label || "Recurring",
    amt: r.avg_amount,
    per: PER[r.cadence] || 30,
    cadence: cadenceText(r.cadence),
    next: daysUntil(r.next_expected),
    income: !!r.is_income,
    category: r.category || "Other",
    confidence: r.confidence ?? 0.8,
  }));

  const cutoff = Date.now() - 90 * 864e5;
  const totals = {};
  for (const t of transactions) {
    if (t.amount >= 0 || t.pending) continue;
    const td = new Date(t.date);
    if (isNaN(td) || td.getTime() < cutoff) continue;
    const cat = t.category === "Uncategorized" ? "Other" : (t.category || "Other");
    totals[cat] = (totals[cat] || 0) + (-t.amount);
  }
  const cats = Object.entries(totals)
    .map(([k, v]) => [k, v / 3])
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8);

  const rent = (profile.recurring || [])
    .filter((r) => !r.is_income && r.category === "Housing" && r.cadence === "monthly" && Math.abs(r.avg_amount) >= 400)
    .reduce((max, r) => Math.max(max, Math.abs(r.avg_amount)), 0) || null;

  return {
    d: {
      rec: recurring,
      tx: transactions,
      months: 14,
      p: {
        checking: b.liquid_balance || 0,
        income: b.monthly_income || 0,
        fixed: b.monthly_fixed || 0,
        vmean: b.monthly_variable_mean || 0,
        vstd: b.monthly_variable_std || 0,
        liquidBalance: b.liquid_balance || 0,
      },
      cats,
    },
    cash: Math.round(b.liquid_balance || 0),
    derived: {
      monthly_income: b.monthly_income || 0,
      monthly_fixed: b.monthly_fixed || 0,
      monthly_variable_mean: b.monthly_variable_mean || 0,
      rent,
    },
  };
}

function mapRisksFromBackend(riskList) {
  return (riskList.risks || []).map((r) => ({
    key: r.key,
    category: r.category || "Other",
    label: r.label,
    annualProbability: r.annual_probability,
    medianCost: r.median_cost,
    coverage: r.coverage,
    incomeLossFraction: r.income_loss_fraction,
    durationMonthsMean: r.duration_months_mean,
  }));
}

// ────────────────────────────────────────────────────────────── CSS
const CSS = `
@import url("https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800&display=swap");

html, body {
  margin: 0 !important;
  padding: 0 !important;
  background-color: #faf9ff !important;
  color: #1a1a3b !important;
  color-scheme: light !important;
}

.sp{--bg:#faf9ff;--tint:#f1eeff;--ink:#1a1a3b;--soft:rgba(26,26,59,.68);--violet:#6b5ce8;--coral:#ff5c7a;--mint:#5cdbad;--sun:#ffd64a;
 min-height:100vh;background:var(--bg);color:var(--ink);font-family:"Nunito","SF Pro Rounded",ui-rounded,system-ui,-apple-system,"Segoe UI",sans-serif;font-size:16px;font-weight:600;line-height:1.45;color-scheme:light !important;-webkit-font-smoothing:antialiased}
.sp *{box-sizing:border-box}
.sp h1, .sp h2, .sp h3, .sp p, .sp span, .sp b, .sp div { color: inherit; }
.sp header{position:sticky;top:0;z-index:5;background:#fff;border-bottom:2px solid var(--ink)}
.sp .bar1{max-width:1120px;margin:0 auto;padding:12px 24px;display:flex;align-items:center;gap:20px;flex-wrap:wrap}
.sp .logo{font-size:22px;font-weight:800;color:var(--violet);margin-right:auto;border:0;background:none;cursor:pointer;font-family:inherit}
.sp nav{display:flex;gap:4px;flex-wrap:wrap}
.sp nav button{border:0;background:none;padding:8px 14px;border-radius:99px;font-family:inherit;font-weight:700;font-size:15px;color:var(--ink);cursor:pointer}
.sp nav button:hover{background:var(--tint)}.sp nav .on{background:var(--violet);color:#fff}
.sp main{max-width:1120px;margin:0 auto;padding:36px 24px 64px}
.sp footer{border-top:2px solid var(--ink);padding:20px 24px;text-align:center;font-size:13px;color:var(--soft);background:#fff}
.sp h1{font-size:40px;margin:0 0 6px;font-weight:800;color:var(--ink)}.sp h2{font-size:20px;margin:0 0 8px;font-weight:800;color:var(--ink)}
.sp .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:26px 28px;align-items:stretch;padding:0 5px 5px 0}.sp .w2{grid-column:1/-1}
@media(max-width:480px){.sp .grid{grid-template-columns:1fr}.sp h1{font-size:30px}}
.sp .card{background:#fff;border:2px solid var(--ink);border-radius:22px;padding:20px;box-shadow:4px 5px 0 var(--ink);color:var(--ink)}
.sp .sm{font-size:13px;font-weight:600}.sp .mut{color:var(--soft)}.sp .b,.sp b{font-weight:800}.sp .big{font-size:56px;font-weight:800;line-height:1.1;color:var(--ink)}.sp .num{font-size:24px;font-weight:800;color:var(--ink)}
.sp hr{border:0;border-top:1.5px solid rgba(26,26,59,.2);margin:12px 0}
.sp .card>.row:first-child{margin-top:0}
.sp .row{display:flex;align-items:center;justify-content:space-between;gap:10px;margin:10px 0}
.sp .btn{display:block;width:100%;padding:15px;border:2px solid var(--ink);border-radius:18px;background:var(--violet);color:#fff;font-family:inherit;font-weight:700;font-size:17px;line-height:1.2;box-shadow:0 5px 0 var(--ink);cursor:pointer;margin:8px 0 12px;text-align:center}
.sp .btn:disabled{opacity:0.6;cursor:not-allowed}
.sp .btn:active:not(:disabled){transform:translateY(4px);box-shadow:0 1px 0 var(--ink)}.sp .btn.sun{background:var(--sun);color:var(--ink)}.sp .btn.wh{background:#fff;color:var(--ink)}
.sp .link{border:0;background:none;font-family:inherit;font-weight:700;font-size:14px;color:var(--ink);text-decoration:underline;cursor:pointer;padding:0}
.sp .pill{display:inline-block;padding:3px 10px;border:1.5px solid var(--ink);border-radius:99px;font-size:12px;font-weight:700;background:var(--sun);color:var(--ink);margin:8px 0 2px}
.sp .box{display:inline-flex;align-items:center;justify-content:flex-end;min-width:136px;gap:4px;padding:6px 10px;background:var(--tint);border:1.5px solid var(--ink);border-radius:12px;cursor:text}
.sp .box:focus-within{border:2.5px solid var(--violet);padding:5.5px 9.5px}
.sp .box input{width:84px;border:0;background:transparent !important;color:var(--ink) !important;font-family:inherit;font-weight:700;font-size:17px;text-align:right;outline:0}
.sp .pen{color:var(--violet);font-size:13px;font-weight:800}
.sp .q{width:22px;height:22px;border-radius:50%;border:0;background:var(--violet);color:#fff;font-weight:800;font-size:13px;cursor:pointer;vertical-align:middle}
.sp .callout{padding:14px;border:1.5px solid var(--ink);border-radius:16px;background:rgba(255,92,122,.22);margin-top:14px;color:var(--ink)}
.sp .ok{padding:10px;border-radius:12px;background:rgba(92,219,173,.5);margin:8px 0;font-weight:700;font-size:13px;color:var(--ink)}
.sp .inset{padding:14px;border:1.5px solid var(--ink);border-radius:16px;background:var(--tint);margin:10px 0;color:var(--ink)}
.sp .bar{display:flex;height:22px;border:2px solid var(--ink);border-radius:99px;overflow:hidden;margin:8px 0;background:var(--tint)}
.sp .dot{display:inline-block;width:12px;height:12px;border-radius:50%;border:1.5px solid var(--ink);margin-right:8px}
.sp .seg{display:flex;border:2px solid var(--ink);border-radius:12px;overflow:hidden;margin-bottom:12px;background:var(--tint)}
.sp .seg button{flex:1;padding:8px;border:0;background:none;color:var(--ink);font-family:inherit;font-weight:700;font-size:14px;cursor:pointer}.sp .seg .on{background:var(--violet);color:#fff}
.sp .stp{display:inline-flex;align-items:center;gap:8px}
.sp .stp button,.sp .x{width:32px;height:32px;border:1.5px solid var(--ink);border-radius:10px;background:#fff;color:var(--ink);font-size:18px;font-weight:800;cursor:pointer}
.sp .val{padding:5px 10px;background:#fff;border:1.5px solid var(--ink);border-radius:12px;font-weight:800;min-width:96px;text-align:center;color:var(--ink)}
.sp input[type=checkbox]{width:22px;height:22px;flex:none;accent-color:var(--violet);cursor:pointer;margin:0}
.sp .row>select{min-width:140px}
.sp .row>span:first-child,.sp .row>div:first-child{min-width:0}
.sp select,.sp .sel{padding:10px 12px;border:1.5px solid var(--ink);border-radius:12px;background:var(--tint);color:var(--ink) !important;font-family:inherit;font-weight:700;font-size:15px}
.sp select option{background:#fff;color:var(--ink)}
.sp select.add{width:100%;padding:14px;border:2px solid var(--ink);border-radius:18px;background:var(--sun);color:var(--ink);font-size:17px;box-shadow:0 5px 0 var(--ink);margin:8px 0 12px}
.sp .ov{position:fixed;inset:0;background:rgba(26,26,59,.45);display:flex;align-items:center;justify-content:center;padding:24px;z-index:9}
.sp .ov .card{max-width:560px;width:100%;max-height:88vh;overflow:auto}
.sp svg text{fill:var(--ink) !important;font-size:11px}
.sp .hero{display:grid;grid-template-columns:1.2fr .8fr;gap:40px;align-items:center;padding:40px 0 20px}
@media(max-width:800px){.sp .hero{grid-template-columns:1fr}}
.sp .hero h1{font-size:56px;line-height:1.05}.sp .tiles{display:grid;grid-template-columns:1fr 1fr;gap:14px}
.sp .tile-lbl{font-size:11px;font-weight:700;color:var(--soft);text-transform:uppercase;letter-spacing:.03em}
`;

// ────────────────────────────────────────────────────────────── Helpers
const usd = (n) => (n < 0 ? "-" : "") + "$" + Math.round(Math.abs(n)).toLocaleString("en-US");
const cu = (d) => { const a = Math.abs(d), s = d < 0 ? "-" : ""; return a >= 1e6 ? s + "$" + (a / 1e6).toFixed(1) + "M" : a >= 1e3 ? s + "$" + Math.round(a / 1e3) + "k" : s + "$" + Math.round(a); };
const compactUsd = cu;
const odds = (p) => p < 0.01 ? "Less than 1 in 100" : p >= 0.95 ? "Almost certain" : p >= 0.15 ? Math.round(p * 10) + " in 10" : "1 in " + Math.round(1 / p);
const headline = (p) => p < 0.01 ? "You are very unlikely to run out of cash." : p >= 0.95 ? "You will almost certainly run out of cash." : `There is a ${odds(p)} chance you run out of cash.`;
const hzText = (m) => m === 12 ? "a year" : m < 24 ? m + " months" : m % 12 === 0 ? m / 12 + " years" : m + " months";
const pctTxt = (x) => { const v = x * 100; return v > 0 && v < 1 ? "<1%" : Math.round(v) + "%"; };
const dayText = (n) => new Date(Date.now() + n * 864e5).toLocaleDateString("en-US", { month: "short", day: "numeric" });
const prettyDate = (s) => { try { return new Date(s).toLocaleDateString("en-US", { month: "short", day: "numeric" }); } catch { return s; } };

// ── Human-readable chart axis helpers
const axisUsd = (v) =>
  Math.abs(v) >= 1e6
    ? (v < 0 ? "-" : "") + "$" + (Math.abs(v) / 1e6).toFixed(1).replace(/\.0$/, "") + "M"
    : usd(v);

function yearTicks(totalMonths, lastIndex) {
  const y0 = new Date().getFullYear();
  const out = [{ i: 0, label: `Today (${y0})` }];
  if (totalMonths >= 12) {
    const step = totalMonths <= 24 ? 6 : totalMonths <= 72 ? 12 : 24;
    for (let m = step; m <= totalMonths; m += step) {
      out.push({
        i: Math.min(m, lastIndex),
        label: m % 12 === 0 ? String(y0 + m / 12) : `${m} mo`,
      });
    }
  } else if (totalMonths > 0) {
    out.push({ i: lastIndex, label: totalMonths === 1 ? "1 mo" : `${totalMonths} mo` });
  }
  return out;
}

// ────────────────────────────────────────────────────────────── Sample data
const SAMPLE_REC = [
  { label: "Paycheck", amt: 2100, per: 15, cadence: "twice a month", next: 5, income: true, category: "Income", confidence: 0.95 },
  { label: "Rent", amt: -1500, per: 30, cadence: "every month", next: 12, category: "Housing", confidence: 0.95 },
  { label: "Car payment", amt: -250, per: 30, cadence: "every month", next: 9, category: "Transport", confidence: 0.9 },
  { label: "Car insurance", amt: -140, per: 30, cadence: "every month", next: 17, category: "Insurance", confidence: 0.9 },
  { label: "Phone", amt: -80, per: 30, cadence: "every month", next: 21, category: "Utilities", confidence: 0.9 },
  { label: "Internet", amt: -60, per: 30, cadence: "every month", next: 15, category: "Utilities", confidence: 0.9 },
  { label: "Streaming", amt: -35, per: 30, cadence: "every month", next: 3, category: "Subscriptions", confidence: 0.85 },
  { label: "Gym", amt: -40, per: 30, cadence: "every month", next: 7, category: "Health", confidence: 0.85 },
];
const SAMPLE = {
  rec: SAMPLE_REC, tx: [], months: 0,
  p: { checking: 8500, income: 4200, vmean: 1100, vstd: 300, fixed: 2105, liquidBalance: 8500 },
  cats: [["Housing", 1500], ["Food", 520], ["Car and transport", 390], ["Shopping", 300], ["Fun", 180], ["Phone and internet", 140], ["Other", 175]],
};

const RISKS = [
  { key: "job", category: "Work", label: "Job loss", annualProbability: 0.06, medianCost: 0, coverage: 0, incomeLossFraction: 1, durationMonthsMean: 4 },
  { key: "hrs", category: "Work", label: "Hours cut", annualProbability: 0.08, medianCost: 0, coverage: 0, incomeLossFraction: 0.3, durationMonthsMean: 3 },
  { key: "med", category: "Health", label: "Medical bill", annualProbability: 0.15, medianCost: 2500, coverage: 0.7, incomeLossFraction: 0, durationMonthsMean: 0 },
  { key: "ill", category: "Health", label: "Long illness", annualProbability: 0.02, medianCost: 3000, coverage: 0.5, incomeLossFraction: 0.5, durationMonthsMean: 3 },
  { key: "fix", category: "Car", label: "Car repair", annualProbability: 0.3, medianCost: 900, coverage: 0, incomeLossFraction: 0, durationMonthsMean: 0 },
  { key: "crash", category: "Car", label: "Car accident", annualProbability: 0.05, medianCost: 5000, coverage: 0.8, incomeLossFraction: 0, durationMonthsMean: 0 },
  { key: "home", category: "Home", label: "Home or renters claim", annualProbability: 0.03, medianCost: 6000, coverage: 0.6, incomeLossFraction: 0, durationMonthsMean: 0 },
  { key: "pet", category: "Life", label: "Pet emergency", annualProbability: 0.1, medianCost: 1200, coverage: 0, incomeLossFraction: 0, durationMonthsMean: 0 },
];

// ────────────────────────────────────────────────────────────── Event templates
const EVENT_TEMPLATES = [
  { id: "transmission", kind: "bill", label: "Car transmission fails", blurb: "A surprise repair bill.", startMonth: 1,
    params: [
      { key: "amount", label: "Repair bill", unit: "$", value: 2200, min: 100, max: 30000, step: 100 },
      { key: "coverage", label: "Covered by insurance", unit: "%", value: 0, min: 0, max: 100, step: 5 },
    ] },
  { id: "medical", kind: "bill", label: "Surprise medical bill", blurb: "ER visit or procedure after insurance.", startMonth: 1,
    params: [
      { key: "amount", label: "Bill", unit: "$", value: 5000, min: 100, max: 100000, step: 250 },
      { key: "coverage", label: "Covered by insurance", unit: "%", value: 0, min: 0, max: 100, step: 5 },
    ] },
  { id: "jobloss", kind: "jobLoss", label: "Lose your job", blurb: "Paychecks stop. Lower the percent to model unemployment benefits.", startMonth: 1,
    params: [
      { key: "months", label: "Months without work", unit: "mo", value: 3, min: 1, max: 24, step: 1 },
      { key: "lost", label: "Income lost", unit: "%", value: 100, min: 10, max: 100, step: 10 },
    ] },
  { id: "rentup", kind: "rentUp", label: "Rent goes up", blurb: "Applied to the rent we detected in your bank history.", startMonth: 1,
    params: [{ key: "pct", label: "Increase", unit: "%", value: 10, min: 1, max: 50, step: 1 }] },
  { id: "baby", kind: "baby", label: "Have a baby", blurb: "Monthly costs plus delivery and gear. Edit to match your plan.", startMonth: 12,
    params: [
      { key: "monthly", label: "Extra cost per month", unit: "$", value: 1250, min: 0, max: 5000, step: 50 },
      { key: "upfront", label: "Up-front costs", unit: "$", value: 3000, min: 0, max: 20000, step: 250 },
    ] },
  { id: "car", kind: "car", label: "Replace the car", blurb: "We compute the loan payment from price, down payment and rate.", startMonth: 12,
    params: [
      { key: "price", label: "Price", unit: "$", value: 28000, min: 5000, max: 90000, step: 1000 },
      { key: "down", label: "Down payment", unit: "$", value: 4000, min: 0, max: 50000, step: 500 },
      { key: "apr", label: "Loan rate", unit: "%", value: 7, min: 0, max: 20, step: 0.5 },
      { key: "term", label: "Loan length", unit: "mo", value: 60, min: 12, max: 84, step: 12 },
      { key: "insurance", label: "Extra insurance per month", unit: "$", value: 60, min: 0, max: 400, step: 10 },
    ] },
  { id: "home", kind: "home", label: "Buy a home", blurb: "Mortgage plus upkeep, minus the rent you stop paying.", startMonth: 24,
    params: [
      { key: "price", label: "Price", unit: "$", value: 350000, min: 80000, max: 1500000, step: 10000 },
      { key: "downPct", label: "Down payment", unit: "%", value: 10, min: 3, max: 50, step: 1 },
      { key: "apr", label: "Mortgage rate", unit: "%", value: 6.5, min: 2, max: 12, step: 0.25 },
      { key: "years", label: "Loan length", unit: "yr", value: 30, min: 10, max: 30, step: 5 },
      { key: "upkeepPct", label: "Tax, insurance, upkeep per year", unit: "%", value: 1.5, min: 0, max: 4, step: 0.25 },
      { key: "closingPct", label: "Closing costs", unit: "%", value: 3, min: 0, max: 6, step: 0.5 },
    ] },
  { id: "raise", kind: "raise", label: "Raise or new job", blurb: "Applied to your detected monthly income.", startMonth: 6,
    params: [{ key: "pct", label: "Change in income", unit: "%", value: 10, min: -50, max: 100, step: 5 }] },
  { id: "custom", kind: "custom", label: "Custom event", blurb: "Anything else. Set months to 0 to make it permanent.", startMonth: 0,
    params: [
      { key: "monthly", label: "Extra cost per month", unit: "$", value: 0, min: -5000, max: 5000, step: 50 },
      { key: "oneTime", label: "One-time cost", unit: "$", value: 0, min: 0, max: 100000, step: 500 },
      { key: "months", label: "Lasts (0 = forever)", unit: "mo", value: 0, min: 0, max: 120, step: 1 },
    ] },
  { id: "caraccident", kind: "bill", label: "Car accident (your deductible)", blurb: "Insurance pays the rest. You pay the deductible.", startMonth: 1,
    params: [{ key: "amount", label: "Your deductible", unit: "$", value: 1000, min: 0, max: 10000, step: 250 }] },
  { id: "homeclaim", kind: "bill", label: "Home or renters claim (your deductible)", blurb: "Fire, theft or water damage. You pay the deductible.", startMonth: 1,
    params: [{ key: "amount", label: "Your deductible", unit: "$", value: 2500, min: 0, max: 20000, step: 250 }] },
];

// ────────────────────────────────────────────────────────────── Loan math
function pmt(principal, aprPct, months) {
  if (months <= 0 || principal <= 0) return 0;
  const r = aprPct / 1200;
  return r === 0 ? principal / months : principal * r / (1 - Math.pow(1 + r, -months));
}

// ────────────────────────────────────────────────────────────── Draft → API body
function draftToAPI(draft, ctx) {
  const v = (k) => draft.values[k] ?? draft.template.params.find((p) => p.key === k)?.value ?? 0;
  const label = draft.template.label;
  const month = draft.startMonth;
  const t = draft.template.kind;
  const inc = ctx.monthly_income || 0;
  const rent = ctx.rent || 0;
  switch (t) {
    case "baby":
      return { life: { label, month, duration_months: null, income_delta: 0, expense_delta: v("monthly"), one_time_cost: v("upfront") }, forced: null };
    case "car": {
      const loan = Math.max(0, v("price") - v("down"));
      const pay = pmt(loan, v("apr"), v("term"));
      return { life: { label, month, duration_months: v("term"), income_delta: 0, expense_delta: pay + v("insurance"), one_time_cost: v("down") }, forced: null };
    }
    case "home": {
      const price = v("price");
      const mortgage = pmt(price * (1 - v("downPct") / 100), v("apr"), v("years") * 12);
      const upkeep = (price * v("upkeepPct")) / 100 / 12;
      return { life: { label, month, duration_months: null, income_delta: 0, expense_delta: mortgage + upkeep - rent, one_time_cost: (price * (v("downPct") + v("closingPct"))) / 100 }, forced: null };
    }
    case "raise":
      return { life: { label, month, duration_months: null, income_delta: (inc * v("pct")) / 100, expense_delta: 0, one_time_cost: 0 }, forced: null };
    case "rentUp": {
      const base = rent || (ctx.monthly_fixed || 0) * 0.5;
      return { life: { label, month, duration_months: null, income_delta: 0, expense_delta: (base * v("pct")) / 100, one_time_cost: 0 }, forced: null };
    }
    case "jobLoss":
      return { life: null, forced: { key: "layoff", month, duration_months: v("months"), gross_cost: 0, coverage: 0, income_loss_fraction: v("lost") / 100 } };
    case "bill":
      return { life: null, forced: { key: "emergency_bill", month, duration_months: 1, gross_cost: v("amount"), coverage: v("coverage") / 100, income_loss_fraction: 0 } };
    case "custom": {
      const months = v("months");
      return { life: { label, month, duration_months: months > 0 ? months : null, income_delta: 0, expense_delta: v("monthly"), one_time_cost: v("oneTime") }, forced: null };
    }
    default:
      return { life: null, forced: null };
  }
}

function describeDraft(draft, ctx) {
  const r = draftToAPI(draft, ctx);
  if (r.life) {
    const l = r.life;
    const parts = [];
    const net = (l.income_delta || 0) - (l.expense_delta || 0);
    if (Math.abs(net) >= 1) {
      parts.push(`${net >= 0 ? "+" : "-"}${usd(Math.abs(net))} a month` + (l.duration_months ? ` for ${l.duration_months} months` : ""));
    }
    if (l.one_time_cost > 0) parts.push(`${usd(l.one_time_cost)} up front`);
    return parts.join(", ");
  }
  if (r.forced) {
    if (r.forced.key === "layoff") {
      const loss = (ctx.monthly_income || 0) * r.forced.income_loss_fraction;
      return `You lose ${usd(loss)} a month for ${r.forced.duration_months} months`;
    }
    return `${usd(r.forced.gross_cost * (1 - r.forced.coverage))} out of pocket`;
  }
  return "";
}

function fmtParam(value, unit) {
  switch (unit) {
    case "$": return usd(value);
    case "%": return (value === Math.round(value) ? value : value.toFixed(2)) + "%";
    case "mo": return Math.round(value) + " mo";
    case "yr": return Math.round(value) + " yr";
    default: return String(Math.round(value));
  }
}

async function apiSim(body) {
  const res = await fetch(`${BACKEND_URL}/api/simulate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Simulate failed (HTTP ${res.status})`);
  return res.json();
}

async function apiStress(body) {
  const res = await fetch(`${BACKEND_URL}/api/stress-test`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Stress-test failed (HTTP ${res.status})`);
  return res.json();
}

function userToSnake(u) {
  return {
    age: u.age,
    state: u.state,
    housing: u.housing,
    employment: u.employment,
    married: u.married,
    children: u.children,
    has_pets: u.hasPets,
    owns_car: u.ownsCar,
    can_birth: u.canBirth,
  };
}

function buildSimRequest({ accountId, horizon, nPaths, startingBalance, random, excluded, lifeEvents, forcedEvents, user, seed = 42 }) {
  return {
    account_id: accountId || "demo",
    horizon_months: horizon,
    n_paths: nPaths,
    seed,
    starting_balance: startingBalance,
    risk_keys: random ? null : [],
    exclude_risk_keys: Array.from(excluded),
    life_events: lifeEvents,
    forced_events: forcedEvents,
    ruin_floor: 0,
    profile: userToSnake(user),
  };
}

function fanRowsFromResponse(sim) {
  const f = sim.fan_chart;
  if (!f || !f.months) return [];
  return f.months.map((_, i) => [f.p5[i], f.p25[i], f.p50[i], f.p75[i], f.p95[i]]);
}

// ────────────────────────────────────────────────────────────── Help / Guide / Glossary
const FIELD_HELP = {
  "Starting cash": "The money we start the simulation with: checking plus savings you can spend today. Locked deposits are not included. You can also change it on the Foundation tab.",
  "Savings balance": "Money in savings that you can use today without a penalty. It counts as cash.",
  "Savings interest (APY)": "What your savings pays per year. APY just means yearly interest. You can find it in your bank's app.",
  "Locked deposit / CD": "Money your bank holds until a set date (a CD). We don't count it as cash, because taking it out early costs a penalty.",
  "Deposit rate (APY)": "The yearly interest your locked deposit earns.",
  "Early-withdrawal penalty": "The fee for taking a locked deposit out early, counted in months of interest. It's written in your deposit agreement.",
  "Car insurance deductible": "What you pay first when you make a claim. Insurance covers the rest. It's on your policy.",
  "Home / renters deductible": "What you pay first when you make a claim. Insurance covers the rest. It's on your policy.",
  "I have a mortgage": "Turn this on if you own your home with a loan. It adds homeowner risks, like big repairs.",
  "Your overall risk": "We replay your money through thousands of possible futures. This is how many of them hit zero cash. It's not a prediction. It shows how well your cash handles bad luck.",
  "Most likely cash": "The middle result of all the futures we tried. Half end with more cash than this, half with less.",
  "Replace the sample data": "The app starts with demo transactions. Turn this on so your own statement replaces them.",
};

const GUIDE_STEPS = [
  ["Add your money data", "Go to Accounts and add a statement from your bank (PDF or CSV). We read every transaction, skip duplicates, and ignore transfers between your own accounts.", ["Turn on \"Replace the sample data\" the first time, so demo numbers don't mix with yours.", "More months means better detection. One month finds almost no recurring bills.", "Scanned PDFs can't be read. Download the text-based PDF or the CSV from your bank's website."]],
  ["Check what we read", "On the Accounts tab, \"What we read from your files\" shows how many transactions were parsed, the date range, and a few recent rows. The Foundation tab shows the paychecks, bills and subscriptions we found automatically.", ["If a paycheck or your rent is missing, add an older statement.", "If amounts look flipped, re-export the CSV from your bank.", "Your starting cash is editable on the Foundation tab."]],
  ["Add what a bank feed can't see", "Savings balance and rate, a locked deposit or CD, and your insurance deductibles are not in your transactions. Add them on the Accounts tab.", ["A locked deposit is not counted as cash, but it can show up as a last-resort rescue step.", "Deductibles decide how much a car or home claim costs you.", "Turn on \"I have a mortgage\" so homeowner risks apply to you."]],
  ["Choose what could go wrong", "On the Futures tab, add life events and shocks, tell us about yourself, and pick how far ahead to look. The \"random risks of life\" switch adds everyday shocks on top.", ["\"About you\" decides which risks apply.", "Each event has a start month. Try the same event earlier and later and compare."]],
  ["Read your odds", "Tap \"Simulate my future\". The headline says how often your cash runs out across thousands of simulated futures.", ["The odds are not a forecast. They show how well your cash absorbs bad luck.", "Switch between \"Today's path\", \"With events\" and \"With plan\" to see what changes."]],
  ["Fix it", "The rescue plan lists fixes from easiest to hardest. Each one is simulated again, so you see the real risk after it.", ["Cancelled subscriptions and a better savings rate are the easy wins.", "Gig pay and the 4.5% savings rate are assumptions, and the app says so."]],
];

const GLOSSARY = [
  ["Starting cash", FIELD_HELP["Starting cash"]],
  ["Risk of running out of cash", FIELD_HELP["Your overall risk"]],
  ["How far ahead", "The length of the future we simulate: 1, 3, 5 or 10 years. Longer windows give more time for a bad shock to land."],
  ["Life events", "Things you choose to add: a baby, a new car, a home, a raise, a job loss. Each one changes your monthly income or costs from the month you pick."],
  ["Random risks", "Ordinary-life shocks like car repairs, medical bills, layoffs and storms, each with a realistic chance and cost."],
  ["Fan chart", "The dark line is the most likely path of your cash. The darker band covers the middle half of outcomes and the lighter band covers nearly all of them. The dashed red line is zero: if the shaded area dips below it, some futures run out of cash."],
  ["Worst-case cash", "A bad-luck outcome: only about 1 in 20 simulated futures ends with less cash than this."],
  ["Rescue plan", "A list of fixes, cheapest first. Each step is re-simulated, so the risk shown after it is real."],
  ["Cash cushion", "How much starting cash would bring your risk down to the target."],
  ["APY", "Annual percentage yield: the interest an account pays per year, including compounding."],
  ["Locked deposit / CD", "A deposit you agreed not to touch until a set date in exchange for a higher rate."],
  ["Deductible", "The part of an insurance claim you pay yourself before the insurer pays the rest."],
  ["Assumptions", "Gig pay of $110 per shift and a 4.5% savings rate are assumptions used in the rescue plan."],
];

// ────────────────────────────────────────────────────────────── React context
const Ctx = createContext();
const useApp = () => useContext(Ctx);

const Card = ({ children, style, cls = "" }) => <section className={"card " + cls} style={style}>{children}</section>;
const Title = ({ t, sub }) => <div style={{ marginBottom: 26 }}><h1>{t}</h1><div className="mut">{sub}</div></div>;
const HelpBtn = ({ title }) => {
  const a = useApp();
  const text = FIELD_HELP[title];
  if (!text) return null;
  return <button className="q" aria-label={`What is ${title}?`} onClick={() => a.setModal({ title, text })}>?</button>;
};
const Seg = ({ options, value, onChange }) => (
  <div className="seg">{options.map(([v, l]) => <button key={v} className={v === value ? "on" : ""} onClick={() => onChange(v)}>{l}</button>)}</div>
);
const Stepper = ({ text, onStep }) => (
  <span className="stp"><button onClick={() => onStep(-1)} aria-label="less">−</button><span className="val">{text}</span><button onClick={() => onStep(1)} aria-label="more">+</button></span>
);
const Tog = ({ label, helpKey, v, on }) => (
  <label className="row b"><span>{label} {helpKey && <HelpBtn title={helpKey} />}</span><input type="checkbox" checked={v} onChange={(e) => on(e.target.checked)} /></label>
);
const Tile = ({ t, v, c }) => (
  <div><div className="tile-lbl">{t}</div><div className="num" style={{ color: c }}>{v}</div></div>
);

function NumField({ title, value, onChange, pre = "$", suf = "" }) {
  const [txt, setTxt] = useState(String(value));
  useEffect(() => setTxt(String(value)), [value]);
  return (
    <div className="row">
      <span>{title} <HelpBtn title={title} /></span>
      <label className="box">
        {pre && <span className="mut">{pre}</span>}
        <input inputMode="decimal" value={txt} onChange={(e) => setTxt(e.target.value)}
          onBlur={() => onChange(parseFloat(txt.replace(/,/g, "")) || 0)}
          onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()} />
        {suf && <span className="mut">{suf}</span>}<span className="pen">✎</span>
      </label>
    </div>
  );
}

// ── Human-readable chart: dollars on the y-axis, calendar years on the x-axis
function Chart({
  rows,
  months,
  labelHi,
  yFmt = axisUsd,
  yTitle = "Cash in the bank",
  xTitle = "Time from today",
  xTicks: xTicksProp,
  showZeroLine = true,
}) {
  if (!rows || !rows.length) return <div className="sm mut">No chart data yet.</div>;
  const W = 560, H = 290, mL = 78, mR = 18, mT = 30, mB = 48;
  const L = rows.length - 1;
  const lo = Math.min(0, ...rows.map((r) => r[0]));
  const hi = Math.max(1, ...rows.map((r) => r[4]));
  const X = (i) => mL + (i / Math.max(L, 1)) * (W - mL - mR);
  const Y = (v) => mT + (1 - (v - lo) / Math.max(hi - lo, 1e-9)) * (H - mT - mB);
  const band = (a, b) =>
    "M" + rows.map((r, i) => X(i) + "," + Y(r[a])).join("L") +
    "L" + [...rows].reverse().map((r, i) => X(L - i) + "," + Y(r[b])).join("L") + "Z";

  const yTicks = [hi, hi / 2, 0];
  if (lo < 0) yTicks.push(lo);
  const ticks = xTicksProp || yearTicks(months ?? L, L);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label={labelHi || "Your cash over time"}>
      {yTicks.map((v, i) => (
        <line key={"h" + i} x1={mL} x2={W - mR} y1={Y(v)} y2={Y(v)} stroke="rgba(26,26,59,.12)" strokeWidth="1" />
      ))}
      {ticks.map((t, i) => (
        <line key={"v" + i} x1={X(t.i)} x2={X(t.i)} y1={mT} y2={H - mB} stroke="rgba(26,26,59,.07)" strokeWidth="1" />
      ))}
      <path d={band(0, 4)} fill="#6b5ce8" opacity=".16" />
      <path d={band(1, 3)} fill="#6b5ce8" opacity=".34" />
      {showZeroLine && (
        <line x1={mL} x2={W - mR} y1={Y(0)} y2={Y(0)} stroke="#ff5c7a" strokeWidth="2" strokeDasharray="6 4" />
      )}
      <polyline fill="none" stroke="#1a1a3b" strokeWidth="3" points={rows.map((r, i) => X(i) + "," + Y(r[2])).join(" ")} />
      <text x={0} y={14} style={{ fontWeight: 800 }}>{yTitle}</text>
      <text x={mL + (W - mL - mR) / 2} y={H - 4} textAnchor="middle">{xTitle}</text>
      {yTicks.map((v, i) => (
        <text key={"yl" + i} x={mL - 8} y={Y(v) + 4} textAnchor="end">{yFmt(v)}</text>
      ))}
      {ticks.map((t, i) => (
        <text key={"xl" + i} x={X(t.i)} y={H - mB + 15}
          textAnchor={i === 0 ? "start" : t.i >= L ? "end" : "middle"}>{t.label}</text>
      ))}
    </svg>
  );
}

// ────────────────────────────────────────────────────────────── Welcome
function Welcome() {
  const a = useApp();
  return (
    <>
      <div className="hero">
        <div>
          <div className="b" style={{ color: "var(--violet)", fontSize: 20 }}>ShockProof</div>
          <h1>What if next month goes wrong?</h1>
          <p style={{ fontSize: 20 }}>
            Link your bank. We find your paychecks, bills and habits on our own,
            then replay your money through thousands of possible futures.
          </p>
          <div style={{ maxWidth: 360 }}>
            <button className="btn" onClick={a.connect} disabled={a.connecting}>
              {a.connecting ? "Linking & syncing (up to 30 s)…" : "Link bank account"}
            </button>
          </div>
          {a.connectError && (
            <div className="sm" style={{ color: "var(--coral)", marginTop: 8 }}>
              {a.connectError}
            </div>
          )}
          <div className="sm mut">
            First call wakes the free-tier backend — give it ~30 s.
          </div>
        </div>
        <div style={{ position: "relative", height: 280 }}>
          <div style={{ position: "absolute", right: 0, top: 0, width: 220, height: 220, borderRadius: "50%", background: "var(--sun)", border: "2px solid var(--ink)" }} />
          <div style={{ position: "absolute", left: 20, bottom: 0, width: 120, height: 120, borderRadius: "50%", background: "var(--coral)", border: "2px solid var(--ink)" }} />
        </div>
      </div>
      <div className="grid">
        {[["Found for you", "Paychecks, bills and subscriptions, found from merchant names, amounts and dates."],
          ["Thousands of futures", "Your money replayed through job loss, medical bills and car trouble."],
          ["A plan to fix it", "Fixes from easiest to hardest, each one tested again."]].map(([t, s]) => (
          <Card key={t}><h2>{t}</h2><div>{s}</div></Card>
        ))}
      </div>
    </>
  );
}

// ────────────────────────────────────────────────────────────── Foundation
function Foundation() {
  const a = useApp();
  const { cash, setCash, holdings, d } = a;
  const p = d.p, net = p.income - p.fixed - p.vmean;
  const parts = [["var(--violet)", "Fixed bills", p.fixed], ["var(--sun)", "Everyday spending", p.vmean], ["var(--mint)", "Left over", Math.max(0, net)]];
  const inc = d.rec.filter((r) => r.income);
  const bills = d.rec.filter((r) => !r.income);
  const soon = d.rec.filter((r) => r.next <= 30).sort((x, y) => x.next - y.next);
  const maxCat = Math.max(1, ...d.cats.map((c) => c[1]));
  const Row = (r) => (
    <div className="row" key={r.label}>
      <div><b>{r.label}</b><div className="sm mut">{r.cadence}</div></div>
      <div style={{ textAlign: "right" }}>
        <b style={{ color: r.income ? "#0d8059" : "inherit" }}>{r.amt > 0 ? "+" : "-"}{usd(Math.abs(r.amt))}</b>
        <div className="sm mut">next {dayText(r.next)}</div>
      </div>
    </div>
  );
  return (
    <>
      <Title t="Your financial twin" sub={d.tx.length ? `Built from ${d.tx.length} transactions.` : "Built from sample bank data."} />
      <div className="grid">
        <Card style={{ background: net >= 0 ? "var(--mint)" : "var(--coral)", color: "#1a1a3b" }}>
          <div className="sm b">Left over each month</div>
          <div className="big">{usd(net)}</div>
          <hr />
          <div className="row">
            <div><div className="sm">Checking</div><b>{usd(p.checking)}</b></div>
            <div><div className="sm">Savings</div><b>{usd(holdings.savingsBalance)}</b></div>
            <div><div className="sm">Credit debt</div><b style={{ color: "var(--coral)" }}>$0</b></div>
          </div>
          <NumField title="Starting cash" value={cash} onChange={setCash} pre="$" />
        </Card>
        <Card>
          <h2>Where {usd(p.income)} a month goes</h2>
          <div className="bar">{parts.map((x) => <div key={x[1]} style={{ background: x[0], width: Math.max(0, x[2] / Math.max(p.income, 1)) * 100 + "%" }} />)}</div>
          {parts.map((x) => <div className="row" key={x[1]}><span><i className="dot" style={{ background: x[0] }} />{x[1]}</span><b>{usd(x[2])}</b></div>)}
          <div className="sm">Everyday spending swings by about {usd(p.vstd)} a month. The simulator replays that swing.</div>
        </Card>
        <Card>
          <h2>What we found in your bank</h2>
          <div className="sm mut">Found automatically from merchant names, amounts and dates.</div>
          {inc.length > 0 && <><span className="pill" style={{ background: "var(--mint)" }}>Paychecks</span>{inc.map(Row)}</>}
          {bills.length > 0 && <><span className="pill">Bills and subscriptions</span>{bills.map(Row)}</>}
        </Card>
        <Card>
          <h2>Where your money goes</h2>
          <div className="sm mut">Average per month.</div>
          {d.cats.map(([n, v]) => (
            <div key={n} style={{ margin: "10px 0" }}>
              <div className="row" style={{ margin: 0 }}><span>{n}</span><b>{usd(v)}</b></div>
              <div className="bar" style={{ height: 12 }}><div style={{ background: "var(--violet)", width: (v / maxCat) * 100 + "%" }} /></div>
            </div>
          ))}
        </Card>
        <Card cls="w2">
          <h2>Coming up in the next 30 days</h2>
          {!soon.length && <div className="sm">Nothing scheduled that we are confident about.</div>}
          {soon.map((r) => (
            <div className="row" key={r.label}>
              <span className="b" style={{ width: 60 }}>{dayText(r.next)}</span>
              <span style={{ flex: 1 }}>{r.label}</span>
              <b>{r.amt > 0 ? "+" : "-"}{usd(Math.abs(r.amt))}</b>
            </div>
          ))}
        </Card>
      </div>
      <p><button className="link" onClick={() => a.setConnected(false)}>Unlink bank</button></p>
    </>
  );
}

// ────────────────────────────────────────────────────────────── DraftEditor
function DraftEditor({ draft, onChange, onRemove, horizon }) {
  const a = useApp();
  const ctx = a.derived;
  const setValue = (key, v) => onChange({ ...draft, values: { ...draft.values, [key]: v } });
  const setStart = (m) => onChange({ ...draft, startMonth: Math.max(0, Math.min(horizon - 1, m)) });
  const desc = describeDraft(draft, ctx);
  return (
    <div className="inset">
      <div className="row" style={{ marginTop: 0 }}>
        <h2 style={{ margin: 0 }}>{draft.template.label}</h2>
        <button className="x" aria-label="Remove" onClick={onRemove}>✕</button>
      </div>
      <div className="sm mut" style={{ marginBottom: 8 }}>{draft.template.blurb}</div>
      <div className="row">
        <span>Starts in</span>
        <Stepper text={draft.startMonth === 0 ? "now" : draft.startMonth + " months"} onStep={(x) => setStart(draft.startMonth + x)} />
      </div>
      {draft.template.params.map((prm) => {
        const cur = draft.values[prm.key] ?? prm.value;
        return (
          <div className="row" key={prm.key}>
            <span>{prm.label}</span>
            <Stepper
              text={fmtParam(cur, prm.unit)}
              onStep={(x) => setValue(prm.key, Math.max(prm.min, Math.min(prm.max, cur + x * prm.step)))}
            />
          </div>
        );
      })}
      {desc && <span className="pill">{desc}</span>}
    </div>
  );
}

// ────────────────────────────────────────────────────────────── EventsCard
function EventsCard() {
  const a = useApp();
  const [selected, setSelected] = useState("");
  const add = (id) => {
    const t = EVENT_TEMPLATES.find((x) => x.id === id);
    if (!t) return;
    const draft = { id: Date.now() + Math.random(), template: t, startMonth: Math.min(t.startMonth, Math.max(0, a.horizon - 1)), values: {} };
    if (t.id === "caraccident") draft.values.amount = a.holdings.autoDeductible;
    if (t.id === "homeclaim") draft.values.amount = a.holdings.homeDeductible;
    a.setDrafts([...a.drafts, draft]);
  };
  return (
    <Card>
      <h2>Life events and shocks</h2>
      {!a.drafts.length && <div className="sm">Nothing added yet. The simulation will only use the random risks of normal life.</div>}
      {a.drafts.map((d) => (
        <DraftEditor
          key={d.id}
          draft={d}
          horizon={a.horizon}
          onChange={(nd) => a.setDrafts(a.drafts.map((x) => (x.id === d.id ? nd : x)))}
          onRemove={() => a.setDrafts(a.drafts.filter((x) => x.id !== d.id))}
        />
      ))}
      <select className="add" aria-label="Add an event" value={selected} onChange={(e) => { add(e.target.value); setSelected(""); }}>
        <option value="">Add an event…</option>
        {EVENT_TEMPLATES.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
      </select>
    </Card>
  );
}

// ────────────────────────────────────────────────────────────── AboutYouCard
function AboutYouCard() {
  const a = useApp();
  const u = a.user;
  const set = (k) => (v) => a.setUser({ ...u, [k]: v });
  const F = (l, el) => <div className="row"><span>{l}</span>{el}</div>;
  return (
    <Card>
      <details>
        <summary style={{ cursor: "pointer" }}>
          <b style={{ fontSize: 20 }}>About you</b>
          <div className="sm">Decides which of the {a.risks.length} risks apply: hurricanes need a coastal state, pets need pets.</div>
        </summary>
        <div style={{ marginTop: 10 }}>
          {F("Age", <Stepper text={u.age} onStep={(x) => set("age")(Math.max(18, Math.min(80, u.age + x)))} />)}
          {F("State", (
            <select value={u.state} onChange={(e) => set("state")(e.target.value)}>
              {US_STATES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          ))}
          {F("Housing", (
            <select value={u.housing} onChange={(e) => set("housing")(e.target.value)}>
              <option value="rent">Renting</option>
              <option value="own_house">Own a house</option>
              <option value="own_condo">Own a condo</option>
              <option value="with_parents">With family</option>
            </select>
          ))}
          {F("Work", (
            <select value={u.employment} onChange={(e) => set("employment")(e.target.value)}>
              <option value="employed">Employed</option>
              <option value="self">Self-employed</option>
              <option value="gig">Gig work</option>
            </select>
          ))}
          <Tog label="Married" v={u.married} on={set("married")} />
          {F("Children", <Stepper text={u.children} onStep={(x) => set("children")(Math.max(0, Math.min(6, u.children + x)))} />)}
          <Tog label="Pets" v={u.hasPets} on={set("hasPets")} />
          <Tog label="Own a car" v={u.ownsCar} on={set("ownsCar")} />
          <Tog label="Could have a child" v={u.canBirth} on={set("canBirth")} />
        </div>
      </details>
    </Card>
  );
}

const US_STATES = ["AK","AL","AR","AZ","CA","CO","CT","DC","DE","FL","GA","HI","IA","ID","IL","IN","KS","KY","LA","MA","MD","ME","MI","MN","MO","MS","MT","NC","ND","NE","NH","NJ","NM","NV","NY","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VA","VT","WA","WI","WV","WY"];

// ────────────────────────────────────────────────────────────── SettingsCard
function SettingsCard() {
  const a = useApp();
  return (
    <Card>
      <h2>How far ahead</h2>
      <Seg
        options={[[12, "1 yr"], [36, "3 yrs"], [60, "5 yrs"], [120, "10 yrs"]]}
        value={a.horizon}
        onChange={a.setHorizon}
      />
      <Tog label="Include the random risks of life" v={a.randomRisks} on={a.setRandomRisks} />
      <div className="sm">
        {a.randomRisks
          ? `Up to ${Math.max(0, a.risks.length - a.excluded.size)} risk types run together. Change them in the Risks tab.`
          : "Only your events and your normal month-to-month swings."}
      </div>
    </Card>
  );
}

// ────────────────────────────────────────────────────────────── Results cards
function HeadlineCard({ baseline, scenario, cash }) {
  const p = scenario.summary.probability_of_ruin;
  const bad = p > 0.3;
  const mo = scenario.summary.median_months_to_ruin;
  return (
    <Card>
      <div className="row" style={{ justifyContent: "flex-start", gap: 14, alignItems: "flex-start" }}>
        <span style={{ fontSize: 40, color: bad ? "var(--coral)" : "#2fb98a" }}>{bad ? "⚠" : "✔"}</span>
        <div>
          <div className="sm b mut">Your overall risk <HelpBtn title="Your overall risk" /></div>
          <div className="num" style={{ fontSize: 30 }}>{headline(p)}</div>
        </div>
      </div>
      <hr />
      <div className="row" style={{ alignItems: "flex-start" }}>
        <div>
          <div className="tile-lbl">Most likely cash in {hzText(scenario.summary.horizon_months)} <HelpBtn title="Most likely cash" /></div>
          <div className="num">{usd(scenario.summary.median_end_balance)}</div>
        </div>
      </div>
      {mo != null && (
        <div className="callout">
          <h2 style={{ margin: "0 0 4px", fontSize: 18 }}>Danger zone: month {mo + 1}</h2>
          <div>In the futures that go wrong, cash usually runs out around month {mo + 1}. Your {usd(cash)} cushion is too small for a shock like a job loss.</div>
        </div>
      )}
    </Card>
  );
}

function ChartCard({ baseline, scenario, rescueLast }) {
  const [mode, setMode] = useState(1);
  const shown = mode === 0 ? baseline : (mode === 2 && rescueLast ? rescueLast : scenario);
  const opts = [[0, "Today's path"], [1, "With events"]];
  if (rescueLast) opts.push([2, "With plan"]);
  const months = shown.summary?.horizon_months ?? Math.max(0, (shown.fan_chart?.months?.length || 1) - 1);
  return (
    <Card cls="w2">
      {rescueLast && <Seg options={opts} value={mode} onChange={setMode} />}
      <h2>{mode === 0 ? "Your cash if nothing changes" : mode === 2 ? "Your cash with the rescue plan" : "Your cash with your events"}</h2>
      <div className="sm mut" style={{ marginBottom: 6 }}>
        One point per month. The dark line is the middle of 3,000 possible futures; the shaded bands show where the rest land.
      </div>
      <Chart
        rows={fanRowsFromResponse(shown)}
        months={months}
        labelHi="Your cash balance over time, with the range of possible outcomes"
      />
      <div className="row" style={{ justifyContent: "flex-start", gap: 16, flexWrap: "wrap" }}>
        <span className="sm"><i className="dot" style={{ background: "var(--ink)" }} />Most likely cash</span>
        <span className="sm"><i className="dot" style={{ background: "rgba(107,92,232,.5)" }} />Half of futures land here</span>
        <span className="sm"><i className="dot" style={{ background: "rgba(107,92,232,.22)" }} />9 in 10 land here</span>
        <span className="sm"><i className="dot" style={{ background: "var(--coral)" }} />$0: out of cash</span>
      </div>
      <div className="sm">
        If the shaded area ever drops below the red line, some futures run out of cash. The further below it goes, the more of them do.
      </div>
    </Card>
  );
}

function NumbersCard({ s }) {
  return (
    <Card>
      <h2>The numbers behind it</h2>
      <div className="tiles">
        <Tile t={`Most likely cash in ${hzText(s.horizon_months)}`} v={compactUsd(s.median_end_balance)} />
        <Tile t="Worst-case cash (1 in 20)" v={compactUsd(s.p5_end_balance)} c={s.p5_end_balance < 0 ? "#d6264a" : undefined} />
        <Tile t="Average cost of shocks" v={compactUsd(s.expected_total_shock_cost)} />
        <Tile t="Monthly savings" v={compactUsd(s.monthly_net_mean)} c="#0d8059" />
      </div>
    </Card>
  );
}

function DriversCard({ sim }) {
  const drivers = (sim.top_drivers || [])
    .filter((d) => (d.delta_ruin || 0) > 0.005)
    .slice(0, 6);
  return (
    <Card>
      <h2>Random risks that hurt most on top of this</h2>
      <div className="sm mut">
        {(sim.risk_attribution || []).length} risk types simulated together. Layoffs cluster with recessions, storms with property damage.
      </div>
      {!drivers.length && <div className="sm">No single risk moves the odds much. Your cushion is doing its job.</div>}
      {drivers.map((d) => (
        <div key={d.key} style={{ margin: "10px 0" }}>
          <div className="row" style={{ margin: 0 }}>
            <span>{d.label}</span>
            <b>+{Math.round((d.delta_ruin || 0) * 100)} pts</b>
          </div>
          <div className="bar" style={{ height: 12 }}>
            <div style={{ background: "var(--coral)", width: Math.min(100, (d.delta_ruin || 0) * 100) + "%" }} />
          </div>
          <div className="sm">{pctTxt(d.p_occurs_in_horizon)} chance it happens in this window</div>
        </div>
      ))}
    </Card>
  );
}

function RescueCard({ scenario }) {
  const a = useApp();
  const { rescueSteps, rescuing, rescueAchieved, rescueTarget } = a;
  return (
    <Card cls="w2">
      <h2>Your rescue plan</h2>
      {rescuing && <div className="row"><span className="sm">Testing fixes against the simulator…</span></div>}
      {!rescuing && !rescueSteps.length && (
        <div>{rescueAchieved ? "Your risk is already close to normal. No rescue needed." : "No fixes found."}</div>
      )}
      {!rescuing && rescueSteps.length > 0 && (
        <>
          <div className="sm mut">Cheapest fixes first. Each one is re-simulated, so the risk shown after it is real.</div>
          {rescueSteps.map((s) => (
            <div className="inset" key={s.title}>
              <div className="row" style={{ margin: 0 }}>
                <b>{s.title}</b>
                <span className="pill" style={{ margin: 0, background: "var(--mint)" }}>
                  {s.group === "cd" ? `+${usd(s.monthly)} once` : `+${usd(s.monthly)}/mo`}
                </span>
              </div>
              <div className="sm">{s.detail}</div>
              <div className="row" style={{ justifyContent: "flex-start", gap: 10 }}>
                <span className="pill" style={{ margin: 0, background: s.pain === "Easy" ? "var(--mint)" : s.pain === "Medium" ? "var(--sun)" : "var(--coral)" }}>{s.pain}</span>
                <span className="sm b">Risk after: {pctTxt(s.ruinAfter)}</span>
              </div>
            </div>
          ))}
          <hr />
          <div className="row">
            <div><div className="num" style={{ color: "var(--coral)", fontSize: 40 }}>{pctTxt(scenario.summary.probability_of_ruin)}</div><div className="sm">risk now</div></div>
            <div className="b" style={{ fontSize: 18 }}>to</div>
            <div style={{ textAlign: "right" }}><div className="num" style={{ fontSize: 40 }}>{pctTxt(rescueSteps[rescueSteps.length - 1].ruinAfter)}</div><div className="sm">with this plan</div></div>
          </div>
          {!rescueAchieved && <div className="sm" style={{ color: "var(--coral)" }}>Cuts and extra income alone can't absorb this. Your target is {pctTxt(rescueTarget)}.</div>}
          <div className="sm">Gig pay and the 4.5% savings rate are assumptions. Everything else comes from your bank history.</div>
        </>
      )}
      <CushionView scenario={scenario} />
    </Card>
  );
}

function CushionView({ scenario }) {
  const a = useApp();
  if (!a.cushion.length) return null;
  const cs = a.cushion;
  const step = Math.max(1, Math.ceil(cs.length / 3));
  const cushionTicks = cs
    .map((p, i) => ({ i, label: cu(p.balance) }))
    .filter((t, i) => i === 0 || i === cs.length - 1 || i % step === 0);
  return (
    <div style={{ marginTop: 14 }}>
      <hr />
      <h2 style={{ fontSize: 18 }}>Cash cushion</h2>
      {a.cushionNeeded != null
        ? <div className="sm b">About {usd(a.cushionNeeded)} in cash gets this scenario down to {pctTxt(a.rescueTarget)} risk. You have {usd(a.cash)}.</div>
        : <div className="sm b">Even {usd(cs[cs.length - 1]?.balance || 0)} in cash doesn't reach {pctTxt(a.rescueTarget)} risk here.</div>}
      <Chart
        rows={cs.map((p) => [p.ruin * 100, p.ruin * 100, p.ruin * 100, p.ruin * 100, p.ruin * 100])}
        labelHi="Chance of running out of cash at different starting balances"
        yFmt={(v) => Math.round(v) + "%"}
        yTitle="Chance you run out of cash"
        xTitle="Starting cash"
        showZeroLine={false}
        xTicks={cushionTicks}
      />
      <div className="sm">Each point is a different amount of starting cash, re-simulated by the backend. Further right means a bigger cushion; lower means safer.</div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────── Futures screen
function Futures() {
  const a = useApp();
  const { cash, user } = a;
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  const run = async () => {
    setBusy(true); setErr("");
    a.setRunning(true); a.setRescueSteps([]); a.setCushion([]); a.setCushionNeeded(null);
    try {
      const life = [];
      const forced = [];
      for (const draft of a.drafts) {
        const r = draftToAPI(draft, a.derived);
        if (r.life) life.push(r.life);
        if (r.forced) forced.push(r.forced);
      }
      const baseReq = buildSimRequest({
        accountId: a.accountId, horizon: a.horizon, nPaths: 3000,
        startingBalance: cash, random: a.randomRisks, excluded: a.excluded,
        lifeEvents: [], forcedEvents: [], user,
      });
      const scenReq = { ...baseReq, life_events: life, forced_events: forced };

      const [baseRes, scenRes] = await Promise.all([apiSim(baseReq), apiSim(scenReq)]);
      a.setBaselineSim(baseRes);
      a.setScenarioSim(scenRes);
      a.setShowResults(true);

      await buildRescue(a, scenReq, scenRes.summary.probability_of_ruin, baseRes.summary.probability_of_ruin);
    } catch (e) {
      setErr(e.message || "Simulation failed");
      alert(e.message || "Backend connection failed. Check your Render URL.");
    }
    setBusy(false); a.setRunning(false);
  };

  return (
    <>
      <Title t="Simulate your future" sub="Stack life events and shocks, then see how often your cash hits zero." />
      <div className="grid">
        <EventsCard />
        <div>
          <div style={{ marginBottom: 26 }}><AboutYouCard /></div>
          <SettingsCard />
        </div>
      </div>
      <div style={{ maxWidth: 420, margin: "26px 0" }}>
        <button className="btn" onClick={run} disabled={busy}>{busy ? "Simulating…" : "Simulate my future"}</button>
      </div>
      {err && <div className="sm" style={{ color: "var(--coral)" }}>{err}</div>}

      {a.baselineSim && a.scenarioSim && a.showResults && (
        <div className="grid" style={{ marginTop: 20 }}>
          <div className="w2"><HeadlineCard baseline={a.baselineSim} scenario={a.scenarioSim} cash={cash} /></div>
          <ChartCard
            baseline={a.baselineSim}
            scenario={a.scenarioSim}
            rescueLast={a.rescueSteps.length ? a.rescueSteps[a.rescueSteps.length - 1].result : null}
          />
          <NumbersCard s={a.scenarioSim.summary} />
          <DriversCard sim={a.scenarioSim} />
          <RescueCard scenario={a.scenarioSim} />
        </div>
      )}
    </>
  );
}

async function buildRescue(a, scenReq, scenRuin, baselineRuin) {
  const target = Math.max(0.05, baselineRuin + 0.02);
  a.setRescueTarget(target);
  a.setCushion([]); a.setCushionNeeded(null);
  if (scenRuin <= target) { a.setRescueSteps([]); a.setRescueAchieved(true); return; }

  a.setRescuing(true);
  const h = a.holdings;
  const p = a.d;
  const cand = [];

  const gainPct = Math.max(0, 4.5 - h.savingsApy);
  const interest = Math.max(0, a.cash) * gainPct / 1200;
  if (interest >= 1) {
    cand.push({
      group: "hysa", title: "Move cash to a 4.5% APY savings account",
      detail: `Your ${usd(a.cash)} earns ${h.savingsApy.toFixed(1)}% today`,
      monthly: interest, pain: "Easy",
      event: { label: "High-yield savings", month: 0, duration_months: null, income_delta: interest, expense_delta: 0, one_time_cost: 0 },
    });
  }
  const cuttable = ["Subscriptions", "Entertainment", "Health"];
  const subs = p.rec
    .filter((r) => !r.income && r.confidence >= 0.7 && r.cadence === "every month" && cuttable.includes(r.category) && Math.abs(r.amt) <= 150)
    .sort((x, y) => Math.abs(y.amt) - Math.abs(x.amt));
  for (const s of subs) {
    const amt = Math.abs(s.amt);
    cand.push({
      group: "sub", title: `Cancel ${s.label}`,
      detail: `Detected ${s.cadence}, ${usd(amt)} each time`,
      monthly: amt, pain: "Easy",
      event: { label: `Cancel ${s.label}`, month: 0, duration_months: null, income_delta: 0, expense_delta: -amt, one_time_cost: 0 },
    });
  }
  const var10 = p.p.vmean * 0.10;
  for (let n = 1; n <= 3; n++) {
    cand.push({
      group: "trim", title: `Trim everyday spending by ${n * 10}%`,
      detail: `About ${usd(var10 * n)} less a month than your ${usd(p.p.vmean)} average`,
      monthly: var10 * n, pain: n === 3 ? "Hard" : "Medium",
      event: { label: "Trim spending", month: 0, duration_months: null, income_delta: 0, expense_delta: -var10 * n, one_time_cost: 0 },
    });
  }
  if (h.depositAmount > 0) {
    const net = h.depositNet;
    cand.push({
      group: "cd", title: "Break your deposit early",
      detail: `Frees ${usd(net)} after an estimated ${usd(h.depositPenalty)} penalty`,
      monthly: net, pain: "Medium",
      event: { label: "Break deposit", month: 0, duration_months: 1, income_delta: net, expense_delta: 0, one_time_cost: 0 },
    });
  }
  const pay = 110;
  for (let n = 1; n <= 8; n++) {
    cand.push({
      group: "gig", title: `Pick up ${n} gig shift${n === 1 ? "" : "s"} in the next 90 days`,
      detail: `About ${usd(pay)} per shift (assumption)`,
      monthly: (pay * n) / 3, pain: "Hard",
      event: { label: "Gig shift", month: 0, duration_months: 3, income_delta: (pay * n) / 3, expense_delta: 0, one_time_cost: 0 },
    });
  }

  let results;
  try {
    results = await Promise.all(cand.map((_, i) => {
      const req = { ...scenReq, life_events: [...scenReq.life_events, ...cand.slice(0, i + 1).map((c) => c.event)] };
      return apiSim(req).catch(() => null);
    }));
  } catch { results = cand.map(() => null); }

  for (let i = 0; i < cand.length; i++) {
    cand[i].ruinAfter = results[i]?.summary?.probability_of_ruin ?? 1;
    cand[i].result = results[i];
  }

  let chosen;
  const k = cand.findIndex((c) => c.ruinAfter <= target);
  let achieved = false;
  if (k >= 0) { chosen = cand.slice(0, k + 1); achieved = true; }
  else { chosen = cand; }

  const merged = [];
  for (const s of chosen) {
    const last = merged[merged.length - 1];
    if (last && last.group === s.group && (s.group === "trim" || s.group === "gig")) merged[merged.length - 1] = s;
    else merged.push(s);
  }
  a.setRescueSteps(merged);
  a.setRescueAchieved(achieved);
  a.setRescuing(false);

  const baseCash = Math.max(a.cash, 1000);
  const grid = [1.0, 1.5, 2, 3, 4, 6, 8, 12, 16, 24].map((x) => baseCash * x);
  const cushionResults = await Promise.all(grid.map((bal) => {
    const req = { ...scenReq, starting_balance: bal };
    return apiSim(req).then((res) => ({ balance: bal, ruin: res.summary.probability_of_ruin })).catch(() => null);
  }));
  const pts = cushionResults.filter(Boolean).sort((x, y) => x.balance - y.balance);
  a.setCushion(pts);
  const hit = pts.findIndex((p) => p.ruin <= target);
  if (hit < 0) { a.setCushionNeeded(null); }
  else if (hit === 0) { a.setCushionNeeded(pts[0].balance); }
  else {
    const aa = pts[hit - 1], bb = pts[hit];
    const t = (aa.ruin - target) / Math.max(aa.ruin - bb.ruin, 1e-9);
    a.setCushionNeeded(Math.ceil((aa.balance + t * (bb.balance - aa.balance)) / 500) * 500);
  }
}

// ────────────────────────────────────────────────────────────── Stress
function Stress() {
  const a = useApp();
  const [months, setMonths] = useState(36);
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let active = true;
    setLoading(true);
    (async () => {
      try {
        const res = await apiStress({
          account_id: a.accountId,
          starting_balance: a.cash,
          horizon_months: months,
        });
        const out = (res.scenarios || []).map((s) => ({ key: s.key, label: s.label, summary: s }));
        if (active) setRows(out);
      } catch { if (active) setRows([]); }
      if (active) setLoading(false);
    })();
    return () => { active = false; };
  }, [months, a.cash, a.accountId]);

  return (
    <>
      <Title t="Stress-test lab" sub="Seven named disasters, each replayed on your own cash flow and cash on hand." />
      <div style={{ maxWidth: 360 }}>
        <Seg options={[[12, "1 yr"], [36, "3 yrs"], [60, "5 yrs"]]} value={months} onChange={setMonths} />
      </div>
      {loading && <div className="sm">Running 7 scenarios through the engine…</div>}
      <div className="grid">
        {rows.map((s) => {
          const sum = s.summary;
          if (!sum) return <Card key={s.key}><b>{s.label}</b><div className="sm">Couldn't run.</div></Card>;
          const p = sum.probability_of_ruin;
          const bad = p > 0.5;
          return (
            <Card key={s.key} style={bad ? { background: "#ffe3e8", color: "#1a1a3b" } : undefined}>
              <div className="row" style={{ alignItems: "flex-start", marginTop: 0 }}>
                <b>{s.label}</b>
                <span className="num" style={{ fontSize: 20, color: bad ? "#d6264a" : "inherit" }}>{odds(p)}</span>
              </div>
              <div className="bar"><div style={{ background: bad ? "var(--coral)" : "var(--mint)", width: p * 100 + "%" }} /></div>
              <div className="sm">
                {sum.median_months_to_ruin != null
                  ? `In this scenario, your cash runs out around month ${sum.median_months_to_ruin + 1}. Lowest point: ${cu(sum.median_min_balance)}.`
                  : `You survive this scenario. Your cash dips to ${cu(sum.median_min_balance)} but holds.`}
              </div>
            </Card>
          );
        })}
      </div>
    </>
  );
}

// ────────────────────────────────────────────────────────────── Risks
function Risks() {
  const a = useApp();
  const cats = Array.from(new Set(a.risks.map((r) => r.category))).sort();
  const detail = (r) => {
    const parts = [`${(r.annualProbability * 100).toFixed(r.annualProbability < 0.01 ? 1 : 0)}% a year`];
    if (r.medianCost > 0) parts.push(`typically ${usd(r.medianCost)}, insurance covers ${Math.round(r.coverage * 100)}%`);
    if (r.incomeLossFraction > 0) parts.push(`loses ${Math.round(r.incomeLossFraction * 100)}% of income for about ${Math.round(r.durationMonthsMean)} months`);
    return parts.join(", ");
  };
  return (
    <>
      <Title t="Risk universe" sub={`${a.risks.length} things that can go wrong, with how often and how much. Switch off any that don't apply to you.`} />
      <div className="grid">
        {cats.map((cat) => (
          <Card key={cat}>
            <h2>{cat}</h2>
            {a.risks.filter((r) => r.category === cat).map((r) => (
              <label className="row" key={r.key}>
                <span>
                  <b>{r.label}</b>
                  <div className="sm mut">{detail(r)}</div>
                </span>
                <input type="checkbox" checked={!a.excluded.has(r.key)}
                  onChange={(e) => {
                    const n = new Set(a.excluded);
                    e.target.checked ? n.delete(r.key) : n.add(r.key);
                    a.setExcluded(n);
                  }} />
              </label>
            ))}
          </Card>
        ))}
      </div>
    </>
  );
}

// ────────────────────────────────────────────────────────────── Accounts
function Accounts() {
  const a = useApp();
  const [replace, setReplace] = useState(true);
  const [note, setNote] = useState("");
  const [err, setErr] = useState("");
  const h = a.holdings;
  const setH = (k, v) => {
    const n = { ...h, [k]: v };
    n.depositPenalty = n.depositAmount * n.depositApy / 1200 * n.depositPenaltyMonths;
    n.depositNet = Math.max(0, n.depositAmount - n.depositPenalty);
    a.setHoldings(n);
  };
  const pen = h.depositAmount * (h.depositApy / 1200) * h.depositPenaltyMonths;

  const onFile = async (e) => {
    setErr(""); setNote("");
    try {
      if (!a.accountId) throw new Error("Not connected to a backend account. Use sample data for demo.");
      const file = e.target.files?.[0];
      if (!file) return;
      const fd = new FormData();
      fd.append("file", file);
      fd.append("replace", replace ? "true" : "false");
      const res = await fetch(`${BACKEND_URL}/api/accounts/${a.accountId}/import`, { method: "POST", body: fd });
      if (!res.ok) throw new Error("Import failed");
      const data = await res.json();
      setNote(`${data.inserted} new transactions (${data.first_date} to ${data.last_date}), ${data.skipped_duplicates} duplicates skipped.`);
    } catch (x) { setErr(x.message || "Upload failed"); }
    e.target.value = "";
  };

  return (
    <>
      <Title t="Your accounts" sub="Add statements and the things your bank can't see." />
      <p><button className="link" onClick={() => a.setModal("guide")}>How this works</button></p>
      <div className="grid">
        <Card>
          <h2>Bank statements</h2>
          <div className="sm">Download a PDF or CSV from your bank's website. You can add several files.</div>
          <Tog label="Replace the sample data" helpKey="Replace the sample data" v={replace} on={setReplace} />
          <label className="btn" style={{ cursor: "pointer" }}>
            Add statement (PDF or CSV)
            <input type="file" accept=".csv,.pdf,.txt" multiple hidden onChange={onFile} />
          </label>
          {note && <div className="ok">{note}</div>}
          {err && <div className="sm" style={{ color: "var(--coral)" }}>{err}</div>}
        </Card>

        <Card>
          <h2>What we read from your files</h2>
          <div className="sm">Check this looks right before you trust the odds.</div>
          {!a.transactions.length ? (
            <div className="b" style={{ marginTop: 8 }}>Using sample data. Add a statement to see your own numbers.</div>
          ) : (
            <>
              <div className="tiles" style={{ margin: "12px 0" }}>
                <Tile t="Transactions" v={a.transactions.length} />
                <Tile t="Months covered" v={a.d.months} />
              </div>
              <div className="b sm">Found {a.d.rec.filter((r) => r.income).length} paycheck series and {a.d.rec.filter((r) => !r.income).length} bills or subscriptions.</div>
              {a.d.months < 3 && <div className="sm b" style={{ color: "#d6264a" }}>Only {a.d.months} month{a.d.months === 1 ? "" : "s"} of data. Bills are found by repeating, so add older statements.</div>}
            </>
          )}
        </Card>

        <Card>
          <h2>Savings and deposits</h2>
          <NumField title="Savings balance" value={h.savingsBalance} onChange={(v) => setH("savingsBalance", v)} />
          <NumField title="Savings interest (APY)" value={h.savingsApy} onChange={(v) => setH("savingsApy", v)} pre="" suf="%" />
          <hr />
          <NumField title="Locked deposit / CD" value={h.depositAmount} onChange={(v) => setH("depositAmount", v)} />
          {h.depositAmount > 0 && (
            <>
              <NumField title="Deposit rate (APY)" value={h.depositApy} onChange={(v) => setH("depositApy", v)} pre="" suf="%" />
              <div className="row">
                <span>Early-withdrawal penalty <HelpBtn title="Early-withdrawal penalty" /></span>
                <Stepper text={Math.round(h.depositPenaltyMonths) + " mo"}
                  onStep={(x) => setH("depositPenaltyMonths", Math.max(0, Math.min(12, h.depositPenaltyMonths + x)))} />
              </div>
              <div className="sm">Breaking it early frees {usd(h.depositNet)} after a {usd(pen)} penalty.</div>
            </>
          )}
          <button className="btn sun" onClick={() => a.setCash(a.d.p.checking + h.savingsBalance)}>Use as starting cash</button>
          <div className="sm b">Starting cash now: {usd(a.cash)} <HelpBtn title="Starting cash" /></div>
        </Card>

        <Card>
          <h2>Insurance and home</h2>
          <div className="sm">What you pay yourself when you file a claim.</div>
          <NumField title="Car insurance deductible" value={h.autoDeductible} onChange={(v) => setH("autoDeductible", v)} />
          <NumField title="Home / renters deductible" value={h.homeDeductible} onChange={(v) => setH("homeDeductible", v)} />
          <Tog label="I have a mortgage" helpKey="I have a mortgage" v={h.hasMortgage}
            on={(on) => { setH("hasMortgage", on); a.setUser({ ...a.user, housing: on ? "own_house" : "rent" }); }} />
        </Card>
      </div>
    </>
  );
}

// ────────────────────────────────────────────────────────────── Guide modal
function Guide({ onClose }) {
  const [i, setI] = useState(0);
  const total = GUIDE_STEPS.length;
  const isGlossary = i === total;
  return (
    <div className="ov" onClick={onClose}>
      <div className="card" onClick={(e) => e.stopPropagation()}>
        <div className="row"><h2 style={{ margin: 0 }}>How ShockProof works</h2><button className="link" onClick={onClose}>Close</button></div>
        {!isGlossary ? (
          <>
            <span className="pill">Step {i + 1} of {total}</span>
            <h1 style={{ fontSize: 30, marginTop: 8 }}>{GUIDE_STEPS[i][0]}</h1>
            <p>{GUIDE_STEPS[i][1]}</p>
            <div className="inset">
              {GUIDE_STEPS[i][2].map((t) => (
                <div key={t} className="row" style={{ margin: "6px 0", justifyContent: "flex-start", gap: 8 }}>
                  <span style={{ color: "#0d8059" }}>✓</span>
                  <span className="sm">{t}</span>
                </div>
              ))}
            </div>
          </>
        ) : (
          <>
            <span className="pill" style={{ background: "var(--mint)" }}>Glossary</span>
            <h1 style={{ fontSize: 30, marginTop: 8 }}>What every term means</h1>
            {GLOSSARY.map(([t, m]) => (
              <details key={t} style={{ margin: "10px 0" }}>
                <summary className="b">{t}</summary>
                <div className="sm" style={{ marginTop: 4 }}>{m}</div>
              </details>
            ))}
          </>
        )}
        <div style={{ display: "flex", gap: 12, marginTop: 14 }}>
          {i > 0 && <button className="btn wh" onClick={() => setI(i - 1)}>Back</button>}
          <button className="btn" onClick={() => (isGlossary ? onClose() : setI(i + 1))}>
            {isGlossary ? "Done" : i === total - 1 ? "Glossary" : "Next"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────── App
const TABS = [
  ["foundation", "Foundation", Foundation],
  ["futures", "Futures", Futures],
  ["stress", "Stress", Stress],
  ["risks", "Risks", Risks],
  ["accounts", "Accounts", Accounts],
];

export default function ShockProof() {
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [connectError, setConnectError] = useState("");
  const [tab, setTab] = useState("foundation");
  const [accountId, setAccountId] = useState(null);

  const [d, setD] = useState(SAMPLE);
  const [transactions, setTransactions] = useState([]);
  const [risks, setRisks] = useState(RISKS);

  const [cash, setCash] = useState(8500);
  const [holdings, setHoldings] = useState({
    savingsBalance: 0, savingsApy: 0.5,
    depositAmount: 0, depositApy: 4.5, depositPenaltyMonths: 3,
    autoDeductible: 1000, homeDeductible: 2500, hasMortgage: false,
    get depositPenalty() { return this.depositAmount * this.depositApy / 1200 * this.depositPenaltyMonths; },
    get depositNet() { return Math.max(0, this.depositAmount - this.depositPenalty); },
  });
  const [user, setUser] = useState({
    age: 30, state: "NY", housing: "rent", employment: "employed",
    married: false, children: 0, hasPets: false, ownsCar: true, canBirth: true,
  });
  const [drafts, setDrafts] = useState([]);
  const [horizon, setHorizon] = useState(60);
  const [randomRisks, setRandomRisks] = useState(true);
  const [excluded, setExcluded] = useState(new Set());

  const [baselineSim, setBaselineSim] = useState(null);
  const [scenarioSim, setScenarioSim] = useState(null);
  const [running, setRunning] = useState(false);
  const [showResults, setShowResults] = useState(false);
  const [rescueSteps, setRescueSteps] = useState([]);
  const [rescuing, setRescuing] = useState(false);
  const [rescueTarget, setRescueTarget] = useState(0.05);
  const [rescueAchieved, setRescueAchieved] = useState(false);
  const [cushion, setCushion] = useState([]);
  const [cushionNeeded, setCushionNeeded] = useState(null);

  const [modal, setModal] = useState(null);
  const [seenGuide, setSeenGuide] = useState(false);
  useEffect(() => { if (connected && !seenGuide) { setModal("guide"); setSeenGuide(true); } }, [connected, seenGuide]);

  const [derived, setDerived] = useState({
    monthly_income: 4200, monthly_fixed: 2105, monthly_variable_mean: 1100, rent: 1500,
  });

  async function connect() {
    setConnecting(true);
    setConnectError("");
    try {
      const { accountId: aid, profile, txs, riskList } = await bootstrapBackend();
      const mapped = mapProfileToData(profile, txs.transactions || []);
      setAccountId(aid);
      setD(mapped.d);
      setTransactions(txs.transactions || []);
      setCash(mapped.cash);
      setDerived(mapped.derived);
      const realRisks = mapRisksFromBackend(riskList);
      if (realRisks.length) setRisks(realRisks);
      setConnected(true);
    } catch (e) {
      setConnectError(e.message || "Could not reach the backend. Check the Render URL and CORS.");
    }
    setConnecting(false);
  }

  const ctx = {
    connected, connecting, connectError, connect,
    tab, setTab, accountId, setAccountId,
    d, setD, transactions, setTransactions, risks, setRisks,
    cash, setCash,
    holdings, setHoldings,
    user, setUser,
    drafts, setDrafts,
    horizon, setHorizon,
    randomRisks, setRandomRisks,
    excluded, setExcluded,
    baselineSim, setBaselineSim,
    scenarioSim, setScenarioSim,
    running, setRunning, showResults, setShowResults,
    rescueSteps, setRescueSteps, rescuing, setRescuing,
    rescueTarget, setRescueTarget, rescueAchieved, setRescueAchieved,
    cushion, setCushion, cushionNeeded, setCushionNeeded,
    setModal, derived, setConnected,
  };

  const Page = TABS.find((t) => t[0] === tab)[2];
  const close = () => setModal(null);

  return (
    <Ctx.Provider value={ctx}>
      <div className="sp"><style>{CSS}</style>
        <header>
          <div className="bar1">
            <button className="logo" onClick={() => setTab("foundation")}>ShockProof</button>
            {connected && (
              <nav aria-label="Main">
                {TABS.map(([k, l]) => (
                  <button key={k} className={k === tab ? "on" : ""} onClick={() => { setTab(k); window.scrollTo(0, 0); }}>{l}</button>
                ))}
                <button onClick={() => setModal("guide")}>How it works</button>
              </nav>
            )}
          </div>
        </header>
        <main>{connected ? <Page /> : <Welcome />}</main>
        <footer>ShockProof replays your money through possible futures. It shows how fragile your cash is to bad luck. It is not financial advice or a forecast.</footer>
        {modal === "guide" && <Guide onClose={close} />}
        {modal && modal !== "guide" && (
          <div className="ov" onClick={close}>
            <div className="card" onClick={(e) => e.stopPropagation()}>
              <h2>{modal.title}</h2>
              <p>{modal.text}</p>
              <button className="btn" onClick={close}>Got it</button>
            </div>
          </div>
        )}
      </div>
    </Ctx.Provider>
  );
}