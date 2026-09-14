import { env } from "cloudflare:workers";
import { getChatGPTUser } from "@/app/chatgpt-auth";
import { appUserFromRequest, hashPassword, sessionCookie } from "@/lib/auth";

function json(data: unknown, status = 200, headers?: HeadersInit) { return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", ...headers } }); }
function validEmail(value: unknown) { return typeof value === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()); }
function validPassword(value: unknown) { return typeof value === "string" && value.length >= 8 && value.length <= 128; }

async function ensureLocalAccounts(db: D1Database) {
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS app_users (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, email TEXT NOT NULL, password_hash TEXT NOT NULL, display_name TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'member', created_at TEXT NOT NULL)"),
    db.prepare("CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_email ON app_users(email)"),
    db.prepare("CREATE TABLE IF NOT EXISTS app_sessions (token TEXT PRIMARY KEY NOT NULL, user_id INTEGER NOT NULL, expires_at TEXT NOT NULL, FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE CASCADE)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_app_sessions_user ON app_sessions(user_id)"),
  ]);
  if (process.env.NODE_ENV !== "development") return;
  const accounts = [
    ["admin@gymspotter.local", "Admin123!", "Admin GymSpotter", "admin"],
    ["socio@gymspotter.local", "Socio123!", "Socio GymSpotter", "member"],
    ["entrenador@gymspotter.local", "Entrenador123!", "Entrenador GymSpotter", "trainer"],
  ] as const;
  const now = new Date().toISOString();
  const rows = await Promise.all(accounts.map(async ([email, password, displayName, role]) => db.prepare("INSERT OR IGNORE INTO app_users (email, password_hash, display_name, role, created_at) VALUES (?, ?, ?, ?, ?)").bind(email, await hashPassword(password), displayName, role, now)));
  await db.batch(rows);
}

export async function GET(request: Request) {
  const db = env.DB;
  if (!db) return json({ user: null });
  await ensureLocalAccounts(db);
  const appUser = await appUserFromRequest(request, db);
  if (appUser) return json({ user: appUser });
  const chatUser = await getChatGPTUser();
  return json({ user: chatUser ? { ...chatUser, role: "member" } : null });
}

export async function POST(request: Request) {
  const db = env.DB;
  if (!db) return json({ error: "La base de datos no está disponible." }, 503);
  await ensureLocalAccounts(db);
  let body: { action?: string; email?: string; password?: string; displayName?: string; role?: string };
  try { body = await request.json(); } catch { return json({ error: "Solicitud inválida." }, 400); }
  const email = body.email?.trim().toLowerCase();
  if (body.action === "login") {
    if (!validEmail(email) || !validPassword(body.password)) return json({ error: "Ingresá un email y una contraseña válida (mínimo 8 caracteres)." }, 400);
    const user = await db.prepare("SELECT id, email, display_name AS displayName, role, password_hash AS passwordHash FROM app_users WHERE email = ?").bind(email).first<{ id: number; email: string; displayName: string; role: string; passwordHash: string }>();
    if (!user || user.passwordHash !== await hashPassword(body.password!)) return json({ error: "Email o contraseña incorrectos." }, 401);
    const token = crypto.randomUUID();
    await db.prepare("INSERT INTO app_sessions (token, user_id, expires_at) VALUES (?, ?, ?)").bind(token, user.id, new Date(Date.now() + 30 * 86400000).toISOString()).run();
    return json({ user: { userId: `app:${user.id}`, email: user.email, displayName: user.displayName, fullName: user.displayName, role: user.role } }, 200, { "set-cookie": sessionCookie(token) });
  }
  if (body.action === "logout") return json({ ok: true }, 200, { "set-cookie": sessionCookie("", 0) });
  if (body.action === "register") {
    const creator = await appUserFromRequest(request, db);
    if (creator?.role !== "admin") return json({ error: "Solo un administrador puede registrar usuarios." }, 403);
    if (!validEmail(email) || !validPassword(body.password) || typeof body.displayName !== "string" || body.displayName.trim().length < 2) return json({ error: "Completá nombre, email y contraseña (mínimo 8 caracteres)." }, 400);
    const role = body.role === "admin" || body.role === "trainer" ? body.role : "member";
    try {
      const row = await db.prepare("INSERT INTO app_users (email, password_hash, display_name, role, created_at) VALUES (?, ?, ?, ?, ?) RETURNING id").bind(email, await hashPassword(body.password!), body.displayName.trim(), role, new Date().toISOString()).first<{ id: number }>();
      return json({ ok: true, id: row?.id }, 201);
    } catch { return json({ error: "Ese email ya está registrado." }, 409); }
  }
  return json({ error: "Acción desconocida." }, 400);
}
