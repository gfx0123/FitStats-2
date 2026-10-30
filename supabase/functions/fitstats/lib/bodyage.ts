// Body age: the age whose typical person has your fitness, steps, exercise and sleep. Each
// factor's relative risk of death against a reference (from the studies below) becomes years
// with the Gompertz law: adult mortality roughly doubles every 8 years, so a relative risk RR
// is worth 8 × log2(RR) years of age. It is an estimate from population studies, not a
// biological or medical test, and the combination is FitStats' own (not a validated score).
//
// Sources (the numbers used are from their abstracts):
// - VO₂ max ≈ 15.3 × HRmax / HRrest for men (Uth et al., Eur J Appl Physiol 2004), 14.5 for
//   women (Uth et al. 2005); about 4.7 ml/kg/min error with an estimated max heart rate.
// - Typical VO₂ max: 54.4 (men) and 43.0 (women) ml/kg/min at 20–29 years, about 3.5 lower per
//   decade (Loe et al., PLoS One 2013, HUNT3, Norway).
// - All-cause mortality RR 0.87 per 1 MET (3.5 ml/kg/min) higher fitness (Kodama et al., JAMA 2009).
// - Steps: HR 1, 0.60, 0.55 and 0.47 at quartile medians 3553, 5801, 7842 and 10 901 steps/day;
//   no further benefit past 6000–8000 (60+) or 8000–10 000 (under 60) (Paluch et al., Lancet
//   Public Health 2022).
// - Leisure activity: HR 0.80, 0.69, 0.63 and 0.61 at under 1, 1–2, 2–3 and 3–5 times the
//   7.5 MET-h/week minimum, against none (the upper threshold of benefit), and 0.69 at 10 or more
//   times (Arem et al., JAMA Intern Med 2015). 5–10 times isn't in the abstract: kept at 0.61.
// - Sleep: RR 1.12 for short and 1.30 for long sleep against 7–8 h (Cappuccio et al., Sleep 2010).
// - Human mortality rate doubling time "about 8 years" (Finch, Pike & Witten, Science 1990).
// Uth's estimate was tested in trained men and women; it's used here because the band doesn't
// report VO₂ max.

import type { Ymd } from "./util.ts";

export const DOUBLING_YEARS = 8;
/** Days of data each estimate uses (ending yesterday, as today isn't finished). */
export const WINDOW_DAYS = 30;
/** The fewest days with the measure for a factor to count. */
export const MIN_DAYS = 14;
const MAX_TOTAL_YEARS = 15;
/** The studies are of adults; from 16 the youngest adults (20–29) stand in. */
export const MIN_AGE = 16;

type Day = Record<string, unknown> & { date: Ymd };

export interface BodyAgeInput {
  /** Whole years, from their Google profile. */
  age: number;
  sex: string;
  /** The max heart rate strain uses (set by hand, their sustained peak or 208 − 0.7 × age). */
  maxHr: number;
  maxHrSource: string;
}

export interface BodyAgeFactor {
  key: "fitness" | "steps" | "exercise" | "sleep";
  label: string;
  /** Their value and its unit, e.g. 8213 "steps a day". */
  value: number;
  unit: string;
  /** What they're compared with, in words. */
  reference: string;
  /** + older, − younger than their age. */
  years: number;
  detail: string;
  source: string;
  days: number;
}

export interface BodyAge {
  age: number;
  body_age: number;
  /** body_age − age. */
  difference: number;
  factors: BodyAgeFactor[];
  /** Factors without enough data (e.g. "sleep: 9 of 14 nights needed"). */
  missing: string[];
  vo2max: { value: number; typical_for_age: number; method: string; error_ml_kg_min: number } | null;
  what_if: { change: string; years: number }[];
  /** A point every 7 days over the last 6 months, oldest first. */
  history: { date: Ymd; body_age: number }[];
  window: { from: Ymd; to: Ymd };
  note: string;
}

export function yearsFromRisk(rr: number): number {
  return DOUBLING_YEARS * Math.log2(rr);
}

