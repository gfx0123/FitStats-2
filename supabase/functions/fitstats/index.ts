// FitStats Edge Function: Google sign-in, sync triggers and the app's API.
//
// Routes (query parameter `r`):
//   connect            Google OAuth start (opened by the app in a browser sheet)
//   (code/state)       Google OAuth callback — this function's URL is the redirect URI
//   cron               pg_cron trigger, authenticated with x-cron-secret
//   health             unauthenticated setup check
//   status | days | day | stats | sync | settings | journal | home | training | disconnect
//                      app routes, authenticated with x-app-key
//   coach | coach_status | coach_threads | coach_thread | coach_delete | coach_brief
//                      Claude coach (lib/coach.ts), also x-app-key

import { coachBrief, coachDelete, coachStatus, coachThread, coachThreads, coachWeekly, handleCoach, isCoachModel, maybeWeeklySummary } from "./lib/coach.ts";
import * as db from "./lib/db.ts";
import { decodeIdToken, exchangeCode, GOOGLE_AUTH_URL, HEALTH_SCOPES, HealthClient, OAUTH_SCOPES } from "./lib/google.ts";
import { JOURNAL_TAGS, journalEntries, JournalInputError, saveJournalEntry } from "./lib/journal.ts";
import { applySettings, settingsWithMaxHr, SettingsInputError } from "./lib/settings.ts";
import {
  clockFor,
  loadAccount,
  loadSettings,
  maxHrInUse,
  rebuildStats,
  recomputeHistory,
  recomputeScores,
  runSync,
} from "./lib/sync.ts";
import { mainSleepOf } from "./lib/transform.ts";
import {
  deleteLog,
  deleteRoutine,
  reorderRoutines,
  saveLog,
  saveRoutine,
  trainingData,
  TrainingInputError,
} from "./lib/training.ts";
import { addDays, background } from "./lib/util.ts";
import { VERSION } from "./lib/version.ts";

const APP_SCHEME = "fitstats://";
const DEFAULT_APP_REDIRECT = "fitstats://connected";

type Row = Record<string, unknown>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function redirect(location: string): Response {
  return new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "no-store" } });
}

