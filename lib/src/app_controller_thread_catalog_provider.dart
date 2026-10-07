import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller_codex_controller.dart';
import 'app_controller_thread_catalog_snapshot.dart';

/// Publishes only the immutable sidebar catalog needed by thread-list UI.
final codexThreadCatalogSnapshotProvider = Provider.autoDispose
    .family<CodexThreadCatalogSnapshot, CodexController>((ref, controller) {
      void publish() => ref.invalidateSelf();
      controller.addListener(publish);
      ref.onDispose(() => controller.removeListener(publish));
      return CodexThreadCatalogSnapshot.fromValues(
        threads: controller.threads,
        archivedThreads: controller.archivedThreads,
        threadsLoading: controller.threadsLoading,
        threadsError: controller.threadsError,
        archivedThreadsLoading: controller.archivedThreadsLoading,
        archivedThreadsError: controller.archivedThreadsError,
        localThreadStatuses: controller.localThreadStatusesForSnapshot(),
      );
    });
