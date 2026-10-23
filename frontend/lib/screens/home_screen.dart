import '../branding/app_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../features/ppg_delivery_note/screens/ppg_hub_screen.dart';
import '../features/ppg_delivery_note/ui/ppg_navigation.dart';
import 'capture_screen.dart';
import 'history_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String? _highlightedId;
  AnimationController? _glowController;
  String? _filterType;
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    state.loadSchemas();
    // Defer to avoid notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state.loadExtractions();
    });
  }

  @override
  void dispose() {
    _glowController?.dispose();
    super.dispose();
  }

  void _startHighlight(String id) {
    _highlightedId = id;
    _glowController?.dispose();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _highlightedId = null;
          _glowController?.dispose();
          _glowController = null;
        });
      }
    });
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return ts;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppBrand.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CaptureScreen()),
          );
        },
        elevation: 8,
        backgroundColor: AppBrand.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.camera_alt_rounded, size: 26),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Consumer<AppState>(
        builder: (context, state, _) {
          // Pick up new highlight – only when the item is already in the list
          if (state.lastExtractionId != null &&
              _highlightedId != state.lastExtractionId &&
              state.extractions.any(
                  (e) => e['extraction_id'] == state.lastExtractionId)) {
            final newId = state.lastExtractionId!;
            state.clearLastExtractionId();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _startHighlight(newId));
            });
          }
          return RefreshIndicator(
            onRefresh: () => state.loadExtractions(),
            child: CustomScrollView(
              slivers: [
                // App Bar
                SliverAppBar(
                  expandedHeight: 120,
                  floating: true,
                  pinned: true,
                  backgroundColor: AppBrand.navy,
                  foregroundColor: Colors.white,
                  actions: [
                    IconButton(
                      tooltip: 'PPG delivery note',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            settings: const RouteSettings(
                              name: ppgHubRouteName,
                            ),
                            builder: (_) => PpgHubScreen(
                              operatorEmail: state.userEmail,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.local_shipping_outlined),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                    title: Semantics(
                      label: AppBrand.name,
                      image: true,
                      child: Image.asset(
                        AppBrand.wordmarkOnDark,
                        width: 132,
                        height: 36,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppBrand.headerGradient,
                        ),
                      ),
                    ),
                  ),
                ),

                // Section Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      'Extractions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),

                // Filters
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        // Type filter
                        Expanded(
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _filterType,
                                isExpanded: true,
                                hint: const Text('All Types', style: TextStyle(fontSize: 13)),
                                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                                icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('All Types', style: TextStyle(fontSize: 13)),
                                  ),
                                  ...state.schemas.map((s) => DropdownMenuItem<String>(
                                    value: s['equipment_type'] as String,
                                    child: Text(s['display_name'] as String, style: const TextStyle(fontSize: 13)),
                                  )),
                                ],
                                onChanged: (val) => setState(() => _filterType = val),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Date filter
                        GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _filterDate ?? DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => _filterDate = picked);
                            }
                          },
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  _filterDate != null
                                      ? '${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}'
                                      : 'All Dates',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Clear filters
                        if (_filterType != null || _filterDate != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() {
                              _filterType = null;
                              _filterDate = null;
                            }),
                            child: Container(
                              height: 40,
                              width: 40,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.close, size: 18, color: Colors.red),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // List
                _buildSliverList(state, colorScheme),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSliverList(AppState state, ColorScheme colorScheme) {
    if (state.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey[350]),
              const SizedBox(height: 12),
              Text('Cannot connect to server',
                  style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => state.loadExtractions(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Apply filters
    var filtered = state.extractions;
    if (_filterType != null) {
      filtered = filtered.where((e) => e['equipment_type'] == _filterType).toList();
    }
    if (_filterDate != null) {
      filtered = filtered.where((e) {
        try {
          final ts = DateTime.parse(e['timestamp'] ?? '');
          return ts.year == _filterDate!.year &&
              ts.month == _filterDate!.month &&
              ts.day == _filterDate!.day;
        } catch (_) {
          return false;
        }
      }).toList();
    }

    if (filtered.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EAF6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.document_scanner_outlined,
                    size: 56, color: Color(0xFF5C6BC0)),
              ),
              const SizedBox(height: 20),
              Text('No extractions yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600])),
              const SizedBox(height: 6),
              Text('Tap "Scan Label" to get started',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final extraction = filtered[index];
            final isNew = extraction['extraction_id'] == _highlightedId;
            return _buildExtractionCard(extraction, colorScheme, state.schemas, isNew: isNew);
          },
          childCount: filtered.length,
        ),
      ),
    );
  }

  Widget _buildExtractionCard(
      Map<String, dynamic> extraction, ColorScheme colorScheme, List<Map<String, dynamic>> schemas,
      {bool isNew = false}) {
    final fields = extraction['fields'] as Map<String, dynamic>? ?? {};
    final timestamp = extraction['timestamp'] ?? '';
    final type = extraction['equipment_type'] ?? 'unknown';

    // Map equipment_type to display_name from schemas
    final schema = schemas.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s?['equipment_type'] == type,
      orElse: () => null,
    );
    final displayType = schema?['display_name'] as String? ??
        type.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ');

    // Build smart title: manufacturer + model_no, fallback to equipment type
    String cardTitle = displayType;
    final manufacturer = (fields['manufacturer'] ?? fields['manufacturer_name'] ?? '').toString().trim();
    final modelNo = (fields['model_no'] ?? fields['product_name'] ?? '').toString().trim();
    if (manufacturer.isNotEmpty || modelNo.isNotEmpty) {
      final parts = [
        if (manufacturer.isNotEmpty) manufacturer,
        if (modelNo.isNotEmpty) modelNo,
      ];
      cardTitle = parts.join(' · ');
    }

    Widget card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isNew ? const Color(0xFFE8F5E9) : Colors.white,
        border: isNew
            ? Border.all(color: Colors.green.shade400, width: 2)
            : Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: isNew
                ? Colors.green.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: isNew ? 12 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    HistoryDetailScreen(extraction: extraction),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              cardTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayType,
                        style: const TextStyle(
                          color: AppBrand.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          final schemaFields = schema?['fields'] as List<dynamic>?;
                          final totalFields = schemaFields?.length ?? fields.length;
                          final filledFields = fields.entries.where((e) =>
                            e.value != null && e.value.toString().trim().isNotEmpty
                          ).length;
                          return Text(
                            '$filledFields/$totalFields fields extracted',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimestamp(timestamp),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey[350], size: 24),
              ],
            ),
          ),
        ),
      ),
    );

    if (isNew && _glowController != null) {
      return AnimatedBuilder(
        animation: _glowController!,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.green
                      .withValues(alpha: 0.1 + _glowController!.value * 0.15),
                  blurRadius: 8 + _glowController!.value * 8,
                  spreadRadius: _glowController!.value * 2,
                ),
              ],
            ),
            child: child,
          );
        },
        child: card,
      );
    }

    return card;
  }
}
