"use client";

// Shell chrome: 240px green-tint sidebar (icon rail at lg, off-canvas below),
// 56px topbar, 24px content padding (P2-SPEC §1 / §8).
import { useRouter } from "next/navigation";
import * as React from "react";

import { readSession } from "@/lib/session";
import { StoreProvider } from "@/lib/store";
import { AppToaster } from "@/components/app-toaster";
import { Button } from "@/components/ui/button";
import { Sidebar } from "@/components/shell/Sidebar";
import { Topbar } from "@/components/shell/Topbar";

function SessionGuard({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [expired, setExpired] = React.useState(false);

  React.useEffect(() => {
    if (!readSession()) {
      setExpired(true);
      const t = setTimeout(() => router.replace("/login?reason=expired"), 2200);
      return () => clearTimeout(t);
    }
  }, [router]);

  if (expired) {
    return (
      <div
        role="alert"
        className="flex min-h-screen flex-col items-center justify-center gap-4 bg-[var(--background)] p-6"
      >
        <div className="w-full max-w-[560px] rounded-[12px] border border-[var(--chip-amber-border)] bg-[var(--chip-amber-bg)] p-4 text-sm font-medium text-[var(--chip-amber-text)]">
          Your session expired for safety — please sign in again.
        </div>
        <Button onClick={() => router.replace("/login?reason=expired")}>
          Back to sign in
        </Button>
      </div>
    );
  }

  return <>{children}</>;
}

export default function ShellLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <StoreProvider>
      <SessionGuard>
        <div className="flex min-h-screen bg-[var(--background)]">
          {/* Fixed sidebar: full at xl, icon rail at lg, hidden below lg. */}
          <aside className="fixed inset-y-0 left-0 z-30 hidden w-16 border-r border-[var(--border-green)] lg:block xl:w-[240px]">
            <Sidebar />
          </aside>

          <div className="flex min-w-0 flex-1 flex-col lg:pl-16 xl:pl-[240px]">
            <Topbar />
            <main className="flex-1 px-4 py-6 lg:px-6">
              <div className="mx-auto w-full max-w-[1200px]">{children}</div>
            </main>
          </div>
        </div>
        <AppToaster />
      </SessionGuard>
    </StoreProvider>
  );
}
