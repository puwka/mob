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
  deleteCategory,
  deleteCity,
  fetchCategories,
  fetchCities,
  upsertCategory,
  upsertCity,
  type CategoryRow,
  type CityRow,
} from "@/lib/api/content";
import { APP_ROLES, EVENT_STATUSES, LISTING_STATUSES, USER_STATUSES } from "@/lib/constants";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";

type Tab = "cities" | "categories" | "statuses";

export default function DictionariesPage() {
  const [tab, setTab] = useState<Tab>("cities");

  return (
    <div>
      <PageHeader
        title="Справочники"
        description="Города, категории и справочные статусы приложения"
      />
      <div className="mb-4 flex flex-wrap gap-2">
        {(
          [
            ["cities", "Города"],
            ["categories", "Категории"],
            ["statuses", "Роли и статусы"],
          ] as const
        ).map(([id, label]) => (
          <Button
            key={id}
            variant={tab === id ? "primary" : "ghost"}
            onClick={() => setTab(id)}
          >
            {label}
          </Button>
        ))}
      </div>
      {tab === "cities" ? <CitiesPanel /> : null}
      {tab === "categories" ? <CategoriesPanel /> : null}
      {tab === "statuses" ? <StatusesPanel /> : null}
    </div>
  );
}

function CitiesPanel() {
  const qc = useQueryClient();
  const [name, setName] = useState("");
  const [editing, setEditing] = useState<CityRow | null>(null);
  const listQ = useQuery({
    queryKey: ["cities-all"],
    queryFn: () => fetchCities(true),
  });

  const saveMut = useMutation({
    mutationFn: upsertCity,
    onSuccess: async () => {
      setName("");
      setEditing(null);
      await qc.invalidateQueries({ queryKey: ["cities"] });
      await qc.invalidateQueries({ queryKey: ["cities-all"] });
    },
  });

  const delMut = useMutation({
    mutationFn: deleteCity,
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ["cities"] });
      await qc.invalidateQueries({ queryKey: ["cities-all"] });
    },
  });

  return (
    <div>
      <div className="mb-3 flex flex-wrap gap-2">
        <input
          className="admin-input max-w-xs"
          placeholder="Название города"
          value={editing ? editing.name : name}
          onChange={(e) =>
            editing
              ? setEditing({ ...editing, name: e.target.value })
              : setName(e.target.value)
          }
        />
        <Button
          onClick={() =>
            saveMut.mutate(
              editing
                ? {
                    id: editing.id,
                    name: editing.name,
                    sort_order: editing.sort_order,
                    is_active: editing.is_active,
                  }
                : { name, sort_order: (listQ.data?.length ?? 0) + 1 },
            )
          }
          disabled={saveMut.isPending}
        >
          {editing ? "Сохранить" : "Добавить"}
        </Button>
        {editing ? (
          <Button variant="ghost" onClick={() => setEditing(null)}>
            Отмена
          </Button>
        ) : null}
      </div>
      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}
      {!listQ.isLoading && !(listQ.data?.length) ? (
        <EmptyState message="Городов нет" />
      ) : null}
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Название</th>
              <th>Порядок</th>
              <th>Активен</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(listQ.data ?? []).map((c) => (
              <tr key={c.id}>
                <td className="text-white">{c.name}</td>
                <td>{c.sort_order}</td>
                <td>
                  <Badge tone={c.is_active ? "lime" : "red"}>
                    {c.is_active ? "on" : "off"}
                  </Badge>
                </td>
                <td>
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      className="h-7 px-2 text-[12px]"
                      onClick={() => setEditing(c)}
                    >
                      Изменить
                    </Button>
                    <Button
                      variant="ghost"
                      className="h-7 px-2 text-[12px]"
                      onClick={() =>
                        saveMut.mutate({
                          id: c.id,
                          name: c.name,
                          sort_order: c.sort_order,
                          is_active: !c.is_active,
                        })
                      }
                    >
                      {c.is_active ? "Выкл" : "Вкл"}
                    </Button>
                    <Button
                      variant="danger"
                      className="h-7 px-2 text-[12px]"
                      onClick={() => {
                        if (confirm("Удалить город?")) delMut.mutate(c.id);
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
    </div>
  );
}

function CategoriesPanel() {
  const qc = useQueryClient();
  const [name, setName] = useState("");
  const [parentId, setParentId] = useState("");
  const [icon, setIcon] = useState("");
  const [editing, setEditing] = useState<CategoryRow | null>(null);

  const listQ = useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
  });

  const tree = useMemo(() => {
    const rows = listQ.data ?? [];
    const roots = rows.filter((r) => !r.parent_id);
    return roots.map((root) => ({
      root,
      children: rows.filter((r) => r.parent_id === root.id),
    }));
  }, [listQ.data]);

  const saveMut = useMutation({
    mutationFn: upsertCategory,
    onSuccess: async () => {
      setName("");
      setParentId("");
      setIcon("");
      setEditing(null);
      await qc.invalidateQueries({ queryKey: ["categories"] });
    },
  });

  const delMut = useMutation({
    mutationFn: deleteCategory,
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ["categories"] });
    },
  });

  return (
    <div>
      <div className="mb-3 grid gap-2 md:grid-cols-4">
        <input
          className="admin-input"
          placeholder="Название"
          value={editing ? editing.name : name}
          onChange={(e) =>
            editing
              ? setEditing({ ...editing, name: e.target.value })
              : setName(e.target.value)
          }
        />
        <select
          className="admin-input"
          value={editing ? editing.parent_id ?? "" : parentId}
          onChange={(e) =>
            editing
              ? setEditing({
                  ...editing,
                  parent_id: e.target.value || null,
                })
              : setParentId(e.target.value)
          }
        >
          <option value="">Без родителя (корень)</option>
          {(listQ.data ?? [])
            .filter((c) => !c.parent_id && c.id !== editing?.id)
            .map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
        </select>
        <input
          className="admin-input"
          placeholder="Иконка"
          value={editing ? editing.icon ?? "" : icon}
          onChange={(e) =>
            editing
              ? setEditing({ ...editing, icon: e.target.value })
              : setIcon(e.target.value)
          }
        />
        <div className="flex gap-2">
          <Button
            onClick={() =>
              saveMut.mutate(
                editing
                  ? {
                      id: editing.id,
                      name: editing.name,
                      icon: editing.icon,
                      sortOrder: editing.sort_order,
                      parentId: editing.parent_id,
                      clearParent: !editing.parent_id,
                    }
                  : {
                      name,
                      icon: icon || null,
                      parentId: parentId || null,
                      clearParent: !parentId,
                      sortOrder: (listQ.data?.length ?? 0) + 1,
                    },
              )
            }
          >
            {editing ? "Сохранить" : "Добавить"}
          </Button>
          {editing ? (
            <Button variant="ghost" onClick={() => setEditing(null)}>
              Отмена
            </Button>
          ) : null}
        </div>
      </div>

      {listQ.isLoading ? <LoadingBlock /> : null}
      {listQ.error ? <ErrorBlock message={(listQ.error as Error).message} /> : null}

      <div className="space-y-2">
        {tree.map(({ root, children }) => (
          <div key={root.id} className="admin-card p-3">
            <div className="flex items-center justify-between">
              <div>
                <span className="font-medium text-white">{root.name}</span>
                {root.icon ? (
                  <span className="ml-2 text-[12px] text-graphite-600">
                    {root.icon}
                  </span>
                ) : null}
              </div>
              <div className="flex gap-1">
                <Button
                  variant="ghost"
                  className="h-7 px-2 text-[12px]"
                  onClick={() => setEditing(root)}
                >
                  Изменить
                </Button>
                <Button
                  variant="danger"
                  className="h-7 px-2 text-[12px]"
                  onClick={() => {
                    if (confirm("Удалить категорию и подкатегории?"))
                      delMut.mutate(root.id);
                  }}
                >
                  Удалить
                </Button>
              </div>
            </div>
            {children.length ? (
              <div className="mt-2 space-y-1 border-l border-graphite-700 pl-3">
                {children.map((ch) => (
                  <div
                    key={ch.id}
                    className="flex items-center justify-between py-1"
                  >
                    <span className="text-sm text-graphite-600">— {ch.name}</span>
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => setEditing(ch)}
                      >
                        Изменить
                      </Button>
                      <Button
                        variant="danger"
                        className="h-7 px-2 text-[12px]"
                        onClick={() => {
                          if (confirm("Удалить подкатегорию?"))
                            delMut.mutate(ch.id);
                        }}
                      >
                        Удалить
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            ) : null}
          </div>
        ))}
      </div>
    </div>
  );
}

function StatusesPanel() {
  return (
    <div className="grid gap-3 md:grid-cols-2">
      <RefCard title="Роли приложения (profiles.role)" items={[...APP_ROLES]} />
      <RefCard title="Статусы пользователей" items={[...USER_STATUSES]} />
      <RefCard title="Статусы мероприятий" items={[...EVENT_STATUSES]} />
      <RefCard title="Статусы объявлений" items={[...LISTING_STATUSES]} />
    </div>
  );
}

function RefCard({ title, items }: { title: string; items: string[] }) {
  return (
    <div className="admin-card p-4">
      <h3 className="mb-2 text-sm font-semibold text-white">{title}</h3>
      <div className="flex flex-wrap gap-1.5">
        {items.map((item) => (
          <Badge key={item} tone="neutral">
            {item}
          </Badge>
        ))}
      </div>
      <p className="mt-2 text-[12px] text-graphite-600">
        Значения заданы constraint&apos;ами в Supabase; правятся миграциями.
      </p>
    </div>
  );
}
