/**
 * M3 PDF 合成（自有 PdfComposer 移植，计划 §14 复用资产）：
 * @kit.PDFKit pdfService 位图页 → A4 PDF 容器。
 *
 * 链路已在 PocketToolbox Phase 0 真机验证（2026-10-13 Mate 60 Pro）：
 *   1. createDocument(w,h) 自带一张初始空页；
 *   2. insertBlankPage 为"在 index 处插入"，初始页被顶到末尾（index=inserted）
 *      ——必须 deletePage(inserted, 1)，误删 0 会丢第一张图片页；
 *   3. addImageObject 必须传应用沙箱路径（直传相册 file://media URI 静默空白）
 *      ——每页先拷贝到临时沙箱目录再嵌入。
 * 本应用页图 2480×3508 = A4@300dpi，整页贴 A4 595×842pt，所见即所得打印。
 *
 * x86 模拟器无 PDF Kit 运行时（官方仅支持 arm 模拟器/真机），此时 pdfService 为
 * undefined —— 构造必须置于 try 内，composeA4 优雅 resolve(false)，绝不产生
 * 未处理拒绝（否则导出按钮触发 jscrash）。
 */

import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export class PdfCodec {
  /** A4 短边 pt（PDF 单位 72dpi）。历史兼容依赖，冻结勿改。 */
  static readonly A4_SHORT_PT: number = 595;
  /** A4 长边 pt。 */
  static readonly A4_LONG_PT: number = 842;

  private static removeTree(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      for (const name of fs.listFileSync(dir)) {
        fs.unlinkSync(dir + '/' + name);
      }
      fs.rmdirSync(dir);
    } catch (e) {
      // 临时目录清理失败不影响导出结果
    }
  }

  /**
   * 位图页 → A4 PDF。
   * @param imagePaths 沙箱内 PNG 页图路径（每页一张，A4 比例）
   * @param outPath 输出沙箱路径（.pdf）
   */
  static composeA4(imagePaths: string[], outPath: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      if (imagePaths.length === 0 || outPath.indexOf('/') < 0) {
        console.error('[PdfCodec] empty images or invalid path');
        resolve(false);
        return;
      }
      const tmpDir: string = outPath.substring(0, outPath.lastIndexOf('/')) + '/pdfcodec_tmp';
      PdfCodec.removeTree(tmpDir);
      let doc: pdfService.PdfDocument | null = null;
      let inserted: number = 0;
      try {
        doc = new pdfService.PdfDocument();
        doc.createDocument(PdfCodec.A4_SHORT_PT, PdfCodec.A4_LONG_PT);
        fs.mkdirSync(tmpDir, true);
        for (let i = 0; i < imagePaths.length; i++) {
          const tmpPath: string = `${tmpDir}/page${i}.png`;
          fs.copyFileSync(imagePaths[i], tmpPath);
          const page: pdfService.PdfPage | null =
            doc.insertBlankPage(inserted, PdfCodec.A4_SHORT_PT, PdfCodec.A4_LONG_PT);
          if (page === null) {
            continue;
          }
          page.addImageObject(tmpPath, 0, 0, PdfCodec.A4_SHORT_PT, PdfCodec.A4_LONG_PT);
          inserted++;
        }
        if (inserted === 0) {
          console.error('[PdfCodec] no page inserted');
          resolve(false);
          return;
        }
        const total: number = doc.getPageCount();
        if (total === inserted + 1) {
          doc.deletePage(inserted, 1);
        } else {
          console.warn(`[PdfCodec] page count anomaly: total=${total} inserted=${inserted}`);
        }
        doc.saveDocument(outPath);
        resolve(true);
      } catch (e) {
        console.error(`[PdfCodec] compose failed: ${(e as Error).message}`);
        resolve(false);
      } finally {
        if (doc !== null) {
          try {
            doc.releaseDocument();
          } catch (e) {
            // 已失败路径的释放异常忽略
          }
        }
        PdfCodec.removeTree(tmpDir);
      }
    });
  }
}
