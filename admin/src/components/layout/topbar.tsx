"use client";

import { useAuth } from "@/providers/auth-provider";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { globalSearch, type SearchHit } from "@/lib/api/final";
import { formatPhoneDisplay } from "@/lib/phone";
import { usePermissions } from "@/hooks/use-permissions";
import { Bell, LogOut, Menu, Search } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

export function Topbar({ onMenu }: { onMenu?: () => void }) {
  const { admin, signOut } = useAuth();
  const { can } = usePermissions();
  const router = useRouter();
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [hits, setHits] = useState<{
    users: SearchHit[];
    clans: SearchHit[];
    events: SearchHit[];
    listings: SearchHit[];
  } | null>(null);
  const [busy, setBusy] = useState(false);
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onDoc = (e: MouseEvent) => {
      if (!boxRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, []);

  useEffect(() => {
    if (!can("search") || q.trim().length < 2) {
      setHits(null);
      return;
    }
    const t = setTimeout(async () => {
      setBusy(true);
      try {
        const res = await globalSearch(q.trim());
        setHits(res);
        setOpen(true);
      } catch {
        setHits(null);
      } finally {
        setBusy(false);
      }
    }, 280);
    return () => clearTimeout(t);
  }, [q, can]);

  const go = (hit: SearchHit) => {
    setOpen(false);
    setQ("");
    if (hit.kind === "user") router.push(`/users/${hit.id}`);
    else if (hit.kind === "clan") router.push("/clans");
    else if (hit.kind === "event") router.push(`/events/${hit.id}`);
    else router.push("/market");
  };

  const sections: Array<{ key: keyof NonNullable<typeof hits>; title: string }> = [
    { key: "users", title: "Пользователи" },
    { key: "clans", title: "Кланы" },
    { key: "events", title: "Мероприятия" },
    { key: "listings", title: "Объявления" },
  ];

  return (
    <header className="flex h-12 shrink-0 items-center gap-3 border-b border-graphite-700 bg-graphite-900/90 px-3 backdrop-blur sm:px-4">
      <button
        type="button"
        className="rounded-md border border-graphite-700 p-1.5 text-graphite-600 hover:text-white lg:hidden"
        onClick={onMenu}
        aria-label="Меню"
      >
        <Menu size={16} />
      </button>

      <div className="relative max-w-md flex-1" ref={boxRef}>
        <Search
          size={14}
          className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-graphite-600"
        />
        <input
          className="admin-input h-8 pl-8"
          placeholder={can("search") ? "Поиск: пользователь, клан, игра…" : "Нет доступа к поиску"}
          value={q}
          disabled={!can("search")}
          onChange={(e) => setQ(e.target.value)}
          onFocus={() => hits && setOpen(true)}
        />
        {open && hits ? (
          <div className="absolute left-0 right-0 top-full z-50 mt-1 max-h-80 overflow-auto rounded-md border border-graphite-700 bg-graphite-900 shadow-panel">
            {busy ? (
              <div className="px-3 py-2 text-[12px] text-graphite-600">Поиск…</div>
            ) : null}
            {sections.map((sec) => {
              const list = hits[sec.key] ?? [];
              if (!list.length) return null;
              return (
                <div key={sec.key}>
                  <div className="border-b border-graphite-800 px-3 py-1.5 text-[11px] uppercase tracking-wide text-graphite-600">
                    {sec.title}
                  </div>
                  {list.map((hit) => (
                    <button
                      key={`${hit.kind}-${hit.id}`}
                      type="button"
                      className="flex w-full flex-col items-start px-3 py-2 text-left hover:bg-graphite-850"
                      onClick={() => go(hit)}
                    >
                      <span className="text-sm text-white">{hit.label}</span>
                      <span className="text-[12px] text-graphite-600">{hit.meta}</span>
                    </button>
                  ))}
                </div>
              );
            })}
            {!busy &&
            !hits.users.length &&
            !hits.clans.length &&
            !hits.events.length &&
            !hits.listings.length ? (
              <div className="px-3 py-3 text-[12px] text-graphite-600">
                Ничего не найдено
              </div>
            ) : null}
          </div>
        ) : null}
      </div>

      <Link
        href="/notifications"
        className="rounded-md border border-graphite-700 p-1.5 text-graphite-600 hover:bg-graphite-800 hover:text-white"
        aria-label="Уведомления"
      >
        <Bell size={15} />
      </Link>
      <div className="flex items-center gap-2 rounded-md border border-graphite-700 bg-graphite-850 px-2.5 py-1.5">
        <div className="min-w-0">
          <div className="truncate text-[12px] font-medium text-white">
            {admin?.phone ? formatPhoneDisplay(admin.phone) : "…"}
          </div>
          <div className="mt-0.5">
            <Badge tone="lime">{admin?.role ?? "—"}</Badge>
          </div>
        </div>
        <Button variant="ghost" className="h-7 px-2" onClick={() => signOut()}>
          <LogOut size={14} />
        </Button>
      </div>
    </header>
  );
}
