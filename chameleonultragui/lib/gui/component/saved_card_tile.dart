import 'dart:io';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/card_skin.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

enum SavedCardAction { pin, move, edit, export, delete }

/// A credit-card styled tile for the saved cards grid: renders the card's
/// custom image / preset skin / colour as the background, overlays the name,
/// type and tags, and collapses every action into one overflow menu so the
/// layout stays clean on narrow phone screens.
class SavedCardTile extends StatelessWidget {
  final CardSave card;
  final VoidCallback onTap;
  final void Function(SavedCardAction action) onAction;

  const SavedCardTile({
    super.key,
    required this.card,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final skin = cardSkinById(card.skinId);
    final hasImage = card.imagePath != null &&
        card.imagePath!.isNotEmpty &&
        File(card.imagePath!).existsSync();

    // Background precedence: custom image > preset skin > a subtle gradient
    // derived from the card's colour (so even plain cards read as cards).
    final baseColor = skin?.gradient.first ?? card.color;
    final gradient = hasImage
        ? null
        : (skin?.toGradient() ??
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: 0.12), baseColor),
                Color.alphaBlend(Colors.black.withValues(alpha: 0.30), baseColor),
              ],
            ));

    final isHf = chameleonTagToFrequency(card.tag) == TagFrequency.hf;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 140,
          decoration: BoxDecoration(
            color: baseColor,
            gradient: gradient,
            image: hasImage
                ? DecorationImage(
                    image: FileImage(File(card.imagePath!)), fit: BoxFit.cover)
                : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Readability scrim.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 12,
                child: Icon(isHf ? Icons.contactless : Icons.wifi,
                    color: Colors.white70, size: 22),
              ),
              if (card.pinned)
                const Positioned(
                  top: 12,
                  left: 44,
                  child: Icon(Icons.push_pin, color: Colors.white, size: 16),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<SavedCardAction>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: SavedCardAction.pin,
                      child: _menuRow(
                          card.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                          card.pinned
                              ? localizations.unpin
                              : localizations.pin),
                    ),
                    PopupMenuItem(
                      value: SavedCardAction.edit,
                      child: _menuRow(Icons.edit, localizations.edit),
                    ),
                    PopupMenuItem(
                      value: SavedCardAction.move,
                      child: _menuRow(Icons.drive_file_move_outline,
                          localizations.move_card),
                    ),
                    PopupMenuItem(
                      value: SavedCardAction.export,
                      child: _menuRow(Icons.download, localizations.save),
                    ),
                    PopupMenuItem(
                      value: SavedCardAction.delete,
                      child: _menuRow(Icons.delete_outline, localizations.delete),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card.name.isEmpty ? localizations.no_name : card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chameleonCardToString(card, localizations),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                    if (card.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final tag in card.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "#$tag",
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
