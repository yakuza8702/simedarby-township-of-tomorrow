// Isomorphic session helpers (no Node or DOM APIs at module scope).
// Demo auth only — the cookie is readable by JS on purpose (INFERRED #8).

export const SESSION_COOKIE = "totm_session";
export const SESSION_TTL_MS = 8 * 60 * 60 * 1000; // 8h

export interface SessionPayload {
  email: string;
  fullName: string;
  expiresAt: number; // epoch ms
}

/** Cookie value format: `email|fullName|expiresAt` (URL-safe by construction). */
export function serializeSession(email: string, fullName: string, now = Date.now()): string {
  const expiresAt = now + SESSION_TTL_MS;
  return `${email}|${encodeURIComponent(fullName)}|${expiresAt}`;
}

export function parseSession(value: string | undefined | null): SessionPayload | null {
  if (!value) return null;
  const parts = value.split("|");
  if (parts.length !== 3) return null;
  const [email, encodedName, rawExpiresAt] = parts;
  const expiresAt = Number(rawExpiresAt);
  if (!email || !email.includes("@") || !Number.isFinite(expiresAt)) return null;
  return {
    email,
    fullName: decodeURIComponent(encodedName || "Administrator"),
    expiresAt,
  };
}

export function isExpired(session: SessionPayload, now = Date.now()): boolean {
  return now >= session.expiresAt;
}

/* ----------------------------- browser-side ------------------------------ */

const hasDocument = () => typeof document !== "undefined";

export function readSession(): SessionPayload | null {
  if (!hasDocument()) return null;
  const match = document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${SESSION_COOKIE}=`));
  const value = match ? match.slice(SESSION_COOKIE.length + 1) : null;
  const session = parseSession(value);
  if (!session) return null;
  if (isExpired(session)) {
    clearSession();
    return null;
  }
  return session;
}

export function writeSession(email: string, fullName: string): void {
  if (!hasDocument()) return;
  const maxAge = Math.floor(SESSION_TTL_MS / 1000);
  document.cookie = `${SESSION_COOKIE}=${serializeSession(email, fullName)}; path=/; max-age=${maxAge}; SameSite=Lax`;
}

export function clearSession(): void {
  if (!hasDocument()) return;
  document.cookie = `${SESSION_COOKIE}=; path=/; max-age=0; SameSite=Lax`;
}
