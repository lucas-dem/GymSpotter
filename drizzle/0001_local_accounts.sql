CREATE TABLE `app_users` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `email` text NOT NULL,
  `password_hash` text NOT NULL,
  `display_name` text NOT NULL,
  `role` text DEFAULT 'member' NOT NULL,
  `created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_app_users_email` ON `app_users` (`email`);
--> statement-breakpoint
CREATE TABLE `app_sessions` (
  `token` text PRIMARY KEY NOT NULL,
  `user_id` integer NOT NULL,
  `expires_at` text NOT NULL,
  FOREIGN KEY (`user_id`) REFERENCES `app_users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_app_sessions_user` ON `app_sessions` (`user_id`);
