// Whether times show as 14:05 or 2:05 PM; stored per device. Native time inputs always follow the
// device's locale, so the entry editor uses text inputs that read and write times with this.

const KEY = "time_format";

export type TimeFormat = "24h" | "12h";

export function timeFormat(): TimeFormat {
  try {
    return localStorage.getItem(KEY) === "12h" ? "12h" : "24h";
  } catch {
    return "24h";
  }
}

/** "14:05", or "2:05 PM" with the 12-hour format. */
export function formatTime(date: Date): string {
  const twelve = timeFormat() === "12h";
  return date.toLocaleTimeString("en-US", {
    hour: twelve ? "numeric" : "2-digit",
    minute: "2-digit",
    hourCycle: twelve ? "h12" : "h23",
  });
}

/** Reads "14:05", "1405", "9", "2:05 pm" or "2pm" in either format; null if it isn't a time. */
export function parseTime(text: string): { hours: number; minutes: number } | null {
  const match = /^\s*(\d{1,2})(?:[:.]?(\d{2}))?\s*(?:([ap])\.?\s*m?\.?)?\s*$/i.exec(text);
  if (!match) return null;
  let hours = Number(match[1]);
  const minutes = Number(match[2] ?? 0);
  const half = match[3]?.toLowerCase();
  if (minutes > 59) return null;
  if (half) {
    if (hours < 1 || hours > 12) return null;
    hours = (hours % 12) + (half === "p" ? 12 : 0);
  } else if (hours > 23) {
    return null;
  }
  return { hours, minutes };
}

/** Checks the current format in the settings and saves another one when it is picked. */
export function initializeTimeFormatPicker() {
  for (const input of Array.from(
    document.querySelectorAll<HTMLInputElement>('input[name="time-format"]'),
  )) {
    input.checked = input.value === timeFormat();
    input.addEventListener("change", () => {
      if (!input.checked) return;
      try {
        localStorage.setItem(KEY, input.value);
      } catch {}
      window.dispatchEvent(new Event("tracking-changed"));
    });
  }
}
