import '../branding/app_brand.dart';
import 'dart:io';
import 'package:flutter/material.dart';

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> extraction;

  const HistoryDetailScreen({super.key, required this.extraction});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  int _currentImageIndex = 0;

  String _formatFieldName(String fieldName) {
    return fieldName
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w)
        .join(' ');
  }

  String _toTitleCase(String text) {
    return text
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w)
        .join(' ');
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$min $amPm';
    } catch (_) {
      return timestamp;
    }
  }

  String? _confidenceLevel(dynamic raw) {
    if (raw is Map) {
      final level = raw['level']?.toString().trim().toLowerCase();
      if (level == 'high' || level == 'medium' || level == 'low') {
        return level;
      }
      final scoreRaw = raw['score'];
      final score = scoreRaw is num
          ? scoreRaw.toDouble()
          : double.tryParse(scoreRaw?.toString() ?? '');
      if (score == null) return null;
      if (score < 0.70) return 'low';
      if (score < 0.85) return 'medium';
      return 'high';
    }

    final text = raw?.toString().trim().toLowerCase();
    if (text == 'high' || text == 'medium' || text == 'low') return text;
    return null;
  }

  String? _reviewReason({
    required String fieldName,
    required Map<String, dynamic> reviewFlags,
    required Map<String, dynamic> fieldReviewNotes,
  }) {
    final note = fieldReviewNotes[fieldName]?.toString().trim();
    if (note != null && note.isNotEmpty) return note;

    final reviewInfo = reviewFlags[fieldName];
    if (reviewInfo is Map) {
      final reason = reviewInfo['reason']?.toString().trim();
      if (reason != null && reason.isNotEmpty) return reason;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final extraction = widget.extraction;
    final fields = extraction['fields'] as Map<String, dynamic>? ?? {};
    final reviewFlags = extraction['review_flags'] as Map<String, dynamic>? ?? {};
    final fieldConfidenceRaw = extraction['field_confidence'];
    final fieldConfidence = fieldConfidenceRaw is Map
        ? Map<String, dynamic>.from(fieldConfidenceRaw)
        : <String, dynamic>{};
    final fieldReviewNotesRaw = extraction['field_review_notes'];
    final fieldReviewNotes = fieldReviewNotesRaw is Map
        ? Map<String, dynamic>.from(fieldReviewNotesRaw)
        : <String, dynamic>{};

    // Compute the set of required-but-empty fields, accepting two sources:
    // 1) The new top-level `missing_required_fields` list.
    // 2) Legacy records where missing-required was mixed into review_flags
    //    with a `mandatory: true` marker.
    final missingRequired = <String>{};
    final missingRaw = extraction['missing_required_fields'];
    if (missingRaw is List) {
      for (final entry in missingRaw) {
        final key = entry?.toString() ?? '';
        if (key.isEmpty) continue;
        final value = fields[key];
        if (value == null || value.toString().trim().isEmpty) {
          missingRequired.add(key);
        }
      }
    }
    reviewFlags.forEach((key, info) {
      if (info is Map && info['mandatory'] == true) {
        final value = fields[key];
        if (value == null || value.toString().trim().isEmpty) {
          missingRequired.add(key);
        }
      }
    });

    final equipmentType = extraction['equipment_type'] ?? 'unknown';
    final timestamp = extraction['timestamp'] ?? '';
    final imagePath = extraction['image_path'] ?? '';

    // Sort fields: filled first, then empty
    final sortedFieldEntries = fields.entries.toList()
      ..sort((a, b) {
        final aFilled = (a.value != null && a.value.toString().isNotEmpty) ? 0 : 1;
        final bFilled = (b.value != null && b.value.toString().isNotEmpty) ? 0 : 1;
        return aFilled.compareTo(bFilled);
      });

    // Collect image sources for the app bar background
    final List<dynamic> imageSources = [];
    if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
      imageSources.add(File(imagePath));
    }
    final imageUrls = extraction['image_urls'];
    if (imageUrls is List) {
      for (final url in imageUrls) {
        if (url is String && url.isNotEmpty) imageSources.add(url);
      }
    } else {
      final singleUrl = extraction['image_url']?.toString() ?? '';
      if (singleUrl.isNotEmpty && imageSources.isEmpty) {
        imageSources.add(singleUrl);
      }
    }
    final hasImages = imageSources.isNotEmpty;

    Widget imageFromSource(dynamic src, {BoxFit fit = BoxFit.cover}) {
      if (src is File) {
        return Image.file(src, fit: fit, width: double.infinity,
            errorBuilder: (context, error, stackTrace) =>
                Center(child: Icon(Icons.image_not_supported, color: Colors.grey[400])));
      } else {
        return Image.network(src as String, fit: fit, width: double.infinity,
            errorBuilder: (context, error, stackTrace) =>
                Center(child: Icon(Icons.image_not_supported, color: Colors.grey[400])));
      }
    }

    return Scaffold(
      backgroundColor: AppBrand.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: hasImages ? 220 : 100,
            pinned: true,
            centerTitle: false,
            backgroundColor: AppBrand.navy,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding:
                  const EdgeInsets.only(left: 56, bottom: 16, right: 16),
              title: Text(
                '${_toTitleCase(equipmentType.toString())} Detail',
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              background: hasImages
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageSources.length == 1)
                          imageFromSource(imageSources.first)
                        else
                          PageView.builder(
                            itemCount: imageSources.length,
                            onPageChanged: (i) =>
                                setState(() => _currentImageIndex = i),
                            itemBuilder: (_, i) =>
                                imageFromSource(imageSources[i]),
                          ),
                        IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppBrand.navyOverlay,
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (imageSources.length > 1)
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
                                        imageSources.length,
                                        (i) => AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          width: _currentImageIndex == i
                                              ? 18
                                              : 6,
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
                          colors: [AppBrand.navy, AppBrand.blue],
                        ),
                      ),
                    ),
            ),
            actions: [
              if (hasImages)
                IconButton(
                  icon: const Icon(Icons.zoom_in_rounded),
                  tooltip: 'View full image',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        clipBehavior: Clip.antiAlias,
                        child: imageSources.length == 1
                            ? InteractiveViewer(
                                child: imageFromSource(
                                    imageSources.first,
                                    fit: BoxFit.contain))
                            : SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.6,
                                child: PageView.builder(
                                  itemCount: imageSources.length,
                                  controller: PageController(
                                      initialPage: _currentImageIndex),
                                  itemBuilder: (_, i) => InteractiveViewer(
                                    child: imageFromSource(
                                        imageSources[i],
                                        fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
              const SizedBox(width: 4),
            ],
          ),

          // Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Extracted Fields',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${fields.values.where((v) => v != null && v.toString().isNotEmpty).length} / ${fields.length}',
                          style: const TextStyle(
                            color: Colors.teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        _formatTimestamp(timestamp),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Fields list
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                final entry = sortedFieldEntries[index];
                final confidenceLevel =
                    _confidenceLevel(fieldConfidence[entry.key]);
                final reviewReason = _reviewReason(
                  fieldName: entry.key,
                  reviewFlags: reviewFlags,
                  fieldReviewNotes: fieldReviewNotes,
                );
                final value = entry.value?.toString() ?? '';
                final isRequiredMissing =
                    missingRequired.contains(entry.key) &&
                        value.trim().isEmpty;
                // Do not show REVIEW on entries that are really the legacy
                // mandatory-missing signal — those are rendered as REQUIRED.
                final rawReviewEntry = reviewFlags[entry.key];
                final isLegacyMandatory = rawReviewEntry is Map &&
                    rawReviewEntry['mandatory'] == true;
                final isReviewFlag = !isRequiredMissing &&
                    !isLegacyMandatory &&
                    (reviewFlags.containsKey(entry.key) ||
                        confidenceLevel == 'low' ||
                        (reviewReason != null && reviewReason.isNotEmpty));

                Color? cardBg;
                if (isRequiredMissing) {
                  cardBg = Colors.red.withValues(alpha: 0.05);
                } else if (isReviewFlag) {
                  cardBg = Colors.amber.withValues(alpha: 0.06);
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  color: cardBg,
                  child: ListTile(
                    dense: true,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatFieldName(entry.key),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isRequiredMissing) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
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
                        ] else if (isReviewFlag) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              confidenceLevel == null
                                  ? 'REVIEW'
                                  : '${confidenceLevel.toUpperCase()} CONF',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.orange,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.isEmpty ? '—' : value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: value.isEmpty ? Colors.grey : Colors.black87,
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
                            reviewReason.isNotEmpty) ...[
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
                );
              },
              childCount: sortedFieldEntries.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
