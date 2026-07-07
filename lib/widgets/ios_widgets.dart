import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator, Material, MaterialType;
import 'dart:ui';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../services/settings_service.dart';

extension CupertinoThemeDataX on CupertinoThemeData {
  CupertinoColorScheme get colorScheme => CupertinoColorScheme(this);
}

class CupertinoColorScheme {
  final CupertinoThemeData _theme;
  CupertinoColorScheme(this._theme);

  CupertinoThemeData get theme => _theme;

  Color get primary => _theme.primaryColor;
  Color get onPrimary => CupertinoColors.black;
  Color get onSurface => _theme.brightness == Brightness.dark ? CupertinoColors.white : CupertinoColors.black;
  Color get onSurfaceVariant => _theme.brightness == Brightness.dark ? const Color(0xFF9E9E9E) : CupertinoColors.systemGrey2;
  
  Color get surface {
    if (_theme.brightness != Brightness.dark) return const Color(0xFFFAFAFA);
    final isAmoled = SettingsService.instance.amoledTheme;
    return isAmoled ? const Color(0xFF121212) : const Color(0xFF1C1C1E);
  }
  
  Color get surfaceContainerHigh {
    if (_theme.brightness != Brightness.dark) return const Color(0xFFF0F0F0);
    final isAmoled = SettingsService.instance.amoledTheme;
    return isAmoled ? const Color(0xFF1E1E1E) : const Color(0xFF2C2C2E);
  }
  
  Color get surfaceContainerHighest {
    if (_theme.brightness != Brightness.dark) return const Color(0xFFE5E5EA);
    final isAmoled = SettingsService.instance.amoledTheme;
    return isAmoled ? const Color(0xFF2C2C2E) : const Color(0xFF3A3A3C);
  }
  
  Color get surfaceContainerLowest {
    if (_theme.brightness != Brightness.dark) return const Color(0xFFFFFFFF);
    final isAmoled = SettingsService.instance.amoledTheme;
    return isAmoled ? const Color(0xFF000000) : const Color(0xFF121212);
  }
  
  Color get outlineVariant {
    if (_theme.brightness != Brightness.dark) return const Color(0xFFE5E5EA);
    final isAmoled = SettingsService.instance.amoledTheme;
    return isAmoled ? const Color(0xFF1E1E1E) : const Color(0xFF2C2C2E);
  }
  
  Color get primaryContainer => _theme.primaryColor.withValues(alpha: 0.15);
  Color get error => CupertinoColors.systemRed;
  Color get onErrorContainer => CupertinoColors.white;
  Color get errorContainer => CupertinoColors.systemRed.withValues(alpha: 0.15);
  
  Color get onSecondaryContainer => onSurfaceVariant;
  Color get secondaryContainer => _theme.brightness == Brightness.dark
      ? const Color(0x1AFFFFFF)
      : const Color(0x0A000000);
  Color get shadow => CupertinoColors.black;
}

class GlassBox extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const GlassBox({
    super.key,
    required this.child,
    this.blur = 30.0,
    this.opacity = 0.2,
    this.borderRadius = 16.0,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final defaultBg = isDark
        ? const Color(0xCC1C1C1E)
        : const Color(0xCCFFFFFF);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          color: color ?? defaultBg,
          child: child,
        ),
      ),
    );
  }
}

class IOSSearchField extends StatelessWidget {
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextEditingController? controller;

  const IOSSearchField({
    super.key,
    this.placeholder = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: CupertinoSearchTextField(
        controller: controller,
        placeholder: placeholder,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        style: TextStyle(
          color: isDark ? CupertinoColors.white : CupertinoColors.black,
          fontSize: 15,
        ),
        placeholderStyle: TextStyle(
          color: isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2,
          fontSize: 15,
        ),
      ),
    );
  }
}

class IOSSettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const IOSSettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 6, top: 20),
            child: Text(
              title!.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.systemGrey,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? (SettingsService.instance.amoledTheme ? const Color(0xFF121212) : const Color(0xFF1C1C1E))
                : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: List.generate(children.length, (index) {
              return Column(
                children: [
                  children[index],
                  if (index < children.length - 1)
                    Container(
                      margin: const EdgeInsets.only(left: 52),
                      height: 0.5, 
                      color: isDark ? const Color(0x1AFFFFFF) : const Color(0x1F000000),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class IOSSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const IOSSettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: CupertinoColors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) 
              trailing! 
            else 
              const Icon(
                FluentIcons.chevron_right_24_regular, 
                color: CupertinoColors.systemGrey, 
                size: 14
              ),
          ],
        ),
      ),
    );
  }
}

class IOSSettingsSwitch extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const IOSSettingsSwitch({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: CupertinoColors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                fontSize: 15,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: CupertinoColors.systemGreen,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class IOSLoading extends StatelessWidget {
  final String? message;
  final double size;
  const IOSLoading({super.key, this.message, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? (SettingsService.instance.amoledTheme ? const Color(0xCC121212) : const Color(0xCC2C2C2E))
              : const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Material(
                type: MaterialType.transparency,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                ),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class IOSLoadingOverlay extends StatelessWidget {
  final String? message;
  const IOSLoadingOverlay({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.black.withValues(alpha: 0.4),
      child: Center(
        child: IOSLoading(message: message, size: 48),
      ),
    );
  }
}

class ConstrainedBottomSheet extends StatelessWidget {
  final Widget child;
  const ConstrainedBottomSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.75,
        ),
        child: child,
      ),
    );
  }
}

class CompactActionSheet extends StatelessWidget {
  final Widget? title;
  final Widget? message;
  final List<Widget> actions;
  final Widget? cancelButton;

  const CompactActionSheet({
    super.key,
    this.title,
    this.message,
    required this.actions,
    this.cancelButton,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final isAmoled = SettingsService.instance.amoledTheme;
    final bgColor = isDark
        ? (isAmoled ? const Color(0xEE121212) : const Color(0xEE1C1C1E))
        : const Color(0xEEE5E5EA);
    final screenH = MediaQuery.of(context).size.height;
    // Cap the actions pane to 55% of the screen height so the sheet never
    // takes over the full display. Content scrolls if it overflows.
    final maxActionsH = screenH * 0.55;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 20),
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Actions container — scrollable when many items
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    color: bgColor,
                    // Constrain height so it never overflows the screen
                    constraints: BoxConstraints(maxHeight: maxActionsH),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null || message != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? const Color(0x1AFFFFFF) : const Color(0x0F000000),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (title != null)
                                  DefaultTextStyle(
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2,
                                    ),
                                    textAlign: TextAlign.center,
                                    child: title!,
                                  ),
                                if (title != null && message != null)
                                  const SizedBox(height: 2),
                                if (message != null)
                                  DefaultTextStyle(
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? CupertinoColors.systemGrey2 : CupertinoColors.systemGrey,
                                    ),
                                    textAlign: TextAlign.center,
                                    child: message!,
                                  ),
                              ],
                            ),
                          ),
                        // Scrollable actions list
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            physics: const BouncingScrollPhysics(),
                            itemCount: actions.length,
                            separatorBuilder: (_, _) => Container(
                              height: 0.5,
                              color: isDark ? const Color(0x1AFFFFFF) : const Color(0x0F000000),
                            ),
                            itemBuilder: (_, i) => actions[i],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (cancelButton != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: double.infinity,
                      color: isDark
                          ? (isAmoled ? const Color(0xFF121212) : const Color(0xFF1C1C1E))
                          : CupertinoColors.white,
                      child: cancelButton!,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CompactActionSheetAction extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final bool isDestructiveAction;
  final bool isDefaultAction;

  const CompactActionSheetAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDestructiveAction = false,
    this.isDefaultAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    Color textColor = isDestructiveAction
        ? CupertinoColors.systemRed
        : (isDark ? CupertinoColors.white : CupertinoColors.black);

    if (isDefaultAction && !isDestructiveAction) {
      textColor = CupertinoColors.systemBlue;
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 38,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 14,
            fontWeight: isDefaultAction ? FontWeight.w600 : FontWeight.w400,
            color: textColor,
          ),
          child: child,
        ),
      ),
    );
  }
}
