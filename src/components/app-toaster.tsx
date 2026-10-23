"use client";

// Shared toaster wired for the whole app (P2-SPEC §8 a11y: role="status"
// aria-live="polite" viewport — see components/ui/toaster.tsx).
import * as React from "react";

import { Toaster } from "./ui/toaster";

export function AppToaster() {
  return <Toaster />;
}
