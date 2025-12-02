// src/utils/mck/layoutUtils.ts

export function autoArrangeMasses(count: number, spacing = 100, startX = 100, startY = 150) {
    return Array.from({ length: count }).map((_, i) => ({
      x: startX + i * spacing,
      y: startY,
    }));
  }
  