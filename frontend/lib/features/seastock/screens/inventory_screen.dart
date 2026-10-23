import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/stock.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';

/// A plain list of what is on board the vessel: label name, article no.
/// and PC. Rows do nothing when tapped. Search matches label
/// name or article no.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Consumer<SeastockController>(
    builder: (context, ctrl, _) {
      final onBoard = ctrl.stock.onBoardItems;
      final q = _search.text.trim().toLowerCase();
      final items = onBoard
          .where(
            (item) =>
                q.isEmpty ||
                item.articleNumber.contains(q) ||
                (item.product?.toLowerCase().contains(q) ?? false),
          )
          .toList();
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              eyebrow: ctrl.vessel.name,
              title: 'Inventory',
              backTooltip: 'Back to Home',
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text.rich(
                      TextSpan(
                        style: PpgText.figures(size: 16, color: Colors.white),
                        children: [
                          TextSpan(text: '${ctrl.stock.total}'),
                          const TextSpan(
                            text: ' PC',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: PpgColors.onNavyMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              bottom: onBoard.isEmpty
                  ? null
                  : TextField(
                      key: const ValueKey('inventory-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Label name or article no.',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
            ),
            Expanded(
              child: onBoard.isEmpty
                  ? PpgEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Nothing on board ${ctrl.vessel.name}',
                      message: 'Check in a delivery note to add stock.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        PpgSectionLabel(
                          q.isEmpty
                              ? ppgPlural(onBoard.length, 'article')
                              : '${ppgPlural(items.length, 'article')} match',
                          trailing: 'Most cans first',
                        ),
                        const SizedBox(height: PpgSpace.s),
                        if (items.isEmpty)
                          PpgHint('Nothing matches "${_search.text.trim()}".')
                        else
                          PpgPanel(
                            child: Column(
                              children: ppgDivided(items.map(_row)),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _row(StockItem item) => PpgRow(
    key: ValueKey('stock-${item.articleNumber}'),
    title: item.product ?? item.articleNumber,
    subtitle: item.product == null ? null : item.articleNumber,
    showChevron: false,
    trailing: SeastockQuantity(item.onBoard),
    semanticLabel:
        '${item.product ?? ''} article ${item.articleNumber}, ${item.onBoard} PC on board',
  );
}
