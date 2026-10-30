// Small, dependency-free helpers shared by the sync engine, scores and stats.

export type Ymd = string; // "YYYY-MM-DD"

export const MINUTES_PER_DAY = 1440;

/** int64 fields arrive as JSON strings ("62"); int32/double as numbers. */
export function num(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

export function int(v: unknown): number | null {
  const n = num(v);
  return n === null ? null : Math.round(n);
}

/** Google duration strings: "3600s", "1.5s", "-7200s". Returns seconds. */
export function durationSeconds(v: unknown): number | null {
  if (typeof v !== "string") return num(v);
  const m = /^(-?\d+(?:\.\d+)?)s$/.exec(v.trim());
  return m ? Number(m[1]) : null;
}

export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function ymdFromParts(year: number, month: number, day: number): Ymd {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

/** Google `Date` message ({year, month, day}) to "YYYY-MM-DD". */
export function ymdFromGoogleDate(d: unknown): Ymd | null {
  if (!d || typeof d !== "object") return null;
  const o = d as Record<string, unknown>;
  const y = num(o.year), m = num(o.month), day = num(o.day);
  if (!y || !m || !day) return null;
  return ymdFromParts(y, m, day);
}

export function googleDateFromYmd(ymd: Ymd): { year: number; month: number; day: number } {
  const [y, m, d] = ymd.split("-").map(Number);
  return { year: y, month: m, day: d };
}

/** UTC midnight epoch ms of a calendar date (used only for date arithmetic). */
export function ymdToUtcMs(ymd: Ymd): number {
  const [y, m, d] = ymd.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

export function utcMsToYmd(ms: number): Ymd {
  const dt = new Date(ms);
  return ymdFromParts(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

export function addDays(ymd: Ymd, n: number): Ymd {
  return utcMsToYmd(ymdToUtcMs(ymd) + n * 86_400_000);
}

/** Whole days from a to b (b - a). */
export function daysBetween(a: Ymd, b: Ymd): number {
  return Math.round((ymdToUtcMs(b) - ymdToUtcMs(a)) / 86_400_000);
}

export function dateRange(start: Ymd, endExclusive: Ymd): Ymd[] {
  const out: Ymd[] = [];
  for (let d = start; d < endExclusive; d = addDays(d, 1)) out.push(d);
  return out;
}

/** 0 = Monday ... 6 = Sunday. */
export function weekdayIndex(ymd: Ymd): number {
  const js = new Date(ymdToUtcMs(ymd)).getUTCDay(); // 0 = Sunday
  return (js + 6) % 7;
}

const offsetFormatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let f = offsetFormatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    offsetFormatters.set(timeZone, f);
  }
  return f;
}

/** UTC offset (seconds) of an IANA zone at an instant. Falls back to 0 for unknown zones. */
export function zoneOffsetSeconds(timeZone: string, epochMs: number): number {
  try {
    const parts = formatterFor(timeZone).formatToParts(new Date(epochMs));
    const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
    const asUtc = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
    const wholeSecondMs = epochMs - (((epochMs % 1000) + 1000) % 1000);
    return Math.round((asUtc - wholeSecondMs) / 1000);
  } catch {
    return 0;
  }
}

/**
 * Converts instants to local wall-clock positions for one time zone.
 * Offsets are cached per UTC hour, which is exact for every zone whose
 * transitions fall on the hour (all zones Google Health users are likely in).
 */
export class LocalClock {
  private cache = new Map<number, number>();
  readonly timeZone: string | null;
  readonly fixedOffsetSeconds: number;

  constructor(timeZone: string | null, fixedOffsetSeconds = 0) {
    this.timeZone = timeZone;
    this.fixedOffsetSeconds = fixedOffsetSeconds;
  }

  offsetSeconds(epochMs: number): number {
    if (!this.timeZone) return this.fixedOffsetSeconds;
    const hourKey = Math.floor(epochMs / 3_600_000);
    let off = this.cache.get(hourKey);
    if (off === undefined) {
      off = zoneOffsetSeconds(this.timeZone, epochMs);
      this.cache.set(hourKey, off);
    }
    return off;
  }

  /** Local calendar date and minute-of-day (0..1439) of an instant. */
  locate(epochMs: number): { date: Ymd; minute: number } {
    const local = epochMs + this.offsetSeconds(epochMs) * 1000;
    const dt = new Date(local);
    return {
      date: ymdFromParts(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate()),
      minute: dt.getUTCHours() * 60 + dt.getUTCMinutes(),
    };
  }

  today(nowMs = Date.now()): Ymd {
    return this.locate(nowMs).date;
  }

  /** Epoch ms of local midnight starting `ymd`. */
  midnightMs(ymd: Ymd): number {
    const guess = ymdToUtcMs(ymd);
    let t = guess - this.offsetSeconds(guess) * 1000;
    t = guess - this.offsetSeconds(t) * 1000;
    return t;
  }
}

export function round(v: number | null | undefined, decimals = 1): number | null {
  if (v === null || v === undefined || !Number.isFinite(v)) return null;
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

export function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

export function mean(xs: number[]): number | null {
  if (xs.length === 0) return null;
  let s = 0;
  for (const x of xs) s += x;
  return s / xs.length;
}

/** Sample standard deviation (n - 1). */
export function stdDev(xs: number[]): number | null {
  if (xs.length < 2) return null;
  const m = mean(xs)!;
  let s = 0;
  for (const x of xs) s += (x - m) * (x - m);
  return Math.sqrt(s / (xs.length - 1));
}

export function median(xs: number[]): number | null {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

export function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

/** Runs `p` after the response is sent (Supabase Edge Runtime), logging a failure. */
export function background(p: Promise<unknown>): void {
  const rt = (globalThis as unknown as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
  const guarded = p.catch((e) => console.error("background task failed", String(e)));
  if (rt?.waitUntil) rt.waitUntil(guarded);
}
