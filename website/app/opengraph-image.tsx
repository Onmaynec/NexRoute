import { ImageResponse } from "next/og";

export const alt = "NexRoute — управление сетевыми стратегиями для Windows";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "center", padding: 72, background: "#050709", color: "#F4F7F8", position: "relative", fontFamily: "sans-serif" }}>
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(circle at 75% 25%, rgba(34,211,238,.18), transparent 32%), linear-gradient(rgba(255,255,255,.025) 1px, transparent 1px), linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px)", backgroundSize: "auto, 42px 42px, 42px 42px" }} />
      <div style={{ display: "flex", alignItems: "center", gap: 18, position: "relative" }}>
        <div style={{ width: 58, height: 58, border: "1px solid rgba(103,232,249,.35)", borderRadius: 18, display: "flex", alignItems: "center", justifyContent: "center", color: "#67E8F9", fontSize: 28 }}>⌁</div>
        <div style={{ fontSize: 28, fontWeight: 700 }}>NexRoute</div>
      </div>
      <div style={{ marginTop: 54, maxWidth: 920, fontSize: 68, lineHeight: 1.02, letterSpacing: "-0.05em", fontWeight: 700, position: "relative" }}>Управляйте сетевыми стратегиями. Без лишней сложности.</div>
      <div style={{ marginTop: 30, fontSize: 25, color: "#9BA8AE", position: "relative" }}>Service Matrix · Strategy Lab · Safe Updates · Build Provenance</div>
    </div>,
    size,
  );
}
