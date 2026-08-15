// Flutter imports:
import 'package:flutter/material.dart';

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart' hide PermissionStatus;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:i18n/i18n.dart';
import 'package:oktoast/oktoast.dart';

// Project imports:
import '../../../../../foundation/loggers.dart';
import '../../../../../foundation/permissions.dart';
import '../../../../../foundation/platform.dart';
import 'package:gal/gal.dart';
import '../../../../../foundation/toast.dart';
import '../../../../configs/config/types.dart';
import '../../../../ddos/handler/providers.dart';
import '../../../../http/client/types.dart';
import '../../../../http/client/providers.dart';
import '../../../../download_manager/providers.dart';
import '../../../../posts/post/types.dart';
import '../../../../router.dart';
import '../../../../settings/types.dart';
import '../../../filename/types.dart';
import '../../../urls/types.dart';
import '../types/download.dart';
import '../types/metadata.dart';
import '../types/observer.dart';

final downloadNotifierProvider =
    NotifierProvider.family<DownloadNotifier, void, DownloadNotifierParams>(
      DownloadNotifier.new,
    );

typedef DownloadNotifierParams = ({
  BooruConfigAuth auth,
  BooruConfigDownload download,
  String? profileIconUrl,
  DownloadFileUrlExtractor downloadFileUrlExtractor,
  DownloadFilenameGenerator? filenameBuilder,
  DownloadObserver? observer,
  MultipleFileDownloadCheck canDownloadMultipleFiles,
  Map<String, String> headers,
  Settings settings,
  DownloadService downloader,
  Logger logger,
});

typedef MultipleFileDownloadCheck = bool Function();

class DownloadNotifier extends FamilyNotifier<void, DownloadNotifierParams> {
  @override
  void build(DownloadNotifierParams arg) {
    return;
  }

 Future<PermissionStatus?> _getPermissionStatus() async {
   final perm = await ref.read(deviceStoragePermissionProvider.future);
    // iOS does not have a Storage permission — the app writes to its
    // own sandboxed Documents directory which requires no user grant.
    if (isIOS()) return null;
    return isAndroid() ? perm.storagePermission : null;
 }

  void _showToastIfPossible({String? message}) {
    final context = navigatorKey.currentState?.context;

    if (context != null && context.mounted) {
      showDownloadStartToast(context, message: message);
    }
  }

  Future<DownloadTaskInfo?> download(
    Post post, {
    String? overrideUrl,
  }) async {
    final perm = await _getPermissionStatus();
    final observer = arg.observer;

    final info = await _download(
      ref,
      post,
      params: arg,
      permission: perm,
      overrideUrl: overrideUrl,
      onStarted: () {
        final c = navigatorKey.currentState?.context;
        if (c != null) {
          showDownloadStartToast(c);
        }

        observer?.onSingleDownloadStart();
      },
    );

    return info;
  }

  Future<void> bulkDownload(
    List<Post> posts, {
    String? group,
    String? downloadPath,
  }) async {
    // ensure that the booru supports bulk download
    if (!arg.canDownloadMultipleFiles()) {
      final context = navigatorKey.currentState?.context;

      showBulkDownloadUnsupportErrorToast(context);
      return;
    }

    final perm = await _getPermissionStatus();

    _showToastIfPossible(
      message: 'Downloading ${posts.length} files...',
    );

    arg.observer?.onBulkDownloadStart(
      total: posts.length,
    );

    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      await _download(
        ref,
        post,
        params: arg,
        permission: perm,
        group: group,
        downloadPath: downloadPath,
        bulkMetadata: {
          'total': posts.length.toString(),
          'index': i.toString(),
        },
      );
    }
  }
}

