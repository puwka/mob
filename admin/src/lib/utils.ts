import { clsx, type ClassValue } from "clsx";

export function cn(...inputs: ClassValue[]) {
  return clsx(inputs);
}

export function formatDate(value?: string | null) {
  if (!value) return "—";
  try {
    return new Intl.DateTimeFormat("ru-RU", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value));
  } catch {
    return value;
  }
}

export function formatNumber(value?: number | null) {
  if (value == null || Number.isNaN(Number(value))) return "0";
  return new Intl.NumberFormat("ru-RU").format(Number(value));
}

export function shortId(id?: string | null) {
  if (!id) return "—";
  return id.slice(0, 8);
}
