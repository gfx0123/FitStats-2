// Sync engine: pulls Google Health data into fs_* tables, then recomputes
// scores and the statistics cache. Runs from cron every 5 minutes and on
// demand from the app; a database lock prevents overlapping runs. When the
// recent days come back exactly as last time, nothing is written or recomputed.

import { type BodyAge, bodyAge, type Lifestyle, lifestyleFrom } from "./bodyage.ts";
import * as db from "./db.ts";
import { GoogleApiError, HealthClient, refreshAccessToken } from "./google.ts";
import { journalEntries } from "./journal.ts";
import {
  computeRecovery,
  computeSleepScore,
  computeStrain,
  computeStress,
  computeWorkoutLoad,
  COOL_DOWN_MAX,
  coolDownMinutes,
  type DayRow,
  heartRateRecovery,
  HRR_CLEAR_MIN,
  strainTarget,
  STRESS_BASELINE_DAYS,
  stressBaseline,
  type WorkoutRecovery,
} from "./scores.ts";
import { buildStats, type WorkoutRow } from "./stats.ts";
import {
  chooseMaxHr,
  DAILY_TYPES,
  dailyPointsToPatches,
  type DayPatch,
  type ExerciseRow,
  exercisePointToRow,
  type IntradayDay,
  type Json,
  type MaxHr,
  minutesBetween,
  placeMinuteRollups,
  ROLLUP_TYPES,
  rollupPointsToPatches,
  type SampleRow,
  samplePointsToRows,
  SLEEP_DAY_COLUMNS,
  sleepDayPatch,
  sleepPointToRow,
  type SleepRow,
  stepsByHour,
  sustainedPeak,
  vo2SamplePatches,
  wearMinutes,
} from "./transform.ts";
import { addDays, dateRange, LocalClock, median, MINUTES_PER_DAY, round, type Ymd, ymdFromGoogleDate } from "./util.ts";
import { VERSION } from "./version.ts";

export interface Account {
  google_sub: string | null;
  google_email: string | null;
  refresh_token: string | null;
  access_token: string | null;
  access_token_expires_at: string | null;
  token_status: string;
  time_zone: string | null;
  profile: Json | null;
  google_settings: Json | null;
  meta_fetched_at: string | null;
}

export interface UserSettings {
  sex: string;
  max_hr_override: number | null;
  sleep_need_min: number;
  step_goal: number;
  backfill_days: number;
  coach_model?: string | null;
  /** Wake-up times set by hand (lib/planner.ts WakeTimes); missing before the column existed. */
  wake_times?: unknown;
  /** The phone's clock: true for 24 hours, false for 12, null until the app has said. */
  clock_24h?: boolean | null;
  /** Answers to the Body age questions (lib/bodyage.ts Lifestyle); null until answered. */
  lifestyle?: unknown;
}

interface SyncState {
  backfill_oldest: Ymd | null;
  backfill_target: Ymd | null;
  backfill_done: boolean;
  backfill_empty_chunks: number;
  last_recent_sync_at: string | null;
  recent_fingerprint: string | null;
  stats_dirty: boolean;
  /** The max heart rate the stored history was computed with, and where it came from. */
  max_hr_used: number | null;
  max_hr_source: MaxHr["source"] | null;
}

interface TaskResult {
  name: string;
  ok: boolean;
  count?: number;
  error?: string;
  optional?: boolean;
}

interface RangeLog {
  range: string;
  ms: number;
  points: number;
  /** Per successful task: what Google returned, or [points, dates] for daily types, so 0 points can be told from points that did not map. */
  counts?: Record<string, number | [number, number]>;
  failed: TaskResult[];
  /** Optional tasks that failed: logged, but the run stays ok. */
  skipped?: TaskResult[];
  unchanged?: boolean;
}

interface RangeResult {
  points: number;
  /** Hash of everything the range would write; null when a write failed. */
  fingerprint: string | null;
  /** Same data as `previous`: nothing was written. */
  unchanged: boolean;
}

export interface RunLog {
  reason: string;
  started: string;
  finished?: string;
  status: "ok" | "partial" | "skipped" | "token_expired" | "error" | "not_connected";
  calls: number;
  ranges: RangeLog[];
  message?: string;
}

export class TokenExpiredError extends Error {}

const BACKFILL_CHUNK_DAYS = 14;
const EMPTY_CHUNKS_TO_STOP = 8;
const RECENT_DAYS = 3;
/** Cron runs every 5 minutes; anything older than this is fetched again. */
const RECENT_STALE_MS = 4 * 60_000;
/** Recent changes rebuild the statistics cache at most this often: it reads the whole
 * history, which counts as egress. A new day or imported history rebuilds it at once. */
const STATS_MAX_AGE_MS = 60 * 60_000;

function nowIso(): string {
  return new Date().toISOString();
}

export async function loadAccount(): Promise<Account | null> {
  return await db.selectOne<Account>("fs_account", "select=*&id=eq.1");
}

export async function loadSettings(): Promise<UserSettings> {
  const s = await db.selectOne<UserSettings>("fs_user_settings", "select=*&id=eq.1");
  return s ?? { sex: "unspecified", max_hr_override: null, sleep_need_min: 480, step_goal: 10000, backfill_days: 730, coach_model: null };
}

export function clockFor(account: Account | null): LocalClock {
  const tz = account?.time_zone ?? null;
  if (tz) return new LocalClock(tz);
  const off = account?.google_settings?.utcOffset;
  const seconds = typeof off === "string" ? Number(off.replace(/s$/, "")) : 0;
  return new LocalClock(null, Number.isFinite(seconds) ? seconds : 0);
}

