"use client";

// P2-SPEC §6 — login flow: email/password against the single hardcoded admin,
// simulated Council SSO (10% failure), wrong-password + validation states.
import { useRouter } from "next/navigation";
import * as React from "react";
import { AlertTriangle, Eye, EyeOff, Landmark, Loader2 } from "lucide-react";

import { mockDelay } from "@/lib/mock-delay";
import { DEMO_CREDENTIALS } from "@/lib/data/roles";
import { writeSession } from "@/lib/session";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

interface LoginCardProps {
  ssoError: boolean;
  onSsoErrorChange: (v: boolean) => void;
  onForgotPassword: () => void;
  forceSsoFailure: boolean;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function LoginCard({
  ssoError,
  onSsoErrorChange,
  onForgotPassword,
  forceSsoFailure,
}: LoginCardProps) {
  const router = useRouter();
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [showPassword, setShowPassword] = React.useState(false);
  const [errors, setErrors] = React.useState<{
    email?: string;
    password?: string;
    auth?: string;
  }>({});
  const [pending, setPending] = React.useState<"password" | "sso" | null>(
    null
  );

  const finishLogin = (fullName: string) => {
    writeSession(email || DEMO_CREDENTIALS.email, fullName);
    router.push("/reports-queue");
    router.refresh();
  };

  const validate = (): boolean => {
    const next: typeof errors = {};
    if (!email.trim()) next.email = "Enter your email.";
    else if (!EMAIL_RE.test(email.trim()))
      next.email = "Enter a valid email address.";
    if (!password) next.password = "Enter your password.";
    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    onSsoErrorChange(false);
    if (!validate()) return;
    setPending("password");
    await mockDelay();
    if (
      email.trim().toLowerCase() === DEMO_CREDENTIALS.email &&
      password === DEMO_CREDENTIALS.password
    ) {
      finishLogin("A. Rahman");
    } else {
      setErrors({ auth: "Incorrect email or password." });
      setPending(null);
    }
  };

  const handleSso = async () => {
    setErrors({});
    setPending("sso");
    await mockDelay();
    const failed = forceSsoFailure || Math.random() < 0.1; // 10% simulated refusal
    if (failed) {
      onSsoErrorChange(true);
      setPending(null);
      return;
    }
    setEmail(DEMO_CREDENTIALS.email);
    finishLogin("A. Rahman");
  };

  return (
    <div className="w-full max-w-[400px]">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-ink-primary">Sign in</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Council operations console — waste, reports, and collection in one
          place
        </p>
      </div>

      {ssoError ? (
        <div
          role="alert"
          className="mb-4 rounded-[12px] border border-[var(--error-soft)] bg-[var(--chip-red-bg)] p-3 text-sm text-[var(--chip-red-text)]"
        >
          <div className="flex gap-2">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            <div>
              <p>SSO provider refused the handshake. Retry or use email sign-in.</p>
              <Button
                variant="ghost"
                size="sm"
                className="mt-1 h-7 px-2 text-[var(--chip-red-text)] hover:bg-[var(--chip-red-bg)]"
                onClick={handleSso}
                disabled={pending !== null}
              >
                Retry SSO
              </Button>
            </div>
          </div>
        </div>
      ) : null}

      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="login-email">Email</Label>
          <Input
            id="login-email"
            name="email"
            type="email"
            autoComplete="email"
            placeholder="you@township.example"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            aria-invalid={Boolean(errors.email) || Boolean(errors.auth)}
            aria-describedby={
              errors.email || errors.auth ? "login-email-error" : undefined
            }
            className={
              errors.email || errors.auth
                ? "border-[var(--error-soft)] ring-2 ring-[var(--error-ring)]"
                : undefined
            }
          />
          {errors.email ? (
            <p id="login-email-error" className="text-xs font-medium text-[var(--chip-red-text)]">
              {errors.email}
            </p>
          ) : null}
        </div>

        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label htmlFor="login-password">Password</Label>
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              className="text-xs font-medium text-[var(--green-text)] hover:underline"
              aria-label={showPassword ? "Hide password" : "Show password"}
            >
              {showPassword ? (
                <EyeOff className="h-3.5 w-3.5" aria-hidden="true" />
              ) : (
                <Eye className="h-3.5 w-3.5" aria-hidden="true" />
              )}
            </button>
          </div>
          <Input
            id="login-password"
            name="password"
            type={showPassword ? "text" : "password"}
            autoComplete="current-password"
            placeholder="••••••••"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            aria-invalid={Boolean(errors.password) || Boolean(errors.auth)}
            aria-describedby={
              errors.password || errors.auth ? "login-password-error" : undefined
            }
            className={
              errors.password || errors.auth
                ? "border-[var(--error-soft)] ring-2 ring-[var(--error-ring)]"
                : undefined
            }
          />
          {errors.password || errors.auth ? (
            <p
              id="login-password-error"
              className="text-xs font-medium text-[var(--chip-red-text)]"
            >
              {errors.password ?? errors.auth}
            </p>
          ) : null}
        </div>

        <Button type="submit" className="w-full" disabled={pending !== null}>
          {pending === "password" ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              Signing in…
            </>
          ) : (
            "Sign in"
          )}
        </Button>

        <div className="text-center">
          <button
            type="button"
            onClick={onForgotPassword}
            className="text-sm font-medium text-[var(--green-text)] hover:underline"
          >
            Forgot password?
          </button>
        </div>
      </form>

      <div className="my-5 flex items-center gap-3" aria-hidden="true">
        <span className="h-px flex-1 bg-[var(--border-plain)]" />
        <span className="text-xs text-ink-secondary">or</span>
        <span className="h-px flex-1 bg-[var(--border-plain)]" />
      </div>

      <Button
        variant="outline"
        className="w-full"
        onClick={handleSso}
        disabled={pending !== null}
      >
        {pending === "sso" ? (
          <>
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
            Contacting Council SSO…
          </>
        ) : (
          <>
            <Landmark className="h-4 w-4" aria-hidden="true" />
            Sign in with Council SSO
          </>
        )}
      </Button>

      <p className="mt-6 rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] p-3 text-xs text-ink-secondary">
        <span className="font-semibold text-ink-primary">Demo credentials</span>{" "}
        — {DEMO_CREDENTIALS.email} / {DEMO_CREDENTIALS.password}
      </p>
    </div>
  );
}
