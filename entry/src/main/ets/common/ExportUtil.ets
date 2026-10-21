/**
 * M3 导出编排（计划 §6.3）：页请求 → 沙箱产物 → 系统通道（保存器/分享/相册）。
 *
 * - composePdf：页图固定 300dpi（scale=1，A4 全尺寸）→ PdfCodec 合成 A4pt 容器；
 * - composeLongPng：逐页 drawPage(offsetY) 画入单张长图（内存预算内按比例缩放）；
 * - 系统通道全部免权限：DocumentViewPicker.save / systemShare / showAssetsCreationDialog
 *   （均需用户确认，自动化 E2E 以沙箱产物 + hdc file recv 校验为准）；
 * - 产物落 cacheDir/export/，同前缀历史产物合成前清理（避免陈旧文件干扰）。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { drawing } from '@kit.ArkGraphics2D';
import { PageRenderRequest, SheetRenderer } from '../render/SheetRenderer';
import { SheetLayout } from '../core/SheetLayout';
import { PdfCodec } from '../core/PdfCodec';

/** 系统通道交互结果。 */
export class ExportOutcome {
  /** 已落盘（用户确认保存/复制成功）。 */
  static readonly SAVED: number = 0;
  /** 用户取消（弹窗/面板未确认）。 */
  static readonly CANCEL: number = 1;
  /** 失败（服务/IO 异常）。 */
  static readonly FAIL: number = 2;
}

export class ExportUtil {
  /** 长图单帧像素内存预算（RGBA_8888 字节）。 */
  static readonly PNG_BUDGET_BYTES: number = 125829120;
  /** PDF 页渲染缩放（1 = A4 300dpi 全尺寸导出基准）。 */
  static readonly PDF_SCALE: number = 1;

  private static exportDir(ctx: common.Context): string {
    return ctx.cacheDir + '/export';
  }