async function accessToken(acc: Account, force = false): Promise<string> {
  const exp = acc.access_token_expires_at ? Date.parse(acc.access_token_expires_at) : 0;
  if (!force && acc.access_token && exp - Date.now() > 120_000) return acc.access_token;
  if (!acc.refresh_token) throw new TokenExpiredError("No refresh token stored; connect Google again.");
  try {
    const t = await refreshAccessToken(acc.refresh_token, db.env("GOOGLE_CLIENT_ID"), db.env("GOOGLE_CLIENT_SECRET"));
    const expiresAt = new Date(Date.now() + (t.expires_in ?? 3600) * 1000).toISOString();
    const patch: Record<string, unknown> = {
      access_token: t.access_token,
      access_token_expires_at: expiresAt,
      token_status: "ok",
      token_error: null,
      updated_at: nowIso(),
    };
    if (t.refresh_token) patch.refresh_token = t.refresh_token;
    await db.update("fs_account", "id=eq.1", patch);
    acc.access_token = t.access_token;
    acc.access_token_expires_at = expiresAt;
    return t.access_token;
  } catch (e) {
    if (e instanceof GoogleApiError && (e.reason === "invalid_grant" || e.status === 401)) {
      await db.update("fs_account", "id=eq.1", {
        token_status: "expired",
        token_error: e.message,
        access_token: null,
        updated_at: nowIso(),
      });
      throw new TokenExpiredError(e.message);
    }
    throw e;
  }
}

async function refreshMeta(client: HealthClient, acc: Account): Promise<void> {
  const fresh = acc.meta_fetched_at && Date.now() - Date.parse(acc.meta_fetched_at) < 6 * 3_600_000;
  if (fresh) return;
  const patch: Record<string, unknown> = { meta_fetched_at: nowIso(), updated_at: nowIso() };
  try {
    const p = await client.getProfile();
    patch.profile = p;
    acc.profile = p;
  } catch (e) {
    console.warn("profile", String(e));
  }
  try {
    const s = await client.getSettings();
    patch.google_settings = s;
    acc.google_settings = s;
    if (typeof s.timeZone === "string" && s.timeZone) {
      patch.time_zone = s.timeZone;
      acc.time_zone = s.timeZone;
    }
  } catch (e) {
    console.warn("settings", String(e));
  }
  await db.update("fs_account", "id=eq.1", patch);
}

/** Paired devices, fetched with every recent sync: the band's `lastSyncTime` (its last
 * sync with the Fitbit app) tells whether newer data can be at Google yet. */
async function refreshDevices(client: HealthClient): Promise<void> {
  try {
    const d = await client.listDevices();
    await db.update("fs_account", "id=eq.1", { devices: d.pairedDevices ?? [], updated_at: nowIso() });
  } catch (e) {
    if (e instanceof TokenExpiredError) throw e;
    console.warn("devices", String(e));
  }
}

/** JSON with object keys sorted, so equal data always gives the same text. */
function stableJson(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(stableJson).join(",")}]`;
  if (v !== null && typeof v === "object") {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).sort().map((k) => `${JSON.stringify(k)}:${stableJson(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(v) ?? "null";
}

async function fingerprintOf(v: unknown): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(stableJson(v)));
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const byId = (a: { id: string }, b: { id: string }) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

async function pool<T>(items: T[], size: number, fn: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next++];
      await fn(item);
    }
  });
  await Promise.all(workers);
}

interface Task {
  name: string;
  columns: string[];
  run: () => Promise<number>;
  /** Its failure (say Google rejects the data type for this device) is logged but leaves the run ok. */
  optional?: boolean;
}

/** Day columns computed from minute heart rate, from minute steps, and from both. */
const HR_COLUMNS = ["trimp", "strain", "intraday_details", "wear_min", "hr_peak_sustained"];
const STEPS_COLUMNS = ["steps_by_hour"];
const STRESS_COLUMNS = ["stress", "stress_minutes", "stress_still_hrr"];
/** Derived columns that alone don't make a day worth a row. */
const DERIVED_ONLY = new Set(["date", "intraday_details", "wear_min", "steps_by_hour"]);
/** A new effective max heart rate this far from the one in use recomputes the history. */
const MAX_HR_RECOMPUTE_BPM = 2;

type HrFor = (date: Ymd) => (number | null)[] | null | undefined;

/** What stress leaves out for a workout: from its start until heart rate has recovered after it (coolDownMinutes). */
function workoutExclusion(x: ExerciseRow, clock: LocalClock, hrFor: HrFor, rhr: number, maxHr: number, baselineHrr: number): [number, number] {
  const start = Math.floor(Date.parse(x.start_time) / 60000) * 60000;
  const end = Date.parse(x.end_time);
  const before = minutesBetween(start - 30 * 60000, start, clock, hrFor);
  const after = minutesBetween(end, end + (COOL_DOWN_MAX + 2) * 60000, clock, hrFor);
  return [start, end + coolDownMinutes(before, after, rhr, maxHr, baselineHrr) * 60000];
}

/** Minute steps summed over a workout's window (the minutes minutesBetween covers), null without step data. */
function workoutSteps(x: ExerciseRow, clock: LocalClock, stepsFor: HrFor): number | null {
  const steps = minutesBetween(Date.parse(x.start_time), Date.parse(x.end_time), clock, stepsFor);
  return steps.some((v) => typeof v === "number") ? steps.reduce<number>((a, v) => a + (v ?? 0), 0) : null;
}

/**
 * Heart-rate recovery of a workout (heartRateRecovery) from its minute window and the 2 minutes
 * after it. Another workout overlapping the 3 minutes after the end (`all`) leaves it null.
 */
export function workoutRecovery(x: ExerciseRow, all: ExerciseRow[], clock: LocalClock, hrFor: HrFor, rhr: number, maxHr: number): WorkoutRecovery {
  const start = Math.floor(Date.parse(x.start_time) / 60000) * 60000;
  const end = Date.parse(x.end_time);
  const hr = minutesBetween(start, end, clock, hrFor);
  const windowEnd = start + hr.length * 60000;
  const after = minutesBetween(windowEnd, windowEnd + 2 * 60000, clock, hrFor);
  const clear = !all.some((o) => o.id !== x.id && Date.parse(o.start_time) < end + HRR_CLEAR_MIN * 60000 && Date.parse(o.end_time) > end);
  return heartRateRecovery(hr, after, rhr, maxHr, clear);
}

