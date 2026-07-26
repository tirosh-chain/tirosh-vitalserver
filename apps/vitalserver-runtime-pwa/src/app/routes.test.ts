import { describe, expect, it } from "vitest";

import { consoleRoutes } from "./routes";

describe("consoleRoutes", () => {
  it("matches the Swift primary section order", () => {
    expect(labelsForGroup("primary")).toEqual([
      "Status",
      "Recorders",
      "Beds",
      "Lab",
      "Settings",
      "Update"
    ]);
  });

  it("keeps utility and overflow sections separate from primary tabs", () => {
    expect(labelsForGroup("utility")).toEqual(["Advanced"]);
    expect(labelsForGroup("overflow")).toEqual([
      "Observability",
      "Logs",
      "Info",
      "Danger Zone"
    ]);
  });
});

function labelsForGroup(group: "primary" | "utility" | "overflow") {
  return consoleRoutes
    .filter((route) => route.group === group)
    .map((route) => route.label);
}
