ALTER TABLE `routine_exercises` ADD `target_rir` real DEFAULT 3 NOT NULL;
--> statement-breakpoint
PRAGMA optimize;