/** Minute mask (true = skip for stress) for sleep and workouts with their recovery (`workouts`, ms ranges) on one local day. */
function exclusionMask(date: Ymd, sleeps: SleepRow[], workouts: [number, number][], clock: LocalClock): boolean[] {
  const mask = new Array(MINUTES_PER_DAY).fill(false);
  const dayStart = clock.midnightMs(date);
  const dayEnd = clock.midnightMs(addDays(date, 1));
  const mark = (a: number, b: number) => {
    const s = Math.max(a, dayStart), e = Math.min(b, dayEnd);
    if (e <= s) return;
    const from = Math.floor((s - dayStart) / 60000);
    const to = Math.min(MINUTES_PER_DAY, Math.ceil((e - dayStart) / 60000));
    for (let m = from; m < to; m++) mask[m] = true;
  };
  for (const s of sleeps) mark(Date.parse(s.start_time), Date.parse(s.end_time));
  for (const [a, b] of workouts) mark(a, b);
  return mask;
}

/** Stress columns and details for one day; adds the day's still level to `still` for the next days' baselines. */
function stressOfDay(
  date: Ymd,
  m: { hr: (number | null)[]; steps: (number | null)[]; sedentary: (number | null)[] | null },
  ctx: { sleeps: SleepRow[]; exercises: ExerciseRow[]; excluded: [number, number][]; still: Map<Ymd, number>; clock: LocalClock; hrFor: HrFor },
  rhr: number,
  maxHr: number,
): { row: Record<string, unknown>; details: Record<string, unknown> } {
  const baseline = stressBaseline(date, ctx.still);
  for (const x of ctx.exercises) {
    if (x.date === date) ctx.excluded.push(workoutExclusion(x, ctx.clock, ctx.hrFor, rhr, maxHr, baseline.hrr));
  }
  const mask = exclusionMask(date, ctx.sleeps, ctx.excluded, ctx.clock);
  const st = computeStress(m.hr, m.steps, rhr, maxHr, mask, baseline.hrr, m.sedentary);
  if (st.stillHrr !== null) ctx.still.set(date, st.stillHrr);
  return {
    row: { stress: st.stress, stress_minutes: st.minutes, stress_still_hrr: st.stillHrr },
    details: {
      stressHourly: st.hourly,
      stressBaseline: { hrr: round(baseline.hrr, 4), bpm: Math.round(rhr + baseline.hrr * (maxHr - rhr)), days: baseline.days },
    },
  };
}

/**
 * Fetches every data type for [start, end) and writes it. When the result matches
 * `previous` (the fingerprint of the last fetch of this range), nothing is written.
 */
