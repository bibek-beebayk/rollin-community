import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../screens/chat_screen.dart';
import '../theme/app_theme.dart';
import '../main.dart';

class GlobalChatBubble extends StatelessWidget {
  const GlobalChatBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: StaffChatApp.chatRouteObserver.isChatScreenVisible,
      builder: (context, isChatVisible, child) {
        if (isChatVisible) return const SizedBox.shrink();

        final auth = context.watch<AuthProvider>();

        // Only show if authenticated and NOT a staff member (staff uses Dashboard)
        // If you want it for staff too, remove `|| auth.isStaff`
        if (!auth.isAuthenticated || auth.isStaff) {
          return const SizedBox.shrink();
        }

        // Hide on specific screens if needed?
        // The bubble is in Overlay, so it stays on top.

        return Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            heroTag: 'global_support_chat_fab', // Unique tag to avoid conflicts
            onPressed: () => _openChat(context),
            backgroundColor: AppTheme.primary,
            elevation: 6,
            child: const Icon(Icons.support_agent, color: Colors.white),
          ),
        );
      },
    );
  }

  Future<void> _openChat(BuildContext context) async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    try {
      final room = await chatProvider.joinSupportRoom(authProvider.apiClient);

      if (room != null) {
        // Use the global navigator key to push the ChatScreen
        StaffChatApp.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(room: room),
            settings: const RouteSettings(name: 'ChatScreen'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No active support session found. Please contact admin.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
