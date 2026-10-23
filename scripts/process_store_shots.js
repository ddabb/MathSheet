// AGC 商店截图规格化处理（Node + sharp）。
// 依赖：sharp@0.32.6（Node 18 兼容；最新版需 Node>=20.9）：
//   cd %TEMP%\deveco\imgproc && npm install sharp@0.32.6
// 用法：
//   node scripts/process_store_shots.js            # 处理 .shots/phone_s*.jpeg -> .shots/agc/
// 规格：
//   手机（竖屏应用）：1256x2760 源 -> 高度缩放到 1920（874x1920）-> 左右居中衬边到
//     1080x1920（16:9 竖屏，满足 min 边 >= 1080），衬边色 #F5F5F5 = page_background。
//   输出 JPEG 质量 90（单张 < 5MB 上限远余）。
const fs = require('fs');
const path = require('path');

let sharp;
try {
  sharp = require('sharp');
} catch (e) {
  // 仓库内无 node_modules 时回退到独立安装目录
  try {
    sharp = require(path.join(process.env.TEMP || '', 'deveco', 'imgproc', 'node_modules', 'sharp'));
  } catch (e2) {
    console.error('sharp 未安装：cd %TEMP%\\deveco\\imgproc && npm install sharp@0.32.6');
    process.exit(1);
  }
}

const ROOT = path.join(__dirname, '..');
const SRC_DIR = path.join(ROOT, '.shots');
const OUT_DIR = path.join(ROOT, '.shots', 'agc');
const TARGET_W = 1080;
const TARGET_H = 1920;
const PAD = { r: 245, g: 245, b: 245 }; // #F5F5F5 page_background

function padHex(n) { return n.toString(16).padStart(2, '0'); }
const padColor = `#${PAD.r.toString(16)}${PAD.g.toString(16)}${PAD.b.toString(16)}`;

async function processOne(file) {
  const src = path.join(SRC_DIR, file);
  const out = path.join(OUT_DIR, file.replace(/\.jpe?g$/, '') + '_1080x1920.jpg');
  const meta = await sharp(src).metadata();
  if (meta.width !== 1256 || meta.height !== 2760) {
    console.warn(`WARN  ${file}: 非预期源尺寸 ${meta.width}x${meta.height}（期望 1256x2760），按等比适配`);
  }
  // 内容等比缩放到目标高度，再水平居中衬边
  const scaled = Math.round(meta.width * (TARGET_H / meta.height));
  const left = Math.round((TARGET_W - scaled) / 2);
  const buf = await sharp(src)
    .resize({ height: TARGET_H, kernel: 'lanczos3' })
    .toBuffer();
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
    .filter(f => /^phone_s\d+.*\.jpe?g$/.test(f))
    .sort();
  if (files.length === 0) {
    console.error('未找到 .shots/phone_s*.jpeg 源截图');
    process.exit(1);
  }
  for (const f of files) {
    await processOne(f);
  }
  console.log(`\n处理完成：${files.length} 张 -> ${path.relative(ROOT, OUT_DIR)}`);
}

main().catch(e => { console.error(e); process.exit(1); });