async function syncRange(
  client: HealthClient,
  start: Ymd,
  end: Ymd,
  clock: LocalClock,
  settings: UserSettings,
  maxHr: number,
  log: RunLog,
  previous: string | null = null,
): Promise<RangeResult> {
  const t0 = Date.now();
  const patches = new Map<string, Map<Ymd, DayPatch>>();
  const results: TaskResult[] = [];
  const minute = new Map<Ymd, IntradayDay>();
  const samples: SampleRow[] = [];
  let sleeps: SleepRow[] = [];
  let exercises: ExerciseRow[] = [];
  const startMs = clock.midnightMs(start);
  const endMs = clock.midnightMs(end);

  const tasks: Task[] = [];
  const dailyDates = new Map<string, number>();
  for (const [type, spec] of Object.entries(DAILY_TYPES)) {
    tasks.push({
      name: type,
      columns: spec.columns,
      run: async () => {
        const pts = await client.listDaily(type, start, end, type === "daily-heart-rate-zones");
        const m = dailyPointsToPatches(type, pts);
        patches.set(type, m);
        dailyDates.set(type, m.size);
        return pts.length;
      },
    });
  }
  for (const [type, spec] of Object.entries(ROLLUP_TYPES)) {
    tasks.push({
      name: `rollup:${type}`,
      columns: spec.columns,
      run: async () => {
        const pts = await client.dailyRollup(type, start, end);
        const m = rollupPointsToPatches(type, pts);
        patches.set(`rollup:${type}`, m);
        return m.size;
      },
    });
  }
  tasks.push({
    name: "sleep",
    columns: SLEEP_DAY_COLUMNS,
    run: async () => {
      // One extra day so the evening part of the next night is known for stress exclusion.
      const pts = await client.listSleep(start, addDays(end, 1));
      sleeps = pts.map((p) => sleepPointToRow(p, clock)).filter((x): x is SleepRow => x !== null);
      return sleeps.length;
    },
  });
  tasks.push({
    name: "exercise",
    columns: [],
    run: async () => {
      const pts = await client.listExercise(start, end);
      exercises = pts.map((p) => exercisePointToRow(p, clock)).filter((x): x is ExerciseRow => x !== null);
      return exercises.length;
    },
  });
  tasks.push({
    name: "intraday:hr",
    columns: [],
    run: async () => {
      const pts = await client.rollup("heart-rate", startMs, endMs, "60s");
      placeMinuteRollups(pts, "hr", clock, minute);
      return pts.length;
    },
  });
  tasks.push({
    name: "intraday:steps",
    columns: [],
    run: async () => {
      const pts = await client.rollup("steps", startMs, endMs, "60s");
      placeMinuteRollups(pts, "steps", clock, minute);
      return pts.length;
    },
  });
  // Fitbit's own sedentary flag, per minute, for stress's stillness test.
  tasks.push({
    name: "intraday:sedentary",
    columns: [],
    optional: true,
    run: async () => {
      const pts = await client.rollup("sedentary-period", startMs, endMs, "60s");
      placeMinuteRollups(pts, "sedentary", clock, minute);
      return pts.length;
    },
  });
  // VO2 max from samples, for days without Google's daily value. Whether a Fitbit Air
  // produces either is unknown, so a rejected request leaves the run ok.
  const vo2 = new Map<string, Map<Ymd, DayPatch>>();
  for (const type of ["vo2-max", "run-vo2-max"] as const) {
    tasks.push({
      name: `samples:${type}`,
      columns: [],
      optional: true,
      run: async () => {
        const pts = await client.listSamples(type, startMs, endMs);
        vo2.set(type, vo2SamplePatches(type, pts, clock));
        return pts.length;
      },
    });
  }
  for (const type of ["heart-rate-variability", "oxygen-saturation", "respiratory-rate-sleep-summary"]) {
    tasks.push({
      name: `samples:${type}`,
      columns: [],
      run: async () => {
        const pts = await client.listSamples(type, startMs, endMs);
        const rows = samplePointsToRows(type, pts, clock);
        samples.push(...rows);
        return rows.length;
      },
    });
  }

  const ok = new Set<string>();
  await pool(tasks, 4, async (task) => {
    try {
      const count = await task.run();
      ok.add(task.name);
      results.push({ name: task.name, ok: true, count });
    } catch (e) {
      if (e instanceof TokenExpiredError) throw e;
      results.push({
        name: task.name,
        ok: false,
        error: String((e as Error).message ?? e).slice(0, 300),
        ...(task.optional ? { optional: true } : {}),
      });
    }
  });

  const inRange = (d: Ymd) => d >= start && d < end;
  const sleepOk = ok.has("sleep"), exerciseOk = ok.has("exercise");
  const hrOk = ok.has("intraday:hr"), stepsOk = ok.has("intraday:steps"), sedentaryOk = ok.has("intraday:sedentary");

  // Every row is built before anything is written, so an unchanged range can skip the writes.
  const uniqueSamples = [...new Map(samples.map((s) => [`${s.metric}|${s.t}`, s])).entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([, s]) => s);

  const minuteRows: Record<string, unknown>[] = [];
  if (hrOk || stepsOk) {
    for (const date of [...minute.keys()].filter(inRange).sort()) {
      const d = minute.get(date)!;
      const row: Record<string, unknown> = { date };
      if (hrOk) row.hr = d.hr;
      if (stepsOk) row.steps = d.steps;
      if (sedentaryOk) row.sedentary = d.sedentary;
      minuteRows.push(row);
    }
  }

  // Day rows: columns of failed tasks are left untouched in the database.
  const columns = new Set<string>();
  for (const task of tasks) if (ok.has(task.name)) for (const c of task.columns) columns.add(c);
  if (hrOk) for (const c of HR_COLUMNS) columns.add(c);
  if (stepsOk) for (const c of STEPS_COLUMNS) columns.add(c);
  if (hrOk && stepsOk) for (const c of STRESS_COLUMNS) columns.add(c);

  const rangeRhr = median(
    [...(patches.get("daily-resting-heart-rate")?.values() ?? [])]
      .map((p) => p.rhr)
      .filter((v): v is number => typeof v === "number"),
  ) ?? 60;

  // Stress baselines need the still levels of the 30 days before the range; days in it follow in order.
  const stressCtx = {
    sleeps,
    exercises,
    excluded: [] as [number, number][],
    still: new Map<Ymd, number>(),
    clock,
    hrFor: ((d: Ymd) => minute.get(d)?.hr) as HrFor,
  };
  if (hrOk && stepsOk) {
    const prior = await db.select<{ date: Ymd; stress_still_hrr: number }>(
      "fs_days",
      `select=date,stress_still_hrr&date=gte.${addDays(start, -STRESS_BASELINE_DAYS)}&date=lt.${start}&stress_still_hrr=not.is.null`,
    );
    for (const d of prior) stressCtx.still.set(d.date, d.stress_still_hrr);
  }

  const dayRows: Record<string, unknown>[] = [];
  for (const date of dateRange(start, end)) {
    const row: Record<string, unknown> = { date };
    for (const c of columns) row[c] = null;
    for (const task of tasks) {
      if (!ok.has(task.name) || task.columns.length === 0) continue;
      const p = patches.get(task.name)?.get(date);
      if (p) Object.assign(row, p);
    }
    if (ok.has("daily-vo2-max") && row.vo2max === null) {
      const s = vo2.get("vo2-max")?.get(date) ?? vo2.get("run-vo2-max")?.get(date);
      if (s) Object.assign(row, s);
    }
    if (sleepOk) Object.assign(row, sleepDayPatch(date, sleeps, clock));

    const m = minute.get(date);
    // No minute heart rate on a day with other data: the band was not worn.
    if (hrOk) row.wear_min = m ? wearMinutes(m.hr) : 0;
    // Google sends no Active Zone Minutes for a day without any: on a worn day that is 0, not missing.
    if (ok.has("rollup:active-zone-minutes") && typeof row.wear_min === "number" && row.wear_min > 0 && row.azm_fat_burn === null) {
      for (const c of ROLLUP_TYPES["active-zone-minutes"].columns) row[c] = 0;
    }
    if (stepsOk && m) row.steps_by_hour = stepsByHour(m.steps);
    if (hrOk && m) {
      const rhr = typeof row.rhr === "number" ? row.rhr : rangeRhr;
      const strain = computeStrain(m.hr, rhr, maxHr, settings.sex);
      const details: Record<string, unknown> = { maxHr, rhrUsed: rhr };
      row.hr_peak_sustained = sustainedPeak(m.hr);
      if (strain) {
        row.trimp = strain.trimp;
        row.strain = strain.strain;
        details.hrMinutes = strain.hrMinutes;
        details.hrrZoneMinutes = strain.zoneMinutes;
      }
      if (stepsOk) {
        const day = stressOfDay(date, { hr: m.hr, steps: m.steps, sedentary: sedentaryOk ? m.sedentary : null }, stressCtx, rhr, maxHr);
        Object.assign(row, day.row);
        Object.assign(details, day.details);
      }
      row.intraday_details = details;
    }

    const hasData = Object.entries(row).some(([k, v]) => !DERIVED_ONLY.has(k) && v !== null);
    if (hasData) dayRows.push(row);
  }

  // Load, zones, peak heart rate, heart-rate recovery and minute steps of each workout, from its minutes.
  if (exerciseOk && (hrOk || stepsOk)) {
    const all = exercises;
    exercises = exercises.map((x) => {
      const dayRhr = patches.get("daily-resting-heart-rate")?.get(x.date)?.rhr;
      const rhr = typeof dayRhr === "number" ? dayRhr : rangeRhr;
      const hrFor: HrFor = (d) => minute.get(d)?.hr;
      const hr = () => minutesBetween(Date.parse(x.start_time), Date.parse(x.end_time), clock, hrFor);
      return {
        ...x,
        ...(hrOk ? { ...computeWorkoutLoad(hr(), rhr, maxHr, settings.sex), ...workoutRecovery(x, all, clock, hrFor, rhr, maxHr) } : {}),
        ...(stepsOk ? { steps_minute: workoutSteps(x, clock, (d) => minute.get(d)?.steps) } : {}),
      };
    });
  }

  const points = (sleepOk ? sleeps.length : 0) + (exerciseOk ? exercises.length : 0) + samples.length + dayRows.length;
  const failed = results.filter((r) => !r.ok && !r.optional);
  const skipped = results.filter((r) => !r.ok && r.optional);
  const counts: Record<string, number | [number, number]> = {};
  for (const r of [...results].sort((a, b) => a.name.localeCompare(b.name))) {
    if (r.ok) counts[r.name] = dailyDates.has(r.name) ? [r.count ?? 0, dailyDates.get(r.name)!] : r.count ?? 0;
  }
  const fingerprint = await fingerprintOf({
    version: VERSION,
    start,
    end,
    ok: [...ok].sort(),
    sleeps: sleepOk ? [...sleeps].sort(byId) : null,
    exercises: exerciseOk ? [...exercises].sort(byId) : null,
    samples: uniqueSamples,
    minute: minuteRows,
    days: dayRows,
  });
  if (previous !== null && fingerprint === previous) {
    log.ranges.push({ range: `${start}..${end}`, ms: Date.now() - t0, points, counts, failed, ...(skipped.length ? { skipped } : {}), unchanged: true });
    return { points, fingerprint, unchanged: true };
  }

  // Each write is isolated so one unexpected record cannot abort the whole range.
  const writeFailures: TaskResult[] = [];
  const write = async (name: string, fn: () => Promise<void>) => {
    try {
      await fn();
    } catch (e) {
      writeFailures.push({ name: `write:${name}`, ok: false, error: String((e as Error).message ?? e).slice(0, 300) });
    }
  };
  const stamped = (rows: object[]): Record<string, unknown>[] => rows.map((r) => ({ ...r, updated_at: nowIso() }));

  if (sleepOk) {
    await write("fs_sleep", async () => {
      if (sleeps.length) await db.upsert("fs_sleep", stamped(sleeps), "id");
      const keep = sleeps.filter((s) => inRange(s.date)).map((s) => s.id);
      const notIn = keep.length ? `&id=not.in.${db.inList(keep)}` : "";
      await db.remove("fs_sleep", `date=gte.${start}&date=lt.${end}${notIn}`);
    });
  }
  if (exerciseOk) {
    await write("fs_exercise", async () => {
      if (exercises.length) await db.upsert("fs_exercise", stamped(exercises), "id");
      const keep = exercises.map((x) => x.id);
      const notIn = keep.length ? `&id=not.in.${db.inList(keep)}` : "";
      await db.remove("fs_exercise", `date=gte.${start}&date=lt.${end}${notIn}`);
    });
  }
  if (uniqueSamples.length) {
    await write("fs_samples", () => db.upsert("fs_samples", uniqueSamples.map((s) => ({ ...s })), "metric,t", 1000));
  }
  if (minuteRows.length) await write("fs_intraday", () => db.upsert("fs_intraday", stamped(minuteRows), "date", 50));
  if (dayRows.length) await write("fs_days", () => db.upsert("fs_days", stamped(dayRows), "date", 100));

  log.ranges.push({
    range: `${start}..${end}`,
    ms: Date.now() - t0,
    points,
    counts,
    failed: [...failed, ...writeFailures],
    ...(skipped.length ? { skipped } : {}),
  });
  return { points, fingerprint: writeFailures.length ? null : fingerprint, unchanged: false };
}

