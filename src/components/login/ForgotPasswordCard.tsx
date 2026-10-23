"use client";

// P2-SPEC §6.5 — forgot-password variant of the login card.
import * as React from "react";
import { ArrowLeft, Loader2 } from "lucide-react";

import { mockDelay } from "@/lib/mock-delay";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useToast } from "@/components/ui/use-toast";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function ForgotPasswordCard({ onBack }: { onBack: () => void }) {
  const { toast } = useToast();
  const [email, setEmail] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!email.trim()) {
      setError("Enter your email.");
      return;
    }
    if (!EMAIL_RE.test(email.trim())) {
      setError("Enter a valid email address.");
      return;
    }
    setError(null);
    setPending(true);
    await mockDelay();
    setPending(false);
    toast({
      title: "Reset link sent (simulated)",
      description: `Check ${email.trim()} for instructions to reset your password.`,
      variant: "success",
    });
    // Auto-return to sign-in after 3s (P2-SPEC §6.5).
    setTimeout(onBack, 3000);
  };

  return (
    <div className="w-full max-w-[400px]">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-ink-primary">
          Reset your password
        </h1>
        <p className="mt-1 text-sm text-ink-secondary">
          We&apos;ll email you a secure link to choose a new password.
        </p>
      </div>

      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="reset-email">Email</Label>
          <Input
            id="reset-email"
            name="email"
            type="email"
            autoComplete="email"
            placeholder="you@township.example"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            aria-invalid={Boolean(error)}
            aria-describedby={error ? "reset-email-error" : undefined}
            className={
              error
                ? "border-[var(--error-soft)] ring-2 ring-[var(--error-ring)]"
                : undefined
            }
          />
          {error ? (
            <p id="reset-email-error" className="text-xs font-medium text-[var(--chip-red-text)]">
              {error}
            </p>
          ) : null}
        </div>

        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              Sending…
            </>
          ) : (
            "Send reset link"
          )}
        </Button>

        <Button
          type="button"
          variant="ghost"
          className="w-full"
          onClick={onBack}
        >
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          ← Back to sign-in
        </Button>
      </form>
    </div>
  );
}
