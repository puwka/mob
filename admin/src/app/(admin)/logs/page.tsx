"use client";

import { Badge } from "@/components/ui/badge";
import {
  EmptyState,
  ErrorBlock,
  LoadingBlock,
  PageHeader,
} from "@/components/ui/page";
import { fetchAuditLogs } from "@/lib/api/admin";
import { formatDate, shortId } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";
import { Fragment, useState } from "react";

export default function LogsPage() {
  const [openId, setOpenId] = useState<string | null>(null);
  const query = useQuery({
    queryKey: ["admin-audit-logs"],
    queryFn: () => fetchAuditLogs(150),
  });

  return (
    <div>
      <PageHeader
        title="Логи"
        description="Аудит действий администраторов (admin_audit_logs)"
      />

      {query.isLoading ? <LoadingBlock /> : null}
      {query.error ? (
        <ErrorBlock message={(query.error as Error).message} />
      ) : null}
      {!query.isLoading && (query.data?.length ?? 0) === 0 ? (
        <EmptyState message="Логов пока нет" />
      ) : null}

      {(query.data?.length ?? 0) > 0 ? (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Дата</th>
                <th>Администратор</th>
                <th>Действие</th>
                <th>Тип объекта</th>
                <th>Объект</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {query.data!.map((row) => (
                <Fragment key={row.id}>
                  <tr>
                    <td className="text-graphite-600">
                      {formatDate(row.created_at)}
                    </td>
                    <td className="text-[12px]">
                      {row.admin_phone ?? shortId(row.admin_id)}
                    </td>
                    <td>
                      <Badge tone="lime">{row.action}</Badge>
                    </td>
                    <td>{row.entity_type}</td>
                    <td className="font-mono text-[12px] text-graphite-600">
                      {shortId(row.entity_id)}
                    </td>
                    <td>
                      <button
                        type="button"
                        className="text-[12px] text-lime hover:underline"
                        onClick={() =>
                          setOpenId((v) => (v === row.id ? null : row.id))
                        }
                      >
                        {openId === row.id ? "Скрыть" : "Diff"}
                      </button>
                    </td>
                  </tr>
                  {openId === row.id ? (
                    <tr>
                      <td colSpan={6} className="bg-graphite-950/50">
                        <div className="grid gap-3 p-2 md:grid-cols-2">
                          <pre className="overflow-auto rounded border border-graphite-800 bg-graphite-950 p-2 text-[11px] text-graphite-600">
                            {JSON.stringify(row.old_data, null, 2)}
                          </pre>
                          <pre className="overflow-auto rounded border border-graphite-800 bg-graphite-950 p-2 text-[11px] text-lime/80">
                            {JSON.stringify(row.new_data, null, 2)}
                          </pre>
                        </div>
                      </td>
                    </tr>
                  ) : null}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
