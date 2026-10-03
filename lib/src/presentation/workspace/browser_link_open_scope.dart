import 'package:flutter/widgets.dart';

/// Opens a user-activated HTTP(S) link in the retained browser workspace.
typedef BrowserLinkOpenCallback = Future<bool> Function(Uri uri);

/// Exposes the workspace's internal browser link policy to timeline links.
class BrowserLinkOpenScope extends InheritedWidget {
  const BrowserLinkOpenScope({
    required this.onOpenBrowserLink,
    required super.child,
    super.key,
  });

  final BrowserLinkOpenCallback onOpenBrowserLink;

  static BrowserLinkOpenCallback? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<BrowserLinkOpenScope>()
      ?.onOpenBrowserLink;

  @override
  bool updateShouldNotify(BrowserLinkOpenScope oldWidget) =>
      onOpenBrowserLink != oldWidget.onOpenBrowserLink;
}
