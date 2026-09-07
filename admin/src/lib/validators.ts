import { z } from "zod";
import { isValidRuMobile } from "@/lib/phone";

export const loginSchema = z.object({
  phone: z
    .string()
    .min(1, "Введите телефон")
    .refine((v) => isValidRuMobile(v), "Введите номер в формате +7XXXXXXXXXX"),
  password: z.string().min(6, "Минимум 6 символов"),
});

export type LoginValues = z.infer<typeof loginSchema>;

export const profileEditSchema = z.object({
  nickname: z.string().min(3).max(20),
  city: z.string().min(1),
  bio: z.string().max(500).optional().nullable(),
  avatar_url: z.string().url().optional().nullable().or(z.literal("")),
  role: z.enum(["user", "organizer"]),
  status: z.enum(["active", "blocked"]),
  rating: z.number().int().min(0),
  games_played: z.number().int().min(0),
  wins: z.number().int().min(0),
  polygons_visited: z.number().int().min(0),
  game_role: z.string().max(80).optional().nullable(),
  team_name: z.string().max(80).optional().nullable(),
});

export type ProfileEditValues = z.infer<typeof profileEditSchema>;

export const balanceAdjustSchema = z.object({
  amount: z.number().refine((v) => v !== 0, "Сумма не может быть 0"),
  reason: z.string().min(2).max(200),
});

export type BalanceAdjustValues = z.infer<typeof balanceAdjustSchema>;
