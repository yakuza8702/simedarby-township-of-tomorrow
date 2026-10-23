"use client";

// P2-SPEC §6 — broadcast composer: channel / title / body / audience /
// template + send & schedule flows with validation and success toasts.
import { CalendarClock, Send } from "lucide-react";
import * as React from "react";

import { AUDIENCE_REACH } from "@/lib/data/roles";
import { templateById, templates } from "@/lib/data/templates";
import { formatDateTime, formatNaiveLocal, frozenNowTick } from "@/lib/mock-delay";
import { useStore } from "@/lib/store";
import type { BroadcastAudience, BroadcastChannel } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/components/ui/use-toast";
import { ChannelRadio } from "./ChannelRadio";

const AUDIENCES: BroadcastAudience[] = [
  "All residents",
  "Sub-sector 3",
  "State agencies", // audience corrected from the design-source misspelling
];

export function BroadcastForm() {
  const store = useStore();
  const { toast } = useToast();

  const [channel, setChannel] = React.useState<BroadcastChannel>("Push");
  const [title, setTitle] = React.useState(
    "Sector 3 · Road resurfacing tonight 22:00"
  );
  const [body, setBody] = React.useState("");
  const [audiences, setAudiences] = React.useState<BroadcastAudience[]>([
    "All residents",
  ]);
  const [templateId, setTemplateId] = React.useState("TPL-001");
  const [scheduleOpen, setScheduleOpen] = React.useState(false);
  const [scheduledFor, setScheduledFor] = React.useState("");
  const [errors, setErrors] = React.useState<{
    title?: string;
    body?: string;
    schedule?: string;
  }>({});

  const recipients = audiences.reduce(
    (sum, audience) => sum + (AUDIENCE_REACH[audience] ?? 0),
    0
  );

  const validate = (): boolean => {
    const next: typeof errors = {};
    if (!title.trim()) next.title = "Title is required.";
    if (!body.trim()) next.body = "Body is required.";
    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const toggleAudience = (audience: BroadcastAudience, checked: boolean) => {
    setAudiences((prev) =>
      checked ? [...prev, audience] : prev.filter((a) => a !== audience)
    );
  };

  const nextBroadcastId = () => {
    const max = store.broadcasts.reduce((acc, b) => {
      const n = Number(b.id.replace(/\D/g, ""));
      return Number.isFinite(n) && n > acc ? n : acc;
    }, 0);
    return `BCS-${String(max + 1).padStart(3, "0")}`;
  };

  const handleSend = () => {
    if (!validate()) return;
    // No audience selected → no send (the estimate stays honest at 0).
    if (audiences.length === 0) return;
    const chosen = audiences;
    const count = chosen.reduce(
      (sum, audience) => sum + (AUDIENCE_REACH[audience] ?? 0),
      0
    );
    store.appendBroadcast({
      id: nextBroadcastId(),
      channel,
      title: title.trim(),
      body: body.trim(),
      audience: chosen,
      templateId,
      createdAt: formatNaiveLocal(frozenNowTick()),
      recipients: count,
      status: "Sent",
    });
    toast({
      title: "Broadcast sent",
      description: `Broadcast sent to ${count.toLocaleString("en-GB")} residents.`,
      variant: "success",
    });
  };

  const handleSchedule = () => {
    if (!validate()) return;
    if (!scheduledFor) {
      setErrors({ schedule: "Pick a date and time to schedule." });
      return;
    }
    setErrors({});
    const iso = new Date(scheduledFor).toISOString();
    // No audience selected → nothing to schedule (no fallback audience).
    if (audiences.length === 0) return;
    const chosen = audiences;
    store.appendBroadcast({
      id: nextBroadcastId(),
      channel,
      title: title.trim(),
      body: body.trim(),
      audience: chosen,
      templateId,
      scheduledFor: iso.slice(0, 19),
      createdAt: formatNaiveLocal(frozenNowTick()),
      recipients: chosen.reduce(
        (sum, audience) => sum + (AUDIENCE_REACH[audience] ?? 0),
        0
      ),
      status: "Scheduled",
    });
    toast({
      title: "Broadcast scheduled",
      description: `Broadcast scheduled for ${formatDateTime(iso)}.`,
    });
    setScheduleOpen(false);
    setScheduledFor("");
  };

  return (
    <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
      <Card>
        <CardContent className="space-y-5 p-5">
          <ChannelRadio value={channel} onChange={setChannel} />

          <div className="space-y-1.5">
            <Label htmlFor="broadcast-title">Title</Label>
            <Input
              id="broadcast-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Sector 3 · Road resurfacing tonight 22:00"
              aria-invalid={Boolean(errors.title)}
              aria-describedby={
                errors.title ? "broadcast-title-error" : undefined
              }
              className={
                errors.title
                  ? "border-[var(--error-soft)] ring-2 ring-[var(--error-ring)]"
                  : undefined
              }
            />
            {errors.title ? (
              <p
                id="broadcast-title-error"
                className="text-xs font-medium text-[var(--chip-red-text)]"
              >
                {errors.title}
              </p>
            ) : null}
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="broadcast-body">Body</Label>
            <Textarea
              id="broadcast-body"
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Write the message residents will receive…"
              aria-invalid={Boolean(errors.body)}
              aria-describedby={
                errors.body ? "broadcast-body-error" : undefined
              }
              className={
                errors.body
                  ? "min-h-[140px] border-[var(--error-soft)] ring-2 ring-[var(--error-ring)]"
                  : "min-h-[140px]"
              }
            />
            {errors.body ? (
              <p
                id="broadcast-body-error"
                className="text-xs font-medium text-[var(--chip-red-text)]"
              >
                {errors.body}
              </p>
            ) : null}
            <p className="text-xs text-ink-secondary">
              {body.length} characters · delivery estimated to{" "}
              {recipients.toLocaleString("en-GB")} recipients
            </p>
          </div>

          <fieldset>
            <legend className="mb-2 block text-xs font-semibold uppercase tracking-wide text-ink-secondary">
              Audience
            </legend>
            <div className="flex flex-col gap-2">
              {AUDIENCES.map((audience) => (
                <label
                  key={audience}
                  className="flex cursor-pointer items-center gap-2.5 text-sm text-ink-primary"
                >
                  <Checkbox
                    checked={audiences.includes(audience)}
                    onCheckedChange={(v) => toggleAudience(audience, v === true)}
                    aria-label={audience}
                  />
                  {audience}
                  <span className="text-xs text-ink-secondary">
                    ({(AUDIENCE_REACH[audience] ?? 0).toLocaleString("en-GB")}{" "}
                    reached)
                  </span>
                </label>
              ))}
            </div>
          </fieldset>

          <div className="space-y-1.5">
            <Label htmlFor="broadcast-template">Template</Label>
            <Select
              value={templateId}
              onValueChange={(id) => {
                setTemplateId(id);
                const template = templateById(id);
                if (template) {
                  setBody(template.body);
                  setChannel(template.channel);
                }
              }}
            >
              <SelectTrigger
                id="broadcast-template"
                aria-label="Broadcast template"
              >
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {templates.map((template) => (
                  <SelectItem key={template.id} value={template.id}>
                    {template.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-ink-secondary">
              Choosing a template fills the body with the approved copy.
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-2 border-t border-[var(--border-plain)] pt-4">
            <Button onClick={handleSend} disabled={audiences.length === 0}>
              <Send className="h-4 w-4" aria-hidden="true" />
              Send broadcast
            </Button>
            <Button
              variant="outline"
              onClick={() => setScheduleOpen((v) => !v)}
              aria-expanded={scheduleOpen}
            >
              <CalendarClock className="h-4 w-4" aria-hidden="true" />
              Schedule
            </Button>
          </div>

          {scheduleOpen ? (
            <div className="rounded-[12px] border border-[var(--border-plain)] bg-[var(--input-bg)] p-4">
              <Label htmlFor="broadcast-when" className="mb-1.5 block">
                Send at
              </Label>
              <div className="flex flex-wrap items-center gap-2">
                <Input
                  id="broadcast-when"
                  type="datetime-local"
                  className="w-64"
                  value={scheduledFor}
                  onChange={(e) => setScheduledFor(e.target.value)}
                  aria-invalid={Boolean(errors.schedule)}
                  aria-describedby={
                    errors.schedule ? "broadcast-when-error" : undefined
                  }
                />
                <Button
                  size="sm"
                  onClick={handleSchedule}
                  disabled={audiences.length === 0}
                >
                  Confirm schedule
                </Button>
              </div>
              {errors.schedule ? (
                <p
                  id="broadcast-when-error"
                  className="mt-1.5 text-xs font-medium text-[var(--chip-red-text)]"
                >
                  {errors.schedule}
                </p>
              ) : null}
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card className="h-fit">
        <CardContent className="p-5">
          <h3 className="text-sm font-semibold text-ink-primary">
            Recent broadcasts
          </h3>
          <p className="mt-1 text-xs text-ink-secondary">
            Sent and scheduled messages from this console.
          </p>
          <ul className="mt-3 space-y-2.5">
            {store.broadcasts.slice(0, 6).map((broadcast) => (
              <li
                key={broadcast.id}
                className="rounded-[8px] border border-[var(--border-plain)] bg-[var(--input-bg)] p-3"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="font-mono text-[11px] text-ink-secondary">
                    {broadcast.id} · {broadcast.channel}
                  </span>
                  <span
                    className={
                      broadcast.status === "Sent"
                        ? "rounded-full bg-[var(--active-tint)] px-2 py-0.5 text-[11px] font-semibold text-[var(--green-text)]"
                        : "rounded-full bg-[var(--chip-amber-bg)] px-2 py-0.5 text-[11px] font-semibold text-[var(--chip-amber-text)]"
                    }
                  >
                    {broadcast.status}
                  </span>
                </div>
                <p className="mt-1 line-clamp-2 text-sm font-medium text-ink-primary">
                  {broadcast.title}
                </p>
                <p className="mt-0.5 text-xs text-ink-secondary">
                  {broadcast.audience.join(" + ")} ·{" "}
                  {broadcast.status === "Scheduled" && broadcast.scheduledFor
                    ? formatDateTime(broadcast.scheduledFor)
                    : formatDateTime(broadcast.createdAt)}
                </p>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}
