"use client";

import { useSearchParams } from "next/navigation";
import * as React from "react";

import { AppToaster } from "@/components/app-toaster";
import { ForgotPasswordCard } from "@/components/login/ForgotPasswordCard";
import { HeroPane } from "@/components/login/HeroPane";
import { LoginCard } from "@/components/login/LoginCard";

function LoginFlow() {
  const searchParams = useSearchParams();
  const expired = searchParams.get("reason") === "expired";
  // Deterministic demo hook: /login?demo=sso-error forces the SSO failure path.
  const forceSsoFailure = searchParams.get("demo") === "sso-error";

  const [mode, setMode] = React.useState<"signin" | "forgot">("signin");
  const [ssoError, setSsoError] = React.useState(false);

  return (
    <div className="flex min-h-screen bg-[var(--background)]">
      <HeroPane />

      <main className="flex flex-1 items-center justify-center px-4 py-10 sm:px-8">
        <div className="w-full max-w-[400px]">
          {expired ? (
            <div
              role="alert"
              className="mb-4 rounded-[12px] border border-[var(--chip-amber-border)] bg-[var(--chip-amber-bg)] p-3 text-sm font-medium text-[var(--chip-amber-text)]"
            >
              Your session expired for safety — please sign in again.
            </div>
          ) : null}

          {mode === "signin" ? (
            <LoginCard
              ssoError={ssoError}
              onSsoErrorChange={setSsoError}
              onForgotPassword={() => {
                setSsoError(false);
                setMode("forgot");
              }}
              forceSsoFailure={forceSsoFailure}
            />
          ) : (
            <ForgotPasswordCard
              onBack={() => {
                setMode("signin");
              }}
            />
          )}
        </div>
      </main>

      <AppToaster />
    </div>
  );
}

export default function LoginPage() {
  return (
    <React.Suspense fallback={null}>
      <LoginFlow />
    </React.Suspense>
  );
}