Future<DownloadTaskInfo?> _download(
  Ref ref,
  Post downloadable, {
  required DownloadNotifierParams params,
  PermissionStatus? permission,
  String? group,
  String? downloadPath,
  Map<String, String>? bulkMetadata,
  void Function()? onStarted,
  //FIXME: bad solution, need better design
  String? overrideUrl,
}) async {
  final downloadConfig = params.download;
  final service = params.downloader;
  final fileNameBuilder = params.filenameBuilder;
  final logger = params.logger;

  final headers = params.headers;

  final deviceStoragePermissionNotifier = ref.read(
    deviceStoragePermissionProvider.notifier,
  );

  final notificationPermManager = ref.read(
    notificationPermissionManagerProvider,
  );

  final extractedUrlData = await params.downloadFileUrlExtractor
      .getDownloadFileUrl(
        post: downloadable,
        quality: params.settings.downloadQuality.name,
      );

  final urlData = overrideUrl != null
      ? DownloadUrlData(
          url: overrideUrl,
          cookie: null,
        )
      : extractedUrlData;

  if (fileNameBuilder == null) {
    logger.error('Single Download', 'No file name builder found, aborting...');
    // if (ref.context.mounted) {
    //   showErrorToast(ref.context, 'Download aborted, cannot create file name');
    // }
    return null;
  }

  if (urlData == null || urlData.url.isEmpty) {
    logger.error('Single Download', 'No download url found, aborting...');
    // if (ref.context.mounted) {
    //   showErrorToast(ref.context, 'Download aborted, no download url found');
    // }
    return null;
  }

  Future<DownloadTaskInfo?> download() async {
    final fileNameFuture = bulkMetadata != null
        ? fileNameBuilder.generateForBulkDownload(
            params.settings,
            downloadConfig,
            downloadable,
            metadata: bulkMetadata,
            downloadUrl: urlData.url,
          )
        : fileNameBuilder.generate(
            params.settings,
            downloadConfig,
            downloadable,
            downloadUrl: urlData.url,
          );

    final fileName = await fileNameFuture;

    final bypassHeaders = await ref.read(
      bypassDdosHeadersProvider(urlData.url).future,
    );

    // On iOS, save directly to Photos if saveToGallery is enabled
    if (isIOS() && params.settings.saveToGallery) {
      try {
        onStarted?.call();

        final context = navigatorKey.currentState?.context;
        if (context != null && context.mounted) {
          showToast(
            'Saving to Photos...',
            context: context,
            position: const ToastPosition(align: Alignment.topCenter),
            textPadding: const EdgeInsets.all(12),
            textStyle: TextStyle(color: Theme.of(context).colorScheme.surface),
            backgroundColor: Theme.of(context).colorScheme.onSurface,
          );
        }

        final dio = ref.read(dioForWidgetProvider(params.auth));
        final taskId = 'gal_${DateTime.now().millisecondsSinceEpoch}';
        final task = DownloadTask(
          taskId: taskId,
          url: urlData.url,
          filename: fileName,
          group: '${group ?? FileDownloader.defaultGroup}',
          headers: urlData.cookie != null
              ? {AppHttpHeaders.cookieHeader: urlData.cookie!}
              : null,
        );
        final updates = ref.read(downloadTaskUpdatesProvider.notifier);
        updates.addOrUpdate(
          TaskStatusUpdate(task, TaskStatus.enqueued),
        );

        final tempDir = await Directory.systemTemp.createTemp('boorusama_');
        final tempPath = '${tempDir.path}/$fileName';
        final startTime = DateTime.now();

        await dio.download(
          urlData.url,
          tempPath,
          onReceiveProgress: (received, total) {
            final progress = total > 0 ? received / total : 0.0;
            final elapsed = DateTime.now().difference(startTime);
            final speed = elapsed.inMilliseconds > 0
                ? received / (elapsed.inMilliseconds / 1000) / (1024 * 1024)
                : 0.0;
            final remaining = speed > 0 && total > 0
                ? Duration(
                    milliseconds:
                        ((total - received) / (received / elapsed.inMilliseconds))
                            .round())
                : null;
            updates.addOrUpdate(
              TaskProgressUpdate(task, progress),
            );
          },
          options: Options(headers: {
            ...headers,
            ...bypassHeaders,
            if (urlData.cookie != null)
              AppHttpHeaders.cookieHeader: urlData.cookie!,
          }),
        );

        if (downloadable.isVideo) {
          await Gal.putVideo(tempPath);
        } else {
          await Gal.putImage(tempPath);
        }

        // We DO NOT delete tempDir here because the share feature might need tempPath
        // The OS will automatically clean up the system temp directory later.

        updates.addOrUpdate(
          TaskStatusUpdate(task, TaskStatus.complete),
        );

        if (context != null && context.mounted) {
          showToast(
            'Saved to Photos',
            context: context,
            position: const ToastPosition(align: Alignment.topCenter),
            backgroundColor: Colors.green,
          );
        }

        return DownloadTaskInfo(path: tempPath, id: taskId);
      } on GalException catch (e) {
        logger.error('iOS Download', 'Failed to save to Photos: ${e.type}');
        showDownloadErrorToast(
          navigatorKey.currentState?.context,
          'Failed to save to Photos',
        );
        return null;
      } catch (e) {
        logger.error('iOS Download', 'Download failed: $e');
        showDownloadErrorToast(
          navigatorKey.currentState?.context,
          'Download failed',
        );
        return null;
      }
    }

    final result = await service.download(

      DownloadOptions.fromSettings(
        params.settings,
        config: downloadConfig,
        metadata: DownloaderMetadata(
          thumbnailUrl: downloadable.thumbnailImageUrl,
          fileSize: downloadable.fileSize,
          siteUrl: params.auth.url,
          profileIconUrl: params.profileIconUrl,
          group: group,
          isVideo: downloadable.isVideo,
        ),
        url: urlData.url,
        filename: fileName,
        headers: {
          ...headers,
          ...bypassHeaders,
          if (urlData.cookie != null)
            AppHttpHeaders.cookieHeader: urlData.cookie!,
        },
        customPath: downloadPath,
      ),
    );

    return switch (result) {
      DownloadSuccess(:final info) => () {
        onStarted?.call();

        return info;
      }(),
      final DownloadFailure e => () {
        final msg = e.error.getErrorMessage();

        logger.error(
          'Single Download',
          msg,
        );

        showDownloadErrorToast(
          navigatorKey.currentState?.context,
          msg,
        );
      }(),
    };
  }

  await notificationPermManager.requestIfNotGranted();

  // Platform doesn't require permissions, just download it right away
  if (permission == null) {
    return download();
  }

  if (permission == PermissionStatus.granted) {
    return download();
  } else {
    logger.info('Single Download', 'Permission not granted, requesting...');
    DownloadTaskInfo? info;

    await deviceStoragePermissionNotifier.requestPermission(
      onDone: (isGranted) async {
        if (isGranted) {
          info = await download();
        } else {
          logger.info(
            'Single Download',
            'Storage permission request denied, aborting...',
          );
        }
      },
    );

    return info;
  }
}

void showDownloadErrorToast(
  BuildContext? context,
  String message,
) {
  if (context == null) return;
  if (!context.mounted) return;

  showErrorToast(
    context,
    duration: const Duration(seconds: 5),
    message,
  );
}

void showDownloadStartToast(BuildContext context, {String? message}) {
  showToast(
    message ?? context.t.download.notification.started,
    context: context,
    position: const ToastPosition(
      align: Alignment.bottomCenter,
    ),
    textPadding: const EdgeInsets.all(12),
    textStyle: TextStyle(color: Theme.of(context).colorScheme.surface),
    backgroundColor: Theme.of(context).colorScheme.onSurface,
  );
}

void showBulkDownloadUnsupportErrorToast(BuildContext? context) {
  if (context == null) return;

  showErrorToast(
    context,
    duration: const Duration(seconds: 3),
    'This booru does not support downloading multiple files',
  );
}
