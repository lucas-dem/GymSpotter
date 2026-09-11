import { env } from "cloudflare:workers";
import { getChatGPTUser } from "@/app/chatgpt-auth";

type ActionBody = {
  action?: string; name?: string; level?: string; daysPerWeek?: number; exerciseIds?: number[];
  routineId?: number; routineName?: string; memberName?: string; sessionId?: number;
  exerciseId?: number; setNumber?: number; weight?: number; reps?: number; rir?: number; value?: number;
};

const seedExercises = [
  ["press-banca", "Press banca", "Pecho", "Barra", "Escápulas juntas, pies firmes y bajá la barra al centro del pecho.", "/exercises/bench-press.png"],
  ["press-inclinado", "Press inclinado", "Pecho superior", "Mancuernas", "Banco a 30°, muñecas neutras y recorrido controlado.", "/exercises/incline-press.png"],
  ["aperturas-polea", "Aperturas en polea", "Pectoral", "Polea", "Codos apenas flexionados; juntá las manos sin encoger hombros.", "/exercises/cable-fly.png"],
  ["extension-triceps", "Extensión de tríceps", "Tríceps", "Polea", "Pegá los codos al cuerpo y extendé sin mover los hombros.", null],
  ["sentadilla", "Sentadilla con barra", "Cuádriceps", "Barra", "Mantené el torso firme, rodillas alineadas y controlá la profundidad.", null],
  ["remo-polea", "Remo en polea", "Espalda", "Polea", "Iniciá retrayendo las escápulas y llevá los codos hacia atrás.", null],
] as const;

function json(data: unknown, status = 200) { return Response.json(data, { status }); }
function validString(value: unknown, max = 80) { return typeof value === "string" && value.trim().length > 0 && value.trim().length <= max; }

async function currentUser() {
  const user = await getChatGPTUser();
  return user ?? (process.env.NODE_ENV === "development" ? { userId: "local-demo", email: "demo@gymspotter.local", displayName: "Lucas", fullName: "Lucas" } : null);
}

async function seedForUser(db: D1Database, user: { userId: string; email: string; displayName: string }) {
  const now = new Date().toISOString();
  const expires = new Date(Date.now() + 12 * 86400000).toISOString();
  const statements = seedExercises.map((item) => db.prepare(
    "INSERT OR IGNORE INTO exercises (slug, name, muscle, equipment, instructions, media_path) VALUES (?, ?, ?, ?, ?, ?)"
  ).bind(...item));
  statements.push(
    db.prepare("INSERT OR IGNORE INTO profiles (user_id, email, display_name, role, created_at) VALUES (?, ?, ?, 'member', ?)").bind(user.userId, user.email, user.displayName, now),
    db.prepare("INSERT OR IGNORE INTO memberships (user_id, plan, expires_at, status) VALUES (?, 'Plan mensual', ?, 'active')").bind(user.userId, expires),
  );
  await db.batch(statements);

  const routineCount = await db.prepare("SELECT COUNT(*) AS count FROM routines WHERE owner_user_id = ?").bind(user.userId).first<{ count: number }>();
  if (!routineCount?.count) {
    const inserted = await db.prepare("INSERT INTO routines (owner_user_id, name, level, days_per_week, created_at) VALUES (?, 'Pecho + tríceps', 'Intermedio', 4, ?) RETURNING id").bind(user.userId, now).first<{ id: number }>();
    if (inserted) {
      const ids = await db.prepare("SELECT id, slug FROM exercises WHERE slug IN ('press-banca','press-inclinado','aperturas-polea','extension-triceps') ORDER BY id").all<{ id: number; slug: string }>();
      const order = ["press-banca", "press-inclinado", "aperturas-polea", "extension-triceps"];
      await db.batch(order.map((slug, position) => {
        const exercise = ids.results.find((item) => item.slug === slug)!;
        const sets = position === 0 ? 4 : 3;
        const repsMin = position === 3 ? 12 : position === 2 ? 12 : position === 1 ? 10 : 8;
        const repsMax = position === 3 ? 15 : position === 0 ? 10 : repsMin;
        const weight = [62.5, 22, 17.5, 25][position];
        return db.prepare("INSERT INTO routine_exercises (routine_id, exercise_id, day_name, position, sets, reps_min, reps_max, target_weight, rest_seconds) VALUES (?, ?, 'Viernes', ?, ?, ?, ?, ?, ?)").bind(inserted.id, exercise.id, position, sets, repsMin, repsMax, weight, position === 0 ? 120 : position === 1 ? 90 : 60);
      }));
    }
  }

  const weightCount = await db.prepare("SELECT COUNT(*) AS count FROM body_weights WHERE user_id = ?").bind(user.userId).first<{ count: number }>();
  if (!weightCount?.count) await db.prepare("INSERT INTO body_weights (user_id, weight, recorded_at) VALUES (?, 78.4, ?)").bind(user.userId, now).run();
}

