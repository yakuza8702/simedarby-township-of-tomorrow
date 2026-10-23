// Login hero pane (P2-SPEC Appendix B copy verbatim). Hidden below sm.
import { Leaf, MapPin, Recycle, Truck } from "lucide-react";

const TEASERS: Array<{ icon: React.ReactNode; text: string }> = [
  { icon: <Recycle className="h-5 w-5" />, text: "24 open reports" },
  { icon: <Truck className="h-5 w-5" />, text: "6 routes today" },
  { icon: <MapPin className="h-5 w-5" />, text: "61 resolved this week" },
];

export function HeroPane() {
  return (
    <aside
      aria-hidden="true"
      className="relative hidden w-[44%] max-w-[520px] flex-col justify-between overflow-hidden bg-[var(--sidebar)] p-12 sm:flex"
    >
      <div className="absolute -right-24 -top-24 h-72 w-72 rounded-full bg-[var(--active-tint)]" />
      <div className="absolute -bottom-32 -left-16 h-80 w-80 rounded-full bg-[var(--hero-orb-blue)]" />

      <div className="relative flex items-center gap-2">
        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-[#2E7D32] text-white">
          <Leaf className="h-5 w-5" />
        </span>
        <span className="text-sm font-bold text-ink-primary">
          Township of Tomorrow
        </span>
      </div>

      <div className="relative">
        <h2 className="max-w-[380px] text-3xl font-bold leading-snug text-ink-primary">
          Council operations console — waste, reports, and collection in one
          place
        </h2>
        <p className="mt-4 max-w-[380px] text-sm text-ink-secondary">
          Review resident reports, dispatch collection routes, and keep every
          sector accountable — all from the green-community desk.
        </p>
      </div>

      <ul className="relative flex flex-col gap-3">
        {TEASERS.map((teaser) => (
          <li
            key={teaser.text}
            className="flex items-center gap-3 rounded-[12px] border border-[var(--border-green)] bg-[var(--surface-80)] px-4 py-3 text-sm font-semibold text-ink-primary shadow-sm"
          >
            <span className="text-[var(--green-text)]">{teaser.icon}</span>
            {teaser.text}
          </li>
        ))}
      </ul>
    </aside>
  );
}
