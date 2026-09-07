"use client";

import { createClient } from "@/lib/supabase/client";
import { fetchAdminMe } from "@/lib/api/admin";
import type { AdminUser } from "@/lib/types";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
} from "react";

type AuthContextValue = {
  admin: AdminUser | null | undefined;
  isLoading: boolean;
  error: Error | null;
  signOut: () => Promise<void>;
  refresh: () => void;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ["admin-me"],
    queryFn: fetchAdminMe,
    retry: false,
  });

  const signOut = useCallback(async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    queryClient.clear();
    router.replace("/login");
    router.refresh();
  }, [queryClient, router]);

  const refresh = useCallback(() => {
    void refetch();
  }, [refetch]);

  const value = useMemo<AuthContextValue>(
    () => ({
      admin: data,
      isLoading,
      error: error ?? null,
      signOut,
      refresh,
    }),
    [data, error, isLoading, refresh, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
