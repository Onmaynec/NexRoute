import { cn } from "@/lib/utils";

export function LogoMark({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      className={cn("size-9", className)}
      viewBox="0 0 40 40"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <rect x="1" y="1" width="38" height="38" rx="12" fill="#0A1116" stroke="rgba(103,232,249,.28)" />
      <path d="M10 26.5 18.4 13l3.1 8.2L30 13.5" stroke="#67E8F9" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="10" cy="26.5" r="2.2" fill="#22D3EE" />
      <circle cx="18.4" cy="13" r="2.2" fill="#F4F7F8" />
      <circle cx="21.5" cy="21.2" r="2.2" fill="#38BDF8" />
      <circle cx="30" cy="13.5" r="2.2" fill="#22D3EE" />
      <path d="m27.2 27.5 4.3-4.3m0 0-4.2-.4m4.2.4-.4 4.2" stroke="#748188" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
