import { createClient } from "@/lib/supabase/client";

function mapRpcError(error: { message?: string } | null): never {
  const msg = error?.message ?? "Ошибка запроса";
  if (msg.includes("FORBIDDEN") || msg.includes("42501")) {
    throw new Error("Нет прав для этого действия");
  }
  throw new Error(msg);
}

async function rpc<T>(name: string, params?: Record<string, unknown>): Promise<T> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc(name, params);
  if (error) mapRpcError(error);
  return data as T;
}

export type AdminPermission =
  | "dashboard"
  | "users"
  | "organizers"
  | "events"
  | "clans"
  | "ranking"
  | "market"
  | "moderation"
  | "dialogs"
  | "achievements"
  | "dictionaries"
  | "economy_view"
  | "economy_adjust"
  | "attendance"
  | "settings_view"
  | "settings_write"
  | "notifications"
  | "logs"
  | "search";

export const fetchMyPermissions = () =>
  rpc<AdminPermission[]>("admin_my_permissions");

// ——— Dialogs ———
export type ConversationRow = {
  id: string;
  type: string;
  title: string | null;
  status: string;
  listing_id: string | null;
  clan_id: string | null;
  created_at: string;
  updated_at: string;
  members_count: number;
  messages_count: number;
  unread_approx: number;
  last_message: string | null;
  last_message_at: string | null;
  member_names: string | null;
};

export type MessageRow = {
  id: string;
  sender_id: string;
  sender_nickname: string | null;
  text: string;
  created_at: string;
  edited_at: string | null;
  deleted_at: string | null;
  deleted_by: string | null;
};

export const fetchConversations = (params: {
  type?: string;
  status?: string;
  search?: string;
} = {}) =>
  rpc<ConversationRow[]>("admin_list_conversations", {
    p_type: params.type || null,
    p_status: params.status || null,
    p_search: params.search || null,
    p_limit: 50,
    p_offset: 0,
  });

export const fetchMessages = (conversationId: string) =>
  rpc<MessageRow[]>("admin_list_messages", {
    p_conversation_id: conversationId,
  });

export const softDeleteMessage = (id: string) =>
  rpc<void>("admin_soft_delete_message", { p_message_id: id });

export const setConversationStatus = (
  id: string,
  status: "active" | "blocked" | "archived",
) =>
  rpc<void>("admin_set_conversation_status", {
    p_id: id,
    p_status: status,
  });

export const deleteConversation = (id: string) =>
  rpc<void>("admin_delete_conversation", { p_id: id });

// ——— Economy ———
export type EconomyStats = {
  organizers_total: number;
  balance_total: number;
  awarded_total: number;
  awarded_today: number;
  awarded_month: number;
};

export type EconomyOrganizer = {
  id: string;
  nickname: string;
  avatar_url: string | null;
  city: string;
  balance: number;
  events_count: number;
  confirmed_count: number;
  earned: number;
};

export type TransactionRow = {
  id: string;
  created_at: string;
  organizer_id: string;
  organizer_nickname: string;
  event_id: string | null;
  event_title: string | null;
  participant_id: string | null;
  participant_nickname: string | null;
  type: string;
  amount: number;
  description: string;
};

export const fetchEconomyStats = () =>
  rpc<EconomyStats>("admin_economy_stats");

export const fetchEconomyOrganizers = () =>
  rpc<EconomyOrganizer[]>("admin_economy_organizers", {
    p_limit: 100,
    p_offset: 0,
  });

export const fetchTransactions = (params: {
  organizerId?: string;
  type?: string;
} = {}) =>
  rpc<TransactionRow[]>("admin_list_transactions", {
    p_organizer_id: params.organizerId || null,
    p_type: params.type || null,
    p_limit: 100,
    p_offset: 0,
  });

export const adjustBalance = (
  organizerId: string,
  amount: number,
  reason: string,
) =>
  rpc<number>("admin_adjust_organizer_balance", {
    p_organizer_id: organizerId,
    p_amount: amount,
    p_reason: reason,
  });

// ——— Attendance ———
export type AttendanceRow = {
  participant_id: string;
  event_id: string;
  event_title: string;
  event_city: string;
  organizer_id: string | null;
  organizer_nickname: string | null;
  user_id: string;
  user_nickname: string;
  public_qr_id: string;
  registration_status: string;
  attendance_status: string;
  registered_at: string | null;
  attended_at: string | null;
  reward_amount: number;
  has_reward: boolean;
};

export const fetchAttendance = (params: Record<string, unknown> = {}) =>
  rpc<AttendanceRow[]>("admin_list_attendance", {
    p_organizer_id: params.organizerId ?? null,
    p_event_id: params.eventId ?? null,
    p_city: params.city ?? null,
    p_date_from: params.dateFrom ?? null,
    p_date_to: params.dateTo ?? null,
    p_status: params.status ?? null,
    p_limit: 100,
    p_offset: 0,
  });

// ——— Settings ———
export type SettingRow = {
  key: string;
  value: string;
  updated_at: string;
};

export const fetchSettings = () => rpc<SettingRow[]>("admin_list_settings");

export const upsertSetting = (key: string, value: string) =>
  rpc<SettingRow>("admin_upsert_setting", { p_key: key, p_value: value });

// ——— Notifications ———
export type NotificationRow = {
  id: string;
  title: string;
  body: string;
  type: string;
  target_city: string | null;
  target_event_id: string | null;
  target_clan_id: string | null;
  status: string;
  created_by: string | null;
  created_at: string;
  sent_at: string | null;
};

export const fetchNotifications = () =>
  rpc<NotificationRow[]>("admin_list_notifications", { p_limit: 50 });

export const createNotification = (p: {
  title: string;
  body: string;
  type: string;
  targetCity?: string;
  targetEventId?: string;
  targetClanId?: string;
}) =>
  rpc<NotificationRow>("admin_create_notification", {
    p_title: p.title,
    p_body: p.body,
    p_type: p.type,
    p_target_city: p.targetCity ?? null,
    p_target_event_id: p.targetEventId ?? null,
    p_target_clan_id: p.targetClanId ?? null,
  });

// ——— Search ———
export type SearchHit = {
  id: string;
  label: string;
  meta: string;
  kind: "user" | "clan" | "event" | "listing";
};

export type SearchResult = {
  users: SearchHit[];
  clans: SearchHit[];
  events: SearchHit[];
  listings: SearchHit[];
};

export const globalSearch = (query: string) =>
  rpc<SearchResult>("admin_global_search", {
    p_query: query,
    p_limit: 8,
  });
