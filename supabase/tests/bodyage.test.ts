import assert from "node:assert/strict";
import { test } from "node:test";
import {
  bodyAge, exerciseYears, fitnessYears, metHours, sleepYears, STEP_REFERENCE, stepsYears, typicalVo2, vo2FromHeartRate, yearsFromRisk,
} from "../functions/fitstats/lib/bodyage.ts";
import { addDays } from "../functions/fitstats/lib/util.ts";

const close = (a: number, b: number, tol = 0.01) => assert.ok(Math.abs(a - b) <= tol, `${a} ≈ ${b}`);

test("body age: risk to years with mortality doubling every 8 years", () => {
  close(yearsFromRisk(2), 8);
  close(yearsFromRisk(1), 0);
  close(yearsFromRisk(0.5), -8);
});

test("body age: each factor against its study", () => {
  // Uth: 15.3 (men) / 14.5 (women) × HRmax / HRrest.
  close(vo2FromHeartRate(190, 60, "male"), 48.45);
  close(vo2FromHeartRate(190, 60, "female"), 45.92, 0.01);
  // Loe: 54.4 / 43.0 at 20–29, 3.5 lower per decade.
  close(typicalVo2(25, "male"), 54.4);
  close(typicalVo2(45, "male"), 47.4);
  close(typicalVo2(22, "female"), 43.0);
  // Kodama: RR 0.87 per 3.5 ml/kg/min.
  close(fitnessYears(typicalVo2(40, "male"), 40, "male"), 0);
  close(fitnessYears(typicalVo2(40, "male") + 3.5, 40, "male"), 8 * Math.log2(0.87));
  // Paluch: 0 at the reference; the 4th quartile median against it; the plateau by age.
  close(stepsYears(STEP_REFERENCE, 30), 0);
  close(stepsYears(10901, 30), 8 * Math.log2(0.47 / 0.575), 0.02);
  close(stepsYears(15000, 30), stepsYears(10901, 30));
  close(stepsYears(12000, 65), stepsYears(8000, 65));
  // Arem: 7.5 MET-h a week = 150 moderate minutes; none against the minimum.
  close(metHours(150, 0), 7.5);
  close(exerciseYears(7.5), 0);
  close(exerciseYears(0), 8 * Math.log2(1 / 0.745));
  close(exerciseYears(7.5 * 4), 8 * Math.log2(0.61 / 0.745));
  // Cappuccio: 7–8.5 h is the reference; RR 1.12 short, 1.30 long.
  close(sleepYears(7.5), 0);
  close(sleepYears(5.5), 8 * Math.log2(1.12));
  close(sleepYears(9.5), 8 * Math.log2(1.30));
});

function days(n: number, today: string, row: (i: number) => Record<string, unknown>) {
  return Array.from({ length: n }, (_, i) => ({ date: addDays(today, -n + i), ...row(i) }));
}

test("body age: the estimate, its factors, what-ifs and history", () => {
  const today = "2026-10-30";
  const data = days(200, today, () => ({ rhr: 55, steps: 9000, active_moderate_min: 20, active_vigorous_min: 5, sleep_in_bed_min: 450 }));
  const b = bodyAge(data, today, { age: 30, sex: "male", maxHr: 190, maxHrSource: "observed" }, addDays)!;
  assert.deepEqual(b.factors.map((f) => f.key), ["fitness", "steps", "exercise", "sleep"]);
  assert.equal(b.window.to, "2026-10-29", "today isn't finished");
  close(b.vo2max!.value, 52.9, 0.05);
  // Fitness + the average of steps and exercise + sleep.
  const y = (k: string) => b.factors.find((f) => f.key === k)!.years;
  close(b.difference, y("fitness") + (y("steps") + y("exercise")) / 2 + y("sleep"), 0.15);
  close(b.body_age, 30 + b.difference, 0.05);
  assert.ok(b.what_if.length > 0 && b.what_if.every((w) => w.years < 0));
  assert.ok(b.history.length >= 20, "a point a week for months");
  assert.equal(b.history.at(-1)!.body_age, b.body_age);

  // Too little data for a factor: it's listed as missing; without age there's nothing.
  const few = days(20, today, (i) => ({ rhr: 60, steps: i < 10 ? 5000 : null }));
  const partial = bodyAge(few, today, { age: 30, sex: "male", maxHr: 190, maxHrSource: "age" }, addDays)!;
  assert.deepEqual(partial.factors.map((f) => f.key), ["fitness"]);
  assert.ok(partial.missing.some((m) => m.startsWith("steps: 10 of 14")));
  assert.equal(bodyAge(data, today, { age: NaN, sex: "male", maxHr: 190, maxHrSource: "age" }, addDays), null);
  // Low-wear days don't count towards day totals.
  const lazy = days(40, today, () => ({ rhr: 55, steps: 1000, low_wear: true }));
  assert.ok(bodyAge(lazy, today, { age: 30, sex: "male", maxHr: 190, maxHrSource: "age" }, addDays)!.missing.some((m) => m.startsWith("steps: 0")));
});

test("body age: from 16 the youngest adults stand in, with a note", () => {
  const today = "2026-10-30";
  const data = days(40, today, () => ({ rhr: 60, steps: 8184, active_moderate_min: 208 / 7, active_vigorous_min: 268 / 7, sleep_in_bed_min: 7.26 * 60 }));
  const b = bodyAge(data, today, { age: 17, sex: "male", maxHr: 199, maxHrSource: "observed" }, addDays)!;
  close(b.vo2max!.typical_for_age, 54.4);
  close(b.body_age, 17.2, 0.15);
  assert.match(b.note, /studies are of adults/);
  assert.equal(bodyAge(data, today, { age: 15, sex: "male", maxHr: 199, maxHrSource: "observed" }, addDays), null);
});