function withParams(base: string, params: Record<string, string>): string {
  const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== "")).toString();
  return qs ? `${base}${base.includes("?") ? "&" : "?"}${qs}` : base;
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomToken(bytes: number): string {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

async function sha256(s: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
}

async function sha256Hex(s: string): Promise<string> {
  return [...(await sha256(s))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function selfUrl(): string {
  return `${db.env("SUPABASE_URL")}/functions/v1/fitstats`;
}

const q = encodeURIComponent;
const YMD = /^\d{4}-\d{2}-\d{2}$/;

// ------------------------------------------------------------------- OAuth

async function oauthStart(params: URLSearchParams): Promise<Response> {
  const appRedirect = params.get("app_redirect") ?? DEFAULT_APP_REDIRECT;
  if (!appRedirect.startsWith(APP_SCHEME)) return json({ error: "app_redirect must use the fitstats:// scheme" }, 400);
  const clientId = db.optionalEnv("GOOGLE_CLIENT_ID");
  if (!clientId || !db.optionalEnv("GOOGLE_CLIENT_SECRET")) {
    return redirect(withParams(appRedirect, {
      error: "server_not_configured",
      message: "The Google client ID and secret are not set in Supabase yet.",
    }));
  }
  const state = randomToken(24);
  const verifier = randomToken(48);
  const challenge = b64url(await sha256(verifier));
  await db.remove("fs_oauth_states", `created_at=lt.${q(new Date(Date.now() - 3_600_000).toISOString())}`);
  await db.insert("fs_oauth_states", [{ state, code_verifier: verifier, app_redirect: appRedirect }]);

  const url = new URL(GOOGLE_AUTH_URL);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("redirect_uri", selfUrl());
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", OAUTH_SCOPES.join(" "));
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("include_granted_scopes", "true");
  url.searchParams.set("state", state);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  return redirect(url.toString());
}

async function oauthCallback(params: URLSearchParams): Promise<Response> {
  const state = params.get("state") ?? "";
  const st = await db.selectOne<Row>("fs_oauth_states", `select=*&state=eq.${q(state)}`);
  if (!st) {
    return redirect(withParams(DEFAULT_APP_REDIRECT, { error: "invalid_state", message: "This sign-in link expired. Try again." }));
  }
  await db.remove("fs_oauth_states", `state=eq.${q(state)}`);
  const appRedirect = String(st.app_redirect);
  const fail = (error: string, message: string) => redirect(withParams(appRedirect, { error, message }));

  if (Date.now() - Date.parse(String(st.created_at)) > 30 * 60_000) return fail("expired", "Sign-in took too long. Try again.");
  const googleError = params.get("error");
  if (googleError) return fail(googleError, params.get("error_description") ?? "Google sign-in was cancelled.");

  const clientId = db.env("GOOGLE_CLIENT_ID");
  const clientSecret = db.env("GOOGLE_CLIENT_SECRET");
  let tokens;
  try {
    tokens = await exchangeCode(params.get("code") ?? "", String(st.code_verifier), selfUrl(), clientId, clientSecret);
  } catch (e) {
    return fail("token_exchange", String((e as Error).message).slice(0, 200));
  }

  const claims = decodeIdToken(tokens.id_token);
  const acc = await loadAccount();
  if (acc?.google_sub && claims.sub && acc.google_sub !== claims.sub) {
    // No email here: anyone can open the sign-in link, so this must not say whose server it is.
    return fail("wrong_account", "This server is already set up with a different Google account. Sign in with the account you set it up with.");
  }
  const refreshToken = tokens.refresh_token ?? acc?.refresh_token ?? null;
  if (!refreshToken) return fail("no_refresh_token", "Google did not return offline access. Remove FitStats from your Google account permissions and try again.");

  const granted = (tokens.scope ?? "").split(" ");
  const missing = HEALTH_SCOPES.filter((s) => !granted.includes(s)).map((s) => s.split(".").slice(-2).join("."));

  let healthUserId: string | null = null;
  try {
    const identity = await new HealthClient(tokens.access_token, async () => tokens!.access_token).getIdentity();
    healthUserId = typeof identity.healthUserId === "string" ? identity.healthUserId : null;
  } catch (e) {
    console.warn("identity", String(e));
  }

  const now = new Date().toISOString();
  await db.update("fs_account", "id=eq.1", {
    google_sub: claims.sub ?? acc?.google_sub ?? null,
    google_email: claims.email ?? acc?.google_email ?? null,
    health_user_id: healthUserId,
    refresh_token: refreshToken,
    access_token: tokens.access_token,
    access_token_expires_at: new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000).toISOString(),
    granted_scopes: tokens.scope ?? null,
    connected_at: now,
    token_status: "ok",
    token_error: null,
    meta_fetched_at: null,
    updated_at: now,
  });

  const key = randomToken(32);
  await db.insert("fs_app_keys", [{ key_hash: await sha256Hex(key) }]);
  const keys = await db.select<Row>("fs_app_keys", "select=key_hash&order=created_at.desc");
  const stale = keys.slice(5).map((k) => String(k.key_hash));
  if (stale.length) await db.remove("fs_app_keys", `key_hash=in.${db.inList(stale)}`);

  background(runSync("connect", true));
  return redirect(withParams(appRedirect, {
    key,
    email: claims.email ?? "",
    missing_scopes: missing.join(","),
  }));
}

// ------------------------------------------------------------- app routes

async function authorized(req: Request): Promise<boolean> {
  const key = req.headers.get("x-app-key") ?? "";
  if (key.length < 20) return false;
  const hash = await sha256Hex(key);
  const row = await db.selectOne<Row>("fs_app_keys", `select=key_hash,last_used_at&key_hash=eq.${hash}`);
  if (!row) return false;
  const last = row.last_used_at ? Date.parse(String(row.last_used_at)) : 0;
  if (Date.now() - last > 3_600_000) {
    await db.update("fs_app_keys", `key_hash=eq.${hash}`, { last_used_at: new Date().toISOString() });
  }
  return true;
}

async function status(): Promise<Response> {
  const [acc, state, settings] = await Promise.all([
    db.selectOne<Row>("fs_account", "select=*&id=eq.1"),
    db.selectOne<Row>("fs_sync_state", "select=*&id=eq.1"),
    loadSettings(),
  ]);
  const clock = clockFor(acc as never);
  const today = clock.today();
  const devices = Array.isArray(acc?.devices) ? (acc!.devices as Row[]) : [];
  const granted = String(acc?.granted_scopes ?? "").split(" ");
  const target = state?.backfill_target ? String(state.backfill_target) : null;
  const oldest = state?.backfill_oldest ? String(state.backfill_oldest) : null;
  let progress: number | null = null;
  if (target && oldest) {
    const total = Math.max(1, (Date.parse(today) - Date.parse(target)) / 86_400_000);
    progress = state?.backfill_done ? 1 : Math.min(1, Math.max(0, (Date.parse(today) - Date.parse(oldest)) / 86_400_000 / total));
  }
  const lockUntil = state?.lock_until ? Date.parse(String(state.lock_until)) : 0;
  return json({
    version: VERSION,
    serverTime: new Date().toISOString(),
    today,
    timeZone: acc?.time_zone ?? null,
    connection: {
      status: acc?.token_status ?? "disconnected",
      email: acc?.google_email ?? null,
      connectedAt: acc?.connected_at ?? null,
      error: acc?.token_error ?? null,
      missingScopes: acc?.granted_scopes ? HEALTH_SCOPES.filter((s) => !granted.includes(s)).map((s) => s.split(".").slice(-2).join(".")) : [],
    },
    sync: {
      running: lockUntil > Date.now(),
      lastRunAt: state?.last_run_finished_at ?? null,
      lastRunStatus: state?.last_run_status ?? null,
      lastRecentSyncAt: state?.last_recent_sync_at ?? null,
      backfillOldest: oldest,
      backfillTarget: target,
      backfillDone: state?.backfill_done ?? false,
      backfillProgress: progress,
      lastRunLog: state?.last_run_log ?? null,
    },
    // The max heart rate the stored strain, stress and zones were computed with.
    maxHr: typeof state?.max_hr_used === "number" ? { value: state.max_hr_used, source: state.max_hr_source ?? null } : null,
    devices: devices.map((d) => ({
      name: d.deviceVersion ?? null,
      type: d.deviceType ?? null,
      batteryLevel: d.batteryLevel ?? null,
      batteryStatus: d.batteryStatus ?? null,
      lastSyncTime: d.lastSyncTime ?? null,
    })),
    profile: { age: (acc?.profile as Row | null)?.age ?? null },
    settings,
  });
}

async function days(params: URLSearchParams): Promise<Response> {
  const acc = await loadAccount();
  const today = clockFor(acc).today();
  const to = params.get("to") ?? today;
  const from = params.get("from") ?? addDays(to, -400);
  if (!YMD.test(from) || !YMD.test(to)) return json({ error: "from/to must be YYYY-MM-DD" }, 400);
  const rows = await db.select<Row>("fs_days", `select=*&date=gte.${from}&date=lte.${to}&order=date.asc`);
  return json({ from, to, today, days: rows });
}

async function day(params: URLSearchParams): Promise<Response> {
  const date = params.get("date") ?? "";
  if (!YMD.test(date)) return json({ error: "date must be YYYY-MM-DD" }, 400);
  const [row, intraday, sleeps, exercises] = await Promise.all([
    db.selectOne<Row>("fs_days", `select=*&date=eq.${date}`),
    db.selectOne<Row>("fs_intraday", `select=hr,steps&date=eq.${date}`),
    db.select<Row>("fs_sleep", `select=*&date=eq.${date}&order=start_time.asc`),
    db.select<Row>("fs_exercise", `select=*&date=eq.${date}&order=start_time.asc`),
  ]);
  const samples: Record<string, [number, number][]> = {};
  // The session fs_days took its sleep columns from, so the detail screen shows the same night.
  const main = mainSleepOf(sleeps, row?.sleep_main_id);
  if (main) {
    const rows = await db.select<Row>(
      "fs_samples",
      `select=metric,t,value&t=gte.${q(String(main.start_time))}&t=lte.${q(String(main.end_time))}&order=t.asc`,
    );
    for (const s of rows) {
      const k = String(s.metric);
      (samples[k] ??= []).push([Math.round(Date.parse(String(s.t)) / 1000), Number(s.value)]);
    }
  }
  return json({ date, day: row, intraday, sleeps, exercises, samples });
}

async function stats(): Promise<Response> {
  const cached = await db.selectOne<Row>("fs_cache", "select=value&key=eq.stats");
  // Stats an older server built miss what this one adds (body age came with 1.14.0): rebuilt once.
  if (cached && (cached.value as Row | null)?.server_version === VERSION) return json(cached.value);
  const acc = await loadAccount();
  const settings = await loadSettings();
  await rebuildStats(clockFor(acc).today(), settings);
  const fresh = await db.selectOne<Row>("fs_cache", "select=value&key=eq.stats");
  return json(fresh?.value ?? null);
}

/** Settings with the max heart rate strain, stress and zones use: "max_hr" {value, source}. */
async function getSettings(): Promise<Response> {
  return json(await settingsWithMaxHr());
}

async function saveSettings(req: Request): Promise<Response> {
  const body = (await req.json().catch(() => ({}))) as Row;
  try {
    return json(await applySettings(body, isCoachModel(body.coach_model) ? { coach_model: body.coach_model } : {}));
  } catch (e) {
    if (e instanceof SettingsInputError) return json({ error: "invalid settings", detail: e.message }, 400);
    throw e;
  }
}

/** GET: the tag list and entries (default: the last 400 days). POST: save or clear one day. */
async function journal(req: Request, params: URLSearchParams): Promise<Response> {
  const today = clockFor(await loadAccount()).today();
  if (req.method !== "POST") {
    const from = params.get("from") ?? addDays(today, -400);
    if (!YMD.test(from)) return json({ error: "from must be YYYY-MM-DD" }, 400);
    return json({ tags: JOURNAL_TAGS, entries: await journalEntries(from) });
  }
  const body = (await req.json().catch(() => ({}))) as Row;
  try {
    const entry = await saveJournalEntry(body, today);
    // Tag effects are part of the statistics cache.
    background(loadSettings().then((settings) => rebuildStats(today, settings)));
    return json({ entry });
  } catch (e) {
    if (e instanceof JournalInputError) return json({ error: "invalid journal entry", detail: e.message }, 400);
    throw e;
  }
}

/**
 * GET: the Home layout the app saved ({layout: null} before the first save).
 * POST {layout, edited_at}: saves it, unless the stored one was edited later (then replies with
 * that one, saved: false). The layout is the app's own JSON; the server only stores it.
 */
async function homeLayout(req: Request): Promise<Response> {
  const current = await db.selectOne<Row>("fs_home_layout", "select=layout,edited_at&id=eq.1");
  const currentEdited = Number(current?.edited_at ?? 0);
  if (req.method !== "POST") return json({ layout: current?.layout ?? null, edited_at: currentEdited });
  const body = (await req.json().catch(() => ({}))) as Row;
  const edited = Number(body.edited_at);
  if (!body.layout || typeof body.layout !== "object" || Array.isArray(body.layout) || !Number.isFinite(edited)) {
    return json({ error: "layout (an object) and edited_at are required" }, 400);
  }
  if (JSON.stringify(body.layout).length > 200_000) return json({ error: "layout too large" }, 413);
  if (current && currentEdited > edited) return json({ saved: false, layout: current.layout, edited_at: currentEdited });
  await db.upsert("fs_home_layout", [{ id: 1, layout: body.layout, edited_at: edited, updated_at: new Date().toISOString() }], "id");
  return json({ saved: true, edited_at: edited });
}

/**
 * GET: routines, the workouts logged in the last year and the band's workouts of the last 120
 * days. POST {action, ...}: save_routine {routine}, delete_routine {id}, reorder_routines
 * {ids}, save_log {log}, delete_log {id}.
 */
async function training(req: Request): Promise<Response> {
  const today = clockFor(await loadAccount()).today();
  if (req.method !== "POST") return json(await trainingData(today));
  const body = (await req.json().catch(() => ({}))) as Row;
  try {
    switch (body.action) {
      case "save_routine":
        return json({ routine: await saveRoutine((body.routine ?? {}) as Row, "user") });
      case "delete_routine":
        await deleteRoutine(String(body.id ?? ""));
        return json({ deleted: true });
      case "reorder_routines":
        await reorderRoutines(body.ids);
        return json({ saved: true });
      case "save_log":
        return json({ log: await saveLog((body.log ?? {}) as Row, today) });
      case "delete_log":
        await deleteLog(String(body.id ?? ""));
        return json({ deleted: true });
      default:
        return json({ error: "unknown action" }, 400);
    }
  } catch (e) {
    if (e instanceof TrainingInputError) return json({ error: "invalid training data", detail: e.message }, 400);
    throw e;
  }
}

async function disconnect(params: URLSearchParams): Promise<Response> {
  await db.update("fs_account", "id=eq.1", {
    refresh_token: null,
    access_token: null,
    access_token_expires_at: null,
    token_status: "disconnected",
    updated_at: new Date().toISOString(),
  });
  if (params.get("wipe") === "true") {
    const tables = ["fs_days", "fs_sleep", "fs_exercise", "fs_intraday", "fs_samples", "fs_cache", "fs_journal", "fs_coach_messages", "fs_coach_threads", "fs_home_layout", "fs_workout_logs", "fs_routines", "fs_coach_trash"];
    const keyColumn: Record<string, string> = { fs_samples: "metric", fs_cache: "key", fs_days: "date", fs_intraday: "date", fs_journal: "date" };
    for (const t of tables) await db.remove(t, `${keyColumn[t] ?? "id"}=not.is.null`);
    await db.update("fs_account", "id=eq.1", { google_sub: null, google_email: null, profile: null, google_settings: null, devices: null });
    await db.update("fs_sync_state", "id=eq.1", {
      backfill_oldest: null, backfill_target: null, backfill_done: false, backfill_empty_chunks: 0,
      last_recent_sync_at: null, recent_fingerprint: null, stats_dirty: false, last_run_log: null,
    });
  }
  await db.remove("fs_app_keys", "key_hash=not.is.null");
  return json({ disconnected: true, wiped: params.get("wipe") === "true" });
}

// ------------------------------------------------------------------ router

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const params = url.searchParams;
  const route = params.get("r") ?? "";
  try {
    if (!route && params.has("state") && (params.has("code") || params.has("error"))) return await oauthCallback(params);
    if (route === "connect") return await oauthStart(params);
    if (route === "health") {
      await db.selectOne("fs_sync_state", "select=id&id=eq.1");
      return json({
        ok: true,
        version: VERSION,
        googleConfigured: !!db.optionalEnv("GOOGLE_CLIENT_ID") && !!db.optionalEnv("GOOGLE_CLIENT_SECRET"),
        redirectUri: selfUrl(),
      });
    }
    if (route === "cron") {
      const secret = req.headers.get("x-cron-secret") ?? "";
      const row = await db.selectOne<Row>("fs_secrets", "select=value&name=eq.cron_secret");
      if (!secret || !row || secret !== row.value) return json({ error: "forbidden" }, 403);
      background(runSync("cron", false));
      // Sunday evening's weekly summary, once a week (does nothing the rest of the time).
      background(maybeWeeklySummary().catch((e) => console.error("weekly summary", String(e))));
      return json({ accepted: true }, 202);
    }

    if (!(await authorized(req))) return json({ error: "unauthorized" }, 401);
    switch (route) {
      case "status":
        return await status();
      case "days":
        return await days(params);
      case "day":
        return await day(params);
      case "stats":
        return await stats();
      case "sync":
        if (req.method !== "POST") return json({ error: "use POST" }, 405);
        background(runSync("app", true));
        return json({ started: true }, 202);
      case "settings":
        if (req.method === "POST") return await saveSettings(req);
        return await getSettings();
      case "journal":
        return await journal(req, params);
      case "home":
        return await homeLayout(req);
      case "training":
        return await training(req);
      case "disconnect":
        if (req.method !== "POST") return json({ error: "use POST" }, 405);
        return await disconnect(params);
      case "coach":
        if (req.method !== "POST") return json({ error: "use POST" }, 405);
        return await handleCoach(req);
      case "coach_status":
        return json(await coachStatus());
      case "coach_threads":
        return json(await coachThreads());
      case "coach_thread":
        return await coachThread(params.get("id") ?? "");
      case "coach_delete":
        if (req.method !== "POST") return json({ error: "use POST" }, 405);
        return await coachDelete(params.get("id") ?? "");
      case "coach_brief":
        return json(await coachBrief());
      case "coach_weekly":
        return json(await coachWeekly());
      default:
        return json({ error: "unknown route" }, 404);
    }
  } catch (e) {
    console.error(route, String(e));
    return json({ error: "server_error", detail: String((e as Error).message ?? e).slice(0, 300) }, 500);
  }
});
