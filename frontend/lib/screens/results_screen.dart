import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/review_provenance_helpers.dart';

class ResultsScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  final File? imageFile;
  final List<File> imageFiles;

  const ResultsScreen({
    super.key,
    required this.result,
    this.imageFile,
    this.imageFiles = const [],
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late Map<String, String> _editedFields;
  late Map<String, dynamic> _reviewFlags;
  late Set<String> _missingRequired;
  final Set<String> _modifiedFields = {};
  bool _isSubmitting = false;
  bool _highlightUpc = false;
  int _currentImageIndex = 0;
  late final PageController _imagePageController;

  List<MapEntry<String, String>> get _sortedEntries {
    final entries = _editedFields.entries.toList();
    entries.sort((a, b) {
      final aFilled = a.value.isNotEmpty ? 0 : 1;
      final bFilled = b.value.isNotEmpty ? 0 : 1;
      return aFilled.compareTo(bFilled);
    });
    return entries;
  }

  int get _filledCount =>
      _editedFields.values.where((v) => v.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    final fields = widget.result['fields'] as Map<String, dynamic>? ?? {};
    _editedFields = editableFieldsFromSchemaFields(fields);
    _reviewFlags =
        widget.result['review_flags'] as Map<String, dynamic>? ?? {};
    _missingRequired = _computeMissingRequired();
  }

  /// Build the set of fields that are required (via schema mandatory_fields)
  /// AND currently empty. Accepts two back-compat sources:
  /// 1. A new `missing_required_fields` list on the extraction result.
  /// 2. Legacy records where the mandatory signal was mixed into review_flags
  ///    as entries with `mandatory: true`.
  Set<String> _computeMissingRequired() {
    final missing = <String>{};
    final listRaw = widget.result['missing_required_fields'];
    if (listRaw is List) {
      for (final entry in listRaw) {
        final key = entry?.toString() ?? '';
        if (key.isEmpty) continue;
        final value = _editedFields[key];
        if (value == null || value.trim().isEmpty) missing.add(key);
      }
    }
    _reviewFlags.forEach((key, info) {
      if (info is Map && info['mandatory'] == true) {
        final value = _editedFields[key];
        if (value == null || value.trim().isEmpty) missing.add(key);
      }
    });
    return missing;
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  void _editField(String fieldName, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(Icons.edit_note, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _formatFieldName(fieldName),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter value',
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => controller.clear(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _editedFields[fieldName] = controller.text;
                  _modifiedFields.add(fieldName);
                  // Re-evaluate required-missing after an edit so the red
                  // REQUIRED badge clears as soon as the field has a value.
                  if (controller.text.trim().isNotEmpty) {
                    _missingRequired.remove(fieldName);
                  } else if (_reviewFlags[fieldName] is Map &&
                      (_reviewFlags[fieldName] as Map)['mandatory'] == true) {
                    _missingRequired.add(fieldName);
                  }
                  if (fieldName == 'upc_barcode') {
                    final digits =
                        controller.text.trim().replaceAll(RegExp(r'\D'), '');
                    if ([8, 12, 13].contains(digits.length)) {
                      _highlightUpc = false;
                    }
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmMissingRequired(List<String> missing) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: Colors.red[700], size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              'Required Fields Empty',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              'These fields are marked required but are empty:',
              style: TextStyle(
                color: Color(0xFF424242),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: missing
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 2),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 6, color: Colors.orange[800]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatFieldName(f),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Submitting will flag this record for review so a human can fill in the missing values later.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey[500],
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
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
              child: const Text('Fill Them In'),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _submitCorrections() async {
    // 1. Required-field presence check — applies to ANY schema whose
    //    mandatory_fields include an entry that came back empty. The operator
    //    can still "Submit anyway" after confirming, but there is no silent
    //    bypass.
    final liveMissing = _missingRequired
        .where((f) => (_editedFields[f] ?? '').trim().isEmpty)
        .toList()
      ..sort();
    if (liveMissing.isNotEmpty) {
      final confirmed = await _confirmMissingRequired(liveMissing);
      if (!confirmed) return;
    }

    // 2. UPC length format check — paint labels only, unrelated to the
    //    generic mandatory-presence rule above. Empty-UPC case is now handled
    //    by the generic check; this branch only fires when the UPC is
    //    present but the wrong length.
    final equipType = widget.result['equipment_type']?.toString() ?? '';
    if (equipType == 'paint_label') {
      final upc = (_editedFields['upc_barcode'] ?? '').trim();
      final digitsOnly = upc.replaceAll(RegExp(r'\D'), '');
      if (upc.isNotEmpty && ![8, 12, 13].contains(digitsOnly.length)) {
        setState(() => _highlightUpc = true);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange[800], size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Invalid UPC Length',
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
                const Text(
                  'UPC Barcode must be 8 digits (UPC-E/EAN-8), 12 digits (UPC-A), or 13 digits (EAN-13).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF424242),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Current length: ${digitsOnly.length} digits',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
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
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        );
        return;
      }
      if (upc.isNotEmpty) {
        _editedFields['upc_barcode'] = digitsOnly;
      }
    }

    setState(() => _isSubmitting = true);
    final state = context.read<AppState>();
    final fieldsToSubmit = fieldsFromEditableFields(_editedFields);

    final success = await state.submitExtraction(
      result: widget.result,
      imageFiles: widget.imageFiles,
      finalFields: fieldsToSubmit,
      modifiedFields: Set<String>.from(_modifiedFields),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Submitted successfully'),
            ],
          ),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.error ?? 'Submission failed'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  String _formatFieldName(String fieldName) {
    final isAdditional = isExtraFieldPath(fieldName);
    final normalizedName =
        isAdditional ? extraFieldKeyFromPath(fieldName) : fieldName;
    final formatted = normalizedName
        .replaceAll('_', ' ')
        .split(' ')
        .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
    return isAdditional ? 'Additional: $formatted' : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final equipmentType = widget.result['equipment_type'] ?? 'Unknown';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          // App Bar with image background
          SliverAppBar(
            expandedHeight: widget.imageFiles.isNotEmpty ? 220 : 100,
            pinned: true,
            centerTitle: false,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding:
                  const EdgeInsets.only(left: 56, bottom: 16, right: 16),
              title: Text(
                '${equipmentType.toString().replaceAll('_', ' ').toUpperCase()} Results',
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              background: widget.imageFiles.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _imagePageController,
                          itemCount: widget.imageFiles.length,
                          onPageChanged: (i) =>
                              setState(() => _currentImageIndex = i),
                          itemBuilder: (_, i) => Image.file(
                            widget.imageFiles[i],
                            fit: BoxFit.cover,
                            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded) return child;
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: frame != null
                                    ? child
                                    : Container(color: const Color(0xFF1A237E)),
                              );
                            },
                          ),
                        ),
                        IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xDD1A237E),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (widget.imageFiles.length > 1)
                          Positioned(
                            bottom: 44,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(
                                        widget.imageFiles.length,
                                        (i) => AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          width:
                                              _currentImageIndex == i ? 18 : 6,
                                          height: 6,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 2),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            color: _currentImageIndex == i
                                                ? Colors.white
                                                : Colors.white38,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                        ),
                      ),
                    ),
            ),
            actions: [
              if (widget.imageFiles.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.zoom_in_rounded),
                  tooltip: 'View full image',
                  onPressed: () => _showFullImage(context),
                ),
              if (_modifiedFields.isNotEmpty)
                Badge(
                  label: Text('${_modifiedFields.length}'),
                  child: IconButton(
                    icon: const Icon(Icons.edit_note),
                    onPressed: () {},
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),

          // Stats Cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _buildStatCard(
                    '${_editedFields.length}',
                    'Fields',
                    Icons.list_alt_rounded,
                    const Color(0xFF3949AB),
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    '$_filledCount',
                    'Filled',
                    Icons.check_circle_outline_rounded,
                    const Color(0xFF00897B),
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    '${_modifiedFields.length}',
                    'Reviewed',
                    Icons.rate_review_outlined,
                    const Color(0xFF2E7D32),
                  ),
                ],
              ),
            ),
          ),

          // Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Extracted Fields',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_filledCount / ${_editedFields.length}',
                      style: const TextStyle(
                        color: Colors.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to edit',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Field List
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = _sortedEntries[index];
                  final reviewInfo = _reviewFlags[entry.key];
                  // Only treat it as a GPT review flag if it is not an old-style
                  // mandatory-missing entry mixed into review_flags on legacy
                  // records. Those are rendered via the REQUIRED badge instead.
                  final isLegacyMandatory = reviewInfo is Map &&
                      reviewInfo['mandatory'] == true;
                  final isReviewFlag = _reviewFlags.containsKey(entry.key) &&
                      !isLegacyMandatory;
                  final reviewReason = (isReviewFlag && reviewInfo is Map)
                      ? reviewInfo['reason']?.toString()
                      : null;
                  final isRequiredMissing =
                      _missingRequired.contains(entry.key) &&
                          entry.value.trim().isEmpty;
                  final isModified = _modifiedFields.contains(entry.key);
                  final isFilled = entry.value.isNotEmpty;
                  final isUpcError = _highlightUpc &&
                      entry.key == 'upc_barcode' &&
                      entry.value.isEmpty;

                  return _buildFieldCard(
                    fieldName: entry.key,
                    value: entry.value,
                    isReviewFlag: isReviewFlag,
                    isRequiredMissing: isRequiredMissing,
                    isModified: isModified,
                    isFilled: isFilled,
                    isError: isUpcError,
                    reviewReason: reviewReason,
                    colorScheme: colorScheme,
                  );
                },
                childCount: _sortedEntries.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),

      // Submit Button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submitCorrections,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                backgroundColor: _modifiedFields.isNotEmpty
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF3949AB),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _modifiedFields.isNotEmpty
                              ? Icons.check_circle
                              : Icons.send_rounded,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _modifiedFields.isEmpty
                              ? 'Submit as-is'
                              : 'Submit ${_modifiedFields.length} correction${_modifiedFields.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard({
    required String fieldName,
    required String value,
    required bool isReviewFlag,
    bool isRequiredMissing = false,
    required bool isModified,
    required bool isFilled,
    bool isError = false,
    String? reviewReason,
    required ColorScheme colorScheme,
  }) {
    Color? bgColor;
    if (isError) {
      bgColor = Colors.red.withValues(alpha: 0.06);
    } else if (isModified) {
      bgColor = Colors.green.withValues(alpha: 0.05);
    } else if (isRequiredMissing) {
      bgColor = Colors.red.withValues(alpha: 0.05);
    } else if (isReviewFlag) {
      bgColor = Colors.amber.withValues(alpha: 0.06);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? Colors.red.withValues(alpha: 0.6)
              : isModified
                  ? Colors.green.withValues(alpha: 0.3)
                  : isRequiredMissing
                      ? Colors.red.withValues(alpha: 0.35)
                      : isReviewFlag
                          ? Colors.amber.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.15),
          width: (isError || isRequiredMissing) ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editField(fieldName, value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isError
                        ? Colors.red
                        : isModified
                            ? Colors.green
                            : isFilled
                                ? Colors.teal
                                : Colors.grey[300],
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatFieldName(fieldName),
                            style: TextStyle(
                              fontSize: 12,
                              color: isError ? Colors.red : Colors.grey[500],
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (isError || isRequiredMissing) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'REQUIRED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.red,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                          if (isReviewFlag &&
                              !isModified &&
                              !isError &&
                              !isRequiredMissing) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'REVIEW',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.orange,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                          if (isModified) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'EDITED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.isEmpty ? '—' : value,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: value.isEmpty
                              ? Colors.grey[350]
                              : colorScheme.onSurface,
                        ),
                      ),
                      if (isRequiredMissing) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Required field is missing or empty.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else if (isReviewFlag &&
                          reviewReason != null &&
                          reviewReason.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          reviewReason,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, size: 18, color: Colors.grey[350]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: widget.imageFiles.length == 1
            ? InteractiveViewer(
                child: Image.file(widget.imageFiles.first),
              )
            : SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: PageView.builder(
                  itemCount: widget.imageFiles.length,
                  controller:
                      PageController(initialPage: _currentImageIndex),
                  itemBuilder: (_, i) => InteractiveViewer(
                    child: Image.file(widget.imageFiles[i]),
                  ),
                ),
              ),
      ),
    );
  }
}
