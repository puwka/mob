import { createClient } from "@/lib/supabase/client";
import type {
  ActivityItem,
  AdminRole,
  AdminUser,
  AdminUserRow,
  AuditLogRow,
  DashboardStats,
  OrganizerRow,
} from "@/lib/types";
import type { ProfileEditValues } from "@/lib/validators";

function mapRpcError(error: { message?: string } | null): never {
  const msg = error?.message ?? "Ошибка запроса";
  if (msg.includes("FORBIDDEN") || msg.includes("42501")) {
    throw new Error("Нет прав администратора");
  }
  if (msg.includes("NOT_AUTHENTICATED")) {
    throw new Error("Сессия истекла");
  }
  throw new Error(msg);
}

export async function fetchAdminMe(): Promise<AdminUser> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_me");
  if (error) mapRpcError(error);
  return data as AdminUser;
}

export async function fetchDashboardStats(): Promise<DashboardStats> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_dashboard_stats");
  if (error) mapRpcError(error);
  return data as DashboardStats;
}

export async function fetchRecentActivity(limit = 20): Promise<ActivityItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_recent_activity", {
    p_limit: limit,
  });
  if (error) mapRpcError(error);
  return (data as ActivityItem[]) ?? [];
}

export type UserListParams = {
  search?: string;
  role?: string;
  city?: string;
  status?: string;
  clanId?: string;
  limit?: number;
  offset?: number;
};

export async function fetchUsers(params: UserListParams = {}): Promise<AdminUserRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_list_users", {
    p_search: params.search || null,
    p_role: params.role || null,
    p_city: params.city || null,
    p_status: params.status || null,
    p_clan_id: params.clanId || null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });
  if (error) mapRpcError(error);
  return (data as AdminUserRow[]) ?? [];
}

export async function fetchOrganizers(params: {
  search?: string;
  status?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<OrganizerRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_list_organizers", {
    p_search: params.search || null,
    p_status: params.status || null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });
  if (error) mapRpcError(error);
  return (data as OrganizerRow[]) ?? [];
}

export async function updateProfileAdmin(
  userId: string,
  values: ProfileEditValues,
): Promise<AdminUserRow> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_update_profile", {
    p_user_id: userId,
    p_nickname: values.nickname,
    p_city: values.city,
    p_bio: values.bio || null,
    p_clear_bio: !values.bio,
    p_avatar_url: values.avatar_url || null,
    p_clear_avatar: !values.avatar_url,
    p_role: values.role,
    p_rating: values.rating,
    p_games_played: values.games_played,
    p_wins: values.wins,
    p_polygons_visited: values.polygons_visited,
    p_status: values.status,
    p_game_role: values.game_role || null,
    p_team_name: values.team_name || null,
  });
  if (error) mapRpcError(error);
  return data as AdminUserRow;
}

export async function setUserStatus(userId: string, status: "active" | "blocked") {
  const supabase = createClient();
  const { error } = await supabase.rpc("admin_set_user_status", {
    p_user_id: userId,
    p_status: status,
  });
  if (error) mapRpcError(error);
}

export async function setAppRole(userId: string, role: "user" | "organizer") {
  const supabase = createClient();
  const { error } = await supabase.rpc("admin_set_app_role", {
    p_user_id: userId,
    p_role: role,
  });
  if (error) mapRpcError(error);
}

export async function fetchPanelRole(
  userId: string,
): Promise<AdminRole | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_get_panel_role", {
    p_user_id: userId,
  });
  if (error) mapRpcError(error);
  return (data as AdminRole | null) ?? null;
}

export async function setPanelRole(
  userId: string,
  role: AdminRole | null,
): Promise<AdminRole | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_set_panel_role", {
    p_user_id: userId,
    p_role: role,
  });
  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("CANNOT_CHANGE_SELF")) {
      throw new Error("Нельзя менять свою админ-роль");
    }
    if (msg.includes("PHONE_REQUIRED")) {
      throw new Error("У пользователя не указан телефон");
    }
    if (msg.includes("PHONE_TAKEN")) {
      throw new Error("Этот телефон уже привязан к другому админу");
    }
    if (msg.includes("INVALID_ADMIN_ROLE")) {
      throw new Error("Некорректная роль админки");
    }
    mapRpcError(error);
  }
  return (data as AdminRole | null) ?? null;
}

export type ProfileTag = "sherpa";

export async function fetchProfileTag(
  userId: string,
): Promise<ProfileTag | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_get_profile_tag", {
    p_user_id: userId,
  });
  if (error) mapRpcError(error);
  return (data as ProfileTag | null) ?? null;
}

