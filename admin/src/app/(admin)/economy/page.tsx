"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Avatar,
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
  StatCard,
} from "@/components/ui/page";
import {
  adjustBalance,
  approveWithdrawal,
  fetchEconomyOrganizers,
  fetchEconomyStats,
  fetchTransactions,
  fetchWithdrawalRequests,
  rejectWithdrawal,
  type WithdrawalRequestRow,
} from "@/lib/api/final";
import { usePermissions } from "@/hooks/use-permissions";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

type Tab = "withdrawals" | "orgs" | "tx";

const STATUS_LABEL: Record<WithdrawalRequestRow["status"], string> = {
  pending: "На проверке",
  approved: "Выплачено",
  rejected: "Отклонено",
  cancelled: "Отменено",
};

export default function EconomyPage() {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [msg, setMsg] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("withdrawals");
  const [wdFilter, setWdFilter] = useState<"pending" | "all">("pending");

  const statsQ = useQuery({
    queryKey: ["economy-stats"],
    queryFn: fetchEconomyStats,
  });
  const orgsQ = useQuery({
    queryKey: ["economy-orgs"],
    queryFn: fetchEconomyOrganizers,
  });
  const txQ = useQuery({
    queryKey: ["economy-tx"],
    queryFn: () => fetchTransactions(),
    enabled: tab === "tx",
  });
  const wdQ = useQuery({
    queryKey: ["economy-withdrawals", wdFilter],
    queryFn: () =>
      fetchWithdrawalRequests(wdFilter === "pending" ? "pending" : undefined),
    enabled: tab === "withdrawals",
  });

  const invalidateEconomy = async () => {
    await qc.invalidateQueries({ queryKey: ["economy-stats"] });
    await qc.invalidateQueries({ queryKey: ["economy-orgs"] });
    await qc.invalidateQueries({ queryKey: ["economy-tx"] });
    await qc.invalidateQueries({ queryKey: ["economy-withdrawals"] });
    await qc.invalidateQueries({ queryKey: ["admin-audit-logs"] });
  };

  const adjustMut = useMutation({
    mutationFn: ({
      id,
      amount,
      reason,
    }: {
      id: string;
      amount: number;
      reason: string;
    }) => adjustBalance(id, amount, reason),
    onSuccess: async () => {
      setMsg("Баланс скорректирован (manual_adjustment + audit)");
      await invalidateEconomy();
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const approveMut = useMutation({
    mutationFn: ({ id, note }: { id: string; note?: string }) =>
      approveWithdrawal(id, note),
    onSuccess: async () => {
      setMsg("Заявка на вывод одобрена");
      await invalidateEconomy();
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const rejectMut = useMutation({
    mutationFn: ({ id, note }: { id: string; note?: string }) =>
      rejectWithdrawal(id, note),
    onSuccess: async () => {
      setMsg("Заявка отклонена, средства возвращены");
      await invalidateEconomy();
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const stats = statsQ.data;
  const pendingCount =
    wdFilter === "pending"
      ? (wdQ.data?.length ?? 0)
      : (wdQ.data?.filter((w) => w.status === "pending").length ?? 0);

  return (
    <div>
      <PageHeader
        title="Экономика"
        description="Заявки на вывод, кошельки организаторов и транзакции."
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      {statsQ.isLoading ? <LoadingBlock /> : null}
      {statsQ.error ? (
        <ErrorBlock message={(statsQ.error as Error).message} />
      ) : null}

      {stats ? (
        <div className="mb-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <StatCard label="Организаторов" value={formatNumber(stats.organizers_total)} />
          <StatCard label="Общий баланс" value={formatNumber(stats.balance_total)} />
          <StatCard label="Всего начислено" value={formatNumber(stats.awarded_total)} />
          <StatCard label="Сегодня" value={formatNumber(stats.awarded_today)} />
          <StatCard label="За месяц" value={formatNumber(stats.awarded_month)} />
        </div>
      ) : null}

      <div className="mb-3 flex flex-wrap gap-2">
        <Button
          variant={tab === "withdrawals" ? "primary" : "ghost"}
          onClick={() => setTab("withdrawals")}
        >
          Выводы
          {tab === "withdrawals" && pendingCount > 0 ? ` (${pendingCount})` : ""}
        </Button>
        <Button
          variant={tab === "orgs" ? "primary" : "ghost"}
          onClick={() => setTab("orgs")}
        >
          Организаторы
        </Button>
        <Button
          variant={tab === "tx" ? "primary" : "ghost"}
          onClick={() => setTab("tx")}
        >
          Транзакции
        </Button>
      </div>

      {tab === "withdrawals" ? (
        <>
          <div className="mb-3 flex gap-2">
            <Button
              variant={wdFilter === "pending" ? "primary" : "ghost"}
              className="h-8"
              onClick={() => setWdFilter("pending")}
            >
              Ожидают
            </Button>
            <Button
              variant={wdFilter === "all" ? "primary" : "ghost"}
              className="h-8"
              onClick={() => setWdFilter("all")}
            >
              Все
            </Button>
          </div>
          {wdQ.isLoading ? <LoadingBlock /> : null}
          {wdQ.error ? (
            <ErrorBlock message={(wdQ.error as Error).message} />
          ) : null}
          {!wdQ.isLoading && !(wdQ.data?.length) ? (
            <EmptyState message="Заявок нет" />
          ) : null}
          {(wdQ.data?.length ?? 0) > 0 ? (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Дата</th>
                    <th>Организатор</th>
                    <th>Сумма</th>
                    <th>Комиссия</th>
                    <th>Реквизиты</th>
                    <th>Статус</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {wdQ.data!.map((w) => (
                    <tr key={w.id}>
                      <td className="text-graphite-600">
                        {formatDate(w.created_at)}
                      </td>
                      <td>
                        <Link
                          href={`/users/${w.organizer_id}`}
                          className="text-lime hover:underline"
                        >
                          {w.organizer_nickname}
                        </Link>
                        <div className="text-[11px] text-graphite-600">
                          {w.organizer_phone}
                        </div>
                      </td>
                      <td className="tabular-nums text-lime">
                        {formatNumber(w.amount)} CR
                      </td>
                      <td className="tabular-nums">
                        {formatNumber(w.fee)} CR
                      </td>
                      <td className="max-w-[220px] whitespace-pre-wrap text-[12px]">
                        {w.payment_details}
                      </td>
                      <td>
                        <Badge
                          tone={
                            w.status === "pending"
                              ? "amber"
                              : w.status === "approved"
                                ? "lime"
                                : w.status === "rejected"
                                  ? "red"
                                  : "neutral"
                          }
                        >
                          {STATUS_LABEL[w.status]}
                        </Badge>
                        {w.admin_note ? (
                          <div className="mt-1 text-[11px] text-graphite-600">
                            {w.admin_note}
                          </div>
                        ) : null}
                      </td>
                      <td>
                        {w.status === "pending" && can("economy_adjust") ? (
                          <div className="flex flex-col gap-1">
                            <Button
                              variant="primary"
                              className="h-7 px-2 text-[12px]"
                              disabled={approveMut.isPending || rejectMut.isPending}
                              onClick={() => {
                                const note =
                                  prompt("Комментарий (необязательно)") ||
                                  undefined;
                                approveMut.mutate({ id: w.id, note });
                              }}
                            >
                              Выплатить
                            </Button>
                            <Button
                              variant="ghost"
                              className="h-7 px-2 text-[12px] text-red-300"
                              disabled={approveMut.isPending || rejectMut.isPending}
                              onClick={() => {
                                const note =
                                  prompt("Причина отклонения") || undefined;
                                if (!note) {
                                  setMsg("Укажите причину отклонения");
                                  return;
                                }
                                rejectMut.mutate({ id: w.id, note });
                              }}
                            >
                              Отклонить
                            </Button>
                          </div>
                        ) : w.status === "pending" ? (
                          <span className="text-[11px] text-graphite-600">
                            только просмотр
                          </span>
                        ) : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
        </>
      ) : null}

      {tab === "orgs" ? (
        <>
          {orgsQ.isLoading ? <LoadingBlock /> : null}
          {orgsQ.error ? (
            <ErrorBlock message={(orgsQ.error as Error).message} />
          ) : null}
          {!orgsQ.isLoading && !(orgsQ.data?.length) ? (
            <EmptyState message="Нет организаторов" />
          ) : null}
          {(orgsQ.data?.length ?? 0) > 0 ? (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Организатор</th>
                    <th>Баланс</th>
                    <th>Мероприятия</th>
                    <th>Подтверждённые</th>
                    <th>Заработано</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {orgsQ.data!.map((o) => (
                    <tr key={o.id}>
                      <td>
                        <div className="flex items-center gap-2">
                          <Avatar src={o.avatar_url} name={o.nickname} />
                          <Link
                            href={`/users/${o.id}`}
                            className="text-lime hover:underline"
                          >
                            {o.nickname}
                          </Link>
                        </div>
                      </td>
                      <td className="tabular-nums text-lime">
                        {formatNumber(o.balance)} CR
                      </td>
                      <td className="tabular-nums">
                        {formatNumber(o.events_count)}
                      </td>
                      <td className="tabular-nums">
                        {formatNumber(o.confirmed_count)}
                      </td>
                      <td className="tabular-nums">
                        {formatNumber(o.earned)} CR
                      </td>
                      <td>
                        {can("economy_adjust") ? (
                          <Button
                            variant="ghost"
                            className="h-7 px-2 text-[12px]"
                            onClick={() => {
                              const raw = prompt(
                                "Сумма корректировки (+/-), CR",
                                "100",
                              );
                              if (raw == null) return;
                              const amount = Number(raw);
                              if (!amount) {
                                setMsg("Сумма не может быть 0");
                                return;
                              }
                              const reason =
                                prompt("Причина", "Ручная корректировка") ||
                                "manual_adjustment";
                              adjustMut.mutate({ id: o.id, amount, reason });
                            }}
                          >
                            Корректировка
                          </Button>
                        ) : (
                          <span className="text-[11px] text-graphite-600">
                            только view
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
        </>
      ) : null}

      {tab === "tx" ? (
        <>
          {txQ.isLoading ? <LoadingBlock /> : null}
          {txQ.error ? (
            <ErrorBlock message={(txQ.error as Error).message} />
          ) : null}
          {!txQ.isLoading && !(txQ.data?.length) ? (
            <EmptyState message="Транзакций нет" />
          ) : null}
          {(txQ.data?.length ?? 0) > 0 ? (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Дата</th>
                    <th>Организатор</th>
                    <th>Мероприятие</th>
                    <th>Участник</th>
                    <th>Тип</th>
                    <th>Сумма</th>
                  </tr>
                </thead>
                <tbody>
                  {txQ.data!.map((t) => (
                    <tr key={t.id}>
                      <td className="text-graphite-600">
                        {formatDate(t.created_at)}
                      </td>
                      <td>{t.organizer_nickname}</td>
                      <td>{t.event_title ?? "—"}</td>
                      <td>{t.participant_nickname ?? "—"}</td>
                      <td>
                        <Badge tone="neutral">{t.type}</Badge>
                      </td>
                      <td
                        className={
                          t.amount >= 0
                            ? "tabular-nums text-lime"
                            : "tabular-nums text-red-300"
                        }
                      >
                        {t.amount > 0 ? "+" : ""}
                        {formatNumber(t.amount)} CR
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
        </>
      ) : null}
    </div>
  );
}
