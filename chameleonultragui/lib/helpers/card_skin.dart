import 'package:flutter/material.dart';

/// A preset "card face" — a named gradient used to visually distinguish saved
/// cards at a glance (bus pass, office badge, hotel key, ...). Users can also
/// supply their own photo via CardSave.imagePath, which takes precedence.
class CardSkin {
  final String id;
  final String label;
  final List<Color> gradient;

  const CardSkin(this.id, this.label, this.gradient);

  LinearGradient toGradient() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradient,
      );
}

/// Built-in skins. `id` is what gets persisted on CardSave.skinId.
const List<CardSkin> cardSkins = [
  CardSkin('transit', 'Transit', [Color(0xFF1E88E5), Color(0xFF26C6DA)]),
  CardSkin('office', 'Office', [Color(0xFF3949AB), Color(0xFF5C6BC0)]),
  CardSkin('hotel', 'Hotel', [Color(0xFFB8860B), Color(0xFFFFD54F)]),
  CardSkin('access', 'Access', [Color(0xFF6A1B9A), Color(0xFFAB47BC)]),
  CardSkin('bus', 'Bus', [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
  CardSkin('rose', 'Rose', [Color(0xFFC2185B), Color(0xFFF06292)]),
  CardSkin('slate', 'Slate', [Color(0xFF37474F), Color(0xFF78909C)]),
];

CardSkin? cardSkinById(String? id) {
  if (id == null) {
    return null;
  }
  for (final skin in cardSkins) {
    if (skin.id == id) {
      return skin;
    }
  }
  return null;
}