/**
 * A finished day is low-wear when it has under 60 % of your usual wear (median of the
 * worn days among the previous 30), or under 10 hours while there are fewer than 5 such
 * days. When you usually wear the band under 10 hours, no day is judged. A day without
 * minute heart rate (wear 0) is low-wear only once the account has any worn day
 * (`anyWorn`), so an account that never records minute heart rate keeps its day totals.
 */
export function lowWear(wear: unknown, previous: DayRow[], isFinished: boolean, anyWorn: boolean): boolean | null {
  if (!isFinished || typeof wear !== "number") return null;
  if (wear === 0) return anyWorn ? true : null;
  const usual = previous.map((d) => d.wear_min).filter((v): v is number => typeof v === "number" && v > 0);
  if (usual.length < 5) return wear < 600 ? true : null;
  const typical = median(usual)!;
  return typical >= 600 ? wear < 0.6 * typical : null;
}

/**
 * Recomputes sleep score, recovery and the low-wear flag for dates from..to (baselines
 * need the previous 30 days). `to` is today, whose wear is still growing.
 */
export async function recomputeScores(from: Ymd, to: Ymd, settings: UserSettings): Promise<number> {
  const cols = [
    "date", "hrv_rmssd", "rhr", "resp_rate", "skin_temp_c", "skin_temp_baseline_c", "skin_temp_stddev_c",
    "sleep_asleep_min", "sleep_in_bed_min", "sleep_deep_min", "sleep_rem_min", "sleep_has_stages",
    "sleep_bedtime_min", "sleep_waketime_min", "wear_min",
  ].join(",");
  const rows = await db.select<DayRow>("fs_days", `select=${cols}&date=gte.${addDays(from, -31)}&date=lte.${to}&order=date.asc`);
  const anyWorn = rows.some((d) => typeof d.wear_min === "number" && d.wear_min > 0) ||
    (await db.selectOne("fs_days", "select=date&wear_min=gt.0")) !== null;
  const out: Record<string, unknown>[] = [];
  for (let i = 0; i < rows.length; i++) {
    const day = rows[i];
    if (day.date < from) continue;
    const prev30: DayRow[] = [];
    const prev14: DayRow[] = [];
    const min30 = addDays(day.date, -30), min14 = addDays(day.date, -14);
    for (let j = i - 1; j >= 0 && rows[j].date >= min30; j--) {
      prev30.push(rows[j]);
      if (rows[j].date >= min14) prev14.push(rows[j]);
    }
    const sleep = computeSleepScore(day, prev14, settings.sleep_need_min);
    const recovery = computeRecovery(day, prev30, sleep.score);
    out.push({
      date: day.date,
      sleep_score: sleep.score,
      recovery: recovery.score,
      score_details: { sleep, recovery, strainTarget: strainTarget(recovery.score) },
      low_wear: lowWear(day.wear_min, prev30, day.date < to, anyWorn),
    });
  }
  if (out.length) await db.upsert("fs_days", out, "date", 200);
  return out.length;
}

