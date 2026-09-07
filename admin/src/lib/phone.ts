/** Phone helpers — same scheme as the Flutter app (phone.local auth email). */

const PHONE_AUTH_DOMAIN = "phone.local";

export function normalizePhone(input: string): string {
  const digits = input.replace(/\D/g, "");
  if (!digits) return "";

  if (digits.length === 11 && (digits.startsWith("7") || digits.startsWith("8"))) {
    return `7${digits.slice(1)}`;
  }
  if (digits.length === 10) {
    return `7${digits}`;
  }
  return digits;
}

export function toE164(input: string): string {
  const n = normalizePhone(input);
  if (!n) return "";
  return `+${n}`;
}

export function toAuthEmail(phone: string): string {
  const n = normalizePhone(phone);
  return `${n}@${PHONE_AUTH_DOMAIN}`;
}

export function formatPhoneDisplay(input: string): string {
  const n = normalizePhone(input);
  if (n.length !== 11 || !n.startsWith("7")) {
    return input.trim();
  }
  return `+7 (${n.slice(1, 4)}) ${n.slice(4, 7)}-${n.slice(7, 9)}-${n.slice(9, 11)}`;
}

export function isValidRuMobile(input: string): boolean {
  return /^7\d{10}$/.test(normalizePhone(input));
}
