import { bridge } from "./bridge.ts";
import { formatHoursToHoursAndMinutes } from "./overtime-summary.ts";
import { localIsoDate, localMidnight } from "../shared/overtime.ts";
import type { WorkSchedule } from "../shared/rpc.ts";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

interface ScheduleBox {
  element: HTMLElement;
  date: HTMLInputElement | null;
  until: HTMLElement | null;
  inputs: HTMLInputElement[];
  total: HTMLElement;
}

/**
 * The hours expected on each weekday, as schedules that each apply from a date on, newest first.
 * A change is saved right away and recalculates the balance.
 */
export function initializeWorkHours(container: HTMLElement) {
  let schedules: WorkSchedule[] = [];
  let boxes: ScheduleBox[] = [];

  const formatDate = (iso: string) =>
    localMidnight(iso).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
    });

  function build() {
    boxes = schedules.map((schedule, index) => {
      const element = document.createElement("div");
      element.className = "group-box";

      let date: HTMLInputElement | null = null;
      let until: HTMLElement | null = null;
      if (schedules.length > 1) {
        const period = document.createElement("div");
        period.className = "row work-hours-period";
        const label = document.createElement("span");
        label.className = "row-label";
        period.append(label);
        if (schedule.from === null) {
          until = label;
        } else {
          label.textContent = "From";
          date = document.createElement("input");
          date.type = "date";
          date.required = true;
          date.value = schedule.from;
          date.setAttribute("aria-label", "Applies from");
          // Not on "change": typing a year digit by digit would save every step.
          date.addEventListener("blur", () => void save());
          date.addEventListener("keydown", (event) => {
            if (event.key === "Enter") void save();
          });
          period.append(date, removeButton(index));
        }
        element.append(period);
      }

      const days = document.createElement("div");
      days.className = "row work-hours-days";
      const inputs = DAYS.map((day) => {
        const label = document.createElement("label");
        label.className = "work-hours-day";
        const input = document.createElement("input");
        Object.assign(input, { type: "number", min: "0", max: "24", step: "0.25" });
        input.inputMode = "decimal";
        input.setAttribute("aria-label", `Hours on ${day}`);
        input.addEventListener("input", () => showTotal(boxes[index]!));
        input.addEventListener("change", () => void save());
        label.append(day, input);
        days.append(label);
        return input;
      });

      const totalRow = document.createElement("div");
      totalRow.className = "row";
      totalRow.innerHTML = `<span class="row-label">Per week</span>`;
      const total = document.createElement("span");
      total.className = "work-hours-total";
      totalRow.append(total);

      element.append(days, totalRow);
      return { element, date, until, inputs, total };
    });

    const add = document.createElement("button");
    add.type = "button";
    add.className = "btn work-hours-add";
    add.textContent = "Add a change";
    add.addEventListener("click", () => void addChange());

    container.replaceChildren(...boxes.map((box) => box.element).reverse(), add);
  }

  function removeButton(index: number) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn-danger";
    button.textContent = "Remove";
    let confirm: ReturnType<typeof setTimeout> | null = null;
    button.addEventListener("click", () => {
      if (confirm === null) {
        button.textContent = "Click again";
        button.classList.add("btn-danger-confirm");
        confirm = setTimeout(() => {
          confirm = null;
          button.textContent = "Remove";
          button.classList.remove("btn-danger-confirm");
        }, 3000);
        return;
      }
      clearTimeout(confirm);
      void store(schedules.filter((_, i) => i !== index));
    });
    return button;
  }

  function show(next: WorkSchedule[]) {
    schedules = next;
    // Rebuilding while an input has focus would lose it, so keep the boxes when they still match.
    const sameBoxes =
      boxes.length === next.length &&
      boxes.every((box, i) => (box.date?.value ?? null) === next[i]!.from);
    if (!container.contains(document.activeElement) || !sameBoxes) build();
    const nextChange = schedules[1]?.from;
    if (boxes[0]?.until && nextChange) {
      boxes[0].until.textContent = `Until ${formatDate(localIsoDate(localMidnight(nextChange, -1)))}`;
    }
    boxes.forEach((box, i) => {
      schedules[i]!.hours.forEach((h, day) => {
        const input = box.inputs[day]!;
        if (input !== document.activeElement) input.value = String(h);
      });
      showTotal(box);
    });
  }

  function showTotal(box: ScheduleBox) {
    const sum = box.inputs.reduce((s, input) => s + (Number(input.value) || 0), 0);
    box.total.textContent = formatHoursToHoursAndMinutes(sum);
    box.total.classList.remove("is-error");
  }

  function fail(box: ScheduleBox, message: string) {
    box.total.textContent = message;
    box.total.classList.add("is-error");
  }

  /** The schedules as entered, or null after showing what is wrong. */
  function read(): WorkSchedule[] | null {
    const result: WorkSchedule[] = [];
    for (const box of boxes) {
      const hours = box.inputs.map((input) => Number(input.value));
      if (hours.some((h, day) => !box.inputs[day]!.value || !(h >= 0 && h <= 24))) {
        fail(box, "0 to 24 hours a day");
        return null;
      }
      const from = box.date ? box.date.value : null;
      if (from === "") {
        fail(box, "Pick a start date");
        return null;
      }
      const same = boxes.filter((other) => from !== null && other.date?.value === from);
      if (same.length > 1) {
        for (const other of same) fail(other, "Another change starts that day");
        return null;
      }
      result.push({ from, hours });
    }
    return result;
  }

  async function save() {
    const next = read();
    if (!next) return;
    if (JSON.stringify(next) !== JSON.stringify(schedules)) await store(next);
    else boxes.forEach(showTotal);
  }

  async function store(next: WorkSchedule[]) {
    try {
      show((await bridge.setWorkSchedules({ schedules: next })).schedules);
      window.dispatchEvent(new Event("tracking-changed"));
    } catch (error) {
      const box = boxes.at(-1);
      if (box) fail(box, error instanceof Error ? error.message : String(error));
    }
  }

  /** A new schedule from the coming Monday on, starting with the hours that apply then. */
  async function addChange() {
    const current = read();
    if (!current) return;
    const today = new Date();
    let from = localIsoDate(localMidnight(localIsoDate(today), (8 - today.getDay()) % 7));
    while (current.some((s) => s.from === from)) from = localIsoDate(localMidnight(from, 7));
    const base = current.findLast((s) => s.from === null || s.from <= from) ?? current[0]!;
    const next = [...current, { from, hours: [...base.hours] }];
    next.sort((a, b) => (a.from ?? "").localeCompare(b.from ?? ""));
    await store(next);
    boxes[schedules.findIndex((s) => s.from === from)]?.date?.focus();
  }

  const load = () =>
    bridge
      .getWorkSchedules({})
      .then(({ schedules }) => show(schedules))
      .catch((error) => console.error(error));
  void load();
  // Signing in to a server or switching the data source can bring other schedules.
  window.addEventListener("tracking-changed", () => {
    if (!container.contains(document.activeElement)) void load();
  });
}
