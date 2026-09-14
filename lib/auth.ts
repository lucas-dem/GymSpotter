import type { ChatGPTUser } from "@/app/chatgpt-auth";

export type AppUser = ChatGPTUser & { role: "member" | "trainer" | "admin" };

export async function hashPassword(password: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(password));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function sessionCookie(token: string, maxAge = 60 * 60 * 24 * 30) {
  return `gym_session=${encodeURIComponent(token)}; Path=/; Max-Age=${maxAge}; HttpOnly; SameSite=Lax${process.env.NODE_ENV === "production" ? "; Secure" : ""}`;
}

export function readSessionToken(request: Request) {
  const match = (request.headers.get("cookie") ?? "").match(/(?:^|;\s*)gym_session=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

export async function appUserFromRequest(request: Request, db: D1Database): Promise<AppUser | null> {
  const token = readSessionToken(request);
  if (!token) return null;
  const row = await db.prepare("SELECT u.id, u.email, u.display_name AS displayName, u.role, s.expires_at AS expiresAt FROM app_sessions s JOIN app_users u ON u.id = s.user_id WHERE s.token = ? AND s.expires_at > ?").bind(token, new Date().toISOString()).first<{ id: number; email: string; displayName: string; role: string; expiresAt: string }>();
  if (!row) return null;
  return { userId: `app:${row.id}`, email: row.email, displayName: row.displayName, fullName: row.displayName, role: row.role === "admin" || row.role === "trainer" ? row.role : "member" };
}
