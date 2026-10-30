// Coach end to end: a real sync fills the in-memory database, then chat and
// briefing requests run against the fake streaming Claude API.
// Run: node --experimental-strip-types --test supabase/tests/coach.test.ts
import assert from "node:assert/strict";
import { before, test } from "node:test";

import { claudeFailures, claudeRequests, env, FAKE_ROUTINE, NAP_MAIN_DAY, PNG_SCREENSHOT, type Row, tables } from "./fakes.ts";

const coach = await import("../functions/fitstats/lib/coach.ts");

async function events(res: Response): Promise<Row[]> {
  assert.equal(res.headers.get("content-type"), "text/event-stream; charset=utf-8");
  const text = await res.text();
  return text.split("\n\n").filter((b) => b.startsWith("data: ")).map((b) => JSON.parse(b.slice(6)) as Row);
}

function post(body: unknown): Request {
  return new Request("https://example.supabase.co/functions/v1/fitstats?r=coach", { method: "POST", body: JSON.stringify(body) });
}

before(async () => {
  const { runSync } = await import("../functions/fitstats/lib/sync.ts");
  const log = await runSync("test", true, 95_000);
  assert.equal(log.status, "ok");
});

test("chat: tool round trip, streamed reply, saved thread and usage", async () => {
  const evs = await events(await coach.handleCoach(post({ message: "How has my sleep been this week, and is it affecting my HRV?" })));
  const status = evs.filter((e) => e.type === "status").map((e) => e.text);
  assert.equal(status.length, 1);
  assert.match(String(status[0]), /^Looking at HRV \(RMSSD\) and time asleep, \w{3} \d+ – \w{3} \d+$/);
  const streamed = evs.filter((e) => e.type === "text").map((e) => e.text).join("");
  assert.match(streamed, /^Let me look at your last week\.\n\nYour HRV averaged \*\*\d+ ms\*\*/);
  const done = evs.at(-1)!;
  assert.equal(done.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));
  // The thread is known from the start, so the app can pick the answer up if it goes away.
  assert.equal(evs[0].type, "started");
  assert.equal(evs[0].thread_id, done.thread_id);

  // First request: cached system prompt with the data summary, tools, medium effort.
  const first = claudeRequests[0];
  assert.equal(first.model, "claude-sonnet-5-5");
  assert.equal((first.output_config as Row).effort, "medium");
  assert.deepEqual((first.tools as Row[]).map((t) => t.name), ["get_daily_metrics", "get_metric_stats", "get_day", "get_workouts", "get_training", "save_routine", "get_journal",
    "get_body_age", "get_settings", "update_settings", "save_journal_entry", "save_workout_log", "delete_item", "get_deleted", "restore_deleted"]);
  const system = first.system as Row[];
  assert.deepEqual(system[1].cache_control, { type: "ephemeral" });
  assert.match(String(system[1].text), /Last 14 days/);
  assert.match(String(system[1].text), /HRV \(RMSSD\): \d+ ms/);
  assert.equal(first.tool_choice, undefined);

  const threads = tables.fs_coach_threads;
  assert.equal(threads.length, 1);
  assert.equal(threads[0].id, done.thread_id);
  assert.equal(threads[0].title, "How has my sleep been this week, and is it affecting my HRV?");
  const msgs = tables.fs_coach_messages.filter((m) => m.thread_id === done.thread_id);
  assert.deepEqual(msgs.map((m) => m.role), ["user", "assistant"]);
  assert.ok(String(msgs[0].created_at) < String(msgs[1].created_at));
  assert.equal(msgs[1].content, streamed.trim());
  assert.equal(msgs[1].id, done.message_id);

  const usage = done.usage as Row;
  assert.equal(usage.requests, 2);
  assert.equal(usage.cache_write, 5200);
  assert.equal(usage.cache_read, 5200);
  // 40×2 + 5200×2.5 + 1400×2 + 5200×0.1 + (210+140)×10, per million tokens
  assert.equal(usage.cost_usd, 0.0199);
  const saved = tables.fs_cache.find((c) => c.key === "coach_usage")!.value as Row;
  assert.equal(saved.day_requests, 1);
  assert.equal(saved.requests, 2);
});