  private static ensureDir(ctx: common.Context): boolean {
    const d: string = ExportUtil.exportDir(ctx);
    try {
      if (!fs.accessSync(d)) {
        fs.mkdirSync(d, true);
      }
      return true;
    } catch (e) {
      console.error(`[ExportUtil] ensureDir failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 清理同前缀历史产物（合成前调用，避免陈旧文件干扰 E2E/用户二次导出）。 */
  private static cleanPrefix(dir: string, prefix: string): void {
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      for (const name of fs.listFileSync(dir)) {
        if (name.indexOf(prefix) === 0) {
          fs.unlinkSync(dir + '/' + name);
        }
      }
    } catch (e) {
      // 清理失败不阻断导出
    }
  }

  private static withScale(r: PageRenderRequest, scale: number): PageRenderRequest {
    return new PageRenderRequest(r.items, r.layout, r.spec, r.pageIndex,
      r.pageLabel, r.fieldsText, r.showAnswers, scale);
  }

  /** 单页渲染 → PNG 文件（成功后显式释放位图与打包器）。 */
  private static async renderPng(req: PageRenderRequest, outPath: string): Promise<boolean> {
    let pm: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      pm = await SheetRenderer.renderPage(req);
      packer = image.createImagePacker();
      const file: fs.File = fs.openSync(outPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const opts: image.PackingOption = { format: 'image/png', quality: 100 };
        await packer.packToFile(pm, file.fd, opts);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      console.error(`[ExportUtil] renderPng failed: ${(e as Error).message}`);
      return false;
    } finally {
      if (packer !== null) {
        packer.release();
      }
      if (pm !== null) {
        pm.release();
      }
    }
  }

  /**
   * 页请求 → 沙箱 PDF（300dpi 页图 → A4pt 容器）。
   * @param baseName 产物基名（ASCII，如 sheet_lx3a2k；页图临时文件同前缀）
   * @returns PDF 沙箱路径；失败返回 null
   */
  static async composePdf(ctx: common.Context, reqs: PageRenderRequest[],
                          baseName: string): Promise<string | null> {
    if (reqs.length === 0 || !ExportUtil.ensureDir(ctx)) {
      return null;
    }
    const dir: string = ExportUtil.exportDir(ctx);
    ExportUtil.cleanPrefix(dir, baseName);
    const pngs: string[] = [];
    for (let i = 0; i < reqs.length; i++) {
      const path: string = `${dir}/${baseName}_p${i}.png`;
      if (!await ExportUtil.renderPng(ExportUtil.withScale(reqs[i], ExportUtil.PDF_SCALE), path)) {
        return null;
      }
      pngs.push(path);
    }
    const outPath: string = `${dir}/${baseName}.pdf`;
    const ok: boolean = await PdfCodec.composeA4(pngs, outPath);
    if (ok) {
      console.info(`[ExportUtil] pdf ready: ${outPath}`);
    }
    for (const p of pngs) {
      try {
        if (fs.accessSync(p)) {
          fs.unlinkSync(p);
        }
      } catch (e) {
        // 临时页图清理失败不影响结果
      }
    }
    return ok ? outPath : null;
  }

  /**
   * 页请求 → 单张纵向长图 PNG（逐页 drawPage offsetY 画入同一位图；
   * 超内存预算按 sqrt 比例整体缩放，页序保持）。
   */
  static async composeLongPng(ctx: common.Context, reqs: PageRenderRequest[],
                              baseName: string): Promise<string | null> {
    const n: number = reqs.length;
    if (n === 0 || !ExportUtil.ensureDir(ctx)) {
      return null;
    }
    const dir: string = ExportUtil.exportDir(ctx);
    ExportUtil.cleanPrefix(dir, baseName);
    const unitBytes: number = SheetLayout.PAGE_W * SheetLayout.PAGE_H * 4;
    const scale: number = Math.min(1, Math.sqrt(ExportUtil.PNG_BUDGET_BYTES / (unitBytes * n)));
    const w: number = Math.max(1, Math.round(SheetLayout.PAGE_W * scale));
    const h: number = Math.max(1, Math.round(SheetLayout.PAGE_H * scale));
    let pm: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(w * h * n * 4);
      new Uint8Array(buffer).fill(255);
      const opts: image.InitializationOptions = {
        size: { width: w, height: h * n },
        pixelFormat: image.PixelMapFormat.RGBA_8888
      };
      pm = await image.createPixelMap(buffer, opts);
      const canvas: drawing.Canvas = new drawing.Canvas(pm);
      for (let i = 0; i < n; i++) {
        SheetRenderer.drawPage(canvas, ExportUtil.withScale(reqs[i], scale), w, h * i);
      }
      const outPath: string = `${dir}/${baseName}_long.png`;
      packer = image.createImagePacker();
      const file: fs.File = fs.openSync(outPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
        await packer.packToFile(pm, file.fd, packOpts);
      } finally {
        fs.closeSync(file);
      }
      console.info(`[ExportUtil] long png ready: ${outPath}`);
      return outPath;
    } catch (e) {
      console.error(`[ExportUtil] composeLongPng failed: ${(e as Error).message}`);
      return null;
    } finally {
      if (packer !== null) {
        packer.release();
      }
      if (pm !== null) {
        pm.release();
      }
    }
  }

  /** 系统保存器（文件管理器选目录，免权限）。 */
  static async saveToDocument(uiContext: UIContext, srcPath: string,
                              fileName: string, suffix: string): Promise<number> {
    const ctx: Context | undefined = uiContext.getHostContext();
    if (ctx === undefined) {
      return ExportOutcome.FAIL;
    }
    try {
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = [fileName + suffix];
      opts.fileSuffixChoices = [suffix];
      const dp: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await dp.save(opts);
      if (uris.length === 0) {
        return ExportOutcome.CANCEL;
      }
      const src: fs.File = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      const dst: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dst.fd);
      } finally {
        fs.closeSync(src);
        fs.closeSync(dst);
      }
      return ExportOutcome.SAVED;
    } catch (e) {
      console.error(`[ExportUtil] saveToDocument failed: ${(e as Error).message}`);
      return ExportOutcome.FAIL;
    }
  }

  /** 系统分享面板（免权限）。 */
  static shareFile(uiContext: UIContext, path: string, fileSuffix: string): boolean {
    const ctx: Context | undefined = uiContext.getHostContext();
    if (ctx === undefined) {
      return false;
    }
    try {
      const uriStr: string = fileUri.getUriFromPath(path);
      const utdId: string = utd.getUniformDataTypeByFilenameExtension(fileSuffix);
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utdId,
        uri: uriStr
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.on('dismiss', () => {
      });
      controller.show(ctx as common.UIAbilityContext, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      return true;
    } catch (e) {
      console.error(`[ExportUtil] shareFile failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 长图 PNG → 系统相册（保存确认弹窗，免权限）。 */
  static async saveImageToAlbum(uiContext: UIContext, pngPath: string,
                                title: string): Promise<number> {
    const ctx: Context | undefined = uiContext.getHostContext();
    if (ctx === undefined) {
      return ExportOutcome.FAIL;
    }
    try {
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(ctx as common.UIAbilityContext);
      const srcUri: string = fileUri.getUriFromPath(pngPath);
      const config: photoAccessHelper.PhotoCreationConfig = {
        fileNameExtension: 'png',
        title: title,
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      const des: Array<string> = await helper.showAssetsCreationDialog([srcUri], [config]);
      if (des.length === 0) {
        return ExportOutcome.CANCEL;
      }
      const src: fs.File = fs.openSync(pngPath, fs.OpenMode.READ_ONLY);
      const dst: fs.File = await fs.open(des[0], fs.OpenMode.READ_WRITE);
      try {
        await fs.copyFile(src.fd, dst.fd);
      } finally {
        await fs.close(dst);
        fs.closeSync(src);
      }
      return ExportOutcome.SAVED;
    } catch (e) {
      console.error(`[ExportUtil] saveImageToAlbum failed: ${(e as Error).message}`);
      return ExportOutcome.FAIL;
    }
  }
}
