"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Avatar,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { adjustBalance, fetchUserDetail, setAppRole, setUserStatus, updateProfileAdmin } from "@/lib/api/admin";
import { CITIES } from "@/lib/constants";
import { usePermissions } from "@/hooks/use-permissions";
import { formatDate, formatNumber } from "@/lib/utils";
import {
  balanceAdjustSchema,
  profileEditSchema,
  type BalanceAdjustValues,
  type ProfileEditValues,
} from "@/lib/validators";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";

export default function UserDetailPage() {
  const params = useParams<{ id: string }>();
  const userId = params.id;
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const [message, setMessage] = useState<string | null>(null);

  const detailQuery = useQuery({
    queryKey: ["admin-user", userId],
    queryFn: () => fetchUserDetail(userId),
  });

  const user = detailQuery.data?.user;

  const form = useForm<ProfileEditValues>({
    resolver: zodResolver(profileEditSchema),
  });

  useEffect(() => {
    if (!user) return;
    form.reset({
      nickname: user.nickname,
      city: user.city,
      bio: user.bio ?? "",
      avatar_url: user.avatar_url ?? "",
      role: user.role,
      status: user.status,
      rating: user.rating,
      games_played: user.games_played,
      wins: user.wins,
      polygons_visited: user.polygons_visited,
      game_role: user.game_role ?? "",
      team_name: user.team_name ?? "",
    });
  }, [user, form]);

  const saveMutation = useMutation({
    mutationFn: (values: ProfileEditValues) =>
      updateProfileAdmin(userId, values),
    onSuccess: async () => {
      setMessage("Сохранено");
      await queryClient.invalidateQueries({ queryKey: ["admin-user", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin-users"] });
      await queryClient.invalidateQueries({ queryKey: ["admin-organizers"] });
      await queryClient.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (err: Error) => setMessage(err.message),
  });

  const statusMutation = useMutation({
    mutationFn: (status: "active" | "blocked") => setUserStatus(userId, status),
    onSuccess: async () => {
      setMessage("Статус обновлён");
      await queryClient.invalidateQueries({ queryKey: ["admin-user", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin-users"] });
    },
    onError: (err: Error) => setMessage(err.message),
  });

  const roleMutation = useMutation({
    mutationFn: (role: "user" | "organizer") => setAppRole(userId, role),
    onSuccess: async () => {
      setMessage("Роль обновлена");
      await queryClient.invalidateQueries({ queryKey: ["admin-user", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin-users"] });
      await queryClient.invalidateQueries({ queryKey: ["admin-organizers"] });
    },
    onError: (err: Error) => setMessage(err.message),
  });

  const balanceForm = useForm<BalanceAdjustValues>({
    resolver: zodResolver(balanceAdjustSchema),
    defaultValues: { amount: 100, reason: "Корректировка админом" },
  });

  const balanceMutation = useMutation({
    mutationFn: (values: BalanceAdjustValues) =>
      adjustBalance(userId, values.amount, values.reason),
    onSuccess: async () => {
      setMessage("Баланс обновлён");
      await queryClient.invalidateQueries({ queryKey: ["admin-user", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin-organizers"] });
      await queryClient.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (err: Error) => setMessage(err.message),
  });

  if (detailQuery.isLoading) return <LoadingBlock />;
  if (detailQuery.error) {
    return <ErrorBlock message={(detailQuery.error as Error).message} />;
  }
  if (!user) return <ErrorBlock message="Пользователь не найден" />;

  return (
    <div>
      <PageHeader
        title={user.nickname}
        description={`ID ${user.id}`}
        actions={
          <Link href="/users" className="admin-btn-ghost">
            ← К списку
          </Link>
        }
      />

      {message ? (
        <div className="mb-4 rounded-md border border-graphite-700 bg-graphite-900 px-3 py-2 text-sm text-lime">
          {message}
        </div>
      ) : null}

      <div className="mb-5 flex flex-wrap items-center gap-3 admin-card p-4">
        <Avatar src={user.avatar_url} name={user.nickname} size={56} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-lg font-semibold text-white">{user.nickname}</span>
            <Badge tone={user.role === "organizer" ? "blue" : "neutral"}>
              {user.role}
            </Badge>
            <Badge tone={user.status === "blocked" ? "red" : "lime"}>
              {user.status}
            </Badge>
          </div>
          <div className="mt-1 text-sm text-graphite-600">
            {user.phone} · {user.city} · рейтинг {formatNumber(user.rating)}
            {user.clan_name ? ` · клан ${user.clan_name}` : ""}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {user.status === "active" ? (
            <Button
              variant="danger"
              onClick={() => statusMutation.mutate("blocked")}
              disabled={statusMutation.isPending}
            >
              Заблокировать
            </Button>
          ) : (
            <Button
              variant="ghost"
              onClick={() => statusMutation.mutate("active")}
              disabled={statusMutation.isPending}
            >
              Разблокировать
            </Button>
          )}
          {user.role === "user" ? (
            <Button
              variant="ghost"
              onClick={() => roleMutation.mutate("organizer")}
              disabled={roleMutation.isPending}
            >
              Сделать организатором
            </Button>
          ) : (
            <Button
              variant="ghost"
              onClick={() => roleMutation.mutate("user")}
              disabled={roleMutation.isPending}
            >
              Снять организатора
            </Button>
          )}
        </div>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <form
          className="admin-card space-y-3 p-4"
          onSubmit={form.handleSubmit((v) => saveMutation.mutate(v))}
        >
          <h2 className="text-sm font-semibold text-white">Редактирование</h2>
          <Field label="Nickname">
            <input className="admin-input" {...form.register("nickname")} />
          </Field>
          <Field label="City">
            <select className="admin-input" {...form.register("city")}>
              {CITIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Bio">
            <textarea className="admin-input min-h-[80px]" {...form.register("bio")} />
          </Field>
          <Field label="Avatar URL">
            <input className="admin-input" {...form.register("avatar_url")} />
          </Field>
          <div className="grid grid-cols-2 gap-2">
            <Field label="Role">
              <select className="admin-input" {...form.register("role")}>
                <option value="user">user</option>
                <option value="organizer">organizer</option>
              </select>
            </Field>
            <Field label="Status">
              <select className="admin-input" {...form.register("status")}>
                <option value="active">active</option>
                <option value="blocked">blocked</option>
              </select>
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <Field label="Rating">
              <input
                className="admin-input"
                type="number"
                {...form.register("rating", { valueAsNumber: true })}
              />
            </Field>
            <Field label="Games">
              <input
                className="admin-input"
                type="number"
                {...form.register("games_played", { valueAsNumber: true })}
              />
            </Field>
            <Field label="Wins">
              <input
                className="admin-input"
                type="number"
                {...form.register("wins", { valueAsNumber: true })}
              />
            </Field>
            <Field label="Polygons">
              <input
                className="admin-input"
                type="number"
                {...form.register("polygons_visited", { valueAsNumber: true })}
              />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <Field label="Game role">
              <input className="admin-input" {...form.register("game_role")} />
            </Field>
            <Field label="Team">
              <input className="admin-input" {...form.register("team_name")} />
            </Field>
          </div>
          <Button type="submit" disabled={saveMutation.isPending}>
            {saveMutation.isPending ? "Сохранение…" : "Сохранить в Supabase"}
          </Button>
        </form>

        <div className="space-y-4">
          <div className="admin-card p-4">
            <h2 className="mb-3 text-sm font-semibold text-white">Статистика</h2>
            <dl className="grid grid-cols-2 gap-2 text-sm">
              <Stat label="Создан" value={formatDate(user.created_at)} />
              <Stat label="Клан" value={user.clan_name ?? "—"} />
              <Stat label="Игры" value={formatNumber(user.games_played)} />
              <Stat label="Победы" value={formatNumber(user.wins)} />
            </dl>
          </div>

          {user.role === "organizer" ? (
            <div className="admin-card p-4">
              <h2 className="mb-2 text-sm font-semibold text-white">
                Баланс организатора
              </h2>
              <div className="mb-3 text-2xl font-semibold text-lime">
                {formatNumber(detailQuery.data?.wallet?.balance ?? 0)}{" "}
                <span className="text-sm text-graphite-600">
                  {detailQuery.data?.wallet?.currency ?? "credits"}
                </span>
              </div>
              {can("economy_adjust") ? (
                <form
                  className="space-y-2"
                  onSubmit={balanceForm.handleSubmit((v) =>
                    balanceMutation.mutate(v),
                  )}
                >
                  <input
                    className="admin-input"
                    type="number"
                    step="1"
                    {...balanceForm.register("amount", { valueAsNumber: true })}
                  />
                  <input
                    className="admin-input"
                    placeholder="Причина"
                    {...balanceForm.register("reason")}
                  />
                  <Button
                    type="submit"
                    variant="ghost"
                    disabled={balanceMutation.isPending}
                  >
                    Начислить / списать
                  </Button>
                </form>
              ) : (
                <p className="mb-2 text-[12px] text-graphite-600">
                  Корректировка баланса доступна только Super Admin.
                </p>
              )}
              <div className="mt-4 divide-y divide-graphite-800 border-t border-graphite-700">
                {(detailQuery.data?.transactions ?? []).map((tx) => (
                  <div
                    key={tx.id}
                    className="flex items-center justify-between py-2 text-[12px]"
                  >
                    <div>
                      <div className="text-white">{tx.type}</div>
                      <div className="text-graphite-600">{tx.description}</div>
                    </div>
                    <div className="text-right">
                      <div className="tabular-nums text-lime">
                        {tx.amount > 0 ? "+" : ""}
                        {formatNumber(tx.amount)}
                      </div>
                      <div className="text-graphite-600">
                        {formatDate(tx.created_at)}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : null}

          <div className="admin-card p-4">
            <h2 className="mb-3 text-sm font-semibold text-white">Достижения</h2>
            <div className="space-y-1.5">
              {(detailQuery.data?.achievements ?? []).map((a, idx) => (
                <div
                  key={`${a.title}-${idx}`}
                  className="flex items-center justify-between text-sm"
                >
                  <span className="text-white">{a.title}</span>
                  <Badge tone={a.unlocked ? "lime" : "neutral"}>
                    {a.unlocked ? "unlocked" : `prog ${a.progress}`}
                  </Badge>
                </div>
              ))}
              {(detailQuery.data?.achievements?.length ?? 0) === 0 ? (
                <div className="text-sm text-graphite-600">Нет данных</div>
              ) : null}
            </div>
          </div>

          <div className="admin-card p-4">
            <h2 className="mb-3 text-sm font-semibold text-white">
              Участия в мероприятиях
            </h2>
            <div className="space-y-2">
              {(detailQuery.data?.events ?? []).map((e) => (
                <div key={`${e.id}-${e.event_date}`} className="text-sm">
                  <div className="text-white">{e.title}</div>
                  <div className="text-[12px] text-graphite-600">
                    {formatDate(e.event_date)} · {e.registration_status} ·{" "}
                    {e.attendance_status}
                  </div>
                </div>
              ))}
              {(detailQuery.data?.events?.length ?? 0) === 0 ? (
                <div className="text-sm text-graphite-600">Нет участий</div>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-[12px] text-graphite-600">{label}</span>
      {children}
    </label>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-graphite-800 bg-graphite-950/40 px-2.5 py-2">
      <div className="text-[11px] uppercase tracking-wide text-graphite-600">
        {label}
      </div>
      <div className="mt-0.5 text-white">{value}</div>
    </div>
  );
}
