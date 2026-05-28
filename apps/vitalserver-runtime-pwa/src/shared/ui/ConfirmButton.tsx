import type { ButtonHTMLAttributes, ReactNode } from "react";

import { Button } from "./Button";

type ConfirmButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  confirmMessage: string;
  children: ReactNode;
};

export function ConfirmButton({
  confirmMessage,
  children,
  onClick,
  ...props
}: ConfirmButtonProps) {
  return (
    <Button
      {...props}
      onClick={(event) => {
        if (!globalThis.confirm(confirmMessage)) {
          return;
        }
        onClick?.(event);
      }}
    >
      {children}
    </Button>
  );
}
