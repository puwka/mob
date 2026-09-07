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
  fetchEconomyOrganizers,
  fetchEconomyStats,
  fetchTransactions,
} from "@/lib/api/final";
import { usePermissions } from "@/hooks/use-permissions";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

export default function EconomyPage() {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [msg, setMsg] = useState<string | null>(null);
  const [tab, setTab] = useState<"orgs" | "tx">("orgs");

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
      await qc.invalidateQueries({ queryKey: ["economy-stats"] });
      await qc.invalidateQueries({ queryKey: ["economy-orgs"] });
      await qc.invalidateQueries({ queryKey: ["economy-tx"] });
      await qc.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const stats = statsQ.data;

  return (
    <div>
      <PageHeader
        title="Экономика"
        description="Кошельки организаторов и транзакции. Корректировка — только Super Admin через RPC."
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

      <div className="mb-3 flex gap-2">
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
      ) : (
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
      )}
    </div>
  );
}
