import { cn } from "@/lib/utils";

export function Badge({
  children,
  tone = "neutral",
  className,
}: {
  children: React.ReactNode;
  tone?: "neutral" | "lime" | "red" | "amber" | "blue";
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-medium uppercase tracking-wide",
        tone === "neutral" && "bg-graphite-700 text-graphite-600",
        tone === "lime" && "bg-lime-soft text-lime",
        tone === "red" && "bg-red-950/50 text-red-300",
        tone === "amber" && "bg-amber-950/40 text-amber-300",
        tone === "blue" && "bg-sky-950/40 text-sky-300",
        className,
      )}
    >
      {children}
    </span>
  );
}