/** Linear interpolation through (x, y) points sorted by x, flat beyond both ends. */
function curve(points: [number, number][], x: number): number {
  if (x <= points[0][0]) return points[0][1];
  for (let i = 1; i < points.length; i++) {
    const [x1, y1] = points[i];
    if (x <= x1) {
      const [x0, y0] = points[i - 1];
      return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
  }
  return points[points.length - 1][1];
}

const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
}

const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
const r1 = (v: number) => Math.round(v * 10) / 10;

// ---------------------------------------------------------------- factors

/** Typical VO₂ max for an age (Loe et al. 2013): the 20–29 mean, 3.5 lower per decade after 25. */
export function typicalVo2(age: number, sex: string): number {
  const base = sex === "female" ? 43.0 : 54.4;
  return base - 0.35 * Math.max(0, age - 25);
}

/** VO₂ max from the heart-rate ratio (Uth et al. 2004, 2005). */
export function vo2FromHeartRate(maxHr: number, restingHr: number, sex: string): number {
  return (sex === "female" ? 14.5 : 15.3) * maxHr / restingHr;
}

export function fitnessYears(vo2: number, age: number, sex: string): number {
  const mets = (vo2 - typicalVo2(age, sex)) / 3.5;
  return yearsFromRisk(Math.pow(0.87, mets));
}

const STEP_RISK: [number, number][] = [[3553, 1], [5801, 0.60], [7842, 0.55], [10901, 0.47]];
/** The middle of the studied adults: halfway between the 2nd and 3rd quartile medians. */
export const STEP_REFERENCE = Math.round((5801 + 7842) / 2);

export function stepsYears(steps: number, age: number): number {
  // Past the plateau more steps don't lower the risk further.
  const capped = Math.min(steps, age >= 60 ? 8000 : 10901);
  return yearsFromRisk(curve(STEP_RISK, capped) / curve(STEP_RISK, STEP_REFERENCE));
}

/** Multiples of the 7.5 MET-h/week minimum (group midpoints) → hazard ratio against none. */
const ACTIVITY_RISK: [number, number][] = [[0, 1], [0.5, 0.80], [1.5, 0.69], [2.5, 0.63], [4, 0.61], [9.99, 0.61], [10, 0.69]];

/** MET-hours a week from moderate (3 MET) and vigorous (6 MET) minutes a week. */
export function metHours(moderateMinWeek: number, vigorousMinWeek: number): number {
  return (moderateMinWeek * 3 + vigorousMinWeek * 6) / 60;
}

export function exerciseYears(metHoursWeek: number): number {
  return yearsFromRisk(curve(ACTIVITY_RISK, metHoursWeek / 7.5) / curve(ACTIVITY_RISK, 1));
}

/** Time in bed (studies asked people how long they sleep, which is closer to time in bed). */
export function sleepYears(hours: number): number {
  const rr = hours < 7 ? curve([[6, 1.12], [7, 1]], hours) : hours > 8.5 ? curve([[8.5, 1], [9, 1.30]], hours) : 1;
  return yearsFromRisk(rr);
}

// ---------------------------------------------------------------- the estimate

interface Window {
  rhr: number[];
  steps: number[];
  moderate: number[];
  vigorous: number[];
  inBed: number[];
  from: Ymd;
  to: Ymd;
}

function windowOf(days: Day[], end: Ymd, from: Ymd): Window {
  const w: Window = { rhr: [], steps: [], moderate: [], vigorous: [], inBed: [], from, to: end };
  for (const d of days) {
    if (d.date < from || d.date > end) continue;
    const rhr = num(d.rhr);
    if (rhr !== null && rhr > 25 && rhr < 130) w.rhr.push(rhr);
    const inBed = num(d.sleep_in_bed_min);
    if (inBed !== null && inBed >= 120) w.inBed.push(inBed);
    // Day totals only from days worn as usual.
    if (d.low_wear === true) continue;
    const steps = num(d.steps);
    if (steps !== null) w.steps.push(steps);
    const mod = num(d.active_moderate_min), vig = num(d.active_vigorous_min);
    if (mod !== null || vig !== null) {
      w.moderate.push(mod ?? 0);
      w.vigorous.push(vig ?? 0);
    }
  }
  return w;
}

