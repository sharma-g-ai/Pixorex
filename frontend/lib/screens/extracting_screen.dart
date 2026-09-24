import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'results_screen.dart';

/// Outcome of the type-mismatch dialog. Replaces the old bool result so
/// the dialog can express three user choices instead of two:
///   - keep       → continue to the results screen with current (possibly wrong) extraction
///   - discard    → abandon the extraction and go back to capture
///   - reextract  → run extraction again using `_suggested_schema` instead
enum _MismatchAction { keep, discard, reextract }

class ExtractingScreen extends StatefulWidget {
  final List<File> imageFiles;
  final String equipmentType;

  const ExtractingScreen({
    super.key,
    required this.imageFiles,
    required this.equipmentType,
  });

  @override
  State<ExtractingScreen> createState() => _ExtractingScreenState();
}

class _ExtractingScreenState extends State<ExtractingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int _stepIndex = 0;
  static const _steps = [
    'Reading label text...',
    'Identifying fields...',
    'Extracting values...',
    'Validating data...',
    'Almost done...',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _cycleSteps();
    _startExtraction();
  }

  void _cycleSteps() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _stepIndex < _steps.length - 1) {
        setState(() => _stepIndex++);
        _cycleSteps();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startExtraction() async {
    final state = context.read<AppState>();
    final success = await state.extractFields(
      imageFiles: widget.imageFiles,
      equipmentType: widget.equipmentType,
    );

    if (!mounted) return;

    if (!success || state.currentResult == null) {
      // Show error and go back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.error ?? 'Extraction failed'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
      return;
    }

    final result = state.currentResult!;
    final mismatchWarning = result['mismatch_warning'] as String?;

    if (mismatchWarning != null && mounted) {
      // Offer the "Re-extract as X" action only when GPT's suggestion is
      // present AND differs from the user's current selection. Otherwise
      // the third button would be redundant or non-actionable.
      final rawSuggested = result['suggested_schema'] as String?;
      final reextractSchema =
          (rawSuggested != null && rawSuggested != widget.equipmentType)
              ? rawSuggested
              : null;
      final reextractDisplayName = reextractSchema == null
          ? null
          : _lookupSchemaDisplayName(state, reextractSchema) ??
              reextractSchema.replaceAll('_', ' ');

      final action = await showDialog<_MismatchAction>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange[800], size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Type Mismatch',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A237E),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text(
                  mismatchWarning,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF424242),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reextractDisplayName == null
                      ? 'Do you want to keep the results or discard?'
                      : 'Re-extract with the suggested schema, keep the current results, or discard?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            actionsOverflowDirection: VerticalDirection.down,
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              // Primary action — Keep Results
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, _MismatchAction.keep),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Keep Results'),
                ),
              ),
              // Re-extract (if available)
              if (reextractDisplayName != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pop(ctx, _MismatchAction.reextract),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text('Re-extract as $reextractDisplayName'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A237E),
                      side: const BorderSide(color: Color(0xFF1A237E)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              // Discard
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, _MismatchAction.discard),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[600],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('Discard'),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      // Dismissed or discarded → go back to capture
      if (action == null || action == _MismatchAction.discard) {
        Navigator.pop(context);
        return;
      }

      // Re-extract path → replace the current ExtractingScreen with a fresh
      // one using the suggested schema. The new screen's initState runs a
      // new OpenAI call with the same image set, fresh mismatch detection,
      // and can even surface another dialog if the second guess is also
      // wrong — user stays in control.
      if (action == _MismatchAction.reextract && reextractSchema != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ExtractingScreen(
              imageFiles: widget.imageFiles,
              equipmentType: reextractSchema,
            ),
          ),
        );
        return;
      }

      // Keep Results → fall through to results navigation below
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          result: result,
          imageFile: widget.imageFiles.first,
          imageFiles: widget.imageFiles,
        ),
      ),
    );
  }

  /// Look up the user-facing display name for a schema key by searching
  /// the already-loaded schemas list on AppState. Returns null if the
  /// schema isn't in the list (in which case callers should fall back to
  /// a humanized version of the raw key).
  String? _lookupSchemaDisplayName(AppState state, String schemaKey) {
    for (final schema in state.schemas) {
      if (schema['equipment_type'] == schemaKey) {
        final name = schema['display_name'];
        if (name is String && name.isNotEmpty) return name;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated scanner icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primaryContainer
                          .withValues(alpha: 0.3 + _pulseController.value * 0.3),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary
                              .withValues(alpha: _pulseController.value * 0.15),
                          blurRadius: 20 + _pulseController.value * 20,
                          spreadRadius: _pulseController.value * 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.document_scanner_rounded,
                      size: 48,
                      color: colorScheme.primary.withValues(
                        alpha: 0.6 + (_pulseController.value * 0.4),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Analyzing ${widget.equipmentType.replaceAll('_', ' ')}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _steps[_stepIndex],
                  key: ValueKey(_stepIndex),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Step dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final isActive = i <= _stepIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _stepIndex ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isActive
                          ? colorScheme.primary
                          : Colors.grey[300],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),
              // Image preview
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    widget.imageFiles.first,
                    width: 180,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
