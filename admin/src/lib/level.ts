/** Keep in sync with Flutter `LevelService` and SQL `xp_required_for_level`. */

export function xpRequiredForLevel(level: number): number {
  if (level < 1) return 200;
  return 200 + (level - 1) * 75;
}

/** Minimum total XP needed to reach `level` (start of that level). */
export function totalXpForLevel(level: number): number {
  const safe = Math.max(1, Math.floor(level));
  if (safe <= 1) return 0;
  let total = 0;
  for (let l = 1; l < safe; l++) {
    total += xpRequiredForLevel(l);
  }
  return total;
}

export function computePlayerLevel(xp: number): number {
  const safeXp = Math.max(0, Math.floor(xp));
  let level = 1;
  let threshold = 0;
  let nextCost = xpRequiredForLevel(1);

  while (safeXp >= threshold + nextCost) {
    threshold += nextCost;
    level += 1;
    nextCost = xpRequiredForLevel(level);
  }
  return level;
}
