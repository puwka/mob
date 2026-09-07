"use client";

import {
  ErrorBlock,
  LoadingBlock,
  PageHeader,
  StatCard,
} from "@/components/ui/page";
import { Badge } from "@/components/ui/badge";
import { fetchDashboardStats, fetchRecentActivity } from "@/lib/api/admin";
import { formatDate, formatNumber } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";

const KIND_LABEL: Record<string, string> = {
  new_user: "Новый пользователь",
  new_event: "Новое мероприятие",
  clan_join_request: "Заявка в клан",
  new_listing: "Новое объявление",
  achievement_unlock: "Достижение",
};

export default function DashboardPage() {
  const statsQuery = useQuery({
    queryKey: ["admin-dashboard-stats"],
    queryFn: fetchDashboardStats,
  });
  const activityQuery = useQuery({
    queryKey: ["admin-recent-activity"],
    queryFn: () => fetchRecentActivity(25),
  });

  const stats = statsQuery.data;

  return (
    <div>
      <PageHeader
        title="Dashboard"
        description="Сводка по основным данным приложения"
      />

      {statsQuery.isLoading ? <LoadingBlock /> : null}
      {statsQuery.error ? (
        <ErrorBlock message={(statsQuery.error as Error).message} />
      ) : null}

      {stats ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Пользователи" value={formatNumber(stats.users_total)} />
          <StatCard
            label="Новых за 7 дней"
            value={formatNumber(stats.users_new_7d)}
          />
          <StatCard label="Организаторы" value={formatNumber(stats.organizers)} />
          <StatCard
            label="Активные мероприятия"
            value={formatNumber(stats.events_active)}
            hint={`Всего: ${formatNumber(stats.events_total)}`}
          />
          <StatCard label="Кланы" value={formatNumber(stats.clans_total)} />
          <StatCard
            label="Активные объявления"
            value={formatNumber(stats.listings_active)}
          />
          <StatCard
            label="Подтверждённые участники"
            value={formatNumber(stats.attendance_confirmed)}
          />
          <StatCard
            label="Начислено валюты"
            value={formatNumber(stats.credits_awarded_total)}
            hint={`Сообщений: ${formatNumber(stats.messages_total)}`}
          />
        </div>
      ) : null}

      <div className="mt-6 admin-card">
        <div className="border-b border-graphite-700 px-4 py-3 text-sm font-medium text-white">
          Последние события
        </div>
        {activityQuery.isLoading ? (
          <div className="p-4">
            <LoadingBlock />
          </div>
        ) : null}
        {activityQuery.error ? (
          <div className="p-4">
            <ErrorBlock message={(activityQuery.error as Error).message} />
          </div>
        ) : null}
        <div className="divide-y divide-graphite-800">
          {(activityQuery.data ?? []).map((item) => (
            <div
              key={`${item.kind}-${item.entity_id}-${item.at}`}
              className="flex items-start justify-between gap-3 px-4 py-2.5"
            >
              <div className="min-w-0">
                <div className="mb-1">
                  <Badge tone="lime">{KIND_LABEL[item.kind] ?? item.kind}</Badge>
                </div>
                <div className="truncate text-sm text-white">{item.title}</div>
              </div>
              <div className="shrink-0 text-[12px] text-graphite-600">
                {formatDate(item.at)}
              </div>
            </div>
          ))}
          {!activityQuery.isLoading && (activityQuery.data?.length ?? 0) === 0 ? (
            <div className="px-4 py-8 text-center text-sm text-graphite-600">
              Пока нет событий
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
