// Writes API-shaped JSON for the iOS app's fixture mode (UI screenshots in CI).
// Usage: node --experimental-strip-types supabase/tests/make-fixtures.ts <outDir>
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { PNG_SCREENSHOT, type Row, tables } from "./fakes.ts";

const out = process.argv[2];
if (!out) throw new Error("usage: make-fixtures.ts <outDir>");
mkdirSync(out, { recursive: true });

const { runSync, clockFor, loadSettings, rebuildStats, recomputeScores } = await import("../functions/fitstats/lib/sync.ts");
const { addDays } = await import("../functions/fitstats/lib/util.ts");
const { mainSleepOf, sleepDayPatch, sleepPointToRow } = await import("../functions/fitstats/lib/transform.ts");
const { JOURNAL_TAGS, journalEntries, saveJournalEntry } = await import("../functions/fitstats/lib/journal.ts");
const training = await import("../functions/fitstats/lib/training.ts");
// Body age answers, so the screenshots show the number (the questions are opened from there).
tables.fs_user_settings[0].lifestyle = { smoking: "never", quit_age: null, vaping: "never", alcohol: "1-10" };
const log = await runSync("fixtures", true, 95_000);
if (log.status !== "ok") throw new Error(`sync failed: ${JSON.stringify(log)}`);

const acc = tables.fs_account[0];
const state = tables.fs_sync_state[0];
const today = clockFor(acc as never).today();

// Demo journal for the screenshots: "alcohol" sits on the days before the 8 worst
// sleep scores of the last 45 nights, and those mornings get a lower HRV and a
// higher resting heart rate, so that tag shows a clear (and plausible) effect.
// The other tags are spread evenly and show none.
const scoreAfter = (d: string) => Number(tables.fs_days.find((r) => r.date === addDays(d, 1))?.sleep_score ?? 100);
const logged = Array.from({ length: 45 }, (_, i) => addDays(today, -45 + i));
const alcohol = new Set([...logged].sort((a, b) => scoreAfter(a) - scoreAfter(b)).slice(0, 8));
for (const date of alcohol) {
  const morning = tables.fs_days.find((r) => r.date === addDays(date, 1));
  if (!morning) continue;
  if (typeof morning.hrv_rmssd === "number") morning.hrv_rmssd -= 12;
  if (typeof morning.rhr === "number") morning.rhr += 4;
}
await recomputeScores(addDays(today, -45), today, await loadSettings());
// The screenshots' past day (the latest workout day before today) stays unlogged, to show "Log day".
const unlogged = tables.fs_exercise.map((x) => String(x.date)).filter((d) => d < today).sort().at(-1);
for (const [i, date] of logged.entries()) {
  if (date === unlogged) continue;
  const tags = [
    ...(alcohol.has(date) ? ["alcohol"] : []),
    ...(i % 6 === 1 ? ["late_caffeine"] : []),
    ...(i % 9 === 4 ? ["stressful_day"] : []),
    ...(i % 10 === 2 ? ["Cold shower"] : []),
  ];
  await saveJournalEntry({ date, tags }, today);
}
await saveJournalEntry({ date: today, tags: ["late_caffeine", "stressful_day"], note: "Long day at work, coffee at 4 pm." }, today);