export async function GET() {
  const user = await currentUser();
  if (!user) return json({ error: "Iniciá sesión para cargar tus datos." }, 401);
  const db = env.DB;
  if (!db) return json({ error: "La base de datos no está disponible." }, 503);
  try {
    await seedForUser(db, user);
    const [profile, membership, exerciseRows, routineRows, routineExerciseRows, assignmentRows, sessions, weights] = await Promise.all([
      db.prepare("SELECT user_id AS userId, email, display_name AS displayName, role FROM profiles WHERE user_id = ?").bind(user.userId).first(),
      db.prepare("SELECT id, plan, expires_at AS expiresAt, status FROM memberships WHERE user_id = ?").bind(user.userId).first(),
      db.prepare("SELECT id, slug, name, muscle, equipment, instructions, media_path AS mediaPath FROM exercises ORDER BY name").all(),
      db.prepare("SELECT id, name, level, days_per_week AS daysPerWeek, created_at AS createdAt FROM routines WHERE owner_user_id = ? ORDER BY id DESC").bind(user.userId).all(),
      db.prepare("SELECT re.id, re.routine_id AS routineId, re.exercise_id AS exerciseId, re.day_name AS dayName, re.position, re.sets, re.reps_min AS repsMin, re.reps_max AS repsMax, re.target_weight AS targetWeight, re.rest_seconds AS restSeconds, e.slug, e.name, e.muscle, e.equipment, e.instructions, e.media_path AS mediaPath FROM routine_exercises re JOIN routines r ON r.id = re.routine_id JOIN exercises e ON e.id = re.exercise_id WHERE r.owner_user_id = ? ORDER BY re.routine_id DESC, re.position").bind(user.userId).all(),
      db.prepare("SELECT a.id, a.routine_id AS routineId, a.member_name AS memberName, a.assigned_at AS assignedAt, r.name AS routineName FROM assignments a JOIN routines r ON r.id = a.routine_id WHERE a.trainer_user_id = ? AND a.active = 1 ORDER BY a.id DESC").bind(user.userId).all(),
      db.prepare("SELECT id, routine_name AS routineName, started_at AS startedAt, completed_at AS completedAt, duration_seconds AS durationSeconds FROM workout_sessions WHERE user_id = ? ORDER BY started_at DESC LIMIT 12").bind(user.userId).all(),
      db.prepare("SELECT id, weight, recorded_at AS recordedAt FROM body_weights WHERE user_id = ? ORDER BY recorded_at DESC LIMIT 24").bind(user.userId).all(),
    ]);
    return json({ profile, membership, exercises: exerciseRows.results, routines: routineRows.results, routineExercises: routineExerciseRows.results, assignments: assignmentRows.results, sessions: sessions.results, weights: weights.results });
  } catch (error) {
    console.error("GymSpotter data load failed", error);
    return json({ error: "No pudimos cargar los datos. Intentá nuevamente." }, 500);
  }
}

