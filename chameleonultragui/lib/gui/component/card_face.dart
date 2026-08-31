import 'dart:io';

import 'package:chameleonultragui/helpers/card_skin.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

/// A credit-card shaped preview of a saved card, honoring its custom image,
/// preset skin, or plain color (in that order of precedence). Used in the card
/// detail dialog so users can recognise a card at a glance.
class CardFace extends StatelessWidget {
  final CardSave card;
  final double height;

  const CardFace({super.key, required this.card, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final skin = cardSkinById(card.skinId);
    final hasImage = card.imagePath != null && card.imagePath!.isNotEmpty;

    DecorationImage? image;
    if (hasImage && File(card.imagePath!).existsSync()) {
      image = DecorationImage(
        image: FileImage(File(card.imagePath!)),
        fit: BoxFit.cover,
      );
    }

    return AspectRatio(
      aspectRatio: 1.585, // ISO/IEC 7810 ID-1 card ratio
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: card.color,
          gradient: image == null ? skin?.toGradient() : null,
          image: image,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Scrim so the name stays readable over any background.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 14,
              right: 16,
              child: Text(
                card.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
            const Positioned(
              right: 16,
              top: 14,
              child: Icon(Icons.contactless, color: Colors.white70, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}
