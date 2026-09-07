"use client";

import { fetchMyPermissions, type AdminPermission } from "@/lib/api/final";
import { useAuth } from "@/providers/auth-provider";
import { useQuery } from "@tanstack/react-query";
import { useMemo } from "react";

export function usePermissions() {
  const { admin } = useAuth();
  const query = useQuery({
    queryKey: ["admin-permissions", admin?.id],
    queryFn: fetchMyPermissions,
    enabled: !!admin,
    staleTime: 60_000,
  });

  const set = useMemo(
    () => new Set<AdminPermission>(query.data ?? []),
    [query.data],
  );

  return {
    permissions: set,
    can: (perm: AdminPermission) => set.has(perm),
    isLoading: query.isLoading,
    error: query.error,
  };
}
