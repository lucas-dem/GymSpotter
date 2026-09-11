import { index, integer, real, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

export const profiles = sqliteTable("profiles", {
  id: integer("id").primaryKey({ autoIncrement: true }), userId: text("user_id").notNull(), email: text("email").notNull(),
  displayName: text("display_name").notNull(), role: text("role").notNull().default("member"), createdAt: text("created_at").notNull(),
}, (table) => [uniqueIndex("idx_profiles_user_id").on(table.userId)]);

export const exercises = sqliteTable("exercises", {
  id: integer("id").primaryKey({ autoIncrement: true }), slug: text("slug").notNull(), name: text("name").notNull(), muscle: text("muscle").notNull(),
  equipment: text("equipment").notNull(), instructions: text("instructions").notNull(), mediaPath: text("media_path"),
}, (table) => [uniqueIndex("idx_exercises_slug").on(table.slug), index("idx_exercises_muscle").on(table.muscle)]);

export const routines = sqliteTable("routines", {
  id: integer("id").primaryKey({ autoIncrement: true }), ownerUserId: text("owner_user_id").notNull(), name: text("name").notNull(),
  level: text("level").notNull().default("Intermedio"), daysPerWeek: integer("days_per_week").notNull().default(3), createdAt: text("created_at").notNull(),
}, (table) => [index("idx_routines_owner").on(table.ownerUserId)]);

export const routineExercises = sqliteTable("routine_exercises", {
  id: integer("id").primaryKey({ autoIncrement: true }), routineId: integer("routine_id").notNull().references(() => routines.id, { onDelete: "cascade" }),
  exerciseId: integer("exercise_id").notNull().references(() => exercises.id), dayName: text("day_name").notNull().default("Día 1"),
  position: integer("position").notNull(), sets: integer("sets").notNull().default(3), repsMin: integer("reps_min").notNull().default(8),
  repsMax: integer("reps_max").notNull().default(12), targetWeight: real("target_weight").notNull().default(0), restSeconds: integer("rest_seconds").notNull().default(90),
}, (table) => [index("idx_routine_exercises_routine_position").on(table.routineId, table.position)]);

export const assignments = sqliteTable("assignments", {
  id: integer("id").primaryKey({ autoIncrement: true }), routineId: integer("routine_id").notNull().references(() => routines.id, { onDelete: "cascade" }),
  trainerUserId: text("trainer_user_id").notNull(), memberName: text("member_name").notNull(), assignedAt: text("assigned_at").notNull(), active: integer("active", { mode: "boolean" }).notNull().default(true),
}, (table) => [index("idx_assignments_trainer_active").on(table.trainerUserId, table.active)]);

export const memberships = sqliteTable("memberships", {
  id: integer("id").primaryKey({ autoIncrement: true }), userId: text("user_id").notNull(), plan: text("plan").notNull().default("Plan mensual"),
  expiresAt: text("expires_at").notNull(), status: text("status").notNull().default("active"),
}, (table) => [uniqueIndex("idx_memberships_user_id").on(table.userId)]);

export const workoutSessions = sqliteTable("workout_sessions", {
  id: integer("id").primaryKey({ autoIncrement: true }), userId: text("user_id").notNull(), routineId: integer("routine_id").references(() => routines.id),
  routineName: text("routine_name").notNull(), startedAt: text("started_at").notNull(), completedAt: text("completed_at"), durationSeconds: integer("duration_seconds").notNull().default(0),
}, (table) => [index("idx_workout_sessions_user_started").on(table.userId, table.startedAt)]);

export const workoutSets = sqliteTable("workout_sets", {
  id: integer("id").primaryKey({ autoIncrement: true }), sessionId: integer("session_id").notNull().references(() => workoutSessions.id, { onDelete: "cascade" }),
  exerciseId: integer("exercise_id").notNull().references(() => exercises.id), setNumber: integer("set_number").notNull(), weight: real("weight").notNull(),
  reps: integer("reps").notNull(), rir: real("rir"), completedAt: text("completed_at").notNull(),
}, (table) => [index("idx_workout_sets_session_exercise").on(table.sessionId, table.exerciseId)]);

export const bodyWeights = sqliteTable("body_weights", {
  id: integer("id").primaryKey({ autoIncrement: true }), userId: text("user_id").notNull(), weight: real("weight").notNull(), recordedAt: text("recorded_at").notNull(),
}, (table) => [index("idx_body_weights_user_recorded").on(table.userId, table.recordedAt)]);
