"use client";

import { NAV_ITEMS } from "@/lib/constants";
import { usePermissions } from "@/hooks/use-permissions";
import { cn } from "@/lib/utils";
import {
  Award,
  BadgeCheck,
  Bell,
  BookOpen,
  CalendarDays,
  LayoutDashboard,
  MessagesSquare,
  QrCode,
  ScrollText,
  Settings,
  Shield,
  ShieldCheck,
  Store,
  Trophy,
  Users,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

const ICONS = {
  LayoutDashboard,
  Users,
  BadgeCheck,
  CalendarDays,
  QrCode,
  Shield,
  Trophy,
  Store,
  ShieldCheck,
  MessagesSquare,
  Award,
  BookOpen,
  Wallet,
  Bell,
  Settings,
  ScrollText,
} as const;

export function Sidebar({
  open,
  onClose,
}: {
  open?: boolean;
  onClose?: () => void;
}) {
  const pathname = usePathname();
  const { can, isLoading } = usePermissions();

  return (
    <>
      {open ? (
        <button
          type="button"
          className="fixed inset-0 z-40 bg-black/50 lg:hidden"
          aria-label="Закрыть меню"
          onClick={onClose}
        />
      ) : null}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-[220px] shrink-0 flex-col border-r border-graphite-700 bg-graphite-900 transition-transform lg:static lg:translate-x-0",
          open ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="border-b border-graphite-700 px-4 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-[0.14em] text-lime">
            Мой Страйкбол
          </div>
          <div className="mt-0.5 text-sm font-semibold text-white">Admin Panel</div>
        </div>
        <nav className="flex-1 overflow-y-auto px-2 py-3">
          {isLoading ? (
            <div className="px-2 py-4 text-[12px] text-graphite-600">Загрузка…</div>
          ) : (
            <ul className="space-y-0.5">
              {NAV_ITEMS.filter((item) => can(item.perm)).map((item) => {
                const Icon = ICONS[item.icon as keyof typeof ICONS];
                const active =
                  pathname === item.href || pathname.startsWith(`${item.href}/`);
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      onClick={onClose}
                      className={cn(
                        "flex items-center gap-2.5 rounded-md px-2.5 py-2 text-[13px] transition",
                        active
                          ? "bg-lime-soft text-lime"
                          : "text-graphite-600 hover:bg-graphite-850 hover:text-white",
                      )}
                    >
                      {Icon ? <Icon size={15} strokeWidth={1.8} /> : null}
                      <span>{item.label}</span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </nav>
      </aside>
    </>
  );
}
