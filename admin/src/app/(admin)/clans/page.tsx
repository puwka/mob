"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ImageUploadField } from "@/components/ui/image-upload";
import {
  Avatar,
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchUsers } from "@/lib/api/admin";
import {
  addClanMember,
  deleteClan,
  fetchClanMembers,
  fetchClans,
  removeClanMember,
  upsertClan,
  type ClanRow,
} from "@/lib/api/content";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

export default function ClansPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<ClanRow | null | "new">(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const listQ = useQuery({
    queryKey: ["admin-clans", search],
    queryFn: () => fetchClans(search.trim() || undefined),
  });

  const membersQ = useQuery({
    queryKey: ["admin-clan-members", openId],
    queryFn: () => fetchClanMembers(openId!),
    enabled: !!openId,
  });

  const delMut = useMutation({
    mutationFn: deleteClan,
    onSuccess: async () => {
      setMsg("Клан удалён");
      await qc.invalidateQueries({ queryKey: ["admin-clans"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Кланы"
        description="Рейтинг клана = сумма XP участников (только отображение)"
        actions={
          <Button type="button" onClick={() => setEditing("new")}>
            Создать
          </Button>
        }
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <input
        className="admin-input mb-4 max-w-md"
        placeholder="Поиск по названию / TAG"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Кланы не найдены" />
      ) : null}

      {(listQ.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Эмблема</th>
                <th>Название</th>
                <th>TAG</th>
                <th>Город</th>
                <th>Лидер</th>
                <th>Участники</th>
                <th>Рейтинг</th>
                <th>Создан</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {listQ.data!.map((c) => (
                <tr key={c.id}>
                  <td>
                    <Avatar src={c.avatar_url} name={c.name} />
                  </td>
                  <td className="font-medium text-white">{c.name}</td>
                  <td>
                    <Badge tone="lime">{c.tag}</Badge>
                  </td>
                  <td className="text-graphite-400">{c.city || "—"}</td>
                  <td>
                    {c.leader_id ? (
                      <Link
                        href={`/users/${c.leader_id}`}
                        className="text-lime hover:underline"
                      >
                        {c.leader_nickname}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td className="tabular-nums">
                    {formatNumber(c.members_count)}
                  </td>
                  <td className="tabular-nums text-lime">
                    {formatNumber(c.rating)}
                  </td>
                  <td className="text-graphite-600">
                    {formatDate(c.created_at)}
                  </td>
                  <td>
                    <div className="flex flex-wrap gap-1">
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() =>
                          setOpenId((v) => (v === c.id ? null : c.id))
                        }
                      >
                        Состав
                      </Button>
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => setEditing(c)}
                      >
                        Изменить
                      </Button>
                      <Button
                        variant="danger"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => {
                          if (confirm("Удалить клан?")) delMut.mutate(c.id);
                        }}
                      >
                        Удалить
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {openId ? (
        <ClanMembersPanel
          clanId={openId}
          members={membersQ.data ?? []}
          loading={membersQ.isLoading}
          onClose={() => setOpenId(null)}
          onChanged={async () => {
            await qc.invalidateQueries({ queryKey: ["admin-clan-members", openId] });
            await qc.invalidateQueries({ queryKey: ["admin-clans"] });
          }}
        />
      ) : null}

      {editing ? (
        <ClanFormModal
          initial={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={async () => {
            setEditing(null);
            setMsg("Сохранено");
            await qc.invalidateQueries({ queryKey: ["admin-clans"] });
          }}
        />
      ) : null}
    </div>
  );
}

function ClanMembersPanel({
  clanId,
  members,
  loading,
  onClose,
  onChanged,
}: {
  clanId: string;
  members: Array<{
    user_id: string;
    nickname: string;
    avatar_url: string | null;
    city: string;
    rating: number;
    role: string;
  }>;
  loading: boolean;
  onClose: () => void;
  onChanged: () => Promise<void>;
}) {
  const [q, setQ] = useState("");
  const [userId, setUserId] = useState("");
  const usersQ = useQuery({
    queryKey: ["clan-add-users", q],
    queryFn: () => fetchUsers({ search: q || undefined, limit: 20 }),
    enabled: q.length >= 2,
  });

  return (
    <div className="mt-4 admin-card p-4">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-white">Состав клана</h3>
        <Button variant="ghost" className="h-7" onClick={onClose}>
          Закрыть
        </Button>
      </div>
      {loading ? <LoadingBlock /> : null}
      <div className="mb-3 flex flex-wrap gap-2">
        <input
          className="admin-input max-w-xs"
          placeholder="Добавить: поиск никнейма"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <select
          className="admin-input max-w-xs"
          value={userId}
          onChange={(e) => setUserId(e.target.value)}
        >
          <option value="">Пользователь</option>
          {(usersQ.data ?? []).map((u) => (
            <option key={u.id} value={u.id}>
              {u.nickname}
            </option>
          ))}
        </select>
        <Button
          type="button"
          disabled={!userId}
          onClick={async () => {
            await addClanMember(clanId, userId);
            setUserId("");
            await onChanged();
          }}
        >
          Добавить
        </Button>
      </div>
      <div className="divide-y divide-graphite-800">
        {members.map((m) => (
          <div
            key={m.user_id}
            className="flex items-center justify-between gap-3 py-2"
          >
            <div className="flex items-center gap-2">
              <Avatar src={m.avatar_url} name={m.nickname} />
              <div>
                <div className="text-sm text-white">
                  {m.nickname}{" "}
                  <Badge tone={m.role === "leader" ? "lime" : "neutral"}>
                    {m.role === "leader"
                      ? "Командир"
                      : m.role === "officer"
                        ? "Заместитель"
                        : m.role === "trainer"
                          ? "Тренер"
                          : "Боец"}
                  </Badge>
                </div>
                <div className="text-[12px] text-graphite-600">
                  {m.city} · XP {formatNumber(m.rating)}
                </div>
              </div>
            </div>
            <Button
              variant="danger"
              className="h-7 px-2 text-[12px]"
              onClick={async () => {
                await removeClanMember(clanId, m.user_id);
                await onChanged();
              }}
            >
              Удалить
            </Button>
          </div>
        ))}
      </div>
    </div>
  );
}

function ClanFormModal({
  initial,
  onClose,
  onSaved,
}: {
  initial: ClanRow | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [name, setName] = useState(initial?.name ?? "");
  const [tag, setTag] = useState(initial?.tag ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [city, setCity] = useState(initial?.city ?? "");
  const [avatarUrl, setAvatarUrl] = useState<string | null>(
    initial?.avatar_url ?? null,
  );
  const [leaderQ, setLeaderQ] = useState("");
  const [leaderId, setLeaderId] = useState(initial?.leader_id ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const usersQ = useQuery({
    queryKey: ["clan-leader-pick", leaderQ],
    queryFn: () => fetchUsers({ search: leaderQ || undefined, limit: 20 }),
    enabled: leaderQ.length >= 2 || !initial,
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="w-full max-w-lg rounded-lg border border-graphite-700 bg-graphite-900 p-4">
        <h2 className="mb-3 text-sm font-semibold text-white">
          {initial ? "Редактировать клан" : "Новый клан"}
        </h2>
        <div className="space-y-2">
          <input
            className="admin-input"
            placeholder="Название"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <input
            className="admin-input"
            placeholder="TAG"
            value={tag}
            onChange={(e) => setTag(e.target.value)}
          />
          <input
            className="admin-input"
            placeholder="Местоположение (город)"
            value={city}
            onChange={(e) => setCity(e.target.value)}
          />
          <textarea
            className="admin-input min-h-[70px]"
            placeholder="Описание"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
          <ImageUploadField
            bucket="clan-images"
            folder={leaderId || "admin"}
            value={avatarUrl}
            onChange={setAvatarUrl}
            label="Эмблема"
          />
          <div className="rounded border border-graphite-800 bg-graphite-950/40 px-3 py-2 text-[12px] text-graphite-600">
            Рейтинг клана считается автоматически как сумма XP участников.
            Ручное изменение недоступно.
          </div>
          {!initial || true ? (
            <>
              <input
                className="admin-input"
                placeholder="Поиск лидера"
                value={leaderQ}
                onChange={(e) => setLeaderQ(e.target.value)}
              />
              <select
                className="admin-input"
                value={leaderId}
                onChange={(e) => setLeaderId(e.target.value)}
              >
                <option value="">Лидер</option>
                {initial?.leader_id ? (
                  <option value={initial.leader_id}>
                    {initial.leader_nickname} (текущий)
                  </option>
                ) : null}
                {(usersQ.data ?? []).map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nickname}
                  </option>
                ))}
              </select>
            </>
          ) : null}
          {error ? <p className="text-[12px] text-red-300">{error}</p> : null}
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>
              Отмена
            </Button>
            <Button
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                setError(null);
                try {
                  await upsertClan({
                    id: initial?.id,
                    name,
                    tag,
                    description,
                    city: city.trim() || null,
                    avatarUrl,
                    clearAvatar: !avatarUrl,
                    leaderId: leaderId || undefined,
                  });
                  await onSaved();
                } catch (e) {
                  setError(e instanceof Error ? e.message : "Ошибка");
                } finally {
                  setBusy(false);
                }
              }}
            >
              Сохранить
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
