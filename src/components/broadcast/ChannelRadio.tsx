"use client";

// P2-SPEC §6 — CHANNEL radio group (SMS / Email / Push, Push default).
import * as React from "react";

import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import type { BroadcastChannel } from "@/lib/types";

const CHANNELS: BroadcastChannel[] = ["SMS", "Email", "Push"];

interface ChannelRadioProps {
  value: BroadcastChannel;
  onChange: (next: BroadcastChannel) => void;
}

export function ChannelRadio({ value, onChange }: ChannelRadioProps) {
  return (
    <div role="radiogroup" aria-label="Channel">
      <Label className="mb-2 block text-xs font-semibold uppercase tracking-wide text-ink-secondary">
        Channel
      </Label>
      <RadioGroup
        value={value}
        onValueChange={(v) => onChange(v as BroadcastChannel)}
        className="flex flex-wrap gap-4"
      >
        {CHANNELS.map((channel) => (
          <label
            key={channel}
            className="flex cursor-pointer items-center gap-2 text-sm text-ink-primary"
          >
            <RadioGroupItem
              value={channel}
              id={`channel-${channel}`}
              aria-label={`Channel ${channel}`}
            />
            {channel}
          </label>
        ))}
      </RadioGroup>
    </div>
  );
}
