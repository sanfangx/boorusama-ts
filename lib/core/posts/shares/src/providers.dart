// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cache_manager/cache_manager.dart';
import 'package:coreutils/coreutils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import '../../../../foundation/filesystem.dart';
import '../../../configs/config/types.dart';
import '../../../downloads/filename/types.dart';
import '../../details/providers.dart';
import '../../post/types.dart';
import 'share.dart';

final shareProvider = Provider.autoDispose((ref) => ShareService(ref));

class ShareService {
  ShareService(this.ref);

  final Ref ref;

  Future<void> sharePost(
    Post post,
    BooruConfigAuth config, {
    required BuildContext context,
    required BooruConfigViewer configViewer,
    required BooruConfigDownload download,
    required DownloadFilenameGenerator? filenameBuilder,
    required ImageCacheManager imageCacheManager,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    Rect? rect;
    if (box != null && box.hasSize) {
      rect = box.localToGlobal(Offset.zero) & box.size;
    }

    final mediaUrlResolver = ref.read(mediaUrlResolverProvider(config));
    final imageUrl = mediaUrlResolver.resolveMediaUrl(post, configViewer);

    if (imageUrl == null) return;

    final imageExt = post.format;

    final ext = urlExtension(imageUrl);
    final effectiveExt = ext.isNotEmpty ? ext : imageExt;

    final cacheKey = imageCacheManager.generateCacheKey(imageUrl);
    final filePath = await imageCacheManager.getCachedFilePath(cacheKey);

    if (filePath == null || effectiveExt == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait for the image to load before sharing')),
        );
      }
      return;
    }

    final newPath = filePath + effectiveExt;
    final fs = ref.read(appFileSystemProvider);
    final file = fileCopySync(fs, filePath, newPath);

    if (file != null) {
      SharePlus.instance.share(
        ShareParams(
          files: [file],
          subject: file.name,
          sharePositionOrigin: rect,
        ),
      );
    }
  }
}