test("chat: follow-up sends the thread history", async () => {
  const thread = tables.fs_coach_threads[0].id as string;
  claudeRequests.length = 0;
  const evs = await events(await coach.handleCoach(post({ message: "And what about this weekend?", thread_id: thread })));
  assert.equal(evs.at(-1)!.type, "done");
  const msgs = claudeRequests[0].messages as Row[];
  assert.deepEqual(msgs.map((m) => m.role), ["user", "assistant", "user"]);
  assert.equal(msgs[2].content, "And what about this weekend?");
  assert.equal(tables.fs_coach_messages.filter((m) => m.thread_id === thread).length, 4);

  const listed = await coach.coachThreads();
  assert.equal((listed.threads as Row[]).length, 1);
  const detail = await (await coach.coachThread(thread)).json() as Row;
  assert.equal((detail.messages as Row[]).length, 4);
});

test("briefing: cached for today", async () => {
  const evs = await events(await coach.handleCoach(post({ kind: "brief" })));
  const done = evs.at(-1)!;
  assert.equal(done.type, "done");
  const brief = done.brief as Row;
  assert.match(String(brief.text), /^\*\*Recovery\*\* \d+/);
  assert.match(String(brief.text), /\*\*Today\*\* Aim for strain \d+–\d+/);
  const cached = await coach.coachBrief();
  assert.deepEqual(cached.brief, brief);
});

test("errors: bad key, unknown thread, missing key, bad input", async () => {
  claudeFailures.push(401);
  const threadsBefore = tables.fs_coach_threads.length, messagesBefore = tables.fs_coach_messages.length;
  const evs = await events(await coach.handleCoach(post({ message: "Hi" })));
  assert.deepEqual(evs.map((e) => e.type), ["started", "error"]);
  assert.equal(evs[1].code, "invalid_api_key");
  // The question was saved when it started; a failed answer takes it (and its new thread) away again.
  assert.equal(tables.fs_coach_threads.length, threadsBefore);
  assert.equal(tables.fs_coach_messages.length, messagesBefore);

  const missing = await coach.handleCoach(post({ message: "Hi", thread_id: "00000000-0000-4000-8000-000000000000" }));
  assert.equal(missing.status, 404);

  const empty = await coach.handleCoach(post({ message: "   " }));
  assert.equal(empty.status, 400);

  delete env.ANTHROPIC_API_KEY;
  const notConfigured = await coach.handleCoach(post({ message: "Hi" }));
  assert.equal(notConfigured.status, 503);
  assert.equal(((await notConfigured.json()) as Row).error, "coach_not_configured");
  env.ANTHROPIC_API_KEY = "sk-ant-test";
});

test("tools: validation and data", async () => {
  const ctx = { acc: tables.fs_account[0] as never, settings: tables.fs_user_settings[0] as never, today: "2026-10-18", tz: "Europe/Budapest" };
  await assert.rejects(coach.runTool("get_daily_metrics", { from: "2026-01-01", to: "2027-06-01", metrics: ["steps"] }, ctx, null), /400 days/);
  await assert.rejects(coach.runTool("get_daily_metrics", { from: "2026-10-01", to: "2026-10-18", metrics: ["nope"] }, ctx, null), /unknown metrics: nope/);
  const day = await coach.runTool("get_day", { date: "2026-10-15" }, ctx, null) as Row;
  assert.equal((day.hourly_heart_rate as unknown[]).length, 24);
  assert.ok((day.sleep_sessions as Row[]).length >= 1);
  assert.match(String((day.sleep_sessions as Row[])[0].start), /^\d{2}:\d{2}$/);
  // The afternoon nap Google also flags as main sleep is a nap here too; the night is the main sleep.
  const napSessions = (await coach.runTool("get_day", { date: NAP_MAIN_DAY }, ctx, null) as Row).sleep_sessions as Row[];
  assert.deepEqual(napSessions.map((s) => [s.main, s.nap]), [[true, false], [false, true]]);
  assert.deepEqual([napSessions[1].start, napSessions[1].awakenings, napSessions[1].awake_after_falling_asleep_min], ["17:13", 0, 0]);
  const workouts = (await coach.runTool("get_workouts", { from: "2026-08-20", to: "2026-10-18" }, ctx, null) as Row).workouts as Row[];
  assert.ok(workouts.some((w) => typeof w.hrr_1min === "number" && typeof w.hrr_2min === "number"), "heart-rate recovery of the runs");
  const empty = await coach.runTool("get_day", { date: "2026-01-01" }, ctx, null) as Row;
  assert.equal(empty.note, "Nothing was recorded on this date.");
});

