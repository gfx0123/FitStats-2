// Statistics over fs_days: per-metric ranges, weekday patterns, records,
// streaks, lagged correlations, journal tag effects and plain-language insights.
// Day totals leave out today (still growing) and days you barely wore the band.

import type { BodyAge } from "./bodyage.ts";
import { tagLabel } from "./journal.ts";
import type { DayRow } from "./scores.ts";
import { addDays, daysBetween, mean, median, round, stdDev, weekdayIndex, type Ymd } from "./util.ts";

export interface MetricDef {
  key: string;
  label: string;
  unit: string;
  decimals: number;
  category: "scores" | "activity" | "heart" | "sleep" | "vitals" | "body";
  /** "sum" metrics are day totals (today is partial and excluded from stats). */
  agg: "sum" | "avg";
  better: "higher" | "lower" | null;
  format?: "duration" | "clock" | "percent";
  get: (d: DayRow) => number | null;
}

function col(key: string) {
  return (d: DayRow) => {
    const v = d[key];
    return typeof v === "number" && Number.isFinite(v) ? v : null;
  };
}

function sumCols(...keys: string[]) {
  return (d: DayRow) => {
    let any = false;
    let s = 0;
    for (const k of keys) {
      const v = d[k];
      if (typeof v === "number" && Number.isFinite(v)) {
        s += v;
        any = true;
      }
    }
    return any ? s : null;
  };
}

function ratio(numKey: string, denKey: string, scale = 100) {
  return (d: DayRow) => {
    const a = d[numKey], b = d[denKey];
    return typeof a === "number" && typeof b === "number" && b > 0 ? (a / b) * scale : null;
  };
}

export const METRICS: MetricDef[] = [
  // scores
  { key: "recovery", label: "Recovery", unit: "%", decimals: 0, category: "scores", agg: "avg", better: "higher", get: col("recovery") },
  { key: "strain", label: "Strain", unit: "", decimals: 1, category: "scores", agg: "sum", better: null, get: col("strain") },
  { key: "sleep_score", label: "Sleep score", unit: "", decimals: 0, category: "scores", agg: "avg", better: "higher", get: col("sleep_score") },
  { key: "stress", label: "Stress", unit: "", decimals: 0, category: "scores", agg: "sum", better: "lower", get: col("stress") },
  // activity
  { key: "steps", label: "Steps", unit: "", decimals: 0, category: "activity", agg: "sum", better: "higher", get: col("steps") },
  {
    key: "distance_km", label: "Distance", unit: "km", decimals: 2, category: "activity", agg: "sum", better: "higher",
    get: (d) => (typeof d.distance_m === "number" ? d.distance_m / 1000 : null),
  },
  { key: "floors", label: "Floors", unit: "", decimals: 0, category: "activity", agg: "sum", better: "higher", get: col("floors") },
  { key: "calories_total", label: "Calories burned", unit: "kcal", decimals: 0, category: "activity", agg: "sum", better: null, get: col("calories_total") },
  { key: "calories_active", label: "Active calories", unit: "kcal", decimals: 0, category: "activity", agg: "sum", better: "higher", get: col("calories_active") },
  { key: "azm_total", label: "Active Zone Minutes", unit: "min", decimals: 0, category: "activity", agg: "sum", better: "higher", get: sumCols("azm_fat_burn", "azm_cardio", "azm_peak") },
  { key: "active_min_total", label: "Active minutes", unit: "min", decimals: 0, category: "activity", agg: "sum", better: "higher", get: sumCols("active_light_min", "active_moderate_min", "active_vigorous_min") },
  { key: "active_vigorous_min", label: "Vigorous minutes", unit: "min", decimals: 0, category: "activity", agg: "sum", better: "higher", get: col("active_vigorous_min") },
  {
    key: "sedentary_h", label: "Sedentary time", unit: "h", decimals: 1, category: "activity", agg: "sum", better: "lower",
    get: (d) => (typeof d.sedentary_min === "number" ? d.sedentary_min / 60 : null),
  },
  { key: "trimp", label: "Training load (TRIMP)", unit: "", decimals: 0, category: "activity", agg: "sum", better: null, get: col("trimp") },
  // heart
  { key: "rhr", label: "Resting heart rate", unit: "bpm", decimals: 0, category: "heart", agg: "avg", better: "lower", get: col("rhr") },
  { key: "hrv_rmssd", label: "HRV (RMSSD)", unit: "ms", decimals: 0, category: "heart", agg: "avg", better: "higher", get: col("hrv_rmssd") },
  { key: "hrv_deep_rmssd", label: "Deep-sleep HRV", unit: "ms", decimals: 0, category: "heart", agg: "avg", better: "higher", get: col("hrv_deep_rmssd") },
  { key: "non_rem_hr", label: "Non-REM heart rate", unit: "bpm", decimals: 0, category: "heart", agg: "avg", better: "lower", get: col("non_rem_hr") },
  { key: "hr_avg", label: "Average heart rate", unit: "bpm", decimals: 0, category: "heart", agg: "sum", better: null, get: col("hr_avg") },
  { key: "hr_max", label: "Max heart rate", unit: "bpm", decimals: 0, category: "heart", agg: "sum", better: null, get: col("hr_max") },
  { key: "zone_cardio_min", label: "Cardio + peak zone", unit: "min", decimals: 0, category: "heart", agg: "sum", better: "higher", get: sumCols("zone_vigorous_min", "zone_peak_min") },
  { key: "vo2max", label: "Cardio fitness (VO₂ max)", unit: "ml/kg/min", decimals: 1, category: "heart", agg: "avg", better: "higher", get: col("vo2max") },
  // sleep
  { key: "sleep_asleep_min", label: "Time asleep", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: "higher", format: "duration", get: col("sleep_asleep_min") },
  { key: "sleep_in_bed_min", label: "Time in bed", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: null, format: "duration", get: col("sleep_in_bed_min") },
  { key: "sleep_deep_min", label: "Deep sleep", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: "higher", format: "duration", get: col("sleep_deep_min") },
  { key: "sleep_rem_min", label: "REM sleep", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: "higher", format: "duration", get: col("sleep_rem_min") },
  { key: "sleep_light_min", label: "Light sleep", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: null, format: "duration", get: col("sleep_light_min") },
  { key: "sleep_awake_min", label: "Awake (incl. falling asleep)", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: "lower", format: "duration", get: col("sleep_awake_min") },
  { key: "sleep_waso_min", label: "Awake after falling asleep", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: "lower", format: "duration", get: col("sleep_waso_min") },
  { key: "deep_pct", label: "Deep sleep share", unit: "%", decimals: 0, category: "sleep", agg: "avg", better: "higher", format: "percent", get: ratio("sleep_deep_min", "sleep_asleep_min") },
  { key: "rem_pct", label: "REM sleep share", unit: "%", decimals: 0, category: "sleep", agg: "avg", better: "higher", format: "percent", get: ratio("sleep_rem_min", "sleep_asleep_min") },
  {
    key: "sleep_efficiency", label: "Sleep efficiency", unit: "%", decimals: 0, category: "sleep", agg: "avg", better: "higher", format: "percent",
    get: (d) => (typeof d.sleep_efficiency === "number" ? d.sleep_efficiency * 100 : null),
  },
  { key: "sleep_awakenings", label: "Awakenings", unit: "", decimals: 0, category: "sleep", agg: "avg", better: "lower", get: col("sleep_awakenings") },
  { key: "sleep_bedtime_min", label: "Bedtime", unit: "", decimals: 0, category: "sleep", agg: "avg", better: null, format: "clock", get: col("sleep_bedtime_min") },
  { key: "sleep_waketime_min", label: "Wake time", unit: "", decimals: 0, category: "sleep", agg: "avg", better: null, format: "clock", get: col("sleep_waketime_min") },
  { key: "nap_min", label: "Naps", unit: "min", decimals: 0, category: "sleep", agg: "avg", better: null, format: "duration", get: col("nap_min") },
  // vitals
  { key: "spo2_avg", label: "Blood oxygen (SpO₂)", unit: "%", decimals: 1, category: "vitals", agg: "avg", better: "higher", get: col("spo2_avg") },
  { key: "resp_rate", label: "Breathing rate", unit: "/min", decimals: 1, category: "vitals", agg: "avg", better: null, get: col("resp_rate") },
  {
    key: "skin_temp_dev", label: "Skin temperature variation", unit: "°C", decimals: 2, category: "vitals", agg: "avg", better: null,
    get: (d) => (typeof d.skin_temp_c === "number" && typeof d.skin_temp_baseline_c === "number" ? d.skin_temp_c - d.skin_temp_baseline_c : null),
  },
  // body
  { key: "weight_kg", label: "Weight", unit: "kg", decimals: 1, category: "body", agg: "avg", better: null, get: col("weight_kg") },
  { key: "body_fat_pct", label: "Body fat", unit: "%", decimals: 1, category: "body", agg: "avg", better: "lower", get: col("body_fat_pct") },
];

