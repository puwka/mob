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
import { fetchOrganizers, setAppRole, setUserStatus } from "@/lib/api/admin";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useMemo, useState } from "react";

export default function OrganizersPage() {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const queryClient = useQueryClient();

  const params = useMemo(
    () => ({
      search: search.trim() || undefined,
      status: status || undefined,
    }),
    [search, status],
  );

  const query = useQuery({
    queryKey: ["admin-organizers", params],
    queryFn: () => fetchOrganizers(params),
  });

  const demote = useMutation({
    mutationFn: (id: string) => setAppRole(id, "user"),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin-organizers"] });
      await queryClient.invalidateQueries({ queryKey: ["admin-users"] });
    },
  });

  const block = useMutation({
    mutationFn: ({
      id,
      next,
    }: {
      id: string;
      next: "active" | "blocked";
    }) => setUserStatus(id, next),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin-organizers"] });
    },
  });

  return (
    <div>
      <PageHeader
        title="Организаторы"
        description="Назначение, баланс, мероприятия и статус"
        actions={
          <Link href="/users" className="admin-btn-ghost">
            Назначить из пользователей
          </Link>
        }
      />

      <div className="mb-4 grid gap-2 md:grid-cols-3">
        <input
          className="admin-input md:col-span-2"
          placeholder="Поиск"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="admin-input"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">Статус: все</option>
          <option value="active">active</option>
          <option value="blocked">blocked</option>
        </select>
      </div>

      {query.isLoading ? <LoadingBlock /> : null}
      {query.error ? (
        <ErrorBlock message={(query.error as Error).message} />
      ) : null}
      {!query.isLoading && (query.data?.length ?? 0) === 0 ? (
        <EmptyState message="Организаторы не найдены" />
      ) : null}

      {(query.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Avatar</th>
                <th>Имя</th>
                <th>City</th>
                <th>Мероприятия</th>
                <th>Участники</th>
                <th>Balance</th>
                <th>Регистрация</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {query.data!.map((o) => (
                <tr key={o.id}>
                  <td>
                    <Avatar src={o.avatar_url} name={o.nickname} />
                  </td>
                  <td>
                    <Link
                      href={`/users/${o.id}`}
                      className="font-medium text-lime hover:underline"
                    >
                      {o.nickname}
                    </Link>
                  </td>
                  <td>{o.city}</td>
                  <td className="tabular-nums">
                    {formatNumber(o.events_count)}
                  </td>
                  <td className="tabular-nums">
                    {formatNumber(o.participants_count)}
                  </td>
                  <td className="tabular-nums text-lime">
                    {formatNumber(o.balance)}
                  </td>
                  <td className="text-graphite-600">
                    {formatDate(o.created_at)}
                  </td>
                  <td>
                    <Badge tone={o.status === "blocked" ? "red" : "lime"}>
                      {o.status}
                    </Badge>
                  </td>
                  <td>
                    <div className="flex flex-wrap gap-1">
                      <Link
                        href={`/users/${o.id}`}
                        className="admin-btn-ghost h-7 px-2 text-[12px]"
                      >
                        Профиль
                      </Link>
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => demote.mutate(o.id)}
                        disabled={demote.isPending}
                      >
                        Снять роль
                      </Button>
                      <Button
                        variant="danger"
                        className="h-7 px-2 text-[12px]"
                        onClick={() =>
                          block.mutate({
                            id: o.id,
                            next:
                              o.status === "blocked" ? "active" : "blocked",
                          })
                        }
                        disabled={block.isPending}
                      >
                        {o.status === "blocked" ? "Разблок." : "Блок"}
                      </Button>
                    </div>
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