// An early-afternoon nap today, for the Sleep screen's Naps section: 13:20–14:05 local, with
// stages, made by the real transform from an API-shaped point like the sync's.
{
  const clock = clockFor(acc as never);
  const night = mainSleepOf(tables.fs_sleep.filter((s) => s.date === today));
  const offset = Number(night?.end_offset_s ?? 7200);
  const at = (min: number) => new Date(Date.parse(`${today}T13:20:00Z`) - offset * 1000 + min * 60000).toISOString();
  const parts = [["AWAKE", 0, 4], ["LIGHT", 4, 19], ["DEEP", 19, 28], ["LIGHT", 28, 36], ["REM", 36, 41], ["AWAKE", 41, 45]] as const;
  const minutes = (type: string) => parts.filter((p) => p[0] === type).reduce((sum, p) => sum + p[2] - p[1], 0);
  const row = sleepPointToRow({
    name: `users/me/dataTypes/sleep/dataPoints/n-${today}`,
    sleep: {
      interval: { startTime: at(0), endTime: at(45), startUtcOffset: `${offset}s`, endUtcOffset: `${offset}s` },
      type: "STAGES",
      metadata: { mainSleep: false, nap: true, processed: true },
      stages: parts.map(([type, a, b]) => ({ type, startTime: at(a), endTime: at(b) })),
      summary: {
        minutesAsleep: String(45 - minutes("AWAKE")),
        minutesInSleepPeriod: "45",
        minutesAwake: String(minutes("AWAKE")),
        minutesToFallAsleep: "0",
        stagesSummary: ["DEEP", "REM", "LIGHT", "AWAKE"].map((type) => ({
          type, minutes: String(minutes(type)), count: String(parts.filter((p) => p[0] === type).length),
        })),
      },
    },
  } as never, clock);
  const day = tables.fs_days.find((d) => d.date === today);
  if (!row || row.date !== today || !day) throw new Error(`fixture nap not made for ${today}: ${JSON.stringify(row)}`);
  tables.fs_sleep.push(row as unknown as Row);
  Object.assign(day, sleepDayPatch(today, tables.fs_sleep.filter((s) => s.date === today) as never, clock));
}
// Training: a routine the coach made, two of the user's, and three weeks of logged sessions
// with the weights going up.
const upper = await training.saveRoutine({
  name: "Upper body A",
  notes: "Twice a week, two days apart. Add 2.5 kg once every set reaches the top of the range.",
  exercises: [
    { name: "Bench press", kind: "strength", sets: 3, reps: "8-10", weight_kg: 60, rest_s: 120 },
    { name: "Bent-over row", kind: "strength", sets: 3, reps: "8-10", weight_kg: 50, rest_s: 120 },
    { name: "Overhead press", kind: "strength", sets: 3, reps: "8", weight_kg: 35, rest_s: 90 },
    { name: "Pull-up", kind: "strength", sets: 3, reps: "AMRAP", rest_s: 90 },
    { name: "Plank", kind: "mobility", sets: 3, duration_min: 1 },
  ],
}, "coach");
const legs = await training.saveRoutine({
  name: "Legs",
  exercises: [
    { name: "Squat", kind: "strength", sets: 5, reps: "5", weight_kg: 80, rest_s: 180 },
    { name: "Romanian deadlift", kind: "strength", sets: 3, reps: "8", weight_kg: 70, rest_s: 120 },
    { name: "Walking lunge", kind: "strength", sets: 3, reps: "12", weight_kg: 16 },
    { name: "Calf raise", kind: "strength", sets: 3, reps: "15", weight_kg: 40 },
  ],
}, "user");
await training.saveRoutine({ name: "Easy run", exercises: [{ name: "Run", kind: "cardio", duration_min: 30, distance_km: 5 }] }, "user");
const at = (date: string, hh: number, mm: number) => new Date(Date.parse(`${date}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00Z`) - 2 * 3600_000).toISOString();
for (const [i, ago] of [15, 8, 1].entries()) {
  const date = addDays(today, -ago);
  const kg = 75 + i * 2.5;
  await training.saveLog({
    date, name: "Legs", routine_id: legs.id, effort: 7 + (i === 2 ? 1 : 0), started_at: at(date, 17, 30), ended_at: at(date, 18, 32),
    exercises: [
      { name: "Squat", kind: "strength", sets: Array.from({ length: 5 }, () => ({ reps: 5, weight_kg: kg })) },
      { name: "Romanian deadlift", kind: "strength", sets: Array.from({ length: 3 }, () => ({ reps: 8, weight_kg: 65 + i * 2.5 })) },
      { name: "Walking lunge", kind: "strength", sets: Array.from({ length: 3 }, () => ({ reps: 12, weight_kg: 16 })) },
    ],
  }, today);
}
for (const [i, ago] of [10, 3].entries()) {
  const date = addDays(today, -ago);
  await training.saveLog({
    date, name: "Upper body A", routine_id: upper.id, effort: 6, started_at: at(date, 18, 0), ended_at: at(date, 18, 55),
    notes: i === 1 ? "Last bench set felt heavy." : null,
    exercises: [
      { name: "Bench press", kind: "strength", sets: [{ reps: 10, weight_kg: 57.5 + i * 2.5 }, { reps: 9, weight_kg: 57.5 + i * 2.5 }, { reps: 8, weight_kg: 57.5 + i * 2.5 }] },
      { name: "Bent-over row", kind: "strength", sets: Array.from({ length: 3 }, () => ({ reps: 10, weight_kg: 50 })) },
      { name: "Pull-up", kind: "strength", sets: [{ reps: 8 }, { reps: 7 }, { reps: 6 }] },
    ],
  }, today);
}

