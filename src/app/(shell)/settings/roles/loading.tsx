import { Skeleton } from "@/components/ui/skeleton";

export default function RolesSettingsLoading() {
  return (
    <div className="space-y-5 pb-10">
      <div className="space-y-2">
        <Skeleton className="h-7 w-32" />
        <Skeleton className="h-4 w-80" />
      </div>
      <Skeleton className="h-10 w-[420px] max-w-full rounded-[8px]" />
      <div className="overflow-hidden rounded-[12px] border border-[var(--border-plain)]">
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className="flex items-center gap-4 border-b border-[var(--border-plain)] px-4 py-4 last:border-b-0"
          >
            <Skeleton className="h-8 w-8 rounded-full" />
            <Skeleton className="h-4 flex-1" />
            <Skeleton className="h-4 w-20" />
            <Skeleton className="h-4 w-24" />
            <Skeleton className="h-8 w-8 rounded-[8px]" />
          </div>
        ))}
      </div>
    </div>
  );
}
