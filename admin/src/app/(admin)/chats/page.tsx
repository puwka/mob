"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { usePermissions } from "@/hooks/use-permissions";
import {
  deleteConversation,
  fetchConversationMutes,
  fetchConversations,
  fetchMessages,
  muteCityUser,
  setConversationStatus,
  softDeleteMessage,
  unmuteCityUser,
  type ConversationRow,
} from "@/lib/api/final";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";

const TYPE_LABEL: Record<string, string> = {
  market: "Барахолка",
  clan: "Кланы",
  user: "Пользователи",
  city: "Города",
};

export default function ChatsPage() {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const cityOnly = can("dialogs") && !can("market") && !can("users");
  const [type, setType] = useState(cityOnly ? "city" : "");
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<ConversationRow | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [muteMinutes, setMuteMinutes] = useState("60");
  const [muteReason, setMuteReason] = useState("");

  useEffect(() => {
    if (cityOnly) setType("city");
  }, [cityOnly]);

  const effectiveType = cityOnly ? "city" : type;

  const typeFilters = useMemo(
    () => (cityOnly ? ["city"] : ["", "market", "clan", "user", "city"]),
    [cityOnly],
  );

  const listQ = useQuery({
    queryKey: ["admin-conversations", effectiveType, search],
    queryFn: () =>
      fetchConversations({
        type: effectiveType || undefined,
        search: search.trim() || undefined,
      }),
  });

  const messagesQ = useQuery({
    queryKey: ["admin-messages", selected?.id],
    queryFn: () => fetchMessages(selected!.id),
    enabled: !!selected,
  });

  const mutesQ = useQuery({
    queryKey: ["admin-mutes", selected?.id],
    queryFn: () => fetchConversationMutes(selected!.id),
    enabled: !!selected && selected.type === "city",
  });

  const mut = useMutation({
    mutationFn: async (fn: () => Promise<unknown>) => fn(),
    onSuccess: async () => {
      setMsg("Готово");
      await qc.invalidateQueries({ queryKey: ["admin-conversations"] });
      await qc.invalidateQueries({ queryKey: ["admin-messages"] });
      await qc.invalidateQueries({ queryKey: ["admin-mutes"] });
      await qc.invalidateQueries({ queryKey: ["admin-audit-logs"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Диалоги"
        description={
          cityOnly
            ? "Модератор: только городские чаты, мут пользователей и удаление сообщений"
            : "Модерация переписок (доступ только с permission dialogs, действия в audit log)"
        }
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-4 flex flex-wrap gap-2">
        {typeFilters.map((t) => (
          <Button
            key={t || "all"}
            variant={effectiveType === t ? "primary" : "ghost"}
            onClick={() => !cityOnly && setType(t)}
            disabled={cityOnly && t !== "city"}
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
                {!cityOnly ? (
                  <>
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
                  </>
                ) : null}
              </div>

              {selected.type === "city" ? (
                <div className="space-y-2 border-b border-graphite-700 px-3 py-2">
                  <div className="text-[12px] font-medium text-lime">Муты</div>
                  <div className="flex flex-wrap gap-2">
                    <input
                      className="admin-input w-24"
                      value={muteMinutes}
                      onChange={(e) => setMuteMinutes(e.target.value)}
                      placeholder="мин"
                      title="Минуты (пусто = бессрочно)"
                    />
                    <input
                      className="admin-input min-w-[140px] flex-1"
                      value={muteReason}
                      onChange={(e) => setMuteReason(e.target.value)}
                      placeholder="Причина"
                    />
                  </div>
                  {(mutesQ.data ?? []).length ? (
                    <div className="space-y-1">
                      {(mutesQ.data ?? []).map((m) => (
                        <div
                          key={m.id}
                          className="flex items-center justify-between gap-2 text-[12px] text-graphite-600"
                        >
                          <span className="text-white">
                            {m.nickname ?? m.user_id}
                            {m.muted_until
                              ? ` до ${formatDate(m.muted_until)}`
                              : " бессрочно"}
                          </span>
                          <Button
                            variant="ghost"
                            className="h-6 px-2 text-[11px]"
                            onClick={() =>
                              mut.mutate(() =>
                                unmuteCityUser({
                                  conversationId: selected.id,
                                  userId: m.user_id,
                                }),
                              )
                            }
                          >
                            Снять
                          </Button>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="text-[11px] text-graphite-600">
                      Активных мутов нет — выберите отправителя ниже
                    </div>
                  )}
                </div>
              ) : null}

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
                    <div className="mt-1 flex flex-wrap gap-1">
                      {!m.deleted_at ? (
                        <Button
                          variant="ghost"
                          className="h-6 px-2 text-[11px]"
                          onClick={() =>
                            mut.mutate(() => softDeleteMessage(m.id))
                          }
                        >
                          Удалить сообщение
                        </Button>
                      ) : null}
                      {selected.type === "city" ? (
                        <Button
                          variant="ghost"
                          className="h-6 px-2 text-[11px]"
                          onClick={() => {
                            const mins = Number.parseInt(muteMinutes, 10);
                            mut.mutate(() =>
                              muteCityUser({
                                conversationId: selected.id,
                                userId: m.sender_id,
                                minutes: Number.isFinite(mins) && mins > 0
                                  ? mins
                                  : null,
                                reason: muteReason.trim() || undefined,
                              }),
                            );
                          }}
                        >
                          Мут
                        </Button>
                      ) : null}
                    </div>
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
