import { cn } from "@/lib/utils";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  return (
    <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 className="text-xl font-semibold tracking-tight text-white">
          {title}
        </h1>
        {description ? (
          <p className="mt-1 text-sm text-graphite-600">{description}</p>
        ) : null}
      </div>
      {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export function StatCard({
  label,
  value,
  hint,
  className,
}: {
  label: string;
  value: string | number;
  hint?: string;
  className?: string;
}) {
  return (
    <div className={cn("admin-card px-3.5 py-3", className)}>
      <div className="text-[11px] font-medium uppercase tracking-wide text-graphite-600">
        {label}
      </div>
      <div className="mt-1.5 text-2xl font-semibold tabular-nums text-white">
        {value}
      </div>
      {hint ? (
        <div className="mt-1 text-[12px] text-graphite-600">{hint}</div>
      ) : null}
    </div>
  );
}

export function EmptyState({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-dashed border-graphite-700 px-4 py-10 text-center text-sm text-graphite-600">
      {message}
    </div>
  );
}

export function LoadingBlock({ label = "Загрузка…" }: { label?: string }) {
  return (
    <div className="rounded-lg border border-graphite-700 bg-graphite-900 px-4 py-10 text-center text-sm text-graphite-600">
      {label}
    </div>
  );
}

export function ErrorBlock({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-red-900/50 bg-red-950/30 px-4 py-3 text-sm text-red-300">
      {message}
    </div>
  );
}

export function Avatar({
  src,
  name,
  size = 32,
}: {
  src?: string | null;
  name: string;
  size?: number;
}) {
  const initials = name.slice(0, 2).toUpperCase();
  if (src) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt={name}
        width={size}
        height={size}
        className="rounded object-cover"
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <div
      className="flex items-center justify-center rounded bg-graphite-700 text-[11px] font-semibold text-lime"
      style={{ width: size, height: size }}
    >
      {initials}
    </div>
  );
}
