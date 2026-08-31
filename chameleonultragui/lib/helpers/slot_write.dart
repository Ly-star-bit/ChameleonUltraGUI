import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

/// Writes a saved [card] into emulation [slot] on the device and enables it.
///
/// Extracted from the Slot Manager so both the manual slot picker and the
/// one-tap "Smart Copy" flow share exactly one implementation. [onProgress]
/// reports 0-100 for the long Mifare Classic / Ultralight uploads; UI callers
/// wire it to a progress bar. Throws [UnsupportedError] for card types that
/// cannot be emulated.
Future<void> writeCardToSlot({
  required ChameleonCommunicator communicator,
  required int slot,
  required CardSave card,
  required String noName,
  void Function(int progress)? onProgress,
}) async {
  final name = card.name.isEmpty ? noName : card.name;

  if (isMifareClassic(card.tag)) {
    onProgress?.call(0);
    if (chameleonTagSaveCheckForMifareClassicEV1(card)) {
      card.tag = TagType.mifare2K;
    }

    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.hf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    var cardData = CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats);
    await communicator.setMf1AntiCollision(cardData);

    List<int> blockChunk = [];
    int lastSend = 0;

    for (var blockOffset = 0;
        blockOffset <
            mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(card.tag));
        blockOffset++) {
      if ((card.data.length > blockOffset && card.data[blockOffset].isEmpty) ||
          blockChunk.length >= 128) {
        if (blockChunk.isNotEmpty) {
          await communicator.setMf1BlockData(
              lastSend, Uint8List.fromList(blockChunk));
          blockChunk = [];
          lastSend = blockOffset;
        }
      }

      if (card.data.length > blockOffset &&
          card.data[blockOffset].length == 16) {
        blockChunk.addAll(card.data[blockOffset]);
      }

      onProgress?.call((blockOffset /
              mfClassicGetBlockCount(
                  chameleonTagTypeGetMfClassicType(card.tag)) *
              100)
          .round());
      await asyncSleep(1);
    }

    if (blockChunk.isNotEmpty) {
      await communicator.setMf1BlockData(
          lastSend, Uint8List.fromList(blockChunk));
    }

    onProgress?.call(100);

    await communicator.setSlotTagName(slot, name, TagFrequency.hf);
    await communicator.saveSlotData();
  } else if (isEM410X(card.tag)) {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.lf, true);
    await communicator.activateSlot(slot);
    TagType slotTagType = card.tag == TagType.em410XElectra
        ? TagType.em410XElectra
        : TagType.em410X;
    await communicator.setSlotType(slot, slotTagType);
    await communicator.setDefaultDataToSlot(slot, slotTagType);
    await communicator.setEM410XEmulatorID(hexToBytes(card.uid));
    await communicator.setSlotTagName(slot, name, TagFrequency.lf);
    await communicator.saveSlotData();
  } else if (card.tag == TagType.hidProx) {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.lf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    await communicator
        .setHIDProxEmulatorID(hexToBytes(HIDCard.fromUID(card.uid).toString()));
    await communicator.setSlotTagName(slot, name, TagFrequency.lf);
    await communicator.saveSlotData();
  } else if (card.tag == TagType.viking) {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.lf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    await communicator.setVikingEmulatorID(hexToBytes(card.uid));
    await communicator.setSlotTagName(slot, name, TagFrequency.lf);
    await communicator.saveSlotData();
  } else if (card.tag == TagType.pac) {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.lf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    await communicator.setPacEmulatorID(hexToBytes(card.uid));
    await communicator.setSlotTagName(slot, name, TagFrequency.lf);
    await communicator.saveSlotData();
  } else if (card.tag == TagType.ioProx) {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.lf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    await communicator.setIoProxEmulatorID(hexToBytes(card.uid));
    await communicator.setSlotTagName(slot, name, TagFrequency.lf);
    await communicator.saveSlotData();
  } else if (card.tag == TagType.idteck) {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.lf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    await communicator.setIdteckEmulatorID(hexToBytes(card.uid));
    await communicator.setSlotTagName(slot, name, TagFrequency.lf);
    await communicator.saveSlotData();
  } else if (isMifareUltralight(card.tag)) {
    onProgress?.call(0);

    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.hf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, card.tag);
    await communicator.setDefaultDataToSlot(slot, card.tag);
    var cardData = CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats);
    await communicator.setMf1AntiCollision(cardData);

    for (var page = 0;
        page < mfUltralightGetPagesCount(card.tag) && card.data.length > page;
        page++) {
      await communicator.mf0EmulatorWritePages(page, card.data[page]);
      onProgress
          ?.call((page / mfUltralightGetPagesCount(card.tag) * 100).round());
      await asyncSleep(1);
    }

    if (card.extraData.ultralightVersion.isNotEmpty) {
      await communicator
          .mf0EmulatorSetVersionData(card.extraData.ultralightVersion);
    }

    if (card.extraData.ultralightSignature.isNotEmpty) {
      await communicator
          .mf0EmulatorSetSignatureData(card.extraData.ultralightSignature);
    }

    if (card.extraData.ultralightCounters.isNotEmpty) {
      for (int i = 0; i < card.extraData.ultralightCounters.length; i++) {
        await communicator.mf0EmulatorSetCounterData(
            i, card.extraData.ultralightCounters[i], true);
      }
    }

    if (mfUltralightHasCounters(card.tag)) {
      await communicator.mf0ResetAuthCount();
    }

    onProgress?.call(100);

    await communicator.setSlotTagName(slot, name, TagFrequency.hf);
    await communicator.saveSlotData();
  } else {
    throw UnsupportedError('Cannot emulate card type: ${card.tag}');
  }
}
