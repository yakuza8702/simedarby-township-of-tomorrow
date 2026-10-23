import { Skeleton } from "@/components/ui/skeleton";

export default function BroadcastLoading() {
  return (
    <div className="space-y-5 pb-10">
      <div className="space-y-2">
        <Skeleton className="h-7 w-36" />
        <Skeleton className="h-4 w-96 max-w-full" />
      </div>
      <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
        <Skeleton className="h-[560px] rounded-[12px]" />
        <Skeleton className="h-[320px] rounded-[12px]" />
      </div>
    </div>
  );
}
