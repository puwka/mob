"use client";

import { cn } from "@/lib/utils";
import type { ButtonHTMLAttributes } from "react";

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "ghost" | "danger";
};

export function Button({
  className,
  variant = "primary",
  ...props
}: Props) {
  return (
    <button
      className={cn(
        variant === "primary" && "admin-btn-primary",
        variant === "ghost" && "admin-btn-ghost",
        variant === "danger" && "admin-btn-danger",
        className,
      )}
      {...props}
    />
  );
}
