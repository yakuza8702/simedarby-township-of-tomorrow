"use client";

// P2-SPEC §1 — Broadcast: composer + recent broadcasts list.
import * as React from "react";

import { BroadcastForm } from "@/components/broadcast/BroadcastForm";
import { Skeleton } from "@/components/ui/skeleton";

export default function BroadcastPage() {
  const [ready, setReady] = React.useState(false);
  React.useEffect(() => {
    const t = setTimeout(() => setReady(true), 150);
    return () => clearTimeout(t);
  }, []);

  return (
    <div className="space-y-5 pb-10">
      <div>
        <h2 className="text-xl font-bold text-ink-primary">Broadcast</h2>
        <p className="text-sm text-ink-secondary">
          Announce collection changes, hazards and programmes to residents and
          partner agencies
        </p>
      </div>

      {ready ? (
        <BroadcastForm />
      ) : (
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
          <Skeleton className="h-[560px] rounded-[12px]" />
          <Skeleton className="h-[320px] rounded-[12px]" />
        </div>
      )}
    </div>
  );
}