/**
 * Recomputes strain, stress, the sustained heart-rate peak, workout loads and heart-rate recovery
 * from stored minute data (after sex / max HR changes), with `maxHr` (default: the effective one).
 */
export async function recomputeIntraday(from: Ymd, to: Ymd, settings: UserSettings, acc: Account, maxHr?: number): Promise<number> {
  const clock = clockFor(acc);
  const hrMax = maxHr ?? (await effectiveMaxHr(acc, settings, to)).value;
  const info = await db.select<DayRow>("fs_days", `select=date,rhr,stress_still_hrr&date=gte.${addDays(from, -STRESS_BASELINE_DAYS)}&date=lte.${to}`);
  const rhrByDate = new Map(info.filter((d) => d.date >= from).map((d) => [d.date, typeof d.rhr === "number" ? d.rhr : null]));
  const fallbackRhr = median([...rhrByDate.values()].filter((v): v is number => v !== null)) ?? 60;
  const sleeps = await db.select<SleepRow>("fs_sleep", `select=date,start_time,end_time&date=gte.${from}&date=lte.${addDays(to, 1)}`);
  const exercises = await db.select<ExerciseRow>("fs_exercise", `select=*&date=gte.${from}&date=lte.${to}&order=start_time.asc`);
  // Stress baselines start from the stored still levels before `from`; later days are rebuilt in order.
  const stressCtx = {
    sleeps: [] as SleepRow[],
    exercises,
    excluded: [] as [number, number][],
    still: new Map<Ymd, number>(),
    clock,
    hrFor: (() => null) as HrFor,
  };
  for (const d of info) if (d.date < from && typeof d.stress_still_hrr === "number") stressCtx.still.set(d.date, d.stress_still_hrr);
  let count = 0;
  for (let s = from; s <= to; s = addDays(s, 30)) {
    const next = addDays(s, 30);
    // A day either side: the minutes before a workout just after midnight, recovery past midnight.
    const rows = await db.select<{ date: Ymd; hr: (number | null)[] | null; steps: (number | null)[] | null; sedentary: (number | null)[] | null }>(
      "fs_intraday",
      `select=date,hr,steps,sedentary&date=gte.${addDays(s, -1)}&date=lte.${next}&order=date.asc`,
    );
    const hrByDate = new Map(rows.map((r) => [r.date, r.hr]));
    stressCtx.hrFor = (d) => hrByDate.get(d);
    const out: Record<string, unknown>[] = [];
    for (const r of rows) {
      if (r.date < s || r.date >= next || r.date > to || !r.hr) continue;
      const rhr = rhrByDate.get(r.date) ?? fallbackRhr;
      const strain = computeStrain(r.hr, rhr, hrMax, settings.sex);
      const details: Record<string, unknown> = {
        maxHr: hrMax,
        rhrUsed: rhr,
        hrMinutes: strain?.hrMinutes ?? null,
        hrrZoneMinutes: strain?.zoneMinutes ?? null,
      };
      const row: Record<string, unknown> = {
        date: r.date,
        trimp: strain?.trimp ?? null,
        strain: strain?.strain ?? null,
        hr_peak_sustained: sustainedPeak(r.hr),
        stress: null,
        stress_minutes: null,
        stress_still_hrr: null,
        intraday_details: details,
      };
      if (r.steps) {
        stressCtx.sleeps = sleeps.filter((x) => x.date === r.date || x.date === addDays(r.date, 1));
        const day = stressOfDay(r.date, { hr: r.hr, steps: r.steps, sedentary: r.sedentary }, stressCtx, rhr, hrMax);
        Object.assign(row, day.row);
        Object.assign(details, day.details);
      }
      out.push(row);
    }
    if (out.length) await db.upsert("fs_days", out, "date", 100);
    count += out.length;

    const stepsByDate = new Map(rows.map((r) => [r.date, r.steps]));
    const workouts = exercises
      .filter((x) => x.date >= s && x.date < next)
      .map((x) => {
        const hrFor: HrFor = (d) => hrByDate.get(d);
        const hr = minutesBetween(Date.parse(x.start_time), Date.parse(x.end_time), clock, hrFor);
        const rhr = rhrByDate.get(x.date) ?? fallbackRhr;
        return {
          ...x,
          ...computeWorkoutLoad(hr, rhr, hrMax, settings.sex),
          ...workoutRecovery(x, exercises, clock, hrFor, rhr, hrMax),
          steps_minute: workoutSteps(x, clock, (d) => stepsByDate.get(d)),
          updated_at: new Date().toISOString(),
        };
      });
    if (workouts.length) await db.upsert("fs_exercise", workouts, "id");
  }
  return count;
}

