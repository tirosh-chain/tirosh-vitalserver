import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "./cn";

const buttonVariants = cva("ui-button", {
  variants: {
    tone: {
      default: "ui-button-default",
      primary: "ui-button-primary",
      danger: "ui-button-danger",
      ghost: "ui-button-ghost"
    }
  },
  defaultVariants: {
    tone: "default"
  }
});

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonVariants> & {
    children: ReactNode;
  };

export function Button({ tone, className, children, ...props }: ButtonProps) {
  return (
    <button
      {...props}
      type={props.type ?? "button"}
      className={cn(buttonVariants({ tone }), className)}
    >
      {children}
    </button>
  );
}
