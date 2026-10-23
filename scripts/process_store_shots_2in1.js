// AGC 商店截图规格化处理（2in1/PC，Node + sharp）。
// 依赖：sharp@0.32.6（Node 18 兼容；最新版需 Node>=20.9）：
//   cd %TEMP%\deveco\imgproc && npm install sharp@0.32.6
// 用法：
//   node scripts/process_store_shots_2in1.js
// 规格：
//   2in1（MateBook Pro 3120x2080，3:2 源）-> 左右居中衬边到 3698x2080
//     （16:9，满足 PC min 1920x1080），衬边色 #F5F5F5 = page_background。
//   输出 JPEG 质量 90（单张 < 5MB 上限远余）。
const fs = require('fs');
const path = require('path');

let sharp;
try {
  sharp = require('sharp');
} catch (e) {
  try {
    sharp = require(path.join(process.env.TEMP || '', 'deveco', 'imgproc', 'node_modules', 'sharp'));
  } catch (e2) {
    console.error('sharp 未安装：cd %TEMP%\\deveco\\imgproc && npm install sharp@0.32.6');
    process.exit(1);
  }
}

const ROOT = path.join(__dirname, '..');
const SRC_DIR = path.join(ROOT, '.shots', 'agc', '2in1_raw');
const OUT_DIR = path.join(ROOT, '.shots', 'agc');
const SRC_W = 3120;
const SRC_H = 2080;
const TARGET_W = Math.round(SRC_H * 16 / 9); // 3698
const TARGET_H = SRC_H; // 2080
const PAD = { r: 245, g: 245, b: 245 }; // #F5F5F5 page_background

const padColor = `#${PAD.r.toString(16)}${PAD.g.toString(16)}${PAD.b.toString(16)}`;

async function processOne(file) {
  const src = path.join(SRC_DIR, file);
  const out = path.join(OUT_DIR, '2in1_' + file.replace(/\.jpe?g$/, '').replace(/_raw$/, '') + `_${TARGET_W}x${TARGET_H}.jpg`);
  const meta = await sharp(src).metadata();
  if (meta.width !== SRC_W || meta.height !== SRC_H) {
    console.warn(`WARN  ${file}: 非预期源尺寸 ${meta.width}x${meta.height}（期望 ${SRC_W}x${SRC_H}），按等比适配`);
  }
  // 内容等比缩放到画布高度，再水平居中衬边（源 3:2 -> 画布 16:9）
  const scaledW = Math.round(meta.width * (TARGET_H / meta.height));
  const scaledH = TARGET_H;
  const buf = await sharp(src)
    .resize(scaledW, scaledH, { kernel: 'lanczos3' })
    .toBuffer();
  const left = Math.round((TARGET_W - scaledW) / 2);
  await sharp({
    create: { width: TARGET_W, height: TARGET_H, channels: 3, background: padColor },
  })
    .composite([{ input: buf, left: left, top: 0 }])
    .jpeg({ quality: 90, chromaSubsampling: '4:4:4' })
    .toFile(out);
  const stat = fs.statSync(out);
  console.log(`OK    ${path.basename(out)}  ${TARGET_W}x${TARGET_H}  ${(stat.size / 1024).toFixed(0)}KB`);
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const files = fs.readdirSync(SRC_DIR)
    .filter(f => /^s\d+.*\.jpe?g$/.test(f))
    .sort();
  if (files.length === 0) {
    console.error(`未找到 ${SRC_DIR} 下的 s*.jpeg 源截图`);
    process.exit(1);
  }
  for (const f of files) {
    await processOne(f);
  }
  console.log(`\n处理完成：${files.length} 张 -> ${path.relative(ROOT, OUT_DIR)}`);
}

main().catch(e => { console.error(e); process.exit(1); });
