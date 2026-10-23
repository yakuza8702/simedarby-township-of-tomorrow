import { Skeleton } from "@/components/ui/skeleton";

export default function ReportsQueueLoading() {
  return (
    <div className="space-y-5 pb-10">
      <div className="flex items-end justify-between">
        <div className="space-y-2">
          <Skeleton className="h-7 w-44" />
          <Skeleton className="h-4 w-64" />
        </div>
        <Skeleton className="h-9 w-36 rounded-[8px]" />
      </div>

      <div className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-[12px]" />
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Skeleton className="h-9 w-72" />
        <Skeleton className="h-9 w-28 rounded-full" />
        <Skeleton className="h-9 w-24 rounded-full" />
        <Skeleton className="h-9 w-24 rounded-full" />
        <Skeleton className="h-9 w-24 rounded-full" />
      </div>

      <Skeleton className="h-10 w-80 rounded-[8px]" />

      <div className="overflow-hidden rounded-[12px] border border-[var(--border-plain)]">
        {Array.from({ length: 6 }).map((_, i) => (
          <div
            key={i}
            className="flex items-center gap-4 border-b border-[var(--border-plain)] px-4 py-4 last:border-b-0"
          >
            <Skeleton className="h-2.5 w-2.5 rounded-full" />
            <Skeleton className="h-4 flex-1" />
            <Skeleton className="hidden h-5 w-20 rounded-full sm:block" />
            <Skeleton className="hidden h-8 w-28 sm:block" />
          </div>
        ))}
      </div>
    </div>
  );
}
