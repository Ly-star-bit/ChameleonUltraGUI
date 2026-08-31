import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lists recently deleted cards and lets the user restore them or purge them
/// permanently. Entries expire automatically after
/// [RecycleBinEntry.retentionDays] days.
class RecycleBinMenu extends StatefulWidget {
  const RecycleBinMenu({super.key});

  @override
  RecycleBinMenuState createState() => RecycleBinMenuState();
}

class RecycleBinMenuState extends State<RecycleBinMenu> {
  late List<RecycleBinEntry> entries;

  @override
  void initState() {
    super.initState();
    final appState = context.read<ChameleonGUIState>();
    // Drop expired entries whenever the bin is opened.
    entries = appState.sharedPreferencesProvider.purgeExpiredRecycleBin();
  }

  int _daysLeft(RecycleBinEntry entry) {
    final expiresAt = entry.deletedAt +
        const Duration(days: RecycleBinEntry.retentionDays).inMilliseconds;
    final msLeft = expiresAt - DateTime.now().millisecondsSinceEpoch;
    final days = (msLeft / const Duration(days: 1).inMilliseconds).ceil();
    return days < 0 ? 0 : days;
  }

  void _restore(RecycleBinEntry entry) {
    final appState = context.read<ChameleonGUIState>();
    appState.sharedPreferencesProvider.restoreFromRecycleBin(entry.card.id);
    appState.changesMade();
    setState(() {
      entries.removeWhere((e) => e.card.id == entry.card.id);
    });
  }

  void _deleteForever(RecycleBinEntry entry) {
    final appState = context.read<ChameleonGUIState>();
    appState.sharedPreferencesProvider.deleteFromRecycleBin(entry.card.id);
    setState(() {
      entries.removeWhere((e) => e.card.id == entry.card.id);
    });
  }

  void _emptyAll() {
    final appState = context.read<ChameleonGUIState>();
    appState.sharedPreferencesProvider.emptyRecycleBin();
    setState(() {
      entries = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.recycle_bin),
      content: SizedBox(
        width: double.maxFinite,
        child: entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(localizations.recycle_bin_empty),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.recycle_bin_hint(
                          RecycleBinEntry.retentionDays),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ...entries.map(
                      (entry) => Card(
                        child: ListTile(
                          leading: Icon(Icons.credit_card,
                              color: entry.card.color),
                          title: Text(entry.card.name.isEmpty
                              ? localizations.no_name
                              : entry.card.name),
                          subtitle: Text(
                              localizations.days_left(_daysLeft(entry))),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: localizations.restore,
                                icon: const Icon(Icons.restore_from_trash),
                                onPressed: () => _restore(entry),
                              ),
                              IconButton(
                                tooltip: localizations.delete_forever,
                                icon: const Icon(Icons.delete_forever),
                                onPressed: () => _deleteForever(entry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        if (entries.isNotEmpty)
          TextButton(
            onPressed: _emptyAll,
            child: Text(localizations.empty_recycle_bin),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
