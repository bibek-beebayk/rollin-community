import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.96),
        elevation: 0,
        title: Text(
          'Appearance',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Theme',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ],
                    selected: <ThemeMode>{themeProvider.themeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        final selected = selection.first;
                        themeProvider.setThemeMode(selected);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Accent Color',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ThemeProvider.accentPresets.map((color) {
                final isSelected =
                    color.toARGB32() == themeProvider.accentColor.toARGB32();
                return InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => themeProvider.setAccentColor(color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : AppTheme.cardBorder,
                        width: isSelected ? 2.5 : 1.2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check, color: AppTheme.textPrimary, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Visual Style',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  SegmentedButton<VisualStyle>(
                    segments: const [
                      ButtonSegment(
                        value: VisualStyle.card,
                        label: Text('Card Design'),
                      ),
                      ButtonSegment(
                        value: VisualStyle.flat,
                        label: Text('Flat Design'),
                      ),
                    ],
                    selected: <VisualStyle>{themeProvider.visualStyle},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        final selected = selection.first;
                        themeProvider.setVisualStyle(selected);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    themeProvider.visualStyle == VisualStyle.card
                        ? 'Floating containers with depth'
                        : 'Integrated surfaces and minimal borders',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Text(
                'Theme and appearance choices are saved on this device.',
                style: TextStyle(fontSize: 13),
              ),
            ),

          ],





        ),
      ),
    );
  }
}
