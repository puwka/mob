import { PageHeader } from "@/components/ui/page";

export default function PlaceholderPage({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div>
      <PageHeader title={title} description={description} />
      <div className="admin-card px-4 py-8 text-sm text-graphite-600">
        Раздел подготовлен в навигации. CRUD будет подключён на следующем этапе —
        данные уже живут в той же Supabase.
      </div>
    </div>
  );
}
