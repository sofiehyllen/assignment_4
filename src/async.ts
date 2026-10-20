// Part C - asynchronous code against a real database

import { pool } from './db.js';
import { findStudent, coursesFor, deleteStudent } from './queries.js';

export interface Overview {
  students: number;
  courses: number;
  departments: number;
}

// --- C1. Steps that depend on each other ----------------------------------

/**
 * The title of the first course a student takes, or undefined when the
 * student does not exist or takes nothing.
 *
 * Two steps, the second needing the first. Handle a missing student with
 * try/catch or with a check, and say in a comment which you chose and why.
 */
export async function firstCourseTitle(studentId: string): Promise<string | undefined> {
  // A missing student is handled with a check: findStudent returns undefined 
  // for an unknown id since it is an ordinary answer and not an error. 
  // try/catch is kept for real failures, which are passed on.
  const student = await findStudent(studentId);
  if (student === undefined) {
    return undefined;
  }

  // coursesFor only runs once we know the student exists.
  const courses = await coursesFor(student.id);
  return courses[0]?.title;
}

// --- C2. Steps that do not depend on each other ---------------------------

/**
 * Three counts: students, courses, departments.
 *
 * Write it twice. overviewSlowly does one query after another; overview
 * starts all three together. The runner times both.
 *
 * Use this query, and note the pg_sleep: each count is made to take about
 * 200 ms on purpose.
 *
 *     SELECT pg_sleep(0.2), count(*)::int AS total FROM student
 *
 * Without it the three counts against a local database finish in about a
 * millisecond each, and starting them together costs more than it saves,
 * because the pool has to open two more connections. Waiting is what makes
 * the difference visible, and on a real server the waiting is real.
 */
export async function overviewSlowly(): Promise<Overview> {
  const s = await pool.query<{ n: number }>(
    `SELECT count(*)::int AS n, pg_sleep(0.2) FROM student`);
  const c = await pool.query<{ n: number }>(
    `SELECT count(*)::int AS n, pg_sleep(0.2) FROM course`);
  const d = await pool.query<{ n: number }>(
    `SELECT count(*)::int AS n, pg_sleep(0.2) FROM department`);

  return {
    students: s.rows[0].n,
    courses: c.rows[0].n,
    departments: d.rows[0].n,
  };
}

export async function overview(): Promise<Overview> {
  const [s, c, d] = await Promise.all([
    pool.query<{ n: number }>(`SELECT count(*)::int AS n, pg_sleep(0.2) FROM student`),
    pool.query<{ n: number }>(`SELECT count(*)::int AS n, pg_sleep(0.2) FROM course`),
    pool.query<{ n: number }>(`SELECT count(*)::int AS n, pg_sleep(0.2) FROM department`),
  ]);

  return {
    students: s.rows[0].n,
    courses: c.rows[0].n,
    departments: d.rows[0].n,
  };
}

// --- C3. The forgotten await ----------------------------------------------

/**
 * Written for you, and wrong.
 *
 * It should delete a student and then report whether they are still there.
 * It reports that they are. Run it, explain in a comment what happens and
 * in which order, then write the corrected version below.
 *
 * There is a second problem, worse than the wrong answer: if the delete
 * fails, who finds out?
 */
export async function removeAndCheckBroken(id: string): Promise<boolean> {
  deleteStudent(id);
  const still = await findStudent(id);
  return still !== undefined;
}

/** The same thing, correct: false when the student is really gone. */
export async function removeAndCheck(id: string): Promise<boolean> {
  await deleteStudent(id);
  const still = await findStudent(id);
  return still !== undefined;
}

// Explanation: deleteStudent is not awaited. It starts the DELETE and returns
// a pending promise; findStudent starts its SELECT straight away on
// another connection, so the two run at the same time. The SELECT sees
// the row before the DELETE has committed, and the function returns true.
// If the delete fails, nobody awaits its promise: the error never reaches
// the caller, and Node reports an unhandled rejection and stops the process.