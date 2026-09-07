"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Avatar,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import {
  fetchCities,
  fetchRankingClans,
  fetchRankingPlayers,
  setPlayerRating,
} from "@/lib/api/content";
import { formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

export default function RankingPage() {
  const [tab, setTab] = useState<"players" | "clans">("players");
  const [scope, setScope] = useState<"global" | "regional">("global");
  const [city, setCity] = useState("Москва");
  const [msg, setMsg] = useState<string | null>(null);
  const qc = useQueryClient();

  const citiesQ = useQuery({
    queryKey: ["cities"],
    queryFn: () => fetchCities(true),
  });

  const filterCity = scope === "regional" ? city : null;

  const playersQ = useQuery({
    queryKey: ["ranking-players", filterCity],
    queryFn: () => fetchRankingPlayers(filterCity, 100),
    enabled: tab === "players",
  });

  const clansQ = useQuery({
    queryKey: ["ranking-clans", filterCity],
    queryFn: () => fetchRankingClans(filterCity, 100),
    enabled: tab === "clans",
  });

  const ratingMut = useMutation({
    mutationFn: ({ id, rating }: { id: string; rating: number }) =>
      setPlayerRating(id, rating),
    onSuccess: async () => {
      setMsg("Рейтинг обновлён · клан пересчитается автоматически");
      await qc.invalidateQueries({ queryKey: ["ranking-players"] });
      await qc.invalidateQueries({ queryKey: ["ranking-clans"] });
      await qc.invalidateQueries({ queryKey: ["admin-clans"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  const topPlayers = (playersQ.data ?? []).slice(0, 3);
  const topClans = (clansQ.data ?? []).slice(0, 3);

  return (
    <div>
      <PageHeader
        title="Рейтинг"
        description="Личный рейтинг редактируется; рейтинг клана = сумма участников"
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-4 flex flex-wrap gap-2">
        <Button
          variant={tab === "players" ? "primary" : "ghost"}
          onClick={() => setTab("players")}
        >
          Игроки
        </Button>
        <Button
          variant={tab === "clans" ? "primary" : "ghost"}
          onClick={() => setTab("clans")}
        >
          Кланы
        </Button>
        <div className="mx-2 h-8 w-px bg-graphite-700" />
        <Button
          variant={scope === "global" ? "primary" : "ghost"}
          onClick={() => setScope("global")}
        >
          Общий
        </Button>
        <Button
          variant={scope === "regional" ? "primary" : "ghost"}
          onClick={() => setScope("regional")}
        >
          Региональный
        </Button>
        {scope === "regional" ? (
          <select
            className="admin-input max-w-[180px]"
            value={city}
            onChange={(e) => setCity(e.target.value)}
          >
            {(citiesQ.data ?? []).map((c) => (
              <option key={c.id} value={c.name}>
                {c.name}
              </option>
            ))}
          </select>
        ) : null}
      </div>

      {tab === "players" ? (
        <>
          <Top3
            items={topPlayers.map((p) => ({
              id: p.id,
              title: p.nickname,
              subtitle: p.city,
              value: p.rating,
              avatar: p.avatar_url,
              rank: p.rank,
              href: `/users/${p.id}`,
            }))}
          />
          {playersQ.isLoading ? <LoadingBlock /> : null}
          {playersQ.error ? (
            <ErrorBlock message={(playersQ.error as Error).message} />
          ) : null}
          <div className="admin-table-wrap mt-4">
            <table className="admin-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th></th>
                  <th>Игрок</th>
                  <th>Город</th>
                  <th>Рейтинг</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {(playersQ.data ?? []).map((p) => (
                  <tr key={p.id}>
                    <td className="tabular-nums text-graphite-600">{p.rank}</td>
                    <td>
                      <Avatar src={p.avatar_url} name={p.nickname} />
                    </td>
                    <td>
                      <Link
                        href={`/users/${p.id}`}
                        className="text-lime hover:underline"
                      >
                        {p.nickname}
                      </Link>
                    </td>
                    <td>{p.city}</td>
                    <td className="tabular-nums font-medium text-white">
                      {formatNumber(p.rating)}
                    </td>
                    <td>
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => {
                          const next = prompt(
                            "Новый рейтинг игрока",
                            String(p.rating),
                          );
                          if (next == null) return;
                          const n = Number(next);
                          if (Number.isNaN(n) || n < 0) {
                            setMsg("Некорректное значение");
                            return;
                          }
                          ratingMut.mutate({ id: p.id, rating: n });
                        }}
                      >
                        Изменить
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      ) : (
        <>
          <Top3
            items={topClans.map((c) => ({
              id: c.id,
              title: c.name,
              subtitle: c.tag,
              value: c.rating,
              avatar: c.avatar_url,
              rank: c.rank,
              href: `/clans`,
            }))}
          />
          {clansQ.isLoading ? <LoadingBlock /> : null}
          {clansQ.error ? (
            <ErrorBlock message={(clansQ.error as Error).message} />
          ) : null}
          <div className="admin-table-wrap mt-4">
            <table className="admin-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th></th>
                  <th>Клан</th>
                  <th>TAG</th>
                  <th>Участники</th>
                  <th>Рейтинг</th>
                </tr>
              </thead>
              <tbody>
                {(clansQ.data ?? []).map((c) => (
                  <tr key={c.id}>
                    <td className="tabular-nums text-graphite-600">{c.rank}</td>
                    <td>
                      <Avatar src={c.avatar_url} name={c.name} />
                    </td>
                    <td className="text-white">{c.name}</td>
                    <td>
                      <Badge tone="lime">{c.tag}</Badge>
                    </td>
                    <td className="tabular-nums">
                      {formatNumber(c.members_count)}
                    </td>
                    <td className="tabular-nums text-lime">
                      {formatNumber(c.rating)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-[12px] text-graphite-600">
            Рейтинг клана нельзя менять вручную — он пересчитывается при изменении
            личного рейтинга или состава.
          </p>
        </>
      )}
    </div>
  );
}

function Top3({
  items,
}: {
  items: Array<{
    id: string;
    title: string;
    subtitle: string;
    value: number;
    avatar: string | null;
    rank: number;
    href: string;
  }>;
}) {
  if (!items.length) return null;
  return (
    <div className="mb-4 grid gap-2 sm:grid-cols-3">
      {items.map((item) => (
        <Link
          key={item.id}
          href={item.href}
          className="admin-card flex items-center gap-3 px-3 py-3 hover:border-lime/40"
        >
          <div className="text-lg font-semibold text-lime">#{item.rank}</div>
          <Avatar src={item.avatar} name={item.title} size={40} />
          <div className="min-w-0">
            <div className="truncate font-medium text-white">{item.title}</div>
            <div className="text-[12px] text-graphite-600">{item.subtitle}</div>
            <div className="tabular-nums text-sm text-lime">
              {formatNumber(item.value)}
            </div>
          </div>
        </Link>
      ))}
    </div>
  );
}
