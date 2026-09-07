"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchListings, moderateListing } from "@/lib/api/content";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

export default function ModerationPage() {
  const qc = useQueryClient();
  const [msg, setMsg] = useState<string | null>(null);
  const [rejectId, setRejectId] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  const listQ = useQuery({
    queryKey: ["moderation-pending"],
    queryFn: () => fetchListings({ status: "pending", limit: 100 }),
  });

  const mut = useMutation({
    mutationFn: ({
      id,
      action,
      reason,
    }: {
      id: string;
      action: "approve" | "reject" | "archive" | "restore";
      reason?: string;
    }) => moderateListing(id, action, reason),
    onSuccess: async () => {
      setMsg("Обновлено");
      setRejectId(null);
      setReason("");
      await qc.invalidateQueries({ queryKey: ["moderation-pending"] });
      await qc.invalidateQueries({ queryKey: ["admin-listings"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Модерация объявлений"
        description="Очередь pending → одобрить / отклонить / архивировать"
        actions={
          <Link href="/market" className="admin-btn-ghost">
            ← Барахолка
          </Link>
        }
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Нет объявлений на модерации" />
      ) : null}

      <div className="space-y-3">
        {(listQ.data ?? []).map((l) => (
          <div key={l.id} className="admin-card flex flex-wrap gap-4 p-4">
            {l.cover_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={l.cover_url}
                alt=""
                className="h-20 w-20 rounded object-cover"
              />
            ) : (
              <div className="h-20 w-20 rounded bg-graphite-700" />
            )}
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium text-white">{l.title}</span>
                <Badge tone="amber">{l.status}</Badge>
              </div>
              <div className="mt-1 text-sm text-graphite-600">
                {l.seller_nickname} · {l.city} · {l.category_name} ·{" "}
                {formatNumber(l.price)} ₽ · {formatDate(l.created_at)}
              </div>
              {rejectId === l.id ? (
                <div className="mt-2 flex flex-wrap gap-2">
                  <input
                    className="admin-input max-w-md"
                    placeholder="Причина отклонения"
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                  />
                  <Button
                    variant="danger"
                    disabled={!reason.trim() || mut.isPending}
                    onClick={() =>
                      mut.mutate({
                        id: l.id,
                        action: "reject",
                        reason: reason.trim(),
                      })
                    }
                  >
                    Отклонить
                  </Button>
                  <Button variant="ghost" onClick={() => setRejectId(null)}>
                    Отмена
                  </Button>
                </div>
              ) : (
                <div className="mt-2 flex flex-wrap gap-2">
                  <Button
                    onClick={() => mut.mutate({ id: l.id, action: "approve" })}
                    disabled={mut.isPending}
                  >
                    Одобрить
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => {
                      setRejectId(l.id);
                      setReason("");
                    }}
                  >
                    Отклонить
                  </Button>
                  <Button
                    variant="ghost"
                    onClick={() => mut.mutate({ id: l.id, action: "archive" })}
                  >
                    Архивировать
                  </Button>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
