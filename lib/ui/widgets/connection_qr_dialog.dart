import 'dart:convert';

import 'package:flutter/material.dart';

import '../../state/game_controller.dart';
import 'common.dart';

/// نمایش QR و کد اتصال برای بازیکنانی که باید به میزبان ملحق شوند.
Future<void> showConnectionQrDialog(
  BuildContext context,
  GameController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('QR اتصال به بازی'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrCodePanel(data: jsonEncode(controller.qrConnectionPayload())),
            const SizedBox(height: 10),
            Text(
              'کد اتصال: ${controller.joinToken}',
              style: const TextStyle(
                fontFamily: 'Vazirmatn',
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 6),
            Text(
              'بازیکنان می‌توانند با اسکن این QR به همین جلسه وصل شوند.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('بستن'),
        ),
      ],
    ),
  );
}
