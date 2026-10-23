// P2-SPEC §3e — broadcast templates (INFERRED).
import type { BroadcastTemplate } from "../types";

export const templates: BroadcastTemplate[] = [
  {
    id: "TPL-001",
    name: "Road works — standard",
    channel: "Push",
    version: 4,
    body: "Road works ahead: {street} will be partially closed from {time} tonight while resurfacing crews work through. Please follow the diversion signs and avoid parking along the work stretch. We apologise for the inconvenience.",
  },
  {
    id: "TPL-002",
    name: "Bin collection delay",
    channel: "SMS",
    version: 2,
    body: "Bin collection in {sector} is running late today due to a vehicle breakdown. Crews will clear all routes by this evening — please keep bins out on the kerb. Thank you for your patience.",
  },
  {
    id: "TPL-003",
    name: "Recycling awareness",
    channel: "Push",
    version: 3,
    body: "Recycling reminder: rinse food containers, flatten cardboard, and keep plastic bags out of the blue bin. Contamination forces whole loads to landfill — thank you for keeping the stream clean!",
  },
  {
    id: "TPL-004",
    name: "Hazard alert",
    channel: "SMS",
    version: 1,
    body: "Hazard alert: please avoid the area near {street} while the cleanup crew handles a reported dump site. Updates will follow within the hour. Report new hazards in the app.",
  },
];

export function templateById(id: string): BroadcastTemplate | undefined {
  return templates.find((t) => t.id === id);
}
