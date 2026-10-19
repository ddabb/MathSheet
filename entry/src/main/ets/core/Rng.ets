/**
 * M0 核心①：种子化 PRNG（mulberry32）。
 *
 * 同种子 → 同序列，是「同参数同种子 = 同卷 / 换一批 = 新种子」的基石。
 * 非密码学场景：取模法有极轻微偏差，计划 §6.2 判定可接受（分布抽查兜底）。
 */

export class Rng {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** 推进一步并返回 uint32（mulberry32）。 */
  next(): number {
    this.state = (this.state + 0x6D2B79F5) >>> 0;
    let t: number = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  }

  /** [0, 1) 浮点。 */
  nextFloat(): number {
    return this.next() / 4294967296;
  }

  /** [min, max) 整数；max <= min 时退化为 min。 */
  nextInt(min: number, max: number): number {
    if (max <= min) {
      return min;
    }
    return min + (this.next() % (max - min));
  }

  /** 数组随机取一（空数组返回 undefined，调用方保证非空）。 */
  pick<T>(items: T[]): T | undefined {
    if (items.length === 0) {
      return undefined;
    }
    return items[this.nextInt(0, items.length)];
  }
}
