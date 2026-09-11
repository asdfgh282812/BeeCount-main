import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../ai/core/prompt_builder.dart';
import '../ai/providers/ai_provider_config.dart';
import '../ai/providers/ai_provider_manager.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../providers/ai_chat_providers.dart';
import '../services/attachment_service.dart';
import '../services/billing/post_processor.dart';
import '../services/data/tag_seed_service.dart';
import '../widgets/biz/account_card_picker.dart';
import '../widgets/biz/project_picker.dart';
import '../widgets/ui/ui.dart';

/// 图片记账入口(相册/相机/剪贴板)。瘦身后:UI 流程 + 兜底,业务调 [AiBookkeeper]。
class ImageBillingHelper {
  /// 剪贴板图片支持的格式;文件扩展名需与实际数据匹配,
  /// 否则 Gemini 等按扩展名猜 MIME 类型的供应商会解析失败,见
  /// ai_provider_factory.dart 的 `_visionGemini`。
  static const _clipboardImageFormats = [
    Formats.png,
    Formats.jpeg,
    Formats.webp,
    Formats.heic,
    Formats.heif,
  ];

  /// 从相册选择图片并自动记账;若剪贴板中恰好有图片,先弹出来源选择
  /// (剪贴板/相册),否则直接打开相册,行为与之前一致。
  static Future<void> pickImageForBilling(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final hasClipboardImage = await _clipboardHasImage();
    if (!context.mounted) return;

    if (hasClipboardImage) {
      final l10n = AppLocalizations.of(context);
      final fromClipboard = await _showImageSourceSheet(context, l10n);
      if (fromClipboard == null) return;
      if (!context.mounted) return;

      if (fromClipboard) {
        final file = await _readClipboardImageFile();
        if (file == null) return;
        if (!context.mounted) return;
        await _processImageBilling(
          context,
          ref,
          ImageSource.gallery,
          pickedImage: file,
        );
        return;
      }
    }

    await _processImageBilling(context, ref, ImageSource.gallery);
  }

  /// 打开相机拍照并自动记账
  static Future<void> openCameraForBilling(
    BuildContext context,
    WidgetRef ref,
  ) =>
      _processImageBilling(context, ref, ImageSource.camera);

