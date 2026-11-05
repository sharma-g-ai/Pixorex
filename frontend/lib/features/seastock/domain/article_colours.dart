import 'package:flutter/painting.dart';

/// Paint colour per article no., from the team's master list (one hex code per
/// article). The list has not been supplied yet, so it starts empty and an
/// article shows as "colour not on the master list".
const Map<String, String> seastockArticleHex = {};

sealed class ArticleColour {
  const ArticleColour();
}

/// A paint with a colour on the master list.
class PaintColour extends ArticleColour {
  const PaintColour(this.color);
  final Color color;
}

/// A product with no colour of its own, such as a hardener.
class NoColour extends ArticleColour {
  const NoColour();
}

/// Not on the master list yet.
class UnknownColour extends ArticleColour {
  const UnknownColour();
}

ArticleColour articleColour(
  String articleNumber,
  String? product, {
  Map<String, String> hexByArticle = seastockArticleHex,
}) {
  final color = parseHexColour(hexByArticle[articleNumber]);
  if (color != null) return PaintColour(color);
  if (product != null && RegExp(r'\bHRD\b').hasMatch(product.toUpperCase())) {
    return const NoColour();
  }
  return const UnknownColour();
}

/// Reads "#1F4E9A" or "1F4E9A"; null if it is not a 6-digit hex colour.
Color? parseHexColour(String? hex) {
  if (hex == null) return null;
  final digits = hex.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(digits)) return null;
  return Color(0xFF000000 | int.parse(digits, radix: 16));
}
