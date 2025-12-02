// src/components/ViridisColorMap.ts
export function getViridisColor(v: number): [number, number, number] {
    const t = Math.max(0, Math.min(1, v));
    const r = Math.round(255 * t);
    const g = Math.round(128 * (1 - t));
    const b = Math.round(255 * (1 - t));
    return [r / 255, g / 255, b / 255];
  }
  