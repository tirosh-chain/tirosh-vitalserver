import type { components } from "@/domain/runtime-control/contracts/generated/runtime-control";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";

type RuntimeRecorderIngressStatusReadState =
  components["schemas"]["RuntimeRecorderIngressStatusReadState"];

export function formatRecorderIngressStatusReadState(
  state: RuntimeRecorderIngressStatusReadState | null | undefined
): string {
  if (!state) {
    return NOT_REPORTED;
  }
  return state === "loaded" ? "Ready" : "Not ready";
}
