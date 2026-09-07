"use client";

import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { ErrorBlock, LoadingBlock } from "@/components/ui/page";
import { AuthProvider, useAuth } from "@/providers/auth-provider";
import { QueryProvider } from "@/providers/query-provider";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

function Guard({ children }: { children: React.ReactNode }) {
  const { admin, isLoading, error, signOut } = useAuth();
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    if (!isLoading && error) {
      void signOut();
    }
  }, [error, isLoading, signOut]);

  useEffect(() => {
    if (!isLoading && !admin && !error) {
      router.replace("/login");
    }
  }, [admin, error, isLoading, router]);

  if (isLoading) {
    return (
      <div className="flex h-screen items-center justify-center bg-graphite-950">
        <LoadingBlock label="Проверка доступа…" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-screen items-center justify-center bg-graphite-950 p-6">
        <ErrorBlock message="Нет прав администратора. Войдите под учётной записью из admin_users." />
      </div>
    );
  }

  if (!admin) return null;

  return (
    <div className="flex h-screen overflow-hidden bg-graphite-950">
      <Sidebar open={menuOpen} onClose={() => setMenuOpen(false)} />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar onMenu={() => setMenuOpen(true)} />
        <main className="min-h-0 flex-1 overflow-y-auto p-3 sm:p-5">{children}</main>
      </div>
    </div>
  );
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  return (
    <QueryProvider>
      <AuthProvider>
        <Guard>{children}</Guard>
      </AuthProvider>
    </QueryProvider>
  );
}
