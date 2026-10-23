import { NextResponse, type NextRequest } from "next/server";

import { SESSION_COOKIE, isExpired, parseSession } from "./lib/session";

/**
 * P2-SPEC §7 — auth gate. Checks the demo session cookie on every request:
 * - unauthenticated → /login (expired cookies get ?reason=expired)
 * - authenticated on /login → /reports-queue
 * - "/" → "/reports-queue", "/settings" → "/settings/roles"
 */
export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const raw = request.cookies.get(SESSION_COOKIE)?.value;
  const parsed = parseSession(raw);
  const session = parsed && !isExpired(parsed) ? parsed : null;

  if (pathname === "/login") {
    if (session) {
      return NextResponse.redirect(new URL("/reports-queue", request.url));
    }
    return NextResponse.next();
  }

  if (!session) {
    const url = new URL("/login", request.url);
    if (raw) url.searchParams.set("reason", "expired");
    return NextResponse.redirect(url);
  }

  if (pathname === "/") {
    return NextResponse.redirect(new URL("/reports-queue", request.url));
  }
  if (pathname === "/settings") {
    return NextResponse.redirect(new URL("/settings/roles", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|fonts|.*\\..*).*)"],
};
