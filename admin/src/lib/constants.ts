export const CITIES = ["Москва", "Краснодар", "Санкт-Петербург"] as const;

export const APP_ROLES = ["user", "organizer"] as const;
export const USER_STATUSES = ["active", "blocked"] as const;
export const ADMIN_ROLES = ["super_admin", "admin", "moderator"] as const;

export const EVENT_STATUSES = ["draft", "active", "finished", "cancelled"] as const;
export const LISTING_STATUSES = [
  "pending",
  "active",
  "rejected",
  "archived",
  "sold",
] as const;

/** Achievement condition type → label for admin UI */
export const ACHIEVEMENT_TYPE_OPTIONS = [
  { value: "games_played", label: "Количество сыгранных игр" },
  { value: "polygons_visited", label: "Количество разных полигонов" },
  { value: "team_games", label: "Количество игр в составе команды" },
  { value: "organized_events", label: "Количество проведённых игр" },
  {
    value: "organized_participants",
    label: "Количество участников в организованных играх",
  },
  { value: "role_games", label: "Количество сыгранных игр в роли" },
  { value: "messages_sent", label: "Количество сообщений в чатах" },
  { value: "dating_likes", label: "Количество симпатий в дейтинге" },
  {
    value: "profile_photos",
    label: "Количество фотографий, добавленных в профиль",
  },
  { value: "clan_joined", label: "Вступление в клан (1 = состоит)" },
  {
    value: "events_attended_confirmed",
    label: "Количество подтверждённых участий в игре",
  },
  {
    value: "listings_published",
    label: "Количество опубликованных объявлений на барахолке",
  },
  { value: "events_count", label: "Количество регистраций на игры" },
  { value: "wins", label: "Количество побед" },
  { value: "rating", label: "Рейтинг (XP)" },
] as const;

/** @deprecated use ACHIEVEMENT_TYPE_OPTIONS */
export const ACHIEVEMENT_TYPES = ACHIEVEMENT_TYPE_OPTIONS.map((o) => o.value);

export type NavItem = {
  href: string;
  label: string;
  icon: string;
  perm:
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
    | "attendance"
    | "settings_view"
    | "notifications"
    | "logs";
};

export const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", icon: "LayoutDashboard", perm: "dashboard" },
  { href: "/users", label: "Пользователи", icon: "Users", perm: "users" },
  { href: "/organizers", label: "Организаторы", icon: "BadgeCheck", perm: "organizers" },
  { href: "/events", label: "Мероприятия", icon: "CalendarDays", perm: "events" },
  { href: "/attendance", label: "Посещаемость", icon: "QrCode", perm: "attendance" },
  { href: "/clans", label: "Кланы", icon: "Shield", perm: "clans" },
  { href: "/ranking", label: "Рейтинг", icon: "Trophy", perm: "ranking" },
  { href: "/market", label: "Барахолка", icon: "Store", perm: "market" },
  { href: "/market/moderation", label: "Модерация", icon: "ShieldCheck", perm: "moderation" },
  { href: "/chats", label: "Диалоги", icon: "MessagesSquare", perm: "dialogs" },
  { href: "/achievements", label: "Достижения", icon: "Award", perm: "achievements" },
  { href: "/dictionaries", label: "Справочники", icon: "BookOpen", perm: "dictionaries" },
  { href: "/economy", label: "Экономика", icon: "Wallet", perm: "economy_view" },
  { href: "/notifications", label: "Уведомления", icon: "Bell", perm: "notifications" },
  { href: "/settings", label: "Настройки", icon: "Settings", perm: "settings_view" },
  { href: "/logs", label: "Логи", icon: "ScrollText", perm: "logs" },
];
