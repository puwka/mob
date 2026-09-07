export type AdminRole = "super_admin" | "admin" | "moderator";
export type AppRole = "user" | "organizer";
export type UserStatus = "active" | "blocked";

export type AdminUser = {
  id: string;
  phone: string;
  role: AdminRole;
  created_at: string;
};

export type DashboardStats = {
  users_total: number;
  users_new_7d: number;
  organizers: number;
  events_total: number;
  events_active: number;
  clans_total: number;
  listings_active: number;
  messages_total: number;
  attendance_confirmed: number;
  credits_awarded_total: number;
};

export type ActivityItem = {
  kind: string;
  entity_id: string;
  title: string;
  at: string;
};

export type AdminUserRow = {
  id: string;
  nickname: string;
  phone: string;
  city: string;
  avatar_url: string | null;
  role: AppRole;
  rating: number;
  status: UserStatus;
  created_at: string;
  clan_id: string | null;
  clan_name: string | null;
  games_played: number;
  wins: number;
  polygons_visited: number;
  bio: string | null;
  game_role: string | null;
  team_name: string | null;
};

export type OrganizerRow = {
  id: string;
  nickname: string;
  avatar_url: string | null;
  city: string;
  status: UserStatus;
  created_at: string;
  events_count: number;
  participants_count: number;
  balance: number;
};

export type AuditLogRow = {
  id: string;
  admin_id: string;
  action: string;
  entity_type: string;
  entity_id: string | null;
  old_data: Record<string, unknown> | null;
  new_data: Record<string, unknown> | null;
  created_at: string;
  admin_phone?: string;
};