/**
 * The effective max heart rate (see chooseMaxHr), with the highest fs_days.hr_peak_sustained
 * of the 365 days up to `today` as the observed peak.
 */
export async function effectiveMaxHr(acc: Account | null, settings: UserSettings, today: Ymd): Promise<MaxHr> {
  const age = typeof acc?.profile?.age === "number" ? acc.profile.age : null;
  const top = settings.max_hr_override ? null : await db.selectOne<{ hr_peak_sustained: number }>(
    "fs_days",
    `select=hr_peak_sustained&date=gte.${addDays(today, -365)}&date=lte.${today}&hr_peak_sustained=not.is.null&order=hr_peak_sustained.desc`,
  );
  return chooseMaxHr(age, settings.max_hr_override, top?.hr_peak_sustained ?? null);
}

/**
 * The max heart rate to compute with. The one the stored history used (`saved`) stays while
 * the effective value is within 2 bpm of it, so a new peak 1 bpm higher does not recompute
 * everything; otherwise the effective value, with `changed` set (an override applies exactly).
 */
export async function maxHrInUse(
  acc: Account | null,
  settings: UserSettings,
  today: Ymd,
  saved: { max_hr_used?: unknown; max_hr_source?: unknown } | null,
): Promise<MaxHr & { changed: boolean }> {
  const eff = await effectiveMaxHr(acc, settings, today);
  const used = typeof saved?.max_hr_used === "number" ? saved.max_hr_used : null;
  // An override applies exactly, and setting or removing one always recomputes.
  const overrides = eff.source === "override" || saved?.max_hr_source === "override";
  const keep = used !== null &&
    (overrides ? eff.source === saved?.max_hr_source && eff.value === used : Math.abs(eff.value - used) < MAX_HR_RECOMPUTE_BPM);
  if (keep) {
    const source = saved?.max_hr_source === "override" || saved?.max_hr_source === "observed" || saved?.max_hr_source === "age" ? saved.max_hr_source : eff.source;
    return { value: used, source, changed: false };
  }
  return { ...eff, changed: true };
}

/** Recomputes intraday-derived values and scores for the backfill window with `maxHr`, then saves it as the one in use. */
export async function recomputeHistory(today: Ymd, settings: UserSettings, acc: Account, maxHr: MaxHr): Promise<void> {
  const from = addDays(today, -settings.backfill_days);
  await recomputeIntraday(from, today, settings, acc, maxHr.value);
  await recomputeScores(from, today, settings);
  await db.update("fs_sync_state", "id=eq.1", { max_hr_used: maxHr.value, max_hr_source: maxHr.source, updated_at: nowIso() });
}

async function statsBuiltAt(): Promise<number> {
  const row = await db.selectOne<{ updated_at: string }>("fs_cache", "select=updated_at&key=eq.stats");
  return row ? Date.parse(row.updated_at) : 0;
}

export async function rebuildStats(today: Ymd, settings: UserSettings): Promise<void> {
  const [days, journal, workouts] = await Promise.all([
    db.select<DayRow>("fs_days", "select=*&order=date.asc"),
    journalEntries(addDays(today, -400)),
    // Only what the heart-rate recovery history needs.
    db.select<WorkoutRow>(
      "fs_exercise",
      `select=id,date,start_time,exercise_type,name,end_hr,hrr_1min,hrr_2min&date=gte.${addDays(today, -365)}&hrr_1min=not.is.null&order=start_time.asc`,
    ),
  ]);
  const stats = buildStats(days, today, settings, journal, workouts);
  stats.body_age = await bodyAgeFor(days, today, settings);
  stats.server_version = VERSION;
  await db.upsert("fs_cache", [{ key: "stats", value: stats, updated_at: nowIso() }], "key");
}

/** The stored Body age answers, or null when missing or not readable. */
function storedLifestyle(v: unknown): Lifestyle | null {
  try {
    return lifestyleFrom(v ?? null);
  } catch {
    return null;
  }
}

/** Body age from their Google profile age and the max heart rate strain uses; null without the age. */
async function bodyAgeFor(days: DayRow[], today: Ymd, settings: UserSettings): Promise<BodyAge | null> {
  const acc = await loadAccount();
  const age = typeof acc?.profile?.age === "number" ? acc.profile.age : null;
  if (age === null) return null;
  const state = await db.selectOne<{ max_hr_used: number | null; max_hr_source: string | null }>("fs_sync_state", "select=max_hr_used,max_hr_source&id=eq.1");
  const maxHr = await maxHrInUse(acc, settings, today, state);
  return bodyAge(days as unknown as (Record<string, unknown> & { date: Ymd })[], today,
    { age, sex: settings.sex, maxHr: maxHr.value, maxHrSource: maxHr.source, lifestyle: storedLifestyle(settings.lifestyle) }, addDays);
}

