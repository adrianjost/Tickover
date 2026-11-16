export interface OvertimeData {
  totalOvertimeHours: number;
  totalOvertimeMinutes: number;
  dailyData: Array<{
    date: string;
    actualHours: number;
    expectedHours: number;
    cumulativeOvertimeHours: number;
  }>;
}

export type DataSource = "clockify" | "server";

/** Hours expected on each weekday, Monday first. */
export type WorkHours = number[];
export const DEFAULT_WORK_HOURS: WorkHours = [8, 8, 8, 8, 8, 0, 0];

/**
 * Working hours that apply from `from` (a local YYYY-MM-DD date) until the next schedule starts.
 * Sorted by date; the first one has no start date and also covers everything before.
 */
export interface WorkSchedule {
  from: string | null;
  hours: WorkHours;
}
export const DEFAULT_WORK_SCHEDULES: WorkSchedule[] = [{ from: null, hours: DEFAULT_WORK_HOURS }];

/** "system" follows the light or dark setting of the operating system. */
export type Theme = "system" | "light" | "dark";

/** An entry on the self-hosted time tracking server; ISO 8601 times, `end` null while running. */
export interface TrackedEntry {
  id: string;
  start: string;
  end: string | null;
  /** Set by the self-hosted server, e.g. "project:Bugfixing"; not shown anywhere yet. */
  labels?: string[];
}

// Requests handled by the native app, see macos/Tickover/App/AppController.swift.
export type AppRequests = {
  analyzeOvertime: {
    params: { apiKey: string; startDate: string; endDate: string };
    response: OvertimeData;
  };
  closeApp: { params: {}; response: void };
  getSetupState: {
    params: {};
    response: { dataSource: DataSource | null; configured: boolean; tracking: boolean };
  };
  setDataSource: { params: { dataSource: DataSource }; response: void };
  getServerSettings: {
    params: {};
    response: {
      url: string | null;
      username: string | null;
      signedIn: boolean;
      /** Why the session ended, until you sign in again. */
      notice: string | null;
    };
  };
  signInToServer: { params: { url: string; username: string; password: string }; response: void };
  signOutOfServer: { params: {}; response: void };
  getTimer: { params: {}; response: { running: TrackedEntry | null } };
  startTimer: { params: {}; response: { running: TrackedEntry | null } };
  stopTimer: { params: {}; response: { running: TrackedEntry | null } };
  discardTimer: { params: {}; response: { running: TrackedEntry | null } };
  listEntries: { params: { startDate: string; endDate: string }; response: TrackedEntry[] };
  saveEntry: {
    params: { id?: string; start: string; end: string | null };
    response: TrackedEntry;
  };
  deleteEntry: { params: { id: string }; response: void };
  setContentMaxHeight: { params: { height: number }; response: void };
  setContentMinWidth: { params: { width: number }; response: void };
  getLaunchAtLogin: { params: {}; response: { enabled: boolean } };
  setLaunchAtLogin: { params: { enabled: boolean }; response: void };
  getTrayEnabled: { params: {}; response: { enabled: boolean } };
  setTrayEnabled: { params: { enabled: boolean }; response: void };
  getTraySeconds: { params: {}; response: { enabled: boolean } };
  setTraySeconds: { params: { enabled: boolean }; response: void };
  getTheme: { params: {}; response: { theme: Theme } };
  setTheme: { params: { theme: Theme }; response: void };
  getEntriesSidebar: { params: {}; response: { enabled: boolean } };
  setEntriesSidebar: { params: { enabled: boolean }; response: void };
  getWorkSchedules: { params: {}; response: { schedules: WorkSchedule[] } };
  setWorkSchedules: {
    params: { schedules: WorkSchedule[] };
    response: { schedules: WorkSchedule[] };
  };
  getStoredApiKey: { params: {}; response: { apiKey: string | null } };
  setStoredApiKey: { params: { apiKey: string }; response: void };
  clearStoredApiKey: { params: {}; response: void };
};
