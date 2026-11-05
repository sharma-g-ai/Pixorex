import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ppg_format.dart';
import 'ppg_tokens.dart';

/// Applies the PPG theme to one route. Routes are built under the Navigator,
/// so each PPG screen wraps itself rather than inheriting from the hub.
class PpgThemed extends StatelessWidget {
  const PpgThemed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: buildPpgTheme(Theme.of(context)), child: child);
}

/// The three receiving stages from the PPG workflow spec.
const ppgStages = ['Document', 'Count', 'Submit'];

/// Navy page header: back, title, optional actions and the stage stepper.
class PpgHeader extends StatelessWidget {
  const PpgHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.monoTitle = false,
    this.subtitle,
    this.stage,
    this.completedStages,
    this.onStageTap,
    this.actions = const [],
    this.onBack,
    this.backTooltip = 'Back',
    this.showBack = true,
    this.bottom,
  });

  final String? eyebrow;
  final String title;
  final bool monoTitle;
  final String? subtitle;

  /// Zero-based current stage; null hides the stepper.
  final int? stage;

  /// Stages shown as done. Defaults to every stage before [stage].
  final Set<int>? completedStages;

  /// Makes the other stages tappable so the operator can jump to them.
  final ValueChanged<int>? onStageTap;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final String backTooltip;
  final bool showBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final titleStyle = monoTitle
        ? PpgText.mono(size: 20, color: Colors.white)
        : const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.2,
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: PpgColors.navy,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              showBack ? PpgSpace.s : PpgSpace.l,
              PpgSpace.s,
              PpgSpace.s,
              stage == null && bottom == null ? PpgSpace.m : PpgSpace.l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (showBack)
                      IconButton(
                        tooltip: backTooltip,
                        color: Colors.white,
                        onPressed:
                            onBack ?? () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      ),
                    const SizedBox(width: PpgSpace.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null)
                            Text(
                              eyebrow!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: PpgColors.onNavyMuted,
                              ),
                            ),
                          Text(
                            title,
                            style: titleStyle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: PpgColors.onNavyMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
                if (stage != null) ...[
                  const SizedBox(height: PpgSpace.m),
                  Padding(
                    padding: EdgeInsets.only(
                      left: showBack ? PpgSpace.s : 0,
                      right: PpgSpace.s,
                    ),
                    child: PpgStageStepper(
                      current: stage!,
                      completed:
                          completedStages ??
                          {for (var i = 0; i < stage!; i++) i},
                      onTap: onStageTap,
                    ),
                  ),
                ],
                if (bottom != null) ...[
                  const SizedBox(height: PpgSpace.l),
                  Padding(
                    padding: EdgeInsets.only(
                      left: showBack ? PpgSpace.s : 0,
                      right: PpgSpace.s,
                    ),
                    child: bottom!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PpgStageStepper extends StatelessWidget {
  const PpgStageStepper({
    super.key,
    required this.current,
    required this.completed,
    this.onTap,
  });

  final int current;
  final Set<int> completed;

  /// Called with the stage index when a stage other than [current] is tapped.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap != null) {
      return Row(
        children: [
          for (var i = 0; i < ppgStages.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _tappableStage(i)),
          ],
        ],
      );
    }
    return Semantics(
      label:
          'Stage ${current + 1} of ${ppgStages.length}: ${ppgStages[current]}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < ppgStages.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: completed.contains(i)
                          ? PpgColors.stepDone
                          : i == current
                          ? PpgColors.stepCurrent
                          : PpgColors.stepTodo,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${i + 1} ${ppgStages[i]}${completed.contains(i) ? ' ✓' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == current
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: completed.contains(i)
                          ? PpgColors.stepDoneText
                          : i == current
                          ? Colors.white
                          : PpgColors.stepTodoText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tappableStage(int i) {
    final done = completed.contains(i);
    final isCurrent = i == current;
    final textColor = isCurrent
        ? Colors.white
        : done
        ? PpgColors.stepDoneText
        : PpgColors.onNavyMuted;
    return Semantics(
      button: !isCurrent,
      selected: isCurrent,
      label:
          'Stage ${i + 1}: ${ppgStages[i]}${done ? ', done' : ''}${isCurrent ? ', current' : ''}',
      excludeSemantics: true,
      child: Material(
        color: isCurrent ? PpgColors.stepCurrentFill : PpgColors.stepTapFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isCurrent
              ? const BorderSide(color: PpgColors.stepCurrentOutline)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('ppg-stage-$i'),
          onTap: isCurrent ? null : () => onTap!(i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: done
                          ? PpgColors.stepDone
                          : isCurrent
                          ? PpgColors.stepCurrent
                          : PpgColors.stepTodo,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1} ${ppgStages[i]}${done ? ' ✓' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (!isCurrent)
                        Icon(Icons.chevron_right, size: 16, color: textColor),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PpgStatusBadge extends StatelessWidget {
  const PpgStatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final PpgTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 12 : 12.5,
          fontWeight: FontWeight.w600,
          color: tone.foreground,
        ),
      ),
    );
  }
}

class PpgSectionLabel extends StatelessWidget {
  const PpgSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: PpgText.sectionLabel),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: PpgText.figures(
                size: 13,
                weight: FontWeight.w400,
                color: PpgColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// White, outlined container for grouped rows.
class PpgPanel extends StatelessWidget {
  const PpgPanel({
    super.key,
    required this.child,
    this.padding,
    this.tone,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final PpgTone? tone;

  /// Panel background; white when null.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    // A Material (not a DecoratedBox) so row ink and list tiles paint on it.
    return Material(
      color: fill ?? Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PpgRadii.large),
        side: BorderSide(color: tone?.border ?? PpgColors.line),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// A row inside a [PpgPanel]; separators are drawn between siblings.
class PpgRow extends StatelessWidget {
  const PpgRow({
    super.key,
    required this.title,
    this.monoTitle = false,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.highlight,
    this.showChevron,
    this.semanticLabel,
  });

  final String title;
  final bool monoTitle;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? highlight;
  final bool? showChevron;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chevron = showChevron ?? onTap != null;
    final content = Ink(
      color: highlight,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: monoTitle
                        ? PpgText.mono()
                        : const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: PpgColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (chevron) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: PpgColors.link),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) {
      return Semantics(label: semanticLabel, child: content);
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Puts dividers between rows of a panel.
List<Widget> ppgDivided(Iterable<Widget> rows) {
  final result = <Widget>[];
  for (final row in rows) {
    if (result.isNotEmpty) {
      result.add(const Divider(height: 1, color: PpgColors.divider));
    }
    result.add(row);
  }
  return result;
}

class PpgBanner extends StatelessWidget {
  const PpgBanner({
    super.key,
    required this.tone,
    required this.message,
    this.title,
    this.icon,
    this.action,
  });

  final PpgTone tone;
  final String? title;
  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PpgSpace.m),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(PpgRadii.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ??
                switch (tone) {
                  PpgTone.success => Icons.check_circle_outline,
                  PpgTone.danger => Icons.error_outline,
                  PpgTone.warning => Icons.warning_amber_rounded,
                  _ => Icons.info_outline,
                },
            size: 20,
            color: tone.foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tone.foreground,
                    ),
                  ),
                Text(
                  message,
                  style: TextStyle(fontSize: 14, color: tone.foreground),
                ),
                if (action != null) ...[
                  const SizedBox(height: PpgSpace.xs),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky footer for the screen's primary action.
class PpgBottomBar extends StatelessWidget {
  const PpgBottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const Border(top: BorderSide(color: PpgColors.line)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: PpgSpace.s),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small explanatory line under a primary action.
class PpgHint extends StatelessWidget {
  const PpgHint(this.text, {super.key, this.center = true});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: const TextStyle(fontSize: 13, color: PpgColors.textSecondary),
  );
}

class PpgEmptyState extends StatelessWidget {
  const PpgEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 48, color: PpgColors.textMuted),
          const SizedBox(height: PpgSpace.m),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: PpgSpace.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: PpgColors.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: PpgSpace.l), action!],
        ],
      ),
    );
  }
}

/// A tick or open circle with a sentence, used for checklists.
class PpgCheckLine extends StatelessWidget {
  const PpgCheckLine({
    super.key,
    required this.done,
    required this.text,
    this.onTap,
  });

  final bool done;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: done
                ? PpgTone.success.foreground
                : PpgTone.warning.foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: onTap != null ? PpgColors.link : PpgColors.navy,
                fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: PpgColors.link, size: 20),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: PpgSizes.touch),
        child: row,
      ),
    );
  }
}

void showPpgMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showPpgError(BuildContext context, Object error, {String? prefix}) {
  final message = ppgErrorMessage(error);
  showPpgMessage(context, prefix == null ? message : '$prefix $message');
}

/// Runs a controller action and reports a failure in plain words.
Future<bool> ppgRun(
  BuildContext context,
  Future<void> Function() action, {
  String? failurePrefix,
}) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) showPpgError(context, error, prefix: failurePrefix);
    return false;
  }
}
