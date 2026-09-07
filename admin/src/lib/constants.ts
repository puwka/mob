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
export const ACHIEVEMENT_TYPES = [
  "games_played",
  "wins",
  "polygons_visited",
  "rating",
  "events_count",
] as const;

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
