CREATE TABLE `assignments` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`routine_id` integer NOT NULL,
	`trainer_user_id` text NOT NULL,
	`member_name` text NOT NULL,
	`assigned_at` text NOT NULL,
	`active` integer DEFAULT true NOT NULL,
	FOREIGN KEY (`routine_id`) REFERENCES `routines`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_assignments_trainer_active` ON `assignments` (`trainer_user_id`,`active`);--> statement-breakpoint
CREATE TABLE `body_weights` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` text NOT NULL,
	`weight` real NOT NULL,
	`recorded_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_body_weights_user_recorded` ON `body_weights` (`user_id`,`recorded_at`);--> statement-breakpoint
CREATE TABLE `exercises` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`slug` text NOT NULL,
	`name` text NOT NULL,
	`muscle` text NOT NULL,
	`equipment` text NOT NULL,
	`instructions` text NOT NULL,
	`media_path` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_exercises_slug` ON `exercises` (`slug`);--> statement-breakpoint
CREATE INDEX `idx_exercises_muscle` ON `exercises` (`muscle`);--> statement-breakpoint
CREATE TABLE `memberships` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` text NOT NULL,
	`plan` text DEFAULT 'Plan mensual' NOT NULL,
	`expires_at` text NOT NULL,
	`status` text DEFAULT 'active' NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_memberships_user_id` ON `memberships` (`user_id`);--> statement-breakpoint
CREATE TABLE `profiles` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` text NOT NULL,
	`email` text NOT NULL,
	`display_name` text NOT NULL,
	`role` text DEFAULT 'member' NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_profiles_user_id` ON `profiles` (`user_id`);--> statement-breakpoint
CREATE TABLE `routine_exercises` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`routine_id` integer NOT NULL,
	`exercise_id` integer NOT NULL,
	`day_name` text DEFAULT 'Día 1' NOT NULL,
	`position` integer NOT NULL,
	`sets` integer DEFAULT 3 NOT NULL,
	`reps_min` integer DEFAULT 8 NOT NULL,
	`reps_max` integer DEFAULT 12 NOT NULL,
	`target_weight` real DEFAULT 0 NOT NULL,
	`rest_seconds` integer DEFAULT 90 NOT NULL,
	FOREIGN KEY (`routine_id`) REFERENCES `routines`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`exercise_id`) REFERENCES `exercises`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_routine_exercises_routine_position` ON `routine_exercises` (`routine_id`,`position`);--> statement-breakpoint
CREATE TABLE `routines` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`owner_user_id` text NOT NULL,
	`name` text NOT NULL,
	`level` text DEFAULT 'Intermedio' NOT NULL,
	`days_per_week` integer DEFAULT 3 NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_routines_owner` ON `routines` (`owner_user_id`);--> statement-breakpoint
CREATE TABLE `workout_sessions` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` text NOT NULL,
	`routine_id` integer,
	`routine_name` text NOT NULL,
	`started_at` text NOT NULL,
	`completed_at` text,
	`duration_seconds` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`routine_id`) REFERENCES `routines`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_workout_sessions_user_started` ON `workout_sessions` (`user_id`,`started_at`);--> statement-breakpoint
CREATE TABLE `workout_sets` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`session_id` integer NOT NULL,
	`exercise_id` integer NOT NULL,
	`set_number` integer NOT NULL,
	`weight` real NOT NULL,
	`reps` integer NOT NULL,
	`rir` real,
	`completed_at` text NOT NULL,
	FOREIGN KEY (`session_id`) REFERENCES `workout_sessions`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`exercise_id`) REFERENCES `exercises`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_workout_sets_session_exercise` ON `workout_sets` (`session_id`,`exercise_id`);
--> statement-breakpoint
PRAGMA optimize;
