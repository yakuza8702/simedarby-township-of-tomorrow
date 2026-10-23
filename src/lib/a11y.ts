// P2-SPEC §8 — small aria/focus helpers layered on top of Radix primitives
// (Radix Sheet/Dialog already trap focus; these cover custom surfaces).

const FOCUSABLE =
  'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function getFocusable(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
    (el) => el.offsetParent !== null || el === document.activeElement
  );
}

/** Trap Tab/Shift+Tab inside `container`. Returns a cleanup function. */
export function trapFocus(container: HTMLElement): () => void {
  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key !== "Tab") return;
    const focusable = getFocusable(container);
    if (focusable.length === 0) {
      event.preventDefault();
      return;
    }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };
  container.addEventListener("keydown", onKeyDown);
  return () => container.removeEventListener("keydown", onKeyDown);
}

/** Announce a message through a visually-hidden aria-live region. */
export function announce(message: string, assertive = false): void {
  if (typeof document === "undefined") return;
  let region = document.getElementById(
    assertive ? "sr-announcer-assertive" : "sr-announcer-polite"
  );
  if (!region) {
    region = document.createElement("div");
    region.id = assertive ? "sr-announcer-assertive" : "sr-announcer-polite";
    region.setAttribute("aria-live", assertive ? "assertive" : "polite");
    region.setAttribute("role", assertive ? "alert" : "status");
    region.className = "sr-only";
    document.body.appendChild(region);
  }
  // Clear first so repeated identical messages are re-announced.
  region.textContent = "";
  window.setTimeout(() => {
    if (region) region.textContent = message;
  }, 30);
}
