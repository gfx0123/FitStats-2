// Saving settings, from the app (the settings route) or the coach (update_settings): a changed
// sex or max heart rate recomputes the history; a changed sleep need, step goal or history
// length recomputes the scores.

import * as db from "./db.ts";
import { wakeTimesFrom } from "./planner.ts";
import {
  clockFor,
  loadAccount,
  loadSettings,
  maxHrInUse,
  rebuildStats,
  recomputeHistory,
  recomputeScores,
  type UserSettings,
} from "./sync.ts";
import type { MaxHr } from "./transform.ts";
import { addDays, background } from "./util.ts";

type Row = Record<string, unknown>;

export class SettingsInputError extends Error {}

type SavedMaxHr = { max_hr_used: number | null; max_hr_source: string | null };

export function intOrNull(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : null;
}

/** The settings and the max heart rate strain, stress and zones use. */
export async function settingsWithMaxHr(): Promise<{ settings: UserSettings; max_hr: { value: number; source: string } }> {
  const [acc, settings, state] = await Promise.all([
    loadAccount(),
    loadSettings(),
    db.selectOne<SavedMaxHr>("fs_sync_state", "select=max_hr_used,max_hr_source&id=eq.1"),
  ]);
  const maxHr = await maxHrInUse(acc, settings, clockFor(acc).today(), state);
  return { settings, max_hr: { value: maxHr.value, source: maxHr.source } };
}

/**
 * Saves the settings in `body` (sex, max_hr_override, sleep_need_min, step_goal, backfill_days,
 * wake_times; others are ignored) plus `extra`, and starts the recomputing they need.
 */
export async function applySettings(body: Row, extra: Row = {}): Promise<{ settings: UserSettings; max_hr: { value: number; source: string } }> {
  const current = await loadSettings();
  const patch: Row = { ...extra, updated_at: new Date().toISOString() };
  if (typeof body.sex === "string") {
    if (!["male", "female", "unspecified"].includes(body.sex)) throw new SettingsInputError("sex must be male, female or unspecified");
    patch.sex = body.sex;
  }
  if ("max_hr_override" in body) patch.max_hr_override = intOrNull(body.max_hr_override);
  for (const k of ["sleep_need_min", "step_goal", "backfill_days"]) {
    const v = intOrNull(body[k]);
    if (v !== null) patch[k] = v;
  }
  if ("wake_times" in body) {
    try {
      patch.wake_times = wakeTimesFrom(body.wake_times);
    } catch (e) {
      throw new SettingsInputError((e as Error).message);
    }
  }
  try {
    await db.update("fs_user_settings", "id=eq.1", patch);
  } catch (e) {
    // The table's checks (ranges) reject bad values.
    throw new SettingsInputError(String((e as Error).message).slice(0, 300));
  }
  const settings = await loadSettings();
  if (settings.backfill_days !== current.backfill_days) {
    await db.update("fs_sync_state", "id=eq.1", { backfill_target: null, backfill_done: false, backfill_empty_chunks: 0 });
  }
  const acc = await loadAccount();
  const today = clockFor(acc).today();
  const intradayChanged = settings.sex !== current.sex || settings.max_hr_override !== current.max_hr_override;
  const scoresChanged = intradayChanged || settings.sleep_need_min !== current.sleep_need_min ||
    settings.step_goal !== current.step_goal || settings.backfill_days !== current.backfill_days;
  const state = await db.selectOne<SavedMaxHr>("fs_sync_state", "select=max_hr_used,max_hr_source&id=eq.1");
  const maxHr: MaxHr = await maxHrInUse(acc, settings, today, state);
  if (scoresChanged) {
    background((async () => {
      // Recomputes the scores too and saves the max heart rate it used.
      if (intradayChanged && acc) await recomputeHistory(today, settings, acc, maxHr);
      else await recomputeScores(addDays(today, -settings.backfill_days), today, settings);
      await rebuildStats(today, settings);
    })());
  }
  return { settings, max_hr: { value: maxHr.value, source: maxHr.source } };
}