  /// 剪贴板是否当前持有受支持格式的图片(仅探测,不读取内容)
  static Future<bool> _clipboardHasImage() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return false;
      final reader = await clipboard.read();
      return _clipboardImageFormats.any(reader.canProvide);
    } catch (_) {
      return false;
    }
  }

  /// 弹出「从剪贴板 / 从相册」选择;返回 true=剪贴板,false=相册,null=取消
  static Future<bool?> _showImageSourceSheet(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: Text(l10n.imageBillingPasteFromClipboard),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.attachmentChooseFromGallery),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }

  /// 读取剪贴板图片并写入临时文件;失败或剪贴板内容已变化则返回 null
  static Future<File?> _readClipboardImageFile() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return null;
      final reader = await clipboard.read();
      final format = _clipboardImageFormats
          .firstWhere(reader.canProvide, orElse: () => Formats.png);
      if (!reader.canProvide(format)) return null;

      final completer = Completer<Uint8List?>();
      reader.getFile(
        format,
        (file) async => completer.complete(await file.readAll()),
        onError: (_) => completer.complete(null),
      );
      final bytes = await completer.future;
      if (bytes == null || bytes.isEmpty) return null;

      final tempDir = await getTemporaryDirectory();
      final ext = _extensionForFormat(format);
      final path =
          '${tempDir.path}/clipboard_bill_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File(path);
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  static String _extensionForFormat(SimpleFileFormat format) {
    if (format == Formats.png) return 'png';
    if (format == Formats.webp) return 'webp';
    if (format == Formats.heic) return 'heic';
    if (format == Formats.heif) return 'heif';
    return 'jpg';
  }

  static Future<void> _processImageBilling(
    BuildContext context,
    WidgetRef ref,
    ImageSource source, {
    File? pickedImage,
  }) async {
    final l10n = AppLocalizations.of(context);

    try {
      // 1. 选图(剪贴板已在外层取好文件时跳过 ImagePicker)
      File imageFile;
      if (pickedImage != null) {
        imageFile = pickedImage;
      } else {
        final pickedFile = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (pickedFile == null) return;
        if (!context.mounted) return;
        imageFile = File(pickedFile.path);
      }
      if (!context.mounted) return;

      // 2. 显示 loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.aiOcrRecognizing),
                ],
              ),
            ),
          ),
        ),
      );

      // 3. AI vision 兜底
      if (!await AIProviderManager.isCapabilityConfigured(
          AICapabilityType.vision)) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        showToast(context, l10n.aiNotConfiguredHint);
        return;
      }

      // 4. 当前账本
      final currentLedger = await ref.read(currentLedgerProvider.future);
      if (currentLedger == null) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        showToast(context, l10n.aiOcrNoLedger);
        return;
      }

      // 5. 委托 AiBookkeeper(自动查 categories/accounts + 多笔保存)
      final autoAddAttachment = ref.read(smartBillingAutoAttachmentProvider);
      final billingTypes = <String>[
        source == ImageSource.gallery
            ? TagSeedService.billingTypeImage
            : TagSeedService.billingTypeCamera,
        TagSeedService.billingTypeAi,
      ];

      final attachmentService = ref.read(attachmentServiceProvider);
      final bookkeeper = ref.read(aiBookkeeperProvider);
      final result = await bookkeeper.fromImage(
        image: imageFile,
        ledgerId: currentLedger.id,
        billGuard: PromptBuilder.billGuardForImage,
        billingTypes: billingTypes,
        l10n: l10n,
        resolveMissingAccount: (bill) async {
          if (!context.mounted) return null;
          final picked = await AccountCardPicker.show(context,
              ledgerId: currentLedger.id);
          return picked?.accountId;
        },
        resolveMissingProject: (bill) async {
          if (!context.mounted) return null;
          final picked =
              await ProjectPicker.show(context, ledgerId: currentLedger.id);
          return picked?.project?.id;
        },
        // 多笔时每笔都挂同一张原图,方便后续从任意一笔溯源
        onSaved: autoAddAttachment
            ? (txId, _) => attachmentService.saveAttachment(
                  transactionId: txId,
                  sourceFile: imageFile,
                  index: 0,
                )
            : null,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop();

      // 6. 提示用户
      if (!result.success) {
        // failedCount>0:提取到账单但入库失败(真·错误);否则=AI 判定不是账单/没提取到
        showToast(context,
            result.failedCount > 0 ? l10n.aiOcrCheckLog : l10n.aiOcrNoBill);
        return;
      }

      await PostProcessor.run(
        ref,
        ledgerId: currentLedger.id,
        tags: true,
        attachments: autoAddAttachment,
      );
      if (!context.mounted) return;

      final firstBill = result.firstBill!;
      final typeText = firstBill.type?.name == 'income'
          ? l10n.aiTypeIncome
          : l10n.aiTypeExpense;
      final amountStr = result.totalAbsAmount.toStringAsFixed(2);
      final toastText = result.isMulti
          ? '${l10n.aiOcrSuccess(typeText, amountStr)} × ${result.savedCount}'
          : l10n.aiOcrSuccess(typeText, amountStr);
      // 多币种降级提示(A5):缺汇率已按 1:1 暂记,指路统计页补折算
      final rateMissingHint = result.unconvertedCurrencies.isEmpty
          ? null
          : l10n.aiBillingRateMissingHint(
              result.unconvertedCurrencies.join('、'));
      // 缺帳戶且使用者取消選擇時被主動略過的筆數
      final accountSkippedHint = result.skippedForMissingAccountCount <= 0
          ? null
          : l10n.aiBillingAccountSkippedHint(
              result.skippedForMissingAccountCount);
      final note = [rateMissingHint, accountSkippedHint]
          .whereType<String>()
          .join('\n');
      showToast(
        context,
        note.isEmpty ? toastText : '$toastText\n$note',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      showToast(context, l10n.aiOcrFailed(e.toString()));
    }
  }
}
