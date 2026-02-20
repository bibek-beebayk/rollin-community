import 'package:flutter/material.dart';

class ChatRouteObserver extends NavigatorObserver {
  final ValueNotifier<bool> isChatScreenVisible = ValueNotifier(false);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _checkRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _checkRoute(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _checkRoute(newRoute);
    }
  }

  void _checkRoute(Route<dynamic> route) {
    final isChat = route.settings.name == 'ChatScreen';
    if (isChatScreenVisible.value != isChat) {
      isChatScreenVisible.value = isChat;
    }
  }
}
