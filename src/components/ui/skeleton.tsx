import { cn } from "./utils";

function Skeleton({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn("animate-pulse rounded-[8px] bg-[var(--skeleton)]", className)}
      {...props}
    />
  );
}

export { Skeleton };
