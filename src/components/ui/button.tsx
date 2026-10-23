import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "./utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-[8px] text-sm font-semibold ring-offset-[var(--ring-offset)] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--focus-ring)] focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default:
          "bg-[#2E7D32] text-white hover:bg-[#388E3C] shadow-sm",
        destructive:
          "bg-[#D32F2F] text-white hover:bg-[#B71C1C] shadow-sm",
        outline:
          "border border-[var(--border-plain)] bg-[var(--surface)] text-ink-primary hover:bg-[var(--sidebar)] hover:border-[var(--border-green)]",
        secondary:
          "bg-[var(--sidebar)] text-[var(--green-text)] hover:bg-[var(--active-tint)]",
        ghost: "text-[var(--green-text)] hover:bg-[var(--active-tint)]",
        link: "text-[var(--green-text)] underline-offset-4 hover:underline",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-9 rounded-[8px] px-3 text-xs",
        lg: "h-11 rounded-[8px] px-6",
        icon: "h-10 w-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    );
  }
);
Button.displayName = "Button";

export { Button, buttonVariants };
