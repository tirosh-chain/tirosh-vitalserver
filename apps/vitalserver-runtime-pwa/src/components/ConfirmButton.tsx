import type { ReactNode } from "react";

import { Button, type ButtonProps } from "./Button";

type ConfirmButtonProps = ButtonProps & {
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