function factorsFor(w: Window, input: BodyAgeInput): { factors: BodyAgeFactor[]; missing: string[]; vo2: number | null } {
  const factors: BodyAgeFactor[] = [];
  const missing: string[] = [];
  const need = (what: string, have: number) => missing.push(`${what}: ${have} of ${MIN_DAYS} days`);
  const female = input.sex === "female";
  let vo2: number | null = null;

  if (w.rhr.length >= MIN_DAYS) {
    const rhr = median(w.rhr);
    vo2 = vo2FromHeartRate(input.maxHr, rhr, input.sex);
    const typical = typicalVo2(input.age, input.sex);
    factors.push({
      key: "fitness", label: "Cardio fitness", value: r1(vo2), unit: "ml/kg/min (estimated VO₂ max)",
      reference: `${r1(typical)}, typical for ${female ? "women" : "men"} your age`,
      years: fitnessYears(vo2, input.age, input.sex),
      detail: `Estimated from your max heart rate ${input.maxHr} and resting heart rate ${Math.round(rhr)} bpm (30-day median). Each 3.5 ml/kg/min is linked with 13% lower mortality.`,
      source: "Uth 2004 (estimate), Loe 2013 (typical values), Kodama 2009 (risk)",
      days: w.rhr.length,
    });
  } else need("resting heart rate", w.rhr.length);

  if (w.steps.length >= MIN_DAYS) {
    const steps = mean(w.steps);
    factors.push({
      key: "steps", label: "Daily steps", value: Math.round(steps), unit: "steps a day",
      reference: `${STEP_REFERENCE.toLocaleString("en-US")}, the middle of the adults studied`,
      years: stepsYears(steps, input.age),
      detail: `Risk falls with more steps until about ${input.age >= 60 ? "6,000–8,000" : "8,000–10,000"} a day at your age, then levels off.`,
      source: "Paluch 2022 (15 studies, 47,471 adults)",
      days: w.steps.length,
    });
  } else need("steps", w.steps.length);

  if (w.moderate.length >= MIN_DAYS) {
    const modWeek = mean(w.moderate) * 7, vigWeek = mean(w.vigorous) * 7;
    const met = metHours(modWeek, vigWeek);
    factors.push({
      key: "exercise", label: "Exercise", value: Math.round(modWeek + vigWeek), unit: "active minutes a week",
      reference: "150 moderate minutes a week (the WHO minimum)",
      years: exerciseYears(met),
      detail: `${Math.round(modWeek)} moderate and ${Math.round(vigWeek)} vigorous minutes a week, ${r1(met / 7.5)}× the minimum. The benefit levels off at about 3–5×.`,
      source: "Arem 2015 (6 cohorts, 661,137 adults)",
      days: w.moderate.length,
    });
  } else need("exercise minutes", w.moderate.length);

  if (w.inBed.length >= MIN_DAYS) {
    const hours = mean(w.inBed) / 60;
    factors.push({
      key: "sleep", label: "Sleep", value: r1(hours), unit: "hours in bed a night",
      reference: "7–8.5 hours",
      years: sleepYears(hours),
      detail: "Short (under about 7 h) and long sleep (over about 9 h) are both linked with higher mortality.",
      source: "Cappuccio 2010 (16 studies)",
      days: w.inBed.length,
    });
  } else need("sleep", w.inBed.length);

  return { factors, missing, vo2 };
}

/**
 * Steps and exercise measure much the same activity, so they count as one: their average.
 * Fitness, activity and sleep add up, kept within ±15 years.
 */
export function combine(factors: BodyAgeFactor[]): number {
  const y = (k: string) => factors.find((f) => f.key === k)?.years;
  const activity = [y("steps"), y("exercise")].filter((v): v is number => v !== undefined);
  const total = (y("fitness") ?? 0) + (activity.length ? mean(activity) : 0) + (y("sleep") ?? 0);
  return Math.max(-MAX_TOTAL_YEARS, Math.min(MAX_TOTAL_YEARS, total));
}