export async function setProfileTag(
  userId: string,
  tag: ProfileTag | null,
): Promise<ProfileTag | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_set_profile_tag", {
    p_user_id: userId,
    p_tag: tag,
  });
  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("INVALID_PROFILE_TAG")) {
      throw new Error("Некорректный тег профиля");
    }
    mapRpcError(error);
  }
  return (data as ProfileTag | null) ?? null;
}

export async function adjustBalance(
  organizerId: string,
  amount: number,
  reason: string,
) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("admin_adjust_organizer_balance", {
    p_organizer_id: organizerId,
    p_amount: amount,
    p_reason: reason,
  });
  if (error) mapRpcError(error);
  return data as number;
}

export async function fetchAuditLogs(limit = 100): Promise<AuditLogRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("admin_audit_logs")
    .select("*, admin_users(phone)")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) mapRpcError(error);

  return ((data as Array<AuditLogRow & { admin_users?: { phone: string } | null }>) ?? []).map(
    (row) => ({
      ...row,
      admin_phone: row.admin_users?.phone,
    }),
  );
}

export async function fetchUserDetail(userId: string): Promise<{
  user: AdminUserRow | null;
  achievements: Array<{
    title: string;
    unlocked: boolean;
    progress: number;
    unlocked_at: string | null;
  }>;
  events: Array<{
    id: string;
    title: string;
    event_date: string;
    attendance_status: string;
    registration_status: string;
  }>;
  wallet: { balance: number; currency: string } | null;
  transactions: Array<{
    id: string;
    amount: number;
    type: string;
    description: string;
    created_at: string;
  }>;
}> {
  const supabase = createClient();
  const users = await fetchUsers({ search: undefined, limit: 200 });
  let user = users.find((u) => u.id === userId) ?? null;

  if (!user) {
    const { data } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .maybeSingle();
    if (data) {
      const { data: clan } = await supabase
        .from("clan_members")
        .select("clan_id, clans(name)")
        .eq("user_id", userId)
        .maybeSingle();
      user = {
        id: data.id,
        nickname: data.nickname,
        phone: data.phone,
        city: data.city,
        avatar_url: data.avatar_url,
        role: data.role,
        rating: data.rating,
        status: data.status ?? "active",
        created_at: data.created_at,
        clan_id: clan?.clan_id ?? null,
        clan_name:
          (clan?.clans as unknown as { name?: string } | null)?.name ?? null,
        games_played: data.games_played,
        wins: data.wins,
        polygons_visited: data.polygons_visited,
        bio: data.bio,
        game_role: data.game_role,
        team_name: data.team_name,
      };
    }
  }

  const [{ data: ua }, { data: parts }, { data: wallet }, { data: txs }] =
    await Promise.all([
      supabase
        .from("user_achievements")
        .select("progress, unlocked, unlocked_at, achievements(title)")
        .eq("user_id", userId),
      supabase
        .from("event_participants")
        .select("attendance_status, registration_status, events(id, title, event_date)")
        .eq("user_id", userId)
        .order("registered_at", { ascending: false })
        .limit(30),
      supabase
        .from("organizer_wallets")
        .select("balance, currency")
        .eq("organizer_id", userId)
        .maybeSingle(),
      supabase
        .from("organizer_transactions")
        .select("id, amount, type, description, created_at")
        .eq("organizer_id", userId)
        .order("created_at", { ascending: false })
        .limit(20),
    ]);

  return {
    user,
    achievements: (ua ?? []).map((row) => {
      const ach = row.achievements as unknown as { title?: string } | null;
      return {
        title: ach?.title ?? "—",
        unlocked: Boolean(row.unlocked),
        progress: Number(row.progress ?? 0),
        unlocked_at: row.unlocked_at as string | null,
      };
    }),
    events: (parts ?? []).map((row) => {
      const ev = row.events as unknown as {
        id: string;
        title: string;
        event_date: string;
      } | null;
      return {
        id: ev?.id ?? "",
        title: ev?.title ?? "—",
        event_date: ev?.event_date ?? "",
        attendance_status: String(row.attendance_status),
        registration_status: String(row.registration_status),
      };
    }),
    wallet: wallet
      ? { balance: Number(wallet.balance), currency: wallet.currency }
      : null,
    transactions: (txs ?? []).map((t) => ({
      id: t.id,
      amount: Number(t.amount),
      type: t.type,
      description: t.description,
      created_at: t.created_at,
    })),
  };
}

export async function fetchClans(): Promise<Array<{ id: string; name: string }>> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("clans")
    .select("id, name")
    .order("name");
  if (error) mapRpcError(error);
  return data ?? [];
}
