import { createClient } from "@/lib/supabase/client";

function mapRpcError(error: { message?: string } | null): never {
  const msg = error?.message ?? "Ошибка запроса";
  if (msg.includes("FORBIDDEN") || msg.includes("42501")) {
    throw new Error("Нет прав администратора");
  }
  throw new Error(msg);
}

async function rpc<T>(name: string, params?: Record<string, unknown>): Promise<T> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc(name, params);
  if (error) mapRpcError(error);
  return data as T;
}

// ——— Cities ———
export type CityRow = {
  id: string;
  name: string;
  sort_order: number;
  is_active: boolean;
  created_at: string;
};

export const fetchCities = (all = true) =>
  rpc<CityRow[]>("admin_list_cities", { p_all: all });

export const upsertCity = (p: {
  id?: string;
  name: string;
  sort_order?: number;
  is_active?: boolean;
}) =>
  rpc<CityRow>("admin_upsert_city", {
    p_id: p.id ?? null,
    p_name: p.name,
    p_sort_order: p.sort_order ?? 0,
    p_is_active: p.is_active ?? true,
  });

export const deleteCity = (id: string) =>
  rpc<void>("admin_delete_city", { p_id: id });

// ——— Events ———
export type EventRow = {
  id: string;
  title: string;
  city: string;
  event_date: string;
  status: string;
  max_participants: number;
  participants_count: number;
  organizer_id: string | null;
  organizer_nickname: string | null;
  image_url: string | null;
  location: string;
  description: string;
  created_at: string;
};

export type ParticipantRow = {
  id: string;
  user_id: string;
  nickname: string;
  avatar_url: string | null;
  city: string;
  registration_status: string;
  attendance_status: string;
  registered_at: string | null;
  attended_at: string | null;
  confirmed_by: string | null;
  confirmed_by_nickname: string | null;
};

export const fetchEvents = (params: Record<string, unknown> = {}) =>
  rpc<EventRow[]>("admin_list_events", {
    p_city: params.city ?? null,
    p_organizer_id: params.organizerId ?? null,
    p_status: params.status ?? null,
    p_date_from: params.dateFrom ?? null,
    p_date_to: params.dateTo ?? null,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });

export const upsertEvent = (p: Record<string, unknown>) =>
  rpc<EventRow>("admin_upsert_event", {
    p_id: p.id ?? null,
    p_title: p.title ?? null,
    p_description: p.description ?? null,
    p_city: p.city ?? null,
    p_location: p.location ?? null,
    p_event_date: p.eventDate ?? null,
    p_organizer_id: p.organizerId ?? null,
    p_max_participants: p.maxParticipants ?? null,
    p_image_url: p.imageUrl ?? null,
    p_clear_image: p.clearImage ?? false,
    p_status: p.status ?? null,
  });

export const deleteEvent = (id: string) =>
  rpc<void>("admin_delete_event", { p_id: id });

export const fetchParticipants = (eventId: string) =>
  rpc<ParticipantRow[]>("admin_list_event_participants", {
    p_event_id: eventId,
  });

export const registerParticipant = (eventId: string, userId: string) =>
  rpc("admin_register_participant", {
    p_event_id: eventId,
    p_user_id: userId,
  });

export const cancelParticipant = (id: string) =>
  rpc<void>("admin_cancel_participant", { p_participant_id: id });

export const removeParticipant = (id: string) =>
  rpc<void>("admin_remove_participant", { p_participant_id: id });

export const confirmParticipant = (id: string) =>
  rpc<Record<string, unknown>>("admin_confirm_participant", {
    p_participant_id: id,
  });

// ——— Clans ———
export type ClanRow = {
  id: string;
  name: string;
  tag: string;
  avatar_url: string | null;
  description: string;
  city: string | null;
  leader_id: string | null;
  leader_nickname: string | null;
  members_count: number;
  rating: number;
  created_at: string;
};

export type ClanMemberRow = {
  user_id: string;
  nickname: string;
  avatar_url: string | null;
  city: string;
  rating: number;
  role: string;
  joined_at: string;
};

export const fetchClans = (search?: string) =>
  rpc<ClanRow[]>("admin_list_clans", {
    p_search: search || null,
    p_limit: 100,
    p_offset: 0,
  });

export const upsertClan = (p: Record<string, unknown>) =>
  rpc<ClanRow>("admin_upsert_clan", {
    p_id: p.id ?? null,
    p_name: p.name ?? null,
    p_tag: p.tag ?? null,
    p_description: p.description ?? null,
    p_avatar_url: p.avatarUrl ?? null,
    p_clear_avatar: p.clearAvatar ?? false,
    p_leader_id: p.leaderId ?? null,
    p_city: p.city ?? null,
  });

export const deleteClan = (id: string) =>
  rpc<void>("admin_delete_clan", { p_id: id });

export const fetchClanMembers = (clanId: string) =>
  rpc<ClanMemberRow[]>("admin_list_clan_members", { p_clan_id: clanId });

export const addClanMember = (clanId: string, userId: string, role = "member") =>
  rpc<void>("admin_add_clan_member", {
    p_clan_id: clanId,
    p_user_id: userId,
    p_role: role,
  });

export const removeClanMember = (clanId: string, userId: string) =>
  rpc<void>("admin_remove_clan_member", {
    p_clan_id: clanId,
    p_user_id: userId,
  });