export const METRIC_BY_KEY = new Map(METRICS.map((m) => [m.key, m]));

export interface RangeStats {
  days: number | null;
  n: number;
  mean: number | null;
  median: number | null;
  min: number | null;
  minDate: Ymd | null;
  max: number | null;
  maxDate: Ymd | null;
  sd: number | null;
  sum: number | null;
  slopePerWeek: number | null;
  prevMean: number | null;
  /** mean − prevMean. */
  change: number | null;
  /** Null for clock times and deviations around zero, where a ratio means nothing. */
  changePct: number | null;
}

export interface MetricStats {
  key: string;
  latest: number | null;
  latestDate: Ymd | null;
  ranges: Record<string, RangeStats>;
  weekday: (number | null)[];
  best: { value: number; date: Ymd } | null;
  worst: { value: number; date: Ymd } | null;
}

export const RANGES: [string, number | null][] = [["7", 7], ["30", 30], ["90", 90], ["365", 365], ["all", null]];

type Point = { date: Ymd; v: number };

/** Clock times (zero is midnight) and deviations around zero: compared by the absolute change only. */
export function hasRelativeChange(def: MetricDef): boolean {
  return def.format !== "clock" && def.key !== "skin_temp_dev";
}

/** False for day totals of today (still growing) and of low-wear days (incomplete). */
export function countsToward(def: MetricDef, d: DayRow, today: Ymd): boolean {
  return def.agg !== "sum" || (d.date < today && d.low_wear !== true);
}

function seriesFor(def: MetricDef, days: DayRow[], today: Ymd): Point[] {
  const out: Point[] = [];
  for (const d of days) {
    if (!countsToward(def, d, today)) continue;
    const v = def.get(d);
    if (v !== null) out.push({ date: d.date, v });
  }
  return out;
}

