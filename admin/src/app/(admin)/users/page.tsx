"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Avatar,
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { CITIES } from "@/lib/constants";
import { fetchClans, fetchUsers } from "@/lib/api/admin";
import { formatDate, formatNumber } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useMemo, useState } from "react";

export default function UsersPage() {
  const [search, setSearch] = useState("");
  const [role, setRole] = useState("");
  const [city, setCity] = useState("");
  const [status, setStatus] = useState("");
  const [clanId, setClanId] = useState("");

  const clansQuery = useQuery({
    queryKey: ["admin-clans"],
    queryFn: fetchClans,
  });

  const params = useMemo(
    () => ({
      search: search.trim() || undefined,
      role: role || undefined,
      city: city || undefined,
      status: status || undefined,
      clanId: clanId || undefined,
    }),
    [search, role, city, status, clanId],
  );

  const usersQuery = useQuery({
    queryKey: ["admin-users", params],
    queryFn: () => fetchUsers(params),
  });

  return (
    <div>
      <PageHeader
        title="Пользователи"
        description="Управление профилями, ролями и статусами"
      />

      <div className="mb-4 grid gap-2 md:grid-cols-5">
        <input
          className="admin-input md:col-span-2"
          placeholder="Поиск: ник или телефон"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="admin-input"
          value={role}
          onChange={(e) => setRole(e.target.value)}
        >
          <option value="">Роль: все</option>
          <option value="user">user</option>
          <option value="organizer">organizer</option>
        </select>
        <select
          className="admin-input"
          value={city}
          onChange={(e) => setCity(e.target.value)}
        >
          <option value="">Город: все</option>
          {CITIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        <select
          className="admin-input"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">Статус: все</option>
          <option value="active">active</option>
          <option value="blocked">blocked</option>
        </select>
        <select
          className="admin-input md:col-span-2"
          value={clanId}
          onChange={(e) => setClanId(e.target.value)}
        >
          <option value="">Клан: все</option>
          {(clansQuery.data ?? []).map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
        <div className="md:col-span-3 flex justify-end">
          <Button
            variant="ghost"
            type="button"
            onClick={() => {
              setSearch("");
              setRole("");
              setCity("");
              setStatus("");
              setClanId("");
            }}
          >
            Сбросить
          </Button>
        </div>
      </div>

      {usersQuery.isLoading ? <LoadingBlock /> : null}
      {usersQuery.error ? (
        <ErrorBlock message={(usersQuery.error as Error).message} />
      ) : null}

      {!usersQuery.isLoading && (usersQuery.data?.length ?? 0) === 0 ? (
        <EmptyState message="Пользователи не найдены" />
      ) : null}

      {(usersQuery.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Avatar</th>
                <th>Nickname</th>
                <th>Phone</th>
                <th>City</th>
                <th>Role</th>
                <th>Rating</th>
                <th>Clan</th>
                <th>Created</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {usersQuery.data!.map((u) => (
                <tr key={u.id}>
                  <td>
                    <Avatar src={u.avatar_url} name={u.nickname} />
                  </td>
                  <td>
                    <Link
                      href={`/users/${u.id}`}
                      className="font-medium text-lime hover:underline"
                    >
                      {u.nickname}
                    </Link>
                  </td>
                  <td className="font-mono text-[12px] text-graphite-600">
                    {u.phone}
                  </td>
                  <td>{u.city}</td>
                  <td>
                    <Badge tone={u.role === "organizer" ? "blue" : "neutral"}>
                      {u.role}
                    </Badge>
                  </td>
                  <td className="tabular-nums">{formatNumber(u.rating)}</td>
                  <td>{u.clan_name ?? "—"}</td>
                  <td className="text-graphite-600">{formatDate(u.created_at)}</td>
                  <td>
                    <Badge tone={u.status === "blocked" ? "red" : "lime"}>
                      {u.status}
                    </Badge>
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
