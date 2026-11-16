import { bridge } from "./bridge.ts";
import { formatHoursToHoursAndMinutes } from "./overtime-summary.ts";
import type { WorkHours } from "../shared/rpc.ts";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** The hours expected on each weekday; a change is saved right away and recalculates the balance. */
export function initializeWorkHours(container: HTMLElement) {
  container.innerHTML = `
    <div class="row work-hours-days"></div>
    <div class="row">
      <span class="row-label">Per week</span>
      <span class="work-hours-total"></span>
    </div>`;
  const days = container.querySelector<HTMLElement>(".work-hours-days")!;
  const total = container.querySelector<HTMLElement>(".work-hours-total")!;
  const inputs = DAYS.map((day) => {
    const label = document.createElement("label");
    label.className = "work-hours-day";
    const input = document.createElement("input");
    Object.assign(input, { type: "number", min: "0", max: "24", step: "0.25" });
    input.inputMode = "decimal";
    input.setAttribute("aria-label", `Hours on ${day}`);
    label.append(day, input);
    days.append(label);
    return input;
  });

  let saved: WorkHours = [];
  function show(hours: WorkHours) {
    saved = hours;
    hours.forEach((h, i) => (inputs[i]!.value = String(h)));
    showTotal();
  }
  function showTotal() {
    const sum = inputs.reduce((s, input) => s + (Number(input.value) || 0), 0);
    total.textContent = formatHoursToHoursAndMinutes(sum);
    total.classList.remove("is-error");
  }

  async function save() {
    const hours = inputs.map((input) => Number(input.value));
    if (hours.some((h, i) => !inputs[i]!.value || !(h >= 0 && h <= 24))) {
      total.textContent = "0 to 24 hours a day";
      total.classList.add("is-error");
      return;
    }
    if (hours.every((h, i) => h === saved[i])) return;
    try {
      show((await bridge.setWorkHours({ hours })).hours);
      window.dispatchEvent(new Event("tracking-changed"));
    } catch (error) {
      total.textContent = error instanceof Error ? error.message : String(error);
      total.classList.add("is-error");
    }
  }

  for (const input of inputs) {
    input.addEventListener("input", showTotal);
    input.addEventListener("change", () => void save());
  }
  const load = () =>
    bridge
      .getWorkHours({})
      .then(({ hours }) => show(hours))
      .catch((error) => console.error(error));
  void load();
  // Signing in to a server or switching the data source can bring other hours.
  window.addEventListener("tracking-changed", () => {
    if (!container.contains(document.activeElement)) void load();
  });
}