export async function POST(request: Request) {
  const user = await currentUser();
  if (!user) return json({ error: "Iniciá sesión para guardar cambios." }, 401);
  if (!env.DB) return json({ error: "La base de datos no está disponible." }, 503);
  let body: ActionBody;
  try { body = await request.json() as ActionBody; } catch { return json({ error: "Solicitud inválida." }, 400); }
  const db = env.DB;
  const now = new Date().toISOString();
  try {
    if (body.action === "create_routine") {
      if (!validString(body.name) || !Array.isArray(body.exerciseIds) || body.exerciseIds.length < 1 || body.exerciseIds.length > 20) return json({ error: "Agregá un nombre y al menos un ejercicio." }, 400);
      const ids = [...new Set(body.exerciseIds.filter((id) => Number.isInteger(id) && id > 0))];
      if (!ids.length) return json({ error: "Los ejercicios no son válidos." }, 400);
      const routine = await db.prepare("INSERT INTO routines (owner_user_id, name, level, days_per_week, created_at) VALUES (?, ?, ?, ?, ?) RETURNING id").bind(user.userId, body.name!.trim(), validString(body.level, 30) ? body.level!.trim() : "Intermedio", Math.min(7, Math.max(1, Number(body.daysPerWeek) || 3)), now).first<{ id: number }>();
      if (!routine) throw new Error("Routine insert failed");
      await db.batch(ids.map((exerciseId, position) => db.prepare("INSERT INTO routine_exercises (routine_id, exercise_id, day_name, position, sets, reps_min, reps_max, target_weight, rest_seconds) VALUES (?, ?, 'Día 1', ?, 3, 8, 12, 0, 90)").bind(routine.id, exerciseId, position)));
      return json({ ok: true, id: routine.id }, 201);
    }
    if (body.action === "assign_routine") {
      if (!Number.isInteger(body.routineId) || !validString(body.memberName)) return json({ error: "Elegí alumno y rutina." }, 400);
      const owned = await db.prepare("SELECT id FROM routines WHERE id = ? AND owner_user_id = ?").bind(body.routineId, user.userId).first();
      if (!owned) return json({ error: "Rutina no encontrada." }, 404);
      const result = await db.prepare("INSERT INTO assignments (routine_id, trainer_user_id, member_name, assigned_at, active) VALUES (?, ?, ?, ?, 1) RETURNING id").bind(body.routineId, user.userId, body.memberName!.trim(), now).first();
      return json({ ok: true, assignment: result }, 201);
    }
    if (body.action === "start_workout") {
      const result = await db.prepare("INSERT INTO workout_sessions (user_id, routine_id, routine_name, started_at, duration_seconds) VALUES (?, ?, ?, ?, 0) RETURNING id").bind(user.userId, Number.isInteger(body.routineId) ? body.routineId : null, validString(body.routineName) ? body.routineName!.trim() : "Entrenamiento", now).first();
      return json({ ok: true, session: result }, 201);
    }
    if (body.action === "log_set") {
      if (![body.sessionId, body.exerciseId, body.setNumber, body.reps].every(Number.isInteger) || typeof body.weight !== "number") return json({ error: "Datos de serie inválidos." }, 400);
      const session = await db.prepare("SELECT id FROM workout_sessions WHERE id = ? AND user_id = ? AND completed_at IS NULL").bind(body.sessionId, user.userId).first();
      if (!session) return json({ error: "Entrenamiento no encontrado." }, 404);
      await db.prepare("INSERT INTO workout_sets (session_id, exercise_id, set_number, weight, reps, rir, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?)").bind(body.sessionId, body.exerciseId, body.setNumber, body.weight, body.reps, typeof body.rir === "number" ? body.rir : null, now).run();
      return json({ ok: true }, 201);
    }
    if (body.action === "complete_workout") {
      if (!Number.isInteger(body.sessionId)) return json({ error: "Sesión inválida." }, 400);
      await db.prepare("UPDATE workout_sessions SET completed_at = ?, duration_seconds = CAST((julianday(?) - julianday(started_at)) * 86400 AS INTEGER) WHERE id = ? AND user_id = ?").bind(now, now, body.sessionId, user.userId).run();
      return json({ ok: true });
    }
    if (body.action === "renew_membership") {
      const current = await db.prepare("SELECT expires_at AS expiresAt FROM memberships WHERE user_id = ?").bind(user.userId).first<{ expiresAt: string }>();
      const base = current && new Date(current.expiresAt).getTime() > Date.now() ? new Date(current.expiresAt) : new Date();
      base.setDate(base.getDate() + 30);
      await db.prepare("UPDATE memberships SET expires_at = ?, status = 'active' WHERE user_id = ?").bind(base.toISOString(), user.userId).run();
      return json({ ok: true, expiresAt: base.toISOString() });
    }
    if (body.action === "add_weight") {
      if (typeof body.value !== "number" || body.value < 25 || body.value > 350) return json({ error: "Ingresá un peso válido." }, 400);
      const result = await db.prepare("INSERT INTO body_weights (user_id, weight, recorded_at) VALUES (?, ?, ?) RETURNING id").bind(user.userId, body.value, now).first();
      return json({ ok: true, id: (result as { id?: number } | null)?.id }, 201);
    }
    return json({ error: "Acción desconocida." }, 400);
  } catch (error) {
    console.error("GymSpotter write failed", error);
    return json({ error: "No pudimos guardar el cambio. Intentá nuevamente." }, 500);
  }
}