await rebuildStats(today, await loadSettings());
const byDate = (a: Row, b: Row) => String(a.date).localeCompare(String(b.date));
const days = [...tables.fs_days].sort(byDate);
const write = (name: string, value: unknown) => writeFileSync(join(out, name), JSON.stringify(value));

write("status.json", {
  version: "fixture",
  serverTime: new Date().toISOString(),
  today,
  timeZone: acc.time_zone,
  connection: { status: "ok", email: "you@example.com", connectedAt: new Date().toISOString(), error: null, missingScopes: [] },
  sync: {
    running: false,
    lastRunAt: new Date().toISOString(),
    lastRunStatus: "ok",
    lastRecentSyncAt: state.last_recent_sync_at,
    backfillOldest: state.backfill_oldest,
    backfillTarget: state.backfill_target,
    backfillDone: true,
    backfillProgress: 1,
    lastRunLog: null,
  },
  devices: [{ name: "Fitbit Air", type: "TRACKER", batteryLevel: 81, batteryStatus: "High", lastSyncTime: new Date(Date.now() - 12 * 60000).toISOString() }],
  profile: { age: 31 },
  settings: tables.fs_user_settings[0],
  maxHr: typeof state.max_hr_used === "number" ? { value: state.max_hr_used, source: state.max_hr_source } : null,
});
write("days.json", { from: days[0]?.date ?? today, to: today, today, days });
write("stats.json", tables.fs_cache.find((c) => c.key === "stats")!.value);
write("journal.json", { tags: JOURNAL_TAGS, entries: await journalEntries(addDays(today, -400)) });
write("training.json", await training.trainingData(today));

for (let i = 0; i < 7; i++) {
  const date = addDays(today, -i);
  const sleeps = tables.fs_sleep.filter((s) => s.date === date).sort((a, b) => String(a.start_time).localeCompare(String(b.start_time)));
  const day = tables.fs_days.find((d) => d.date === date) ?? null;
  const main = mainSleepOf(sleeps, day?.sleep_main_id);
  const samples: Record<string, [number, number][]> = {};
  if (main) {
    for (const s of tables.fs_samples) {
      const t = String(s.t);
      if (t < String(main.start_time) || t > String(main.end_time)) continue;
      (samples[String(s.metric)] ??= []).push([Math.round(Date.parse(t) / 1000), Number(s.value)]);
    }
  }
  const intra = tables.fs_intraday.find((r) => r.date === date);
  write(`day-${date}.json`, {
    date,
    day,
    intraday: intra ? { hr: intra.hr, steps: intra.steps } : null,
    sleeps,
    exercises: tables.fs_exercise.filter((x) => x.date === date),
    samples,
  });
}
// Coach: the real coach code against the fake Claude API (see fakes.ts).
const coach = await import("../functions/fitstats/lib/coach.ts");
const ask = async (body: unknown) => {
  const res = await coach.handleCoach(new Request("https://fixtures.invalid/coach", { method: "POST", body: JSON.stringify(body) }));
  const text = await res.text();
  if (!text.includes('"type":"done"')) throw new Error(`coach fixture failed: ${text.slice(0, 500)}`);
};
await ask({ message: "How has my sleep been this week, and is it affecting my HRV?" });
// A follow-up with a screenshot, so the conversation shows an attachment.
await ask({
  message: "Here's my week from another app. Anything stand out?", thread_id: tables.fs_coach_threads[0].id, persona: "nova",
  images: [{ media_type: "image/png", data: PNG_SCREENSHOT, thumb: PNG_SCREENSHOT }],
});
// And a workout file from another app, saved to the Training log.
const strongCsv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n" +
  [5, 3, 1].flatMap((n) => [1, 2, 3].map((set) => `${addDays(today, -n)} 18:00:00,Push,1h,Bench Press (Barbell),${set},80,5,0,0,,,`)).join("\n") + "\n";
await ask({ message: "My workouts from Strong", thread_id: tables.fs_coach_threads[0].id, persona: "nova", files: [{ name: "strong_workouts.csv", text: strongCsv }] });
await ask({ kind: "brief" });
write("coach-status.json", await coach.coachStatus());
write("coach-threads.json", await coach.coachThreads());
write("coach-thread.json", await (await coach.coachThread(String(tables.fs_coach_threads[0].id))).json());
write("coach-brief.json", await coach.coachBrief());
await ask({ kind: "weekly", clock: "12h" });
write("coach-weekly.json", await coach.coachWeekly());

console.log(`fixtures for ${today} written to ${out} (${days.length} days, ${tables.fs_coach_messages.length} coach messages)`);