/** One sync run within `budgetMs`. Safe to call concurrently (second caller is skipped). */
export async function runSync(reason: string, force: boolean, budgetMs = 95_000): Promise<RunLog> {
  const started = Date.now();
  const log: RunLog = { reason, started: new Date(started).toISOString(), status: "ok", calls: 0, ranges: [] };
  const locked = await db.rpc<boolean>("fs_try_lock", { p_seconds: Math.ceil(budgetMs / 1000) + 60 });
  if (!locked) return { ...log, status: "skipped", message: "another sync is running" };

  let client: HealthClient | null = null;
  try {
    const acc = await loadAccount();
    if (!acc || !acc.refresh_token || acc.token_status === "disconnected") {
      log.status = "not_connected";
      return log;
    }
    const settings = await loadSettings();
    const token = await accessToken(acc);
    client = new HealthClient(token, () => accessToken(acc, true), started + budgetMs);
    await refreshMeta(client, acc);
    const clock = clockFor(acc);
    const today = clock.today();

    const state = (await db.selectOne<SyncState>("fs_sync_state", "select=*&id=eq.1"))!;
    if (!state.backfill_target) {
      let target = addDays(today, -settings.backfill_days);
      const member = ymdFromGoogleDate(acc.profile?.membershipStartDate);
      if (member && member > target) target = member;
      state.backfill_target = target;
    }
    if (!state.backfill_oldest) state.backfill_oldest = addDays(today, -RECENT_DAYS);
    const wasDone = state.backfill_done;
    // Kept while within 2 bpm of the value the history used. A bigger change (or none saved
    // yet) recomputes the history first, so the recent days below match it.
    let maxHr = await maxHrInUse(acc, settings, today, state);
    let recomputed = false;
    const recompute = async () => {
      await recomputeHistory(today, settings, acc, maxHr);
      state.max_hr_used = maxHr.value;
      state.max_hr_source = maxHr.source;
      recomputed = true;
    };
    if (maxHr.changed) await recompute();

    const recentStale = !state.last_recent_sync_at || Date.now() - Date.parse(state.last_recent_sync_at) > RECENT_STALE_MS;
    if (force || recentStale) {
      // Recent days are finished (scores included) before any backfill, so the app can
      // show them as soon as last_recent_sync_at moves. Devices come first, so the band's
      // last sync time the app shows is never newer than the data fetched here.
      await refreshDevices(client);
      const from = addDays(today, -RECENT_DAYS);
      const recent = await syncRange(client, from, addDays(today, 1), clock, settings, maxHr.value, log, state.recent_fingerprint ?? null);
      if (!recent.unchanged) {
        await recomputeScores(from, today, settings);
        state.stats_dirty = true;
      }
      state.last_recent_sync_at = nowIso();
      state.recent_fingerprint = recent.fingerprint;
      await db.update("fs_sync_state", "id=eq.1", {
        last_recent_sync_at: state.last_recent_sync_at,
        recent_fingerprint: state.recent_fingerprint,
        stats_dirty: state.stats_dirty,
        updated_at: nowIso(),
      });
    }

    let backfilledFrom: Ymd | null = null;
    while (!state.backfill_done && Date.now() - started < budgetMs - 35_000) {
      const end = state.backfill_oldest!;
      let start = addDays(end, -BACKFILL_CHUNK_DAYS);
      if (start < state.backfill_target!) start = state.backfill_target!;
      if (start >= end) {
        state.backfill_done = true;
        break;
      }
      const { points } = await syncRange(client, start, end, clock, settings, maxHr.value, log);
      state.backfill_oldest = start;
      state.backfill_empty_chunks = points === 0 ? (state.backfill_empty_chunks ?? 0) + 1 : 0;
      if (start <= state.backfill_target! || state.backfill_empty_chunks >= EMPTY_CHUNKS_TO_STOP) {
        state.backfill_done = true;
      }
      backfilledFrom = start;
      await db.update("fs_sync_state", "id=eq.1", {
        backfill_oldest: state.backfill_oldest,
        backfill_target: state.backfill_target,
        backfill_done: state.backfill_done,
        backfill_empty_chunks: state.backfill_empty_chunks,
        updated_at: nowIso(),
      });
    }

    // A finished history import recomputes it all again: stress baselines and the observed
    // heart-rate peak need the whole of it.
    if (!wasDone && state.backfill_done) {
      maxHr = await maxHrInUse(acc, settings, today, state);
      await recompute();
    } else if (backfilledFrom) {
      await recomputeScores(backfilledFrom, today, settings);
    }
    if (backfilledFrom || recomputed || state.stats_dirty) {
      const built = await statsBuiltAt();
      if (backfilledFrom || recomputed || built < clock.midnightMs(today) || Date.now() - built > STATS_MAX_AGE_MS) {
        await rebuildStats(today, settings);
        state.stats_dirty = false;
      }
    }
    if (log.ranges.some((r) => r.failed.length > 0)) log.status = "partial";

    await db.update("fs_sync_state", "id=eq.1", {
      backfill_oldest: state.backfill_oldest,
      backfill_target: state.backfill_target,
      backfill_done: state.backfill_done,
      backfill_empty_chunks: state.backfill_empty_chunks ?? 0,
      last_recent_sync_at: state.last_recent_sync_at,
      stats_dirty: state.stats_dirty ?? false,
      updated_at: nowIso(),
    });
    return log;
  } catch (e) {
    log.status = e instanceof TokenExpiredError ? "token_expired" : "error";
    log.message = String((e as Error).message ?? e).slice(0, 500);
    return log;
  } finally {
    log.calls = client?.calls ?? 0;
    log.finished = nowIso();
    try {
      await db.update("fs_sync_state", "id=eq.1", {
        last_run_finished_at: log.finished,
        last_run_status: log.status,
        last_run_log: log,
        lock_until: null,
        updated_at: nowIso(),
      });
    } catch (e) {
      console.error("failed to save run log", String(e));
      await db.rpc("fs_unlock").catch(() => {});
    }
  }
}
