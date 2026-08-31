
import 'package:chameleonultragui/gui/component/card_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/gui/component/ios_widgets.dart';
import 'package:chameleonultragui/helpers/feedback.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/slot_write.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  List<SlotTypes> usedSlots = List.generate(
    8,
    (_) => SlotTypes(),
  );

  List<EnabledSlotInfo> enabledSlots = List.generate(
    8,
    (_) => EnabledSlotInfo(),
  );

  List<SlotNames> slotData = List.generate(
    8,
    (_) => SlotNames(),
  );

  int progress = -1;
  int gridPosition = 0;
  bool onlyOneSlot = false;

  Future<void> loadSlotData() async {
    if (progress != -1) {
      return;
    }

    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    usedSlots = await appState.communicator!.getSlotTagTypes();
    enabledSlots = await appState.communicator!.getEnabledSlots();
    slotData = await appState.communicator!.getSlotTagNames();

    for (SlotNames slot in slotData) {
      slot.hf = slot.hf.isEmpty ? localizations.no_name : slot.hf;
      slot.lf = slot.lf.isEmpty ? localizations.no_name : slot.lf;
    }
  }

  void refreshSlot() {
    setUploadState(-1);
    AppFeedback.success();

    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  void setUploadState(int progressBar) {
    setState(() {
      progress = progressBar;
    });

    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  Future<void> onTap(
      CardSave card, dynamic close, AppLocalizations localizations) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    // Warn before overwriting a slot that already holds a card.
    if (enabledSlots[gridPosition].any()) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            icon: const Icon(Icons.warning_amber, color: Colors.orange),
            title: Text(localizations.overwrite_slot_title),
            content: Text(localizations.overwrite_slot_message(gridPosition + 1)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(localizations.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(localizations.overwrite),
              ),
            ],
          );
        },
      );
      if (confirm != true || !mounted) {
        return;
      }
    }

    final showsProgress =
        isMifareClassic(card.tag) || isMifareUltralight(card.tag);

    close(context, card.name);
    if (showsProgress) {
      setUploadState(0);
    }

    try {
      await writeCardToSlot(
        communicator: appState.communicator!,
        slot: gridPosition,
        card: card,
        noName: localizations.no_name,
        onProgress: showsProgress ? setUploadState : null,
      );
    } on UnsupportedError {
      appState.log!.e("Can't write this card type yet.");
      return;
    }

    appState.changesMade();
    refreshSlot();
  }

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    // Don't allow user to upload more tags while already uploading dump
    if (progress != -1) {
      return Future.value("");
    }

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards: tags, onTap: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.slot_manager),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            FutureBuilder(
              future: loadSlotData(),
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    progress != -1) {
                  return const Center(child: AdaptiveProgress());
                } else if (snapshot.hasError) {
                  appState.connector!.performDisconnect();
                  return ErrorPage(errorMessage: snapshot.error.toString());
                } else {
                  return Expanded(
                    child: AlignedGridView.count(
                        padding: const EdgeInsets.all(20),
                        crossAxisCount:
                            MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        itemCount: 8,
                        itemBuilder: (BuildContext context, int index) {
                          final enabled = enabledSlots[index].any();
                          final theme = Theme.of(context);
                          final muted =
                              theme.colorScheme.onSurface.withValues(alpha: 0.6);
                          Widget freqRow(
                              IconData icon, String name, dynamic tagType) {
                            return Row(
                              children: [
                                Icon(icon, size: 18, color: muted),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  chameleonTagToString(tagType, localizations),
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            );
                          }

                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() => gridPosition = index);
                                cardSelectDialog(context);
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 8, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 9,
                                          height: 9,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: enabled
                                                ? const Color(0xFF34C759)
                                                : muted.withValues(alpha: 0.4),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          "${localizations.slot} ${index + 1}",
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (BuildContext context) {
                                                return SlotSettings(
                                                    slot: index,
                                                    refresh: refreshSlot);
                                              },
                                            );
                                          },
                                          icon: Icon(Icons.settings,
                                              color: muted, size: 20),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    freqRow(Icons.credit_card,
                                        slotData[index].hf, usedSlots[index].hf),
                                    const SizedBox(height: 8),
                                    freqRow(Icons.wifi, slotData[index].lf,
                                        usedSlots[index].lf),
                                  ],
                                ),
                              ),
                            ),
                          );
                                                }),
                  );
                }
              },
            ),
            if (progress != -1) ...[
              const SizedBox(height: 32),
              Text(localizations.uploading_dump),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: (progress / 100).toDouble(),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
