import type { ButtonHTMLAttributes, ReactNode } from "react";

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
    <button
      {...props}
      type={props.type ?? "button"}
      onClick={(event) => {
        if (!globalThis.confirm(confirmMessage)) {
          return;
        }
        onClick?.(event);
      }}
    >
      {children}
    </button>
  );
}
