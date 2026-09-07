"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchOrganizers } from "@/lib/api/admin";
import { confirmParticipant, fetchCities } from "@/lib/api/content";
import { fetchAttendance } from "@/lib/api/final";
import { formatDate, formatNumber, shortId } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useMemo, useState } from "react";

export default function AttendancePage() {
  const qc = useQueryClient();
  const [organizerId, setOrganizerId] = useState("");
  const [city, setCity] = useState("");
  const [status, setStatus] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [msg, setMsg] = useState<string | null>(null);

  const orgsQ = useQuery({
    queryKey: ["admin-organizers-opts"],
    queryFn: () => fetchOrganizers({ limit: 200 }),
  });
  const citiesQ = useQuery({
    queryKey: ["cities"],
    queryFn: () => fetchCities(),
  });

  const params = useMemo(
    () => ({
      organizerId: organizerId || undefined,
      city: city || undefined,
      status: status || undefined,
      dateFrom: dateFrom ? new Date(dateFrom).toISOString() : undefined,
    }),
    [organizerId, city, status, dateFrom],
  );

  const listQ = useQuery({
    queryKey: ["admin-attendance", params],
    queryFn: () => fetchAttendance(params),
  });

  const confirmMut = useMutation({
    mutationFn: (participantId: string) => confirmParticipant(participantId),
    onSuccess: async (res) => {
      setMsg(
        `Подтверждено · начислено ${formatNumber(Number(res.reward_amount ?? 0))} CR`,
      );
      await qc.invalidateQueries({ queryKey: ["admin-attendance"] });
      await qc.invalidateQueries({ queryKey: ["economy-stats"] });
      await qc.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Посещаемость"
        description="QR / ручное подтверждение. Повторное начисление невозможно (unique index)."
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-4 grid gap-2 md:grid-cols-2 xl:grid-cols-4">
        <select
          className="admin-input"
          value={organizerId}
          onChange={(e) => setOrganizerId(e.target.value)}
        >
          <option value="">Организатор</option>
          {(orgsQ.data ?? []).map((o) => (
            <option key={o.id} value={o.id}>
              {o.nickname}
            </option>
          ))}
        </select>
        <select
          className="admin-input"
          value={city}
          onChange={(e) => setCity(e.target.value)}
        >
          <option value="">Город</option>
          {(citiesQ.data ?? []).map((c) => (
            <option key={c.id} value={c.name}>
              {c.name}
            </option>
          ))}
        </select>
        <select
          className="admin-input"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">Статус</option>
          <option value="not_confirmed">Не подтвержден</option>
          <option value="confirmed">Подтвержден</option>
        </select>
        <input
          className="admin-input"
          type="date"
          value={dateFrom}
          onChange={(e) => setDateFrom(e.target.value)}
        />
      </div>

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Записей нет" />
      ) : null}

      {(listQ.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Мероприятие</th>
                <th>Организатор</th>
                <th>Участник</th>
                <th>QR</th>
                <th>Дата</th>
                <th>Статус</th>
                <th>Начисление</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {listQ.data!.map((r) => (
                <tr key={r.participant_id}>
                  <td>
                    <Link
                      href={`/events/${r.event_id}`}
                      className="text-lime hover:underline"
                    >
                      {r.event_title}
                    </Link>
                    <div className="text-[11px] text-graphite-600">
                      {r.event_city}
                    </div>
                  </td>
                  <td>{r.organizer_nickname ?? "—"}</td>
                  <td>
                    <Link
                      href={`/users/${r.user_id}`}
                      className="text-lime hover:underline"
                    >
                      {r.user_nickname}
                    </Link>
                  </td>
                  <td className="font-mono text-[11px] text-graphite-600">
                    {shortId(r.public_qr_id)}
                  </td>
                  <td className="text-graphite-600">
                    {formatDate(r.attended_at ?? r.registered_at)}
                  </td>
                  <td>
                    <Badge
                      tone={
                        r.attendance_status === "confirmed" ? "lime" : "amber"
                      }
                    >
                      {r.attendance_status === "confirmed"
                        ? "Подтвержден"
                        : "Не подтвержден"}
                    </Badge>
                  </td>
                  <td className="tabular-nums">
                    {r.has_reward
                      ? `+${formatNumber(r.reward_amount)} CR`
                      : "—"}
                  </td>
                  <td>
                    {r.attendance_status !== "confirmed" ? (
                      <Button
                        className="h-7 px-2 text-[12px]"
                        disabled={confirmMut.isPending}
                        onClick={() => confirmMut.mutate(r.participant_id)}
                      >
                        Подтвердить
                      </Button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