function linearSlope(points: Point[], origin: Ymd): number | null {
  if (points.length < 3) return null;
  const xs = points.map((p) => daysBetween(origin, p.date));
  const ys = points.map((p) => p.v);
  const mx = mean(xs)!, my = mean(ys)!;
  let sxx = 0, sxy = 0;
  for (let i = 0; i < xs.length; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  return sxx > 0 ? sxy / sxx : null;
}

function rangeStats(def: MetricDef, series: Point[], start: Ymd | null, end: Ymd, days: number | null): RangeStats {
  const pts = series.filter((p) => (start === null || p.date >= start) && p.date < end);
  const vals = pts.map((p) => p.v);
  let minP: Point | null = null, maxP: Point | null = null;
  for (const p of pts) {
    if (!minP || p.v < minP.v) minP = p;
    if (!maxP || p.v > maxP.v) maxP = p;
  }
  let prevMean: number | null = null;
  if (start !== null && days !== null) {
    const prevStart = addDays(start, -days);
    const prev = series.filter((p) => p.date >= prevStart && p.date < start).map((p) => p.v);
    if (prev.length >= Math.max(2, Math.floor(days / 4))) prevMean = mean(prev);
  }
  const m = mean(vals);
  const d = def.decimals + 1;
  const slope = linearSlope(pts, start ?? (pts[0]?.date ?? end));
  return {
    days,
    n: vals.length,
    mean: round(m, d),
    median: round(median(vals), d),
    min: minP ? round(minP.v, d) : null,
    minDate: minP?.date ?? null,
    max: maxP ? round(maxP.v, d) : null,
    maxDate: maxP?.date ?? null,
    sd: round(stdDev(vals), d),
    sum: def.agg === "sum" && vals.length ? round(vals.reduce((a, b) => a + b, 0), d) : null,
    slopePerWeek: slope === null ? null : round(slope * 7, d),
    prevMean: round(prevMean, d),
    change: m !== null && prevMean !== null ? round(m - prevMean, d) : null,
    changePct: hasRelativeChange(def) && m !== null && prevMean !== null && prevMean !== 0
      ? round(((m - prevMean) / Math.abs(prevMean)) * 100, 1)
      : null,
  };
}

export function metricStats(def: MetricDef, days: DayRow[], today: Ymd): MetricStats {
  const series = seriesFor(def, days, today);
  // Day totals cover the last N complete days (today is still growing); averages include today.
  const end = def.agg === "sum" ? today : addDays(today, 1);
  const ranges: Record<string, RangeStats> = {};
  for (const [name, len] of RANGES) {
    ranges[name] = rangeStats(def, series, len === null ? null : addDays(end, -len), end, len);
  }
  const wdStart = addDays(today, -89);
  const buckets: number[][] = [[], [], [], [], [], [], []];
  for (const p of series) if (p.date >= wdStart) buckets[weekdayIndex(p.date)].push(p.v);
  const weekday = buckets.map((b) => (b.length >= 2 ? round(mean(b), def.decimals + 1) : null));

  let best: Point | null = null, worst: Point | null = null;
  if (def.better) {
    for (const p of series) {
      const better = def.better === "higher" ? (a: number, b: number) => a > b : (a: number, b: number) => a < b;
      if (!best || better(p.v, best.v)) best = p;
      if (!worst || better(worst.v, p.v)) worst = p;
    }
  }
  const latestPoint = [...days].reverse().find((d) => def.get(d) !== null);
  return {
    key: def.key,
    latest: latestPoint ? round(def.get(latestPoint), def.decimals + 1) : null,
    latestDate: latestPoint?.date ?? null,
    ranges,
    weekday,
    best: best ? { value: round(best.v, def.decimals + 1)!, date: best.date } : null,
    worst: worst ? { value: round(worst.v, def.decimals + 1)!, date: worst.date } : null,
  };
}

// -------------------------------------------------------------------- streaks

export interface Streak {
  key: string;
  label: string;
  current: number;
  longest: number;
  longestEnd: Ymd | null;
}

export function streak(
  key: string,
  label: string,
  days: DayRow[],
  today: Ymd,
  test: (d: DayRow) => boolean | null,
  includeToday: boolean,
): Streak {
  const byDate = new Map(days.map((d) => [d.date, d]));
  const first = days.length ? days[0].date : today;
  const last = includeToday ? today : addDays(today, -1);
  let run = 0, longest = 0;
  let longestEnd: Ymd | null = null;
  for (let d = first; d <= last; d = addDays(d, 1)) {
    const row = byDate.get(d);
    const ok = row ? test(row) : null;
    if (ok === true) {
      run++;
      if (run > longest) {
        longest = run;
        longestEnd = d;
      }
    } else {
      run = 0;
    }
  }
  // An incomplete today does not break the current streak.
  let current = 0;
  for (let d = last; d >= first; d = addDays(d, -1)) {
    const row = byDate.get(d);
    const ok = row ? test(row) : null;
    if (ok === true) current++;
    else if (d === today && ok === null) continue; // today's value hasn't synced yet
    else break;
  }
  return { key, label, current, longest, longestEnd };
}

// --------------------------------------------------------------- correlations

export interface Correlation {
  x: string;
  y: string;
  lag: number;
  title: string;
  r: number | null;
  n: number;
  slope: number | null;
  strength: "none" | "weak" | "moderate" | "strong" | "insufficient";
}

export const CORRELATION_PAIRS: { x: string; y: string; lag: number; title: string }[] = [
  { x: "strain", y: "recovery", lag: 1, title: "Strain → next-day recovery" },
  { x: "strain", y: "hrv_rmssd", lag: 1, title: "Strain → next-night HRV" },
  { x: "sleep_asleep_min", y: "recovery", lag: 0, title: "Time asleep → recovery" },
  { x: "sleep_asleep_min", y: "hrv_rmssd", lag: 0, title: "Time asleep → HRV" },
  { x: "sleep_bedtime_min", y: "sleep_score", lag: 0, title: "Later bedtime → sleep score" },
  { x: "steps", y: "sleep_score", lag: 1, title: "Steps → that night's sleep score" },
  { x: "azm_total", y: "sleep_deep_min", lag: 1, title: "Active Zone Minutes → deep sleep" },
  { x: "stress", y: "sleep_score", lag: 1, title: "Stress → that night's sleep score" },
  { x: "sleep_asleep_min", y: "stress", lag: 0, title: "Time asleep → same-day stress" },
  { x: "azm_total", y: "rhr", lag: 1, title: "Active Zone Minutes → next resting HR" },
];

export function pearson(xs: number[], ys: number[]): number | null {
  if (xs.length < 3) return null;
  const mx = mean(xs)!, my = mean(ys)!;
  let sxx = 0, syy = 0, sxy = 0;
  for (let i = 0; i < xs.length; i++) {
    sxx += (xs[i] - mx) ** 2;
    syy += (ys[i] - my) ** 2;
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (sxx === 0 || syy === 0) return null;
  return sxy / Math.sqrt(sxx * syy);
}

function strengthOf(r: number | null, n: number): Correlation["strength"] {
  if (r === null || n < 14) return "insufficient";
  const a = Math.abs(r);
  if (a < 0.1) return "none";
  if (a < 0.3) return "weak";
  if (a < 0.5) return "moderate";
  return "strong";
}

/** Pairs x on day D−lag with y on day D over the last `windowDays` days. */
export function correlations(days: DayRow[], today: Ymd, windowDays = 180): Correlation[] {
  const byDate = new Map(days.map((d) => [d.date, d]));
  const start = addDays(today, -(windowDays - 1));
  return CORRELATION_PAIRS.map((pair) => {
    const dx = METRIC_BY_KEY.get(pair.x)!, dy = METRIC_BY_KEY.get(pair.y)!;
    const xs: number[] = [], ys: number[] = [];
    for (let d = start; d <= today; d = addDays(d, 1)) {
      const xr = byDate.get(addDays(d, -pair.lag)), yr = byDate.get(d);
      if (!xr || !yr || !countsToward(dx, xr, today) || !countsToward(dy, yr, today)) continue;
      const xv = dx.get(xr), yv = dy.get(yr);
      if (xv === null || yv === null) continue;
      xs.push(xv);
      ys.push(yv);
    }
    const r = pearson(xs, ys);
    let slope: number | null = null;
    if (r !== null) {
      const sx = stdDev(xs), sy = stdDev(ys);
      if (sx && sy) slope = (r * sy) / sx;
    }
    return { ...pair, r: round(r, 2), n: xs.length, slope: round(slope, 3), strength: strengthOf(r, xs.length) };
  });
}

// ------------------------------------------------------------------- insights

export interface Insight {
  id: string;
  title: string;
  body: string;
  tone: "positive" | "negative" | "neutral";
  metric?: string;
}

function pctChange(a: number | null, b: number | null): number | null {
  return a !== null && b !== null && b !== 0 ? ((a - b) / Math.abs(b)) * 100 : null;
}

function windowMean(def: MetricDef, days: DayRow[], from: Ymd, toExclusive: Ymd): number | null {
  const vals = days
    .filter((d) => d.date >= from && d.date < toExclusive && (def.agg !== "sum" || d.low_wear !== true))
    .map(def.get)
    .filter((v): v is number => v !== null);
  return vals.length >= 3 ? mean(vals) : null;
}

function fmtDuration(min: number): string {
  const h = Math.floor(Math.abs(min) / 60), m = Math.round(Math.abs(min) % 60);
  return h ? `${h}h ${m}m` : `${m}m`;
}

/** "10,299", "52 ms", "71%", "7h 32m" — the way the app shows the same metric. */
export function fmtValue(def: MetricDef, v: number): string {
  if (def.format === "duration") return fmtDuration(v);
  const n = v.toLocaleString("en-US", { minimumFractionDigits: def.decimals, maximumFractionDigits: def.decimals });
  if (def.format === "percent" || def.unit === "%") return `${n}%`;
  return def.unit ? `${n} ${def.unit}` : n;
}

export function insights(
  days: DayRow[],
  today: Ymd,
  settings: { sleep_need_min: number; step_goal: number },
  corr: Correlation[],
): Insight[] {
  const out: Insight[] = [];
  const end = addDays(today, 1);
  const yesterdayEnd = today;

  const compare = (key: string, label: string, sumType: boolean) => {
    const def = METRIC_BY_KEY.get(key)!;
    const stop = sumType ? yesterdayEnd : end;
    const w7 = windowMean(def, days, addDays(stop, -7), stop);
    const w30 = windowMean(def, days, addDays(stop, -30), stop);
    const ch = pctChange(w7, w30);
    if (ch === null || Math.abs(ch) < 3) return;
    const good = def.better === null ? null : (def.better === "higher") === ch > 0;
    out.push({
      id: `trend_${key}`,
      title: `${label} ${ch > 0 ? "up" : "down"} ${Math.abs(ch).toFixed(0)}%`,
      body: `7-day average ${fmtValue(def, w7!)}, versus ${fmtValue(def, w30!)} over the last 30 days.`,
      tone: good === null ? "neutral" : good ? "positive" : "negative",
      metric: key,
    });
  };
  compare("hrv_rmssd", "HRV", false);
  compare("rhr", "Resting heart rate", false);
  compare("recovery", "Recovery", false);
  compare("steps", "Steps", true);

  // Sleep debt over the last 7 nights; that day's naps count as sleep.
  const sleepDef = METRIC_BY_KEY.get("sleep_asleep_min")!, napDef = METRIC_BY_KEY.get("nap_min")!;
  let debt = 0, nights = 0;
  for (let d = addDays(today, -6); d <= today; d = addDays(d, 1)) {
    const row = days.find((x) => x.date === d);
    const v = row ? sleepDef.get(row) : null;
    if (v === null) continue;
    nights++;
    debt += Math.max(0, settings.sleep_need_min - v - (napDef.get(row!) ?? 0));
  }
  if (nights >= 3) {
    out.push({
      id: "sleep_debt",
      title: debt < 30 ? "Sleep need met" : `Sleep debt ${fmtDuration(debt)}`,
      body: `Over the last ${nights} tracked nights, counting naps, you were ${fmtDuration(debt)} short of your ${fmtDuration(settings.sleep_need_min)} sleep need in total.`,
      tone: debt < 30 ? "positive" : debt > 180 ? "negative" : "neutral",
      metric: "sleep_asleep_min",
    });
  }

  // Best night for sleep score over 90 days. Sleep is dated by the wake-up day, so the
  // night is named after the evening before: waking on Sunday is a Saturday night.
  const ss = metricStats(METRIC_BY_KEY.get("sleep_score")!, days, today);
  const wd = ss.weekday.map((v, i) => ({ v, i })).filter((x) => x.v !== null) as { v: number; i: number }[];
  if (wd.length >= 5) {
    const eve = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    const best = wd.reduce((a, b) => (b.v > a.v ? b : a));
    const worst = wd.reduce((a, b) => (b.v < a.v ? b : a));
    if (best.v - worst.v >= 5) {
      out.push({
        id: "sleep_weekday",
        title: `You sleep best on ${eve[best.i]} nights`,
        body: `Average sleep score: ${eve[best.i]} nights ${best.v.toFixed(0)}, ${eve[worst.i]} nights ${worst.v.toFixed(0)} (last 90 days).`,
        tone: "neutral",
        metric: "sleep_score",
      });
    }
  }

  const strongest = corr
    .filter((c) => c.strength === "moderate" || c.strength === "strong")
    .sort((a, b) => Math.abs(b.r ?? 0) - Math.abs(a.r ?? 0))[0];
  if (strongest) {
    out.push({
      id: `corr_${strongest.x}_${strongest.y}`,
      title: strongest.title,
      body: `${strongest.strength === "strong" ? "Strong" : "Moderate"} ${strongest.r! > 0 ? "positive" : "negative"} link (r = ${strongest.r}, ${strongest.n} days). Correlation, not proof of cause.`,
      tone: "neutral",
      metric: strongest.y,
    });
  }
  return out;
}

// -------------------------------------------------------------------- journal

/** What follows a journal day: that night's sleep (dated by wake-up) and the next morning. */
export const JOURNAL_OUTCOMES = ["sleep_score", "sleep_asleep_min", "hrv_rmssd", "rhr", "recovery"];
const MIN_JOURNAL_DAYS = 3;

export interface TagEffect {
  metric: string;
  /** Mean after tagged days and after the other logged days. */
  with: number;
  without: number;
  diff: number;
  nWith: number;
  nWithout: number;
  /** Welch's t; |t| ≥ 2 counts as a clear difference. */
  t: number | null;
  clear: boolean;
}

export interface TagImpact {
  tag: string;
  label: string;
  /** Tagged days in the window (the last one may not have a following night yet). */
  days: number;
  effects: TagEffect[];
}

function welchT(a: number[], b: number[]): number | null {
  const va = (stdDev(a) ?? 0) ** 2 / a.length, vb = (stdDev(b) ?? 0) ** 2 / b.length;
  const diff = mean(a)! - mean(b)!;
  if (va + vb === 0) return diff === 0 ? 0 : null;
  return diff / Math.sqrt(va + vb);
}

/**
 * Per tag: each outcome on the day after tagged days versus the day after other
 * logged days (an entry with no tags counts as logged). Needs 3+ days on each side.
 */
export function journalImpacts(days: DayRow[], entries: { date: Ymd; tags: string[] }[], today: Ymd, windowDays = 365): TagImpact[] {
  const byDate = new Map(days.map((d) => [d.date, d]));
  const start = addDays(today, -windowDays);
  const logged = entries.filter((e) => e.date >= start && e.date <= today);
  const counts = new Map<string, number>();
  for (const e of logged) for (const t of e.tags) counts.set(t, (counts.get(t) ?? 0) + 1);
  const out: TagImpact[] = [];
  for (const [tag, n] of counts) {
    const effects: TagEffect[] = [];
    for (const key of JOURNAL_OUTCOMES) {
      const def = METRIC_BY_KEY.get(key)!;
      const withVals: number[] = [], withoutVals: number[] = [];
      for (const e of logged) {
        const next = byDate.get(addDays(e.date, 1));
        const v = next ? def.get(next) : null;
        if (v !== null) (e.tags.includes(tag) ? withVals : withoutVals).push(v);
      }
      if (withVals.length < MIN_JOURNAL_DAYS || withoutVals.length < MIN_JOURNAL_DAYS) continue;
      const d = def.decimals + 1;
      const t = welchT(withVals, withoutVals);
      effects.push({
        metric: key,
        with: round(mean(withVals), d)!,
        without: round(mean(withoutVals), d)!,
        diff: round(mean(withVals)! - mean(withoutVals)!, d)!,
        nWith: withVals.length,
        nWithout: withoutVals.length,
        t: round(t, 1),
        clear: t !== null && Math.abs(t) >= 2,
      });
    }
    out.push({ tag, label: tagLabel(tag), days: n, effects });
  }
  return out.sort((a, b) => b.days - a.days || a.label.localeCompare(b.label));
}

/** "Sleep score" → "sleep score", but "HRV (RMSSD)" stays. */
export function lowerFirst(s: string): string {
  return s.length > 1 && s[1] === s[1].toLowerCase() ? s[0].toLowerCase() + s.slice(1) : s;
}

function journalInsight(impacts: TagImpact[]): Insight | null {
  let best: { impact: TagImpact; effect: TagEffect } | null = null;
  for (const impact of impacts) {
    for (const effect of impact.effects) {
      if (effect.clear && (!best || Math.abs(effect.t ?? 0) > Math.abs(best.effect.t ?? 0))) best = { impact, effect };
    }
  }
  if (!best) return null;
  const { impact, effect } = best;
  const def = METRIC_BY_KEY.get(effect.metric)!;
  const good = def.better === null ? null : (def.better === "higher") === effect.diff > 0;
  return {
    id: `journal_${impact.tag}_${effect.metric}`,
    title: `After ${lowerFirst(impact.label)} days: ${lowerFirst(def.label)} ${effect.diff > 0 ? "higher" : "lower"} by ${fmtValue(def, Math.abs(effect.diff))}`,
    body: `${fmtValue(def, effect.with)} after the ${effect.nWith} days you tagged ${lowerFirst(impact.label)}, ${fmtValue(def, effect.without)} after ${effect.nWithout} other logged days. A pattern in your data, not proof of cause.`,
    tone: good === null ? "neutral" : good ? "positive" : "negative",
    metric: effect.metric,
  };
}

// -------------------------------------------------------------- training load

export interface LoadPoint {
  date: Ymd;
  /** That day's TRIMP; null on a day without it, which counts as 0 load. */
  trimp: number | null;
  /** Fitness: 42-day exponentially weighted average of TRIMP. */
  ctl: number;
  /** Fatigue: the same over 7 days. */
  atl: number;
  /** ctl − atl. */
  form: number;
  /** Mean TRIMP of the last 7 days ÷ that of the last 28; null unless 21 of those 28 days have TRIMP. */
  acwr: number | null;
}

export interface TrainingLoad {
  series: LoadPoint[];
  latest: LoadPoint | null;
  status: "calibrating" | "fresh" | "neutral" | "productive" | "overreaching";
  /** acwr ≥ 1.5: the last week's load jumped well above the last month's. */
  spike: boolean;
  /** Days of the series with TRIMP. */
  days: number;
}

const LOAD_SERIES_DAYS = 180;
const LOAD_CALIBRATION_DAYS = 28;
const ACWR_MIN_DAYS = 21;

/**
 * Fitness, fatigue and form from daily TRIMP (fs_days.trimp), from the first day with TRIMP
 * through yesterday (today is still growing); a day without TRIMP counts as 0 load.
 * ctl += (TRIMP − ctl) / 42, atl += (TRIMP − atl) / 7, form = ctl − atl. Until 42 (or 7) days
 * exist the step is 1/n, the plain mean so far, so a short history neither reads as a sudden
 * overload nor depends on later days. The averages run over the whole history; the series keeps
 * the last 180 days.
 * acwr's means count a day without TRIMP as 0 too; while the history is under 28 days the
 * longer mean is over the days there are, so a steady start reads 1, not a spike. Status is
 * "calibrating" until 28 days have passed since the first TRIMP day, then r = form ÷ ctl:
 * over 0.1 fresh, −0.1…0.1 neutral, −0.3…−0.1 productive, under −0.3 overreaching.
 */
export function trainingLoad(days: DayRow[], today: Ymd): TrainingLoad {
  const trimp = new Map<Ymd, number>();
  for (const d of days) {
    if (d.date < today && typeof d.trimp === "number" && Number.isFinite(d.trimp)) trimp.set(d.date, d.trimp);
  }
  const dates = [...trimp.keys()].sort();
  if (!dates.length) return { series: [], latest: null, status: "calibrating", spike: false, days: 0 };
  const first = dates[0];
  // Until a time constant's worth of days exists, each average is the plain mean of the days so
  // far (step 1/n), so it never looks ahead and a new user doesn't start from 0 load.
  let ctl = 0, atl = 0, n = 0;
  const last28: (number | null)[] = [];
  const total = (xs: (number | null)[]) => xs.reduce<number>((s, v) => s + (v ?? 0), 0);
  const all: LoadPoint[] = [];
  for (let d = first; d < today; d = addDays(d, 1)) {
    const t = trimp.get(d) ?? null;
    n++;
    ctl += ((t ?? 0) - ctl) / Math.min(42, n);
    atl += ((t ?? 0) - atl) / Math.min(7, n);
    last28.push(t);
    if (last28.length > 28) last28.shift();
    const withTrimp = last28.filter((v) => v !== null).length;
    // A missing day is 0 load in both means; days before the first TRIMP day are not in the window.
    const m28 = total(last28) / last28.length, m7 = total(last28.slice(-7)) / 7;
    const c = round(ctl, 1)!, a = round(atl, 1)!;
    all.push({
      date: d,
      trimp: round(t, 1),
      ctl: c,
      atl: a,
      form: round(c - a, 1)!,
      acwr: withTrimp >= ACWR_MIN_DAYS && m28 > 0 ? round(m7 / m28, 2) : null,
    });
  }
  const series = all.slice(-LOAD_SERIES_DAYS);
  const latest = series[series.length - 1];
  let status: TrainingLoad["status"] = "calibrating";
  if (daysBetween(first, today) >= LOAD_CALIBRATION_DAYS) {
    const r = latest.ctl > 0 ? latest.form / latest.ctl : 0;
    status = r > 0.1 ? "fresh" : r >= -0.1 ? "neutral" : r >= -0.3 ? "productive" : "overreaching";
  }
  return {
    series,
    latest,
    status,
    spike: latest.acwr !== null && latest.acwr >= 1.5,
    days: series.filter((p) => p.trimp !== null).length,
  };
}

// -------------------------------------------------------------------- bedtime

export interface BedtimeBucket {
  label: string;
  /** In sleep_bedtime_min units (minutes from the wake day's midnight, negative = the evening before): from included, to excluded, null = open. */
  from: number | null;
  to: number | null;
  nights: number;
  /** Means over the bucket's nights, null under 3 nights; recovery is the next morning's. */
  sleepScore: number | null;
  asleepMin: number | null;
  recovery: number | null;
}

export interface BedtimeAnalysis {
  /** Nights looked at: the last 180 with a sleep score. */
  nights: number;
  buckets: BedtimeBucket[];
  /**
   * The bucket of 3+ nights with the highest mean sleep score; diff = its mean − the mean of all
   * other nights, clear = Welch's t ≥ 2. Null under 2 buckets of 3+ nights.
   */
  best: { label: string; diff: number; clear: boolean } | null;
}

const BEDTIME_BUCKETS: [string, number | null, number | null][] = [
  ["before 22:30", null, -90],
  ["22:30–23:00", -90, -60],
  ["23:00–23:30", -60, -30],
  ["23:30–00:00", -30, 0],
  ["00:00–00:30", 0, 30],
  ["00:30–01:00", 30, 60],
  ["after 01:00", 60, null],
];
const BEDTIME_NIGHTS = 180;
const MIN_BUCKET_NIGHTS = 3;

/** Sleep score, time asleep and the next morning's recovery by bedtime, over the last 180 scored nights. */
export function bedtimeAnalysis(days: DayRow[], today: Ymd): BedtimeAnalysis {
  const score = METRIC_BY_KEY.get("sleep_score")!, bed = METRIC_BY_KEY.get("sleep_bedtime_min")!;
  const asleep = METRIC_BY_KEY.get("sleep_asleep_min")!, recovery = METRIC_BY_KEY.get("recovery")!;
  const nights = days
    .filter((d) => d.date <= today && score.get(d) !== null && bed.get(d) !== null)
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
    .slice(-BEDTIME_NIGHTS);
  const groups = BEDTIME_BUCKETS.map(([label, from, to]) => ({
    label,
    from,
    to,
    rows: nights.filter((d) => {
      const v = bed.get(d)!;
      return (from === null || v >= from) && (to === null || v < to);
    }),
  }));
  const meanOf = (def: MetricDef, rows: DayRow[]) => {
    const vals = rows.map(def.get).filter((v): v is number => v !== null);
    return vals.length >= MIN_BUCKET_NIGHTS ? round(mean(vals), def.decimals + 1) : null;
  };
  const buckets = groups.map((g): BedtimeBucket => {
    const enough = g.rows.length >= MIN_BUCKET_NIGHTS;
    return {
      label: g.label,
      from: g.from,
      to: g.to,
      nights: g.rows.length,
      sleepScore: enough ? meanOf(score, g.rows) : null,
      asleepMin: enough ? meanOf(asleep, g.rows) : null,
      recovery: enough ? meanOf(recovery, g.rows) : null,
    };
  });
  const scores = (rows: DayRow[]) => rows.map((d) => score.get(d)!);
  const ranked = groups.filter((g) => g.rows.length >= MIN_BUCKET_NIGHTS);
  let best: BedtimeAnalysis["best"] = null;
  if (ranked.length >= 2) {
    const top = ranked.reduce((a, b) => (mean(scores(b.rows))! > mean(scores(a.rows))! ? b : a));
    const inTop = new Set(top.rows);
    const mine = scores(top.rows), others = scores(nights.filter((d) => !inTop.has(d)));
    const t = welchT(mine, others);
    best = { label: top.label, diff: round(mean(mine)! - mean(others)!, 1)!, clear: t !== null && t >= 2 };
  }
  return { nights: nights.length, buckets, best };
}

/** Minutes from midnight (negative = the evening before) as the phone shows times: "22:30" or "10:30 PM". */
export function clockLabel(min: number, clock24: boolean): string {
  const m = ((Math.round(min) % 1440) + 1440) % 1440;
  const h = Math.floor(m / 60), mm = String(m % 60).padStart(2, "0");
  if (clock24) return `${String(h).padStart(2, "0")}:${mm}`;
  return `${h % 12 === 0 ? 12 : h % 12}:${mm} ${h < 12 ? "AM" : "PM"}`;
}

function bedtimeInsight(b: BedtimeAnalysis, clock24: boolean): Insight | null {
  if (!b.best?.clear) return null;
  const bucket = b.buckets.find((x) => x.label === b.best!.label)!;
  const def = METRIC_BY_KEY.get("sleep_score")!;
  const when = bucket.from !== null && bucket.to !== null
    ? `between ${clockLabel(bucket.from, clock24)} and ${clockLabel(bucket.to, clock24)}`
    : bucket.from === null ? `before ${clockLabel(bucket.to!, clock24)}` : `after ${clockLabel(bucket.from, clock24)}`;
  return {
    id: "best_bedtime",
    title: `You sleep best going to bed ${when}`,
    body: `Average sleep score ${fmtValue(def, bucket.sleepScore!)} on the ${bucket.nights} nights you went to bed ${when}, ` +
      `versus ${fmtValue(def, bucket.sleepScore! - b.best.diff)} on your ${b.nights - bucket.nights} other nights. A pattern in your data, not proof of cause.`,
    tone: "positive",
    metric: "sleep_bedtime_min",
  };
}

// -------------------------------------------------------- heart-rate recovery

export type WorkoutRow = Record<string, unknown> & { id: string; date: Ymd };

export interface HrrPoint {
  id: string;
  date: Ymd;
  exerciseType: string | null;
  name: string | null;
  hrr1: number;
  hrr2: number | null;
  endHr: number;
}

/** Workouts with a heart-rate recovery (fs_exercise.hrr_1min) in the last 365 days, oldest first. */
export function hrrHistory(workouts: WorkoutRow[], today: Ymd): HrrPoint[] {
  const from = addDays(today, -364);
  const str = (v: unknown) => (typeof v === "string" ? v : null);
  return workouts
    .filter((x) => x.date >= from && x.date <= today && typeof x.hrr_1min === "number" && typeof x.end_hr === "number")
    .sort((a, b) => String(a.start_time ?? a.date).localeCompare(String(b.start_time ?? b.date)))
    .map((x) => ({
      id: x.id,
      date: x.date,
      exerciseType: str(x.exercise_type),
      name: str(x.name),
      hrr1: x.hrr_1min as number,
      hrr2: typeof x.hrr_2min === "number" ? x.hrr_2min : null,
      endHr: x.end_hr as number,
    }));
}

// ---------------------------------------------------------------------- build

export interface StatsPayload {
  generatedAt: string;
  /** The server version that built it: a newer server rebuilds it (index.ts stats). */
  server_version?: string;
  today: Ymd;
  firstDate: Ymd | null;
  dayCount: number;
  metrics: Record<string, MetricStats>;
  streaks: Streak[];
  correlations: Correlation[];
  insights: Insight[];
  journal: TagImpact[];
  load: TrainingLoad;
  bedtime: BedtimeAnalysis;
  hrr: HrrPoint[];
  /** Added by rebuildStats when their age is known (lib/bodyage.ts). */
  body_age?: BodyAge | null;
}

export function buildStats(
  daysUnsorted: DayRow[],
  today: Ymd,
  settings: { sleep_need_min: number; step_goal: number; clock_24h?: boolean | null },
  journal: { date: Ymd; tags: string[] }[] = [],
  workouts: WorkoutRow[] = [],
): StatsPayload {
  const days = [...daysUnsorted].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  const metrics: Record<string, MetricStats> = {};
  for (const def of METRICS) metrics[def.key] = metricStats(def, days, today);
  const azm = METRIC_BY_KEY.get("azm_total")!;
  const asleep = METRIC_BY_KEY.get("sleep_asleep_min")!;
  const streaks = [
    streak("steps_goal", `${settings.step_goal.toLocaleString("en-US")}+ steps`, days, today,
      (d) => (typeof d.steps === "number" ? d.steps >= settings.step_goal : null), false),
    streak("sleep_7h", "7h+ sleep", days, today, (d) => {
      const v = asleep.get(d);
      return v === null ? null : v >= 420;
    }, true),
    streak("azm_22", "22+ Active Zone Minutes", days, today, (d) => {
      const v = azm.get(d);
      return v === null ? null : v >= 22;
    }, false),
    streak("recovery_green", "Green recovery (67+)", days, today,
      (d) => (typeof d.recovery === "number" ? d.recovery >= 67 : null), true),
  ];
  const corr = correlations(days, today);
  const impacts = journalImpacts(days, journal, today);
  const notes = insights(days, today, settings, corr);
  const fromJournal = journalInsight(impacts);
  if (fromJournal) notes.push(fromJournal);
  const bedtime = bedtimeAnalysis(days, today);
  // Times as the phone shows them (the app tells the server with each coach request); 24-hour until then.
  const fromBedtime = bedtimeInsight(bedtime, settings.clock_24h !== false);
  if (fromBedtime) notes.push(fromBedtime);
  return {
    generatedAt: new Date().toISOString(),
    today,
    firstDate: days.length ? days[0].date : null,
    dayCount: days.length,
    metrics,
    streaks,
    correlations: corr,
    insights: notes,
    journal: impacts,
    load: trainingLoad(days, today),
    bedtime,
    hrr: hrrHistory(workouts, today),
  };
}
