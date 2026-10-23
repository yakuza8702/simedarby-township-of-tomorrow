import { Skeleton } from "@/components/ui/skeleton";

export default function LoginLoading() {
  return (
    <div className="flex min-h-screen bg-[var(--surface)]">
      <div className="hidden w-[44%] max-w-[520px] flex-col justify-between bg-[var(--sidebar)] p-12 sm:flex">
        <Skeleton className="h-9 w-44 bg-[var(--active-tint)]" />
        <Skeleton className="h-24 w-full max-w-[380px] bg-[var(--active-tint)]" />
        <div className="flex flex-col gap-3">
          <Skeleton className="h-14 w-full bg-[var(--active-tint)]" />
          <Skeleton className="h-14 w-full bg-[var(--active-tint)]" />
          <Skeleton className="h-14 w-full bg-[var(--active-tint)]" />
        </div>
      </div>
      <div className="flex flex-1 items-center justify-center px-6">
        <div className="w-full max-w-[400px] space-y-4">
          <Skeleton className="h-8 w-24" />
          <Skeleton className="h-4 w-72" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-4 w-40 self-center" />
        </div>
      </div>
    </div>
  );
}