test("delete removes the thread and its messages", async () => {
  const thread = tables.fs_coach_threads[0].id as string;
  await coach.coachDelete(thread);
  assert.equal(tables.fs_coach_threads.length, 0);
  assert.equal(tables.fs_coach_messages.filter((m) => m.thread_id === thread).length, 0);
});

test("context: journal entries, tag effects and tonight's sleep plan", async () => {
  const { saveJournalEntry } = await import("../functions/fitstats/lib/journal.ts");
  const { clockFor } = await import("../functions/fitstats/lib/sync.ts");
  const today = clockFor(tables.fs_account[0] as never).today();
  const yesterday = new Date(Date.parse(`${today}T00:00:00Z`) - 86_400_000).toISOString().slice(0, 10);
  await saveJournalEntry({ date: yesterday, tags: ["Alcohol", "late meal"], note: "Birthday dinner" }, today);
  const before = claudeRequests.length;
  const evs = await events(await coach.handleCoach(post({ message: "Why did I sleep badly?" })));
  assert.equal(evs.at(-1)!.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));
  const text = String((claudeRequests[before].system as Row[])[1].text);
  assert.match(text, /journal: Alcohol, Late meal; note "Birthday dinner"/);
  assert.match(text, /Tonight's sleep plan \(FitStats' rule, shown in the app\): need tonight \d+h \d+m \(base 8h 0m/);
  assert.doesNotMatch(text, /sleep need \d+h \d+m \(/, "the plan's total is never called the sleep need");
  assert.match(text, /in bed by \d\d:\d\d to wake at \d\d:\d\d/);
  assert.match(text, /\nWake-up times: none set by hand \(Settings → Wake-up times\), so the sleep plan uses the band's\. From the band, they usually wake at (\d\d:\d\d|not known yet) on weekdays/);
  assert.match(text, /\nTraining load \(shown in the app\) up to \d{4}-\d{2}-\d{2}: fitness [\d.]+, fatigue [\d.]+, form [+−]?[\d.]+, so (fresh|neutral|productive|overreaching); load ratio [\d.]+\./);
  assert.match(text, /\nBedtime vs sleep \(shown in the app; last \d+ scored nights\): best \d\d:\d\d–\d\d:\d\d, sleep score [+−][\d.]+ vs all other nights \((clear|not clear)\)\. By bedtime: .*\d+ nights \(sleep score \d+, asleep \d+h \d+m, recovery \d+\)/);
  const instructions = String((claudeRequests[before].system as Row[])[0].text);
  assert.match(instructions, /- Training load \(shown in the app\): fitness is the 42-day/);
  assert.match(instructions, /- Heart-rate recovery \(per workout\)/);
});

test("context: wake-up times set by hand set tonight's bedtime and are listed", async () => {
  // 2026-10-18 is a Sunday: tonight's plan is for Monday morning.
  const settings = { ...(tables.fs_user_settings[0] as Row), wake_times: [360, 360, 360, 360, 360, 540, null] };
  const ctx = { acc: tables.fs_account[0] as never, settings: settings as never, today: "2026-10-18", tz: "Europe/Budapest" };
  const text = await coach.buildContext(ctx, null);
  assert.match(text, /in bed by \d\d:\d\d to wake at 06:00 \(the wake-up time they set for Mon\)/);
  assert.match(text, /\nWake-up times they set by hand \(the morning of each day; Settings → Wake-up times\): Mon 06:00, Tue 06:00, Wed 06:00, Thu 06:00, Fri 06:00, Sat 09:00, Sun none \(no fixed time: a morning they can sleep in\)\. From the band/);
  // Not a list of 7: ignored, as if none were set.
  const broken = await coach.buildContext({ ...ctx, settings: { ...settings, wake_times: [360] } as never }, null);
  assert.match(broken, /\nWake-up times: none set by hand/);
});

test("training: the app saves routines and workouts, the coach reads them and saves a routine", async () => {
  const training = await import("../functions/fitstats/lib/training.ts");
  const ctx = { acc: tables.fs_account[0] as never, settings: tables.fs_user_settings[0] as never, today: "2026-10-18", tz: "Europe/Budapest" };
  const mine = await training.saveRoutine({ name: "Legs", exercises: [{ name: "Squat", kind: "strength", sets: 5, reps: "5", weight_kg: 80 }] }, "user");
  await training.saveLog({
    date: "2026-10-17", name: "Legs", routine_id: mine.id, effort: 8,
    exercises: [{ name: "Squat", kind: "strength", sets: [{ reps: 5, weight_kg: 80 }, { reps: 5, weight_kg: 85 }] }],
  }, "2026-10-18");
  await assert.rejects(training.saveLog({ date: "2026-10-19", exercises: [{ name: "Squat" }] }, "2026-10-18"), training.TrainingInputError);

  const data = await training.trainingData("2026-10-18");
  assert.deepEqual([(data.routines as Row[]).length, (data.logs as Row[]).length], [1, 1]);
  assert.ok((data.band_workouts as Row[]).length > 0, "the band's workouts of the last 120 days");

  const library = data.library as { muscles: Row[]; exercises: Row[] };
  assert.equal(library.muscles.length, 15);
  assert.ok(library.exercises.length > 60);

  const read = await coach.runTool("get_training", {}, ctx, null) as Row;
  const progress = read.exercise_progress_last_year as Row[];
  assert.deepEqual([progress[0].name, (progress[0].best as Row).weight_kg], ["Squat", 85]);
  // Two done squat sets: 1 each for the main muscles, ½ each for the helpers.
  assert.deepEqual(read.muscle_sets_last_7_days, { quads: 2, glutes: 2, adductors: 1, hamstrings: 1, lower_back: 1 });
  const squat = ((read.routines as Row[])[0].exercises as Row[])[0];
  assert.deepEqual([squat.works, squat.helps], [["quads", "glutes"], ["adductors", "hamstrings", "lower_back"]]);
  assert.ok((read.library_exercises as string[]).includes("Romanian deadlift"));
  // An exercise outside the library keeps the muscles chosen for it (known ones only).
  const sled = await training.saveRoutine({ name: "Sled", exercises: [{ name: "Sled push", kind: "strength", muscles: ["quads", "glutes", "wings"] }] }, "user");
  assert.deepEqual(sled.exercises[0].muscles, ["quads", "glutes"]);
  await training.deleteRoutine(sled.id);
  const context = await coach.buildContext(ctx, null);
  assert.match(context, /Routine \(id [0-9a-f-]{36}\) Legs: Squat \(strength: 5 sets of 5 @ 80 kg; works quads, glutes \(helps: adductors, hamstrings, lower_back\)\)/);
  assert.match(context, /Logged 2026-10-17 Legs \(effort 8\/10\): Squat: 5 reps × 80 kg, 5 reps × 85 kg/);
  await assert.rejects(coach.runTool("save_routine", { id: crypto.randomUUID(), name: "X", exercises: [] }, ctx, null), /no routine with id/);

  // The coach makes one; the app hears that training changed and reloads it.
  const evs = await events(await coach.handleCoach(post({ message: "Make me a routine for my upper body" })));
  assert.deepEqual(evs.filter((e) => e.type === "changed"), [{ type: "changed", what: "training" }]);
  assert.ok(evs.some((e) => e.type === "status" && /Saving “Upper body A” to Training/.test(String(e.text))));
  const saved = tables.fs_routines.find((r) => r.name === FAKE_ROUTINE.name)!;
  assert.equal(saved.created_by, "coach");
  assert.deepEqual((saved.exercises as Row[]).map((e) => e.name), ["Bench press", "Bent-over row", "Easy bike"]);
  assert.equal(saved.position, 1, "after the user's routine");
  const reply = evs.filter((e) => e.type === "text").map((e) => e.text).join("");
  assert.match(reply, /I saved \*\*Upper body A\*\* to your Training tab\./);

  await training.reorderRoutines([String(saved.id), mine.id]);
  assert.deepEqual((await training.loadRoutines()).map((r) => r.name), ["Upper body A", "Legs"]);
  await training.deleteRoutine(mine.id);
  assert.deepEqual((await training.loadRoutines()).map((r) => r.name), ["Upper body A"]);
});

test("chat: a workout CSV is saved to the Training log and the coach is told what was in it", async () => {
  claudeRequests.length = 0;
  const logsBefore = tables.fs_workout_logs.length;
  const today = (await import("../functions/fitstats/lib/sync.ts")).clockFor(tables.fs_account[0] as never).today();
  const day = (n: number) => new Date(Date.parse(`${today}T00:00:00Z`) - n * 86_400_000).toISOString().slice(0, 10);
  const text = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n" +
    `${day(3)} 18:00:00,Push,1h,Bench Press (Barbell),1,80,5,0,0,,,\n${day(3)} 18:00:00,Push,1h,Bench Press (Barbell),2,80,5,0,0,,,\n` +
    `${day(1)} 07:00:00,Legs,50m,Squat (Barbell),1,100,5,0,0,,,\n`;
  const evs = await events(await coach.handleCoach(post({ message: "", files: [{ name: "strong.csv", text }] })));
  const done = evs.at(-1)!;
  assert.equal(done.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));
  assert.deepEqual(evs.slice(0, 3).map((e) => e.type), ["status", "changed", "started"]);
  assert.equal(evs[0].text, "Reading strong.csv");
  assert.equal(tables.fs_workout_logs.length, logsBefore + 2);

  const asked = String((claudeRequests[0].messages as Row[]).at(-1)!.content);
  assert.match(asked, /^Here are my workouts\. Look at how much and how I've been training\.\n\n\[They attached strong\.csv\. FitStats read strong\.csv \(a Strong export\) and saved 2 workouts/);
  assert.match(String((claudeRequests[0].system as Row[])[0].text), /- They can attach workout files \(CSV exports/);
  const thread = tables.fs_coach_threads.find((t) => t.id === done.thread_id)!;
  assert.equal(thread.title, "strong.csv");
  const question = tables.fs_coach_messages.find((m) => m.thread_id === done.thread_id && m.role === "user")!;
  const kept = (question.attachments as Row[])[0];
  assert.deepEqual([kept.media_type, kept.name, kept.thumb], ["text/csv", "strong.csv", null]);

  // Later in the conversation the coach still knows what the file held, without the file.
  claudeRequests.length = 0;
  await events(await coach.handleCoach(post({ message: "And this week?", thread_id: done.thread_id })));
  const history = claudeRequests[0].messages as Row[];
  assert.match(String(history[0].content), /^\[They attached strong\.csv\. FitStats read strong\.csv/);
  assert.ok(!JSON.stringify(history).includes("Bench Press (Barbell),2,80"), "the file itself isn't sent again");

  // A file that isn't workouts: nothing saved, the coach gets its first lines to explain.
  claudeRequests.length = 0;
  const bad = await events(await coach.handleCoach(post({ message: "Can you log these?", files: [{ name: "notes.csv", text: "foo,bar\n1,2\n" }] })));
  assert.equal(bad.at(-1)!.type, "done");
  assert.ok(!bad.some((e) => e.type === "changed"));
  assert.match(String((claudeRequests[0].messages as Row[]).at(-1)!.content), /FitStats couldn't read workouts from notes\.csv/);
  const tooMany = await coach.handleCoach(post({ message: "x", files: [1, 2, 3, 4].map((i) => ({ name: `${i}.csv`, text: "a" })) }));
  assert.equal(tooMany.status, 400);
  // Leave the Training log as the other tests expect it.
  tables.fs_workout_logs.splice(logsBefore);
});

test("weekly summary: written on request or by the cron on Sunday evening, in the phone's clock format", async () => {
  claudeRequests.length = 0;
  tables.fs_cache.splice(0, tables.fs_cache.length, ...tables.fs_cache.filter((c) => c.key !== "coach_weekly"));
  const evs = await events(await coach.handleCoach(post({ kind: "weekly", clock: "12h" })));
  const done = evs.at(-1)!;
  assert.equal(done.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));
  const weekly = done.weekly as Row;
  assert.match(String(weekly.text), /^\*\*Training\*\* 3 sessions/);
  assert.equal(new Date(`${weekly.week}T00:00:00Z`).getUTCDay(), 1, "keyed by the week's Monday");
  assert.equal((claudeRequests[0].messages as Row[]).at(-1)!.content, coach.WEEKLY_PROMPT);
  const system = claudeRequests[0].system as Row[];
  assert.match(String(system.at(-1)!.text), /^Clock: they use a 12-hour clock\. Write times like 7:10 AM/);
  assert.ok(!system.some((b) => String(b.text).startsWith("Your personality")), "no coach personality in the summary");
  assert.equal((tables.fs_user_settings[0] as Row).clock_24h, false, "the clock is remembered for the cron");
  assert.deepEqual(((await coach.coachWeekly()).weekly as Row).text, weekly.text);

  // A 24-hour phone: chat answers are told so too.
  claudeRequests.length = 0;
  await events(await coach.handleCoach(post({ message: "When should I sleep?", clock: "24h" })));
  assert.match(String((claudeRequests[0].system as Row[]).at(-1)!.text), /^Clock: they use a 24-hour clock/);

  // The cron writes it once, on Sunday from 18:00 local time (Europe/Budapest in the fakes).
  tables.fs_cache.splice(0, tables.fs_cache.length, ...tables.fs_cache.filter((c) => c.key !== "coach_weekly"));
  assert.equal(await coach.maybeWeeklySummary(Date.parse("2026-10-18T14:00:00Z")), false, "Sunday 16:00 is too early");
  assert.equal(await coach.maybeWeeklySummary(Date.parse("2026-10-19T17:00:00Z")), false, "Monday");
  assert.equal(await coach.maybeWeeklySummary(Date.parse("2026-10-18T17:30:00Z")), true, "Sunday 19:30");
  assert.equal(await coach.maybeWeeklySummary(Date.parse("2026-10-18T18:30:00Z")), false, "only once a week");
  (tables.fs_user_settings[0] as Row).clock_24h = null;
});

test("chat: the chosen coach's voice, and screenshots in, previews kept, not resent", async () => {
  claudeRequests.length = 0;
  const shot = PNG_SCREENSHOT;
  const evs = await events(await coach.handleCoach(post({
    message: "What do you make of this?", persona: "ace", images: [{ media_type: "image/png", data: shot, thumb: shot }],
  })));
  const done = evs.at(-1)!;
  assert.equal(done.type, "done", JSON.stringify(evs.filter((e) => e.type === "error")));
  assert.equal(done.persona, "ace");
  const first = claudeRequests[0];
  const system = first.system as Row[];
  assert.equal(system.length, 3);
  assert.match(String(system[2].text), /^Your personality\nYou are Ace, the tough-love performance coach/);
  assert.equal(system[2].cache_control, undefined, "after the cached data, so switching coaches keeps the cache");
  const question = (first.messages as Row[]).at(-1)!.content as Row[];
  assert.deepEqual(question, [
    { type: "image", source: { type: "base64", media_type: "image/png", data: shot } },
    { type: "text", text: "What do you make of this?" },
  ]);
  assert.match(evs.filter((e) => e.type === "text").map((e) => e.text).join(""), /I can see your screenshot/);

  const msgs = tables.fs_coach_messages.filter((m) => m.thread_id === done.thread_id);
  assert.deepEqual(msgs[0].attachments, [{ media_type: "image/png", thumb: shot }]);
  assert.equal(msgs[1].persona, "ace");
  const detail = await (await coach.coachThread(String(done.thread_id))).json() as Row;
  assert.deepEqual(((detail.messages as Row[])[0].attachments as Row[]).length, 1);

  // The next message names the earlier screenshot instead of sending it again; Kai's voice now.
  claudeRequests.length = 0;
  const again = await events(await coach.handleCoach(post({ message: "And now?", thread_id: done.thread_id, persona: "kai" })));
  assert.equal(again.at(-1)!.type, "done");
  const history = claudeRequests[0].messages as Row[];
  assert.equal(history[0].content, "What do you make of this?\n\n[They attached a screenshot to this message. You saw it then; it isn't shown again.]");
  assert.ok(!JSON.stringify(history).includes(shot));
  assert.match(String((claudeRequests[0].system as Row[])[2].text), /You are Kai/);

  // No persona: Nova. The briefing has no personality block.
  claudeRequests.length = 0;
  await events(await coach.handleCoach(post({ message: "Hi" })));
  assert.match(String((claudeRequests[0].system as Row[])[2].text), /You are Nova/);

  for (const [images, why] of [
    [[{ media_type: "image/bmp", data: shot }], /JPEG, PNG, WebP or GIF/],
    [[{ media_type: "image/png", data: "not base64!" }], /empty or too large/],
    [Array.from({ length: 4 }, () => ({ media_type: "image/png", data: shot })), /At most 3/],
  ] as const) {
    const res = await coach.handleCoach(post({ message: "x", images }));
    assert.equal(res.status, 400);
    assert.match(String(((await res.json()) as Row).message), why);
  }
  // A screenshot alone is a message.
  const alone = await events(await coach.handleCoach(post({ images: [{ media_type: "image/png", data: shot }] })));
  assert.equal(alone.at(-1)!.type, "done");
  assert.equal(tables.fs_coach_threads.find((t) => t.id === alone.at(-1)!.thread_id)!.title, "Screenshot");
});

test("chat: an answer the app stops listening to (backgrounded, network lost) is still saved", async () => {
  const res = await coach.handleCoach(post({ message: "Quick one before I lock my phone" }));
  const reader = res.body!.getReader();
  const first = new TextDecoder().decode((await reader.read()).value);
  const started = JSON.parse(first.split("\n\n").find((b) => b.startsWith("data: "))!.slice(6)) as Row;
  assert.equal(started.type, "started");
  await reader.cancel();
  const answered = () => tables.fs_coach_messages.some((m) => m.thread_id === started.thread_id && m.role === "assistant");
  for (let i = 0; i < 200 && !answered(); i++) await new Promise((r) => setTimeout(r, 10));
  const saved = tables.fs_coach_messages.filter((m) => m.thread_id === started.thread_id);
  assert.deepEqual(saved.map((m) => m.role), ["user", "assistant"]);
  assert.equal(saved[0].id, started.message_id);
  assert.match(String(saved[1].content), /Your HRV averaged/);
});

test("tools: the coach changes settings, the journal and logged workouts, and deletes only when confirmed, restorably", async () => {
  const ctx = { acc: tables.fs_account[0] as never, settings: tables.fs_user_settings[0] as never, today: "2026-10-18", tz: "Europe/Budapest" };
  // Settings: wake-up times (no recompute needed), and bad values are refused.
  const times = [390, 390, 390, 390, 390, null, 540];
  const saved = await coach.runTool("update_settings", { wake_times: times }, ctx, null) as Row;
  assert.deepEqual((saved.settings as Row).wake_times, times);
  assert.deepEqual(((await coach.runTool("get_settings", {}, ctx, null)) as Row).wake_times, times);
  await assert.rejects(coach.runTool("update_settings", { sex: "robot" }, ctx, null), /sex must be/);
  await coach.runTool("update_settings", { wake_times: null }, ctx, null);
  // Body age answers: saved, and bad ones refused.
  await coach.runTool("update_settings", { lifestyle: { smoking: "former", quit_age: "under40", vaping: "never", alcohol: "1-10" } }, ctx, null);
  assert.deepEqual((tables.fs_user_settings[0].lifestyle as Row).smoking, "former");
  await assert.rejects(coach.runTool("update_settings", { lifestyle: { smoking: "yes", vaping: "never", alcohol: "none" } }, ctx, null), /smoking must be/);

  // Journal: save, then delete only once confirmed, then put back.
  await coach.runTool("save_journal_entry", { date: "2026-10-16", tags: ["alcohol", "Late dinner"], note: "Birthday" }, ctx, null);
  assert.deepEqual(tables.fs_journal.find((j) => j.date === "2026-10-16")!.tags, ["alcohol", "Late dinner"]);
  await assert.rejects(coach.runTool("save_journal_entry", { date: "2099-01-01", tags: [] }, ctx, null), /not in the future/);
  await assert.rejects(coach.runTool("delete_item", { kind: "journal", id: "2026-10-16", confirmed: false }, ctx, null), /Ask them first/);
  assert.ok(tables.fs_journal.some((j) => j.date === "2026-10-16"), "not deleted without confirmation");
  const gone = await coach.runTool("delete_item", { kind: "journal", id: "2026-10-16", confirmed: true }, ctx, null) as Row;
  assert.equal(gone.deleted, true);
  assert.ok(!tables.fs_journal.some((j) => j.date === "2026-10-16"));
  const trash = (await coach.runTool("get_deleted", {}, ctx, null) as Row).recently_deleted as Row[];
  assert.equal(trash[0].label, "Journal 2026-10-16");
  await coach.runTool("restore_deleted", { id: trash[0].id }, ctx, null);
  assert.equal(tables.fs_journal.find((j) => j.date === "2026-10-16")!.note, "Birthday");
  assert.equal(tables.fs_coach_trash.length, 0);

  // Logged workouts: add, change by id, refuse an unknown id, delete and restore.
  const added = (await coach.runTool("save_workout_log", {
    date: "2026-10-18", name: "Pull day", effort: 7,
    exercises: [{ name: "Pull-up", kind: "strength", sets: [{ reps: 8 }, { reps: 7 }] }],
  }, ctx, null) as Row).workout as Row;
  await coach.runTool("save_workout_log", {
    id: added.id, date: "2026-10-18", name: "Pull day", effort: 8,
    exercises: [{ name: "Pull-up", kind: "strength", sets: [{ reps: 8 }, { reps: 8 }] }],
  }, ctx, null);
  assert.equal(tables.fs_workout_logs.find((l) => l.id === added.id)!.effort, 8);
  await assert.rejects(coach.runTool("save_workout_log", { id: crypto.randomUUID(), date: "2026-10-18", name: "X", exercises: [{ name: "Row", kind: "strength", sets: [] }] }, ctx, null), /no logged workout/);
  await coach.runTool("delete_item", { kind: "workout_log", id: added.id, confirmed: true }, ctx, null);
  assert.ok(!tables.fs_workout_logs.some((l) => l.id === added.id));
  const t = ((await coach.runTool("get_deleted", {}, ctx, null)) as Row).recently_deleted as Row[];
  assert.equal(t[0].label, "Pull day (2026-10-18)");
  await coach.runTool("restore_deleted", { id: t[0].id }, ctx, null);
  assert.ok(tables.fs_workout_logs.some((l) => l.id === added.id));
  await assert.rejects(coach.runTool("delete_item", { kind: "routine", id: "nope", confirmed: true }, ctx, null), /id must be/);
});
