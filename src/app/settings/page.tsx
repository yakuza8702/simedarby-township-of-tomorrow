import { redirect } from "next/navigation";

// Convenience redirect (P2-SPEC §1).
export default function SettingsPage() {
  redirect("/settings/roles");
}