export const setPlayerRating = (userId: string, rating: number) =>
  rpc("admin_set_player_rating", { p_user_id: userId, p_rating: rating });

// ——— Ranking (reuse existing RPCs; works for authenticated admin) ———
export type RankingPlayer = {
  id: string;
  nickname: string;
  avatar_url: string | null;
  city: string;
  rating: number;
  rank: number;
};

export type RankingClan = {
  id: string;
  name: string;
  tag: string;
  avatar_url: string | null;
  rating: number;
  members_count: number;
  rank: number;
};

export async function fetchRankingPlayers(city?: string | null, limit = 100) {
  return rpc<RankingPlayer[]>("ranking_players", {
    p_city: city || null,
    p_limit: limit,
    p_offset: 0,
  });
}

export async function fetchRankingClans(city?: string | null, limit = 100) {
  return rpc<RankingClan[]>("ranking_clans", {
    p_city: city || null,
    p_limit: limit,
    p_offset: 0,
  });
}

// ——— Market ———
export type ListingRow = {
  id: string;
  title: string;
  price: number;
  city: string;
  status: string;
  views_count: number;
  is_promoted: boolean;
  promoted_until: string | null;
  created_at: string;
  seller_id: string;
  seller_nickname: string;
  category_id: string;
  category_name: string;
  cover_url: string | null;
  rejection_reason: string | null;
  condition: string;
};

export type CategoryRow = {
  id: string;
  name: string;
  parent_id: string | null;
  icon: string | null;
  sort_order: number;
  created_at: string;
};

export const fetchListings = (params: Record<string, unknown> = {}) =>
  rpc<ListingRow[]>("admin_list_listings", {
    p_category_id: params.categoryId ?? null,
    p_city: params.city ?? null,
    p_status: params.status ?? null,
    p_seller_id: params.sellerId ?? null,
    p_date_from: params.dateFrom ?? null,
    p_date_to: params.dateTo ?? null,
    p_price_min: params.priceMin ?? null,
    p_price_max: params.priceMax ?? null,
    p_search: params.search ?? null,
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });

export const upsertListing = (p: Record<string, unknown>) =>
  rpc<ListingRow>("admin_upsert_listing", {
    p_id: p.id ?? null,
    p_seller_id: p.sellerId ?? null,
    p_category_id: p.categoryId ?? null,
    p_title: p.title ?? null,
    p_description: p.description ?? null,
    p_price: p.price ?? null,
    p_city: p.city ?? null,
    p_condition: p.condition ?? null,
    p_status: p.status ?? null,
    p_is_promoted: p.isPromoted ?? null,
    p_promoted_until: p.promotedUntil ?? null,
    p_rejection_reason: p.rejectionReason ?? null,
    p_clear_rejection: p.clearRejection ?? false,
  });

/** Raise listing to top of feed (indefinite promo unless days set). */
export const boostListing = (id: string, days?: number | null) =>
  rpc<ListingRow>("admin_boost_listing", {
    p_id: id,
    p_days: days ?? null,
  });

export const unboostListing = (id: string) =>
  rpc<ListingRow>("admin_unboost_listing", { p_id: id });

export const deleteListing = (id: string) =>
  rpc<void>("admin_delete_listing", { p_id: id });

export const setListingImages = (listingId: string, urls: string[]) =>
  rpc<void>("admin_set_listing_images", {
    p_listing_id: listingId,
    p_urls: urls,
  });

export const moderateListing = (
  id: string,
  action: "approve" | "reject" | "archive" | "restore",
  reason?: string,
) =>
  rpc<ListingRow>("admin_moderate_listing", {
    p_id: id,
    p_action: action,
    p_reason: reason ?? null,
  });

export const fetchCategories = () =>
  rpc<CategoryRow[]>("admin_list_categories");

export const upsertCategory = (p: Record<string, unknown>) =>
  rpc<CategoryRow>("admin_upsert_category", {
    p_id: p.id ?? null,
    p_name: p.name ?? null,
    p_icon: p.icon ?? null,
    p_sort_order: p.sortOrder ?? null,
    p_parent_id: p.parentId ?? null,
    p_clear_parent: p.clearParent ?? false,
  });

export const deleteCategory = (id: string) =>
  rpc<void>("admin_delete_category", { p_id: id });

// ——— Achievements ———
export type AchievementRow = {
  id: string;
  title: string;
  description: string;
  icon: string;
  type: string;
  required_value: number;
  is_active: boolean;
  created_at: string;
};

export const fetchAchievements = () =>
  rpc<AchievementRow[]>("admin_list_achievements");

export const upsertAchievement = (p: Record<string, unknown>) =>
  rpc<AchievementRow>("admin_upsert_achievement", {
    p_id: p.id ?? null,
    p_title: p.title ?? null,
    p_description: p.description ?? null,
    p_icon: p.icon ?? null,
    p_type: p.type ?? null,
    p_required_value: p.requiredValue ?? null,
    p_is_active: p.isActive ?? null,
  });

export const deleteAchievement = (id: string) =>
  rpc<void>("admin_delete_achievement", { p_id: id });

export async function fetchListingImages(listingId: string) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("listing_images")
    .select("id, url, sort_order")
    .eq("listing_id", listingId)
    .order("sort_order");
  if (error) mapRpcError(error);
  return data ?? [];
}
