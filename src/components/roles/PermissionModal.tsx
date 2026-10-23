"use client";

// P2-SPEC §6 — permission-denied modal (Viewer attempting SLA edits).
import * as React from "react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

interface PermissionModalProps {
  open: boolean;
  onClose: () => void;
}

export function PermissionModal({ open, onClose }: PermissionModalProps) {
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent aria-describedby="permission-modal-desc">
        <DialogHeader>
          <DialogTitle className="text-[var(--chip-red-text)]">
            You don&apos;t have permission to edit SLA policies
          </DialogTitle>
          <DialogDescription id="permission-modal-desc">
            Ask an admin in Run group for access.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button onClick={onClose}>Back to settings</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
