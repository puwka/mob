"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import {
  deleteConversation,
  fetchConversations,
  fetchMessages,
  setConversationStatus,
  softDeleteMessage,
  type ConversationRow,
} from "@/lib/api/final";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

const TYPE_LABEL: Record<string, string> = {
  market: "Барахолка",
  clan: "Кланы",
  user: "Пользователи",
};

export default function ChatsPage() {
  const qc = useQueryClient();
  const [type, setType] = useState("");
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<ConversationRow | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const listQ = useQuery({
    queryKey: ["admin-conversations", type, search],
    queryFn: () =>
      fetchConversations({
        type: type || undefined,
        search: search.trim() || undefined,
      }),
  });

  const messagesQ = useQuery({
    queryKey: ["admin-messages", selected?.id],
    queryFn: () => fetchMessages(selected!.id),
    enabled: !!selected,
  });

  const mut = useMutation({
    mutationFn: async (fn: () => Promise<unknown>) => fn(),
    onSuccess: async () => {
      setMsg("Готово");
      await qc.invalidateQueries({ queryKey: ["admin-conversations"] });
      await qc.invalidateQueries({ queryKey: ["admin-messages"] });
      await qc.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Диалоги"
        description="Модерация переписок (доступ только с permission dialogs, действия в audit log)"
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-4 flex flex-wrap gap-2">
        {["", "market", "clan", "user"].map((t) => (
          <Button
            key={t || "all"}
            variant={type === t ? "primary" : "ghost"}
            onClick={() => setType(t)}
          >
            {t ? TYPE_LABEL[t] : "Все"}
          </Button>
        ))}
        <input
          className="admin-input max-w-xs"
          placeholder="Поиск по участникам"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <div>
          {listQ.isLoading ? <LoadingBlock /> : null}
          {listQ.error ? (
            <ErrorBlock message={(listQ.error as Error).message} />
          ) : null}
          {!listQ.isLoading && !(listQ.data?.length) ? (
            <EmptyState message="Диалоги не найдены" />
          ) : null}
          <div className="admin-table-wrap">
            <table className="admin-table min-w-[640px]">
              <thead>
                <tr>
                  <th>Тип</th>
                  <th>Участники</th>
                  <th>Последнее</th>
                  <th>Дата</th>
                  <th>Сообщ.</th>
                  <th>Unread</th>
                  <th>Статус</th>
                </tr>
              </thead>
              <tbody>
                {(listQ.data ?? []).map((c) => (
                  <tr
                    key={c.id}
                    className={
                      selected?.id === c.id ? "bg-lime-soft/40" : "cursor-pointer"
                    }
                    onClick={() => setSelected(c)}
                  >
                    <td>
                      <Badge tone="neutral">{TYPE_LABEL[c.type] ?? c.type}</Badge>
                    </td>
                    <td className="max-w-[160px] truncate text-white">
                      {c.member_names ?? c.title ?? "—"}
                    </td>
                    <td className="max-w-[160px] truncate text-graphite-600">
                      {c.last_message ?? "—"}
                    </td>
                    <td className="text-graphite-600">
                      {formatDate(c.last_message_at ?? c.updated_at)}
                    </td>
                    <td className="tabular-nums">
                      {formatNumber(c.messages_count)}
                    </td>
                    <td className="tabular-nums">
                      {formatNumber(c.unread_approx)}
                    </td>
                    <td>
                      <Badge
                        tone={
                          c.status === "blocked"
                            ? "red"
                            : c.status === "archived"
                              ? "amber"
                              : "lime"
                        }
                      >
                        {c.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="admin-card flex min-h-[420px] flex-col">
          {!selected ? (
            <div className="flex flex-1 items-center justify-center p-6 text-sm text-graphite-600">
              Выберите диалог
            </div>
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-2 border-b border-graphite-700 px-3 py-2">
                <div className="min-w-0 flex-1 text-sm text-white">
                  {selected.member_names ?? selected.title ?? selected.id}
                </div>
                <Button
                  variant="ghost"
                  className="h-7 text-[12px]"
                  onClick={() =>
                    mut.mutate(() =>
                      setConversationStatus(selected.id, "blocked"),
                    )
                  }
                >
                  Блок
                </Button>
                <Button
                  variant="ghost"
                  className="h-7 text-[12px]"
                  onClick={() =>
                    mut.mutate(() =>
                      setConversationStatus(selected.id, "archived"),
                    )
                  }
                >
                  Архив
                </Button>
                <Button
                  variant="ghost"
                  className="h-7 text-[12px]"
                  onClick={() =>
                    mut.mutate(() =>
                      setConversationStatus(selected.id, "active"),
                    )
                  }
                >
                  Активен
                </Button>
                <Button
                  variant="danger"
                  className="h-7 text-[12px]"
                  onClick={() => {
                    if (confirm("Удалить диалог полностью?")) {
                      mut.mutate(async () => {
                        await deleteConversation(selected.id);
                        setSelected(null);
                      });
                    }
                  }}
                >
                  Удалить
                </Button>
              </div>
              <div className="flex-1 space-y-2 overflow-y-auto p-3">
                {messagesQ.isLoading ? <LoadingBlock /> : null}
                {(messagesQ.data ?? []).map((m) => (
                  <div
                    key={m.id}
                    className="rounded border border-graphite-800 bg-graphite-950/50 px-3 py-2"
                  >
                    <div className="mb-1 flex items-center justify-between gap-2">
                      <span className="text-[12px] font-medium text-lime">
                        {m.sender_nickname ?? "—"}
                      </span>
                      <span className="text-[11px] text-graphite-600">
                        {formatDate(m.created_at)}
                      </span>
                    </div>
                    {m.deleted_at ? (
                      <p className="text-sm italic text-graphite-600">
                        Сообщение удалено модератором.
                      </p>
                    ) : (
                      <p className="whitespace-pre-wrap text-sm text-white">
                        {m.text}
                      </p>
                    )}
                    {!m.deleted_at ? (
                      <Button
                        variant="ghost"
                        className="mt-1 h-6 px-2 text-[11px]"
                        onClick={() =>
                          mut.mutate(() => softDeleteMessage(m.id))
                        }
                      >
                        Удалить сообщение
                      </Button>
                    ) : null}
                  </div>
                ))}
                {!messagesQ.isLoading && !(messagesQ.data?.length) ? (
                  <EmptyState message="Нет сообщений" />
                ) : null}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
