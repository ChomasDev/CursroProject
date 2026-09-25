export const REDACTED = "[rimosso: c'era una chiave o una password]";

const SECRET =
  /\b(sk-[a-zA-Z0-9_-]{12,}|api[_-]?key\s*[:=]\s*\S+|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]+PRIVATE KEY-----|xox[baprs]-[0-9a-zA-Z-]{10,})\b/i;

export function hasSecret(text: string): boolean {
  return SECRET.test(text);
}

export function redact(text: string): string {
  return hasSecret(text) ? REDACTED : text;
}