/** The estimate for the 30 days ending yesterday, or null without the age or a single factor. */
export function bodyAge(daysAll: Day[], today: Ymd, input: BodyAgeInput, addDays: (d: Ymd, n: number) => Ymd): BodyAge | null {
  if (!Number.isFinite(input.age) || input.age < MIN_AGE || input.age > 100 || !(input.maxHr > 100)) return null;
  const end = addDays(today, -1);
  const from = addDays(end, -(WINDOW_DAYS - 1));
  const w = windowOf(daysAll, end, from);
  const { factors, missing, vo2 } = factorsFor(w, input);
  if (!factors.length) return null;
  const difference = combine(factors);

  // What-ifs: the change in body age from one change, the rest as it is.
  const whatIf: { change: string; years: number }[] = [];
  const recompute = (patched: BodyAgeFactor[]) => r1(combine(patched) - difference);
  const steps = factors.find((f) => f.key === "steps");
  if (steps) {
    const more = { ...steps, years: stepsYears(steps.value + 2000, input.age) };
    const d = recompute(factors.map((f) => (f.key === "steps" ? more : f)));
    if (d < -0.05) whatIf.push({ change: "2,000 more steps a day", years: d });
  }
  const exercise = factors.find((f) => f.key === "exercise");
  if (exercise && w.moderate.length) {
    const met = metHours(mean(w.moderate) * 7 + 60, mean(w.vigorous) * 7);
    const d = recompute(factors.map((f) => (f.key === "exercise" ? { ...f, years: exerciseYears(met) } : f)));
    if (d < -0.05) whatIf.push({ change: "1 more hour of moderate exercise a week", years: d });
  }
  const fitness = factors.find((f) => f.key === "fitness");
  if (fitness && vo2 !== null) {
    const better = vo2 + 3.5;
    const d = recompute(factors.map((f) => (f.key === "fitness" ? { ...f, years: fitnessYears(better, input.age, input.sex) } : f)));
    if (d < -0.05) whatIf.push({ change: "VO₂ max 3.5 ml/kg/min higher", years: d });
  }
  const sleep = factors.find((f) => f.key === "sleep");
  if (sleep && sleep.years > 0.05) {
    const d = recompute(factors.map((f) => (f.key === "sleep" ? { ...f, years: 0 } : f)));
    if (d < -0.05) whatIf.push({ change: "7–8.5 hours in bed a night", years: d });
  }

  // History: the same estimate every 7 days back over 6 months, where there was enough data.
  const history: { date: Ymd; body_age: number }[] = [];
  for (let back = 26; back >= 0; back--) {
    const e = addDays(end, -7 * back);
    const hw = windowOf(daysAll, e, addDays(e, -(WINDOW_DAYS - 1)));
    const h = factorsFor(hw, input);
    if (h.factors.length >= 2) history.push({ date: e, body_age: r1(input.age + combine(h.factors)) });
  }

  return {
    age: input.age,
    body_age: r1(input.age + difference),
    difference: r1(difference),
    factors: factors.map((f) => ({ ...f, years: r1(f.years) })),
    missing,
    vo2max: vo2 === null ? null : {
      value: r1(vo2), typical_for_age: r1(typicalVo2(input.age, input.sex)),
      method: `15.3 × max HR ÷ resting HR (Uth 2004${input.sex === "female" ? "; 14.5 for women, Uth 2005" : ""}); max HR ${input.maxHr} (${input.maxHrSource})`,
      error_ml_kg_min: 4.7,
    },
    what_if: whatIf.sort((a, b) => a.years - b.years),
    history,
    window: { from, to: end },
    note: "An estimate from population studies (risk of death converted to years of age), not a medical or biological test. " +
      "Your band doesn't report VO₂ max, so fitness is estimated from heart rate (about ±4.7 ml/kg/min)." +
      (input.age < 20 ? " The studies are of adults; at your age you're compared with 20–29-year-olds, so treat it as a rough guide." : ""),
  };
}
