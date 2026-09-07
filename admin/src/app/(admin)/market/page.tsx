"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ImageUploadField } from "@/components/ui/image-upload";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchUsers } from "@/lib/api/admin";
import {
  deleteListing,
  fetchCategories,
  fetchCities,
  fetchListingImages,
  fetchListings,
  setListingImages,
  upsertListing,
  type ListingRow,
} from "@/lib/api/content";
import { LISTING_STATUSES } from "@/lib/constants";
import { formatDate, formatNumber } from "@/lib/utils";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useMemo, useState } from "react";

export default function MarketPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [city, setCity] = useState("");
  const [status, setStatus] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [priceMin, setPriceMin] = useState("");
  const [priceMax, setPriceMax] = useState("");
  const [editing, setEditing] = useState<ListingRow | null | "new">(null);
  const [msg, setMsg] = useState<string | null>(null);

  const citiesQ = useQuery({ queryKey: ["cities"], queryFn: () => fetchCities() });
  const catsQ = useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
  });

  const params = useMemo(
    () => ({
      search: search.trim() || undefined,
      city: city || undefined,
      status: status || undefined,
      categoryId: categoryId || undefined,
      priceMin: priceMin ? Number(priceMin) : undefined,
      priceMax: priceMax ? Number(priceMax) : undefined,
    }),
    [search, city, status, categoryId, priceMin, priceMax],
  );

  const listQ = useQuery({
    queryKey: ["admin-listings", params],
    queryFn: () => fetchListings(params),
  });

  const delMut = useMutation({
    mutationFn: deleteListing,
    onSuccess: async () => {
      setMsg("Удалено");
      await qc.invalidateQueries({ queryKey: ["admin-listings"] });
    },
    onError: (e: Error) => setMsg(e.message),
  });

  return (
    <div>
      <PageHeader
        title="Барахолка"
        description="Объявления и модерация"
        actions={
          <div className="flex gap-2">
            <Link href="/market/moderation" className="admin-btn-ghost">
              Модерация
            </Link>
            <Button type="button" onClick={() => setEditing("new")}>
              Создать
            </Button>
          </div>
        }
      />
      {msg ? (
        <div className="mb-3 rounded border border-graphite-700 px-3 py-2 text-sm text-lime">
          {msg}
        </div>
      ) : null}

      <div className="mb-4 grid gap-2 md:grid-cols-3 xl:grid-cols-6">
        <input
          className="admin-input md:col-span-2"
          placeholder="Поиск"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select className="admin-input" value={city} onChange={(e) => setCity(e.target.value)}>
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
          {LISTING_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <select
          className="admin-input"
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
        >
          <option value="">Категория</option>
          {(catsQ.data ?? []).map((c) => (
            <option key={c.id} value={c.id}>
              {c.parent_id ? "— " : ""}
              {c.name}
            </option>
          ))}
        </select>
        <div className="flex gap-1">
          <input
            className="admin-input"
            placeholder="Цена от"
            value={priceMin}
            onChange={(e) => setPriceMin(e.target.value)}
          />
          <input
            className="admin-input"
            placeholder="до"
            value={priceMax}
            onChange={(e) => setPriceMax(e.target.value)}
          />
        </div>
      </div>

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Объявления не найдены" />
      ) : null}

      {(listQ.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Фото</th>
                <th>Название</th>
                <th>Продавец</th>
                <th>Цена</th>
                <th>Категория</th>
                <th>Город</th>
                <th>Статус</th>
                <th>Просмотры</th>
                <th>Дата</th>
                <th>Продвижение</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {listQ.data!.map((l) => (
                <tr key={l.id}>
                  <td>
                    {l.cover_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={l.cover_url}
                        alt=""
                        className="h-10 w-10 rounded object-cover"
                      />
                    ) : (
                      <div className="h-10 w-10 rounded bg-graphite-700" />
                    )}
                  </td>
                  <td className="max-w-[180px] truncate text-white">{l.title}</td>
                  <td>
                    <Link
                      href={`/users/${l.seller_id}`}
                      className="text-lime hover:underline"
                    >
                      {l.seller_nickname}
                    </Link>
                  </td>
                  <td className="tabular-nums">{formatNumber(l.price)}</td>
                  <td>{l.category_name}</td>
                  <td>{l.city}</td>
                  <td>
                    <Badge
                      tone={
                        l.status === "active"
                          ? "lime"
                          : l.status === "rejected"
                            ? "red"
                            : l.status === "pending"
                              ? "amber"
                              : "neutral"
                      }
                    >
                      {l.status}
                    </Badge>
                  </td>
                  <td className="tabular-nums">{formatNumber(l.views_count)}</td>
                  <td className="text-graphite-600">{formatDate(l.created_at)}</td>
                  <td>
                    {l.is_promoted ? (
                      <Badge tone="blue">promo</Badge>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => setEditing(l)}
                      >
                        Изменить
                      </Button>
                      <Button
                        variant="danger"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => {
                          if (confirm("Удалить объявление?"))
                            delMut.mutate(l.id);
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

      {editing ? (
        <ListingFormModal
          initial={editing === "new" ? null : editing}
          categories={catsQ.data ?? []}
          cities={(citiesQ.data ?? []).map((c) => c.name)}
          onClose={() => setEditing(null)}
          onSaved={async () => {
            setEditing(null);
            setMsg("Сохранено");
            await qc.invalidateQueries({ queryKey: ["admin-listings"] });
          }}
        />
      ) : null}
    </div>
  );
}

function ListingFormModal({
  initial,
  categories,
  cities,
  onClose,
  onSaved,
}: {
  initial: ListingRow | null;
  categories: Array<{ id: string; name: string; parent_id: string | null }>;
  cities: string[];
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [title, setTitle] = useState(initial?.title ?? "");
  const [description, setDescription] = useState("");
  const [price, setPrice] = useState(initial?.price ?? 0);
  const [city, setCity] = useState(initial?.city ?? cities[0] ?? "Москва");
  const [categoryId, setCategoryId] = useState(
    initial?.category_id ?? categories[0]?.id ?? "",
  );
  const [status, setStatus] = useState(initial?.status ?? "pending");
  const [condition, setCondition] = useState(initial?.condition ?? "used");
  const [sellerQ, setSellerQ] = useState("");
  const [sellerId, setSellerId] = useState(initial?.seller_id ?? "");
  const [imageUrl, setImageUrl] = useState<string | null>(
    initial?.cover_url ?? null,
  );
  const [extraUrls, setExtraUrls] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const usersQ = useQuery({
    queryKey: ["listing-seller", sellerQ],
    queryFn: () => fetchUsers({ search: sellerQ || undefined, limit: 20 }),
    enabled: sellerQ.length >= 2,
  });

  useQuery({
    queryKey: ["listing-images", initial?.id],
    queryFn: async () => {
      if (!initial?.id) return [];
      const imgs = await fetchListingImages(initial.id);
      setExtraUrls(imgs.map((i) => i.url));
      if (imgs[0]) setImageUrl(imgs[0].url);
      return imgs;
    },
    enabled: !!initial?.id,
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-lg border border-graphite-700 bg-graphite-900 p-4">
        <h2 className="mb-3 text-sm font-semibold text-white">
          {initial ? "Редактировать объявление" : "Новое объявление"}
        </h2>
        <div className="space-y-2">
          <input
            className="admin-input"
            placeholder="Название"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
          <textarea
            className="admin-input min-h-[70px]"
            placeholder="Описание"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
          <input
            className="admin-input"
            type="number"
            value={price}
            onChange={(e) => setPrice(Number(e.target.value))}
          />
          <select
            className="admin-input"
            value={city}
            onChange={(e) => setCity(e.target.value)}
          >
            {cities.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          <select
            className="admin-input"
            value={categoryId}
            onChange={(e) => setCategoryId(e.target.value)}
          >
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.parent_id ? "— " : ""}
                {c.name}
              </option>
            ))}
          </select>
          <select
            className="admin-input"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
          >
            {LISTING_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
          <select
            className="admin-input"
            value={condition}
            onChange={(e) => setCondition(e.target.value)}
          >
            <option value="new">new</option>
            <option value="like_new">like_new</option>
            <option value="used">used</option>
          </select>
          <input
            className="admin-input"
            placeholder="Поиск продавца"
            value={sellerQ}
            onChange={(e) => setSellerQ(e.target.value)}
          />
          <select
            className="admin-input"
            value={sellerId}
            onChange={(e) => setSellerId(e.target.value)}
          >
            <option value="">Продавец</option>
            {initial ? (
              <option value={initial.seller_id}>
                {initial.seller_nickname}
              </option>
            ) : null}
            {(usersQ.data ?? []).map((u) => (
              <option key={u.id} value={u.id}>
                {u.nickname}
              </option>
            ))}
          </select>
          <ImageUploadField
            bucket="listing-images"
            folder={sellerId || "admin"}
            value={imageUrl}
            onChange={(url) => {
              setImageUrl(url);
              if (url) setExtraUrls((prev) => [url, ...prev.filter((u) => u !== url)]);
              else setExtraUrls([]);
            }}
            label="Фото (обложка)"
          />
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
                  const row = await upsertListing({
                    id: initial?.id,
                    title,
                    description: description || undefined,
                    price,
                    city,
                    categoryId,
                    status,
                    condition,
                    sellerId: sellerId || undefined,
                    clearRejection: status === "active",
                  });
                  const urls = extraUrls.length
                    ? extraUrls
                    : imageUrl
                      ? [imageUrl]
                      : [];
                  if (urls.length) {
                    await setListingImages(row.id ?? initial!.id, urls);
                  }
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
