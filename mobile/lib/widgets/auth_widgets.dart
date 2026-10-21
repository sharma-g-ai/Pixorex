import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/phone.dart';
import '../core/theme.dart';

/// Navy gradient band with the white wordmark, top of every sign-in screen.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96 + MediaQuery.paddingOf(context).top,
      padding: EdgeInsets.only(left: 22, right: 22, top: MediaQuery.paddingOf(context).top),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(gradient: Brand.headerGradient),
      child: Image.asset(
        'assets/pixorex_wordmark_white.png',
        height: 30,
        semanticLabel: 'Pixorex',
      ),
    );
  }
}

/// Full-width pill button. [outlined] gives the secondary look.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = outlined ? Brand.navy : Colors.white;
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: Material(
        color: outlined ? Colors.white : (enabled ? Brand.navy : Brand.navy.withValues(alpha: 0.45)),
        shape: StadiumBorder(side: outlined ? const BorderSide(color: Brand.navy, width: 1.5) : BorderSide.none),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                  )
                : Text(label, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? error, bool readOnly = false}) {
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    isDense: true,
    // Always filled: an unfilled field would show the focus glow through it.
    filled: true,
    fillColor: readOnly ? Brand.surface : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    enabledBorder: border(error != null ? Brand.error : (readOnly ? Brand.lineSoft : Brand.line)),
    focusedBorder: border(error != null ? Brand.error : Brand.navy, 2),
    border: border(Brand.line),
    errorText: null,
  );
}

/// The design's focus ring: a 3 px light-blue halo around the focused field.
class FocusGlow extends StatefulWidget {
  const FocusGlow({super.key, required this.child, this.error = false});
  final Widget child;
  final bool error;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: _focused
              ? [BoxShadow(color: widget.error ? Brand.errorBg : Brand.info, spreadRadius: 3)]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Label above a field, with an optional error line below.
class FieldBlock extends StatelessWidget {
  const FieldBlock({super.key, required this.label, required this.child, this.error, this.help});
  final String label;
  final Widget child;
  final String? error;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: const TextStyle(fontSize: 12, color: Brand.error, fontWeight: FontWeight.w600)),
        ] else if (help != null) ...[
          const SizedBox(height: 6),
          Text(help!, style: const TextStyle(fontSize: 11, color: Brand.muted, height: 1.45)),
        ],
      ],
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.error,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final String? error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return FocusGlow(
      error: error != null,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 14.5),
        decoration: _fieldDecoration(error: error).copyWith(semanticCounterText: semanticLabel),
      ),
    );
  }
}

/// Read-only value with a lock, e.g. the invited work email.
class LockedField extends StatelessWidget {
  const LockedField({super.key, required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.lineSoft, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, color: Brand.body)),
          ),
          const Icon(Icons.lock_outline, size: 15, color: Brand.hint),
        ],
      ),
    );
  }
}

/// Country code picker plus a national-number field.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    this.error,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Country country;
  final ValueChanged<Country> onCountryChanged;
  final String? error;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Design: "+1 ⌄", 84 x 48, a small grey chevron next to the code.
        PopupMenuButton<Country>(
          enabled: enabled,
          tooltip: 'Country code',
          initialValue: country,
          onSelected: onCountryChanged,
          position: PopupMenuPosition.under,
          itemBuilder: (_) => [
            for (final c in supportedCountries)
              PopupMenuItem(value: c, child: Text(c.dialCode, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
          child: Container(
            height: 48,
            width: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Brand.line, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(country.dialCode, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Brand.body),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FocusGlow(
            error: error != null,
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\-\s]')), NationalPhoneFormatter()],
              onChanged: onChanged,
              style: const TextStyle(fontSize: 14.5),
              decoration: _fieldDecoration(error: error)
                  .copyWith(hintText: '(216) 555-0148', hintStyle: const TextStyle(color: Brand.hint)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Phone number / Email switch used on the sign-in screen.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.selected, required this.onChanged});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Brand.segment, borderRadius: BorderRadius.circular(11)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? Colors.white : null,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: i == selected
                          ? const [BoxShadow(color: Color(0x1F14161A), blurRadius: 3, offset: Offset(0, 1))]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: i == selected ? FontWeight.w700 : FontWeight.w600,
                        color: i == selected ? Brand.navyDeep : Brand.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.icon = Icons.info_outline, this.error = false, this.richBold});
  final String text;
  final IconData icon;
  final bool error;

  /// A word to set in bold inside [text].
  final String? richBold;

  @override
  Widget build(BuildContext context) {
    final fg = error ? Brand.errorInk : Brand.navyDeep;
    final style = TextStyle(fontSize: 12, color: fg, height: 1.45);
    final spans = <InlineSpan>[];
    if (richBold != null && text.contains(richBold!)) {
      final parts = text.split(richBold!);
      spans
        ..add(TextSpan(text: parts.first))
        ..add(TextSpan(text: richBold, style: const TextStyle(fontWeight: FontWeight.w700)))
        ..add(TextSpan(text: parts.sublist(1).join(richBold!)));
    } else {
      spans.add(TextSpan(text: text));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: error ? Brand.errorBg : Brand.info,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: error ? Brand.error : Brand.navy),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text.rich(TextSpan(style: style, children: spans))),
        ],
      ),
    );
  }
}
