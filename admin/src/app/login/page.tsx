"use client";

import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { fetchAdminMe } from "@/lib/api/admin";
import { toAuthEmail } from "@/lib/phone";
import { loginSchema, type LoginValues } from "@/lib/validators";
import { zodResolver } from "@hookform/resolvers/zod";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useForm } from "react-hook-form";

export default function LoginPage() {
  const router = useRouter();
  const [formError, setFormError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { phone: "", password: "" },
  });

  const onSubmit = handleSubmit(async (values) => {
    setFormError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({
      email: toAuthEmail(values.phone),
      password: values.password,
    });
    if (error) {
      setFormError("Неверный телефон или пароль");
      return;
    }

    try {
      await fetchAdminMe();
      router.replace("/dashboard");
      router.refresh();
    } catch {
      await supabase.auth.signOut();
      setFormError(
        "Аккаунт не состоит в admin_users. Добавьте запись в Supabase и повторите вход.",
      );
    }
  });

  return (
    <div className="flex min-h-screen items-center justify-center bg-graphite-950 px-4">
      <div className="w-full max-w-sm rounded-lg border border-graphite-700 bg-graphite-900 p-6 shadow-panel">
        <div className="mb-6">
          <div className="text-[11px] font-semibold uppercase tracking-[0.14em] text-lime">
            Мой Страйкбол
          </div>
          <h1 className="mt-1 text-xl font-semibold text-white">Вход в админку</h1>
          <p className="mt-1 text-sm text-graphite-600">
            Вход по телефону (как в приложении). Роль organizer доступ не даёт.
          </p>
        </div>
        <form onSubmit={onSubmit} className="space-y-3">
          <div>
            <label className="mb-1 block text-[12px] text-graphite-600">
              Телефон
            </label>
            <input
              className="admin-input"
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              placeholder="+7 900 123-45-67"
              {...register("phone")}
            />
            {errors.phone ? (
              <p className="mt-1 text-[12px] text-red-300">{errors.phone.message}</p>
            ) : null}
          </div>
          <div>
            <label className="mb-1 block text-[12px] text-graphite-600">
              Пароль
            </label>
            <input
              className="admin-input"
              type="password"
              autoComplete="current-password"
              {...register("password")}
            />
            {errors.password ? (
              <p className="mt-1 text-[12px] text-red-300">
                {errors.password.message}
              </p>
            ) : null}
          </div>
          {formError ? (
            <div className="rounded-md border border-red-900/50 bg-red-950/40 px-3 py-2 text-[12px] text-red-300">
              {formError}
            </div>
          ) : null}
          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? "Вход…" : "Войти"}
          </Button>
        </form>
      </div>
    </div>
  );
}
